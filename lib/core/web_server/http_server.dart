import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import '../../models/session_info.dart';
import '../../utils/logger.dart';
import '../../utils/mime_parser.dart';

const _tag = 'WebServer';

/// Info about a connected web client.
class WebClientInfo {
  final WebSocket socket;
  final String ip;
  String name;
  bool authenticated;
  String? sessionToken;
  String? _pin;
  String? _nonce;

  WebClientInfo({
    required this.socket,
    required this.ip,
    this.name = 'Mobile Browser',
    this.authenticated = false,
  });
}

/// Embedded HTTP server that serves the web client SPA and handles API routes.
class EmbeddedWebServer {
  HttpServer? _server;
  final String webClientPath;
  final List<WebClientInfo> _connectedClients = [];
  final StreamController<Map<String, dynamic>> _incomingMessages =
      StreamController.broadcast();

  /// Active sessions keyed by token.
  final Map<String, SessionInfo> _sessions = {};

  /// Session configuration.
  Duration sessionMaxAge = const Duration(hours: 24);
  int maxSessions = 10;

  /// Periodic cleanup timer.
  Timer? _cleanupTimer;

  /// Received files stored temporarily for download. fileId → (path, filename, checksum).
  final Map<String, ({String path, String filename, String checksum})> _receivedFiles = {};

  /// Directory for received file storage.
  String? _downloadDir;

  /// Set the directory for storing received files (must be sandbox-accessible).
  void setDownloadDir(String dir) {
    _downloadDir = dir;
  }

  /// Called when a file is uploaded from mobile.
  void Function(String fileId, String filename, int size, String checksum, String savedPath)? onFileUploaded;

  /// Called when a web client connects or disconnects.
  void Function(List<WebClientInfo> clients)? onClientChanged;

  /// Called when a new web client needs PIN verification.
  /// The desktop should display this PIN to the user.
  void Function(String clientIp, String clientName, String pin)? onPinGenerated;

  /// Called when a web client successfully authenticates.
  void Function(String clientIp, String clientName)? onClientAuthenticated;

  /// Stream of incoming WebSocket messages from authenticated mobile clients.
  Stream<Map<String, dynamic>> get onMessage => _incomingMessages.stream;

  /// Currently connected web clients info (authenticated only for external use).
  List<WebClientInfo> get clients =>
      List.unmodifiable(_connectedClients.where((c) => c.authenticated));

  /// All connected clients including unauthenticated.
  List<WebClientInfo> get allClients => List.unmodifiable(_connectedClients);

  int get port => _server?.port ?? 0;
  bool get isRunning => _server != null;

  /// Non-expired active sessions.
  List<SessionInfo> get activeSessions =>
      _sessions.values.where((s) => !s.isExpired(sessionMaxAge)).toList();

  EmbeddedWebServer({required this.webClientPath});

  /// Start the HTTP + WebSocket server.
  Future<int> start({int port = 0}) async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    Log.i(_tag, 'Listening on port ${_server!.port}');

    _server!.listen(_handleRequest);

    // Periodic cleanup of expired sessions.
    _cleanupTimer = Timer.periodic(const Duration(minutes: 15), (_) {
      _cleanupExpiredSessions();
    });

    return _server!.port;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final path = request.uri.path;

    // CORS headers for local network access.
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers
        .add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    request.response.headers
        .add('Access-Control-Allow-Headers', 'Content-Type');

    if (request.method == 'OPTIONS') {
      request.response.statusCode = 200;
      await request.response.close();
      return;
    }

    try {
      if (path == '/ws') {
        await _handleWebSocket(request);
      } else if (path.startsWith('/api/')) {
        await _handleApi(request);
      } else {
        await _serveStaticFile(request);
      }
    } catch (e) {
      Log.e(_tag, 'Error handling $path', e);
      request.response.statusCode = 500;
      request.response.write('Internal Server Error');
      await request.response.close();
    }
  }

  Future<void> _handleWebSocket(HttpRequest request) async {
    final socket = await WebSocketTransformer.upgrade(request);
    final clientIp = request.connectionInfo?.remoteAddress.address ?? 'unknown';

    // Check for session token in query params (reconnect/refresh).
    final token = request.uri.queryParameters['token'];
    final session = (token != null && token.isNotEmpty) ? _sessions[token] : null;
    final hasValidToken = session != null && !session.isExpired(sessionMaxAge);

    // If token exists but expired, remove it.
    if (session != null && session.isExpired(sessionMaxAge)) {
      _sessions.remove(token);
      Log.i(_tag, 'Expired session token from $clientIp');
    }

    final clientInfo = WebClientInfo(
      socket: socket,
      ip: clientIp,
      authenticated: hasValidToken,
    );
    _connectedClients.add(clientInfo);

    Log.i(_tag, 'WebSocket connected from $clientIp '
        '(${hasValidToken ? "has token" : "new"}, ${_connectedClients.length} clients)');

    if (hasValidToken) {
      // Already authenticated via session token — update last seen.
      session.lastSeenAt = DateTime.now();
      clientInfo.sessionToken = token;
      _sendToClient(clientInfo, 'auth:success', {'message': 'Session restored'});
      onClientChanged?.call(_connectedClients);
    } else {
      // New client — require PIN.
      final pin = _generatePin();
      final nonce = _generateNonce();
      clientInfo._pin = pin;
      clientInfo._nonce = nonce;

      _sendToClient(clientInfo, 'auth:challenge', {'nonce': nonce});
      onPinGenerated?.call(clientIp, clientInfo.name, pin);
    }

    socket.listen(
      (data) {
        try {
          final msg = jsonDecode(data as String) as Map<String, dynamic>;
          final event = msg['event'] as String?;

          // Handle device:info (allowed before auth).
          if (event == 'device:info') {
            final info = msg['data'] as Map<String, dynamic>?;
            if (info != null) {
              clientInfo.name = (info['name'] as String?) ?? 'Mobile Browser';
              Log.i(_tag, 'Client identified: ${clientInfo.name} ($clientIp)');
              // Re-notify with updated name.
              if (!clientInfo.authenticated) {
                onPinGenerated?.call(clientIp, clientInfo.name, clientInfo._pin!);
              }
              onClientChanged?.call(_connectedClients);
            }
            return;
          }

          // Handle auth:verify.
          if (event == 'auth:verify') {
            _handleAuthVerify(clientInfo, msg['data'] as Map<String, dynamic>?);
            return;
          }

          // Block all other messages until authenticated.
          if (!clientInfo.authenticated) {
            _sendToClient(clientInfo, 'auth:required', {
              'message': 'PIN verification required',
            });
            return;
          }

          _incomingMessages.add(msg);
        } catch (e) {
          Log.w(_tag, 'Invalid WebSocket message: $e');
        }
      },
      onDone: () {
        _connectedClients.remove(clientInfo);
        Log.i(_tag,
            'WebSocket disconnected: ${clientInfo.name} (${_connectedClients.length} clients)');
        onClientChanged?.call(_connectedClients);
      },
      onError: (error) {
        _connectedClients.remove(clientInfo);
        Log.e(_tag, 'WebSocket error', error);
        onClientChanged?.call(_connectedClients);
      },
    );
  }

  Future<void> _handleAuthVerify(WebClientInfo client, Map<String, dynamic>? data) async {
    if (data == null || client._pin == null) {
      _sendToClient(client, 'auth:failed', {'message': 'Invalid request'});
      return;
    }

    // Accept direct PIN match (works on HTTP where crypto.subtle is unavailable).
    final receivedPin = data['pin'] as String?;
    final receivedHmac = data['hmac'] as String?;

    bool verified = false;

    if (receivedPin != null && receivedPin == client._pin) {
      // Direct PIN match.
      verified = true;
    } else if (receivedHmac != null && client._nonce != null) {
      // HMAC verification (HTTPS/localhost).
      final expectedHmac = await _computeHmac(client._pin!, client._nonce!);
      verified = receivedHmac == expectedHmac;
    }

    if (!verified) {
      Log.w(_tag, 'PIN verification failed from ${client.name} (${client.ip})');
      _sendToClient(client, 'auth:failed', {'message': 'Invalid PIN'});
      return;
    }

    // PIN verified! Generate session token for future reconnects.
    client.authenticated = true;
    client._pin = null;
    client._nonce = null;

    // Enforce max sessions — evict oldest if at limit.
    if (_sessions.length >= maxSessions) {
      final oldest = _sessions.entries
          .reduce((a, b) => a.value.lastSeenAt.isBefore(b.value.lastSeenAt) ? a : b);
      _revokeSession(oldest.key, reason: 'max_sessions');
    }

    final sessionToken = _generateSessionToken();
    client.sessionToken = sessionToken;
    _sessions[sessionToken] = SessionInfo(
      token: sessionToken,
      clientName: client.name,
      clientIp: client.ip,
      createdAt: DateTime.now(),
    );

    Log.i(_tag, 'Client authenticated: ${client.name} (${client.ip}) '
        '(${_sessions.length} sessions)');
    _sendToClient(client, 'auth:success', {
      'message': 'Authenticated',
      'sessionToken': sessionToken,
    });
    onClientAuthenticated?.call(client.ip, client.name);
    onClientChanged?.call(_connectedClients);
  }

  /// Revoke a specific session by token.
  void revokeSession(String token) {
    _revokeSession(token, reason: 'revoked');
  }

  /// Revoke all sessions.
  void revokeAllSessions() {
    final tokens = _sessions.keys.toList();
    for (final token in tokens) {
      _revokeSession(token, reason: 'revoked');
    }
  }

  void _revokeSession(String token, {String reason = 'revoked'}) {
    final session = _sessions.remove(token);
    if (session == null) return;

    Log.i(_tag, 'Session revoked: ${session.clientName} (${session.clientIp}), reason: $reason');

    // Find connected client with this token and disconnect.
    final client = _connectedClients
        .where((c) => c.sessionToken == token)
        .firstOrNull;
    if (client != null) {
      _sendToClient(client, 'auth:revoked', {'reason': reason});
      client.authenticated = false;
      client.sessionToken = null;
      try { client.socket.close(); } catch (_) {}
      _connectedClients.remove(client);
    }

    onClientChanged?.call(_connectedClients);
  }

  void _cleanupExpiredSessions() {
    final expired = _sessions.entries
        .where((e) => e.value.isExpired(sessionMaxAge))
        .map((e) => e.key)
        .toList();
    for (final token in expired) {
      _revokeSession(token, reason: 'expired');
    }
    if (expired.isNotEmpty) {
      Log.i(_tag, 'Cleaned up ${expired.length} expired sessions');
    }
  }

  void _sendToClient(WebClientInfo client, String event, Map<String, dynamic> data) {
    try {
      client.socket.add(jsonEncode({'event': event, 'data': data}));
    } catch (e) {
      _connectedClients.remove(client);
    }
  }

  Future<void> _handleApi(HttpRequest request) async {
    final path = request.uri.path;

    if (path == '/api/status') {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'status': 'ok',
        'clients': clients.length,
      }));
      await request.response.close();
      return;
    }

    if (path == '/api/upload' && request.method == 'POST') {
      await _handleUpload(request);
      return;
    }

    if (path.startsWith('/api/download/')) {
      await _handleDownload(request);
      return;
    }

    request.response.statusCode = 404;
    request.response.write('Not Found');
    await request.response.close();
  }

  Future<void> _handleUpload(HttpRequest request) async {
    // Ensure download dir exists.
    _downloadDir ??= '${Directory.systemTemp.path}/copypaste_files';
    await Directory(_downloadDir!).create(recursive: true);

    try {
      final contentType = request.headers.contentType;
      if (contentType == null || contentType.mimeType != 'multipart/form-data') {
        request.response.statusCode = 400;
        request.response.write(jsonEncode({'error': 'Expected multipart/form-data'}));
        await request.response.close();
        return;
      }

      final boundary = contentType.parameters['boundary'];
      if (boundary == null) {
        request.response.statusCode = 400;
        request.response.write(jsonEncode({'error': 'Missing boundary'}));
        await request.response.close();
        return;
      }

      final parts = await parseMultipart(request, boundary);

      for (final part in parts) {
        final filename = part.filename ?? 'unknown';

        final fileId = _generateSessionToken().substring(0, 16);
        final savePath = '$_downloadDir/$fileId-$filename';
        final file = File(savePath);
        await file.writeAsBytes(part.body);
        final totalBytes = part.body.length;

        // Compute SHA-256 checksum.
        final checksum = await _computeFileChecksum(savePath);

        _receivedFiles[fileId] = (path: savePath, filename: filename, checksum: checksum);
        Log.i(_tag, 'File uploaded: $filename ($totalBytes bytes, id: $fileId)');

        onFileUploaded?.call(fileId, filename, totalBytes, checksum, savePath);

        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'status': 'ok',
          'fileId': fileId,
          'downloadId': fileId,
          'filename': filename,
          'size': totalBytes,
          'checksum': checksum,
        }));
        await request.response.close();
        return;
      }

      request.response.statusCode = 400;
      request.response.write(jsonEncode({'error': 'No file in request'}));
      await request.response.close();
    } catch (e) {
      Log.e(_tag, 'Upload error', e);
      request.response.statusCode = 500;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': e.toString()}));
      await request.response.close();
    }
  }

  Future<void> _handleDownload(HttpRequest request) async {
    final path = request.uri.path;
    final fileId = path.replaceFirst('/api/download/', '');

    final fileInfo = _receivedFiles[fileId];
    if (fileInfo == null) {
      request.response.statusCode = 404;
      request.response.write('File not found');
      await request.response.close();
      return;
    }

    final file = File(fileInfo.path);
    if (!await file.exists()) {
      _receivedFiles.remove(fileId);
      request.response.statusCode = 404;
      request.response.write('File not found');
      await request.response.close();
      return;
    }

    final stat = await file.stat();
    request.response.headers.contentType = ContentType.binary;
    request.response.headers.add('Content-Disposition',
        'attachment; filename="${Uri.encodeComponent(fileInfo.filename)}"');
    request.response.contentLength = stat.size;
    await file.openRead().pipe(request.response);
  }

  /// Make a file available for download by mobile clients.
  String addFileForDownload(String filePath, String filename, String checksum) {
    final fileId = _generateSessionToken().substring(0, 16);
    _receivedFiles[fileId] = (path: filePath, filename: filename, checksum: checksum);
    return fileId;
  }

  Future<String> _computeFileChecksum(String filePath) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final hash = await Sha256().hash(bytes);
    return base64Encode(hash.bytes);
  }

  Future<void> _serveStaticFile(HttpRequest request) async {
    var path = request.uri.path;
    if (path == '/') path = '/index.html';

    final file = File('$webClientPath$path');

    if (await file.exists()) {
      final ext = path.split('.').last;
      request.response.headers.contentType = _contentType(ext);
      // Prevent caching during development.
      request.response.headers.add('Cache-Control', 'no-cache, no-store, must-revalidate');
      request.response.headers.add('Pragma', 'no-cache');
      await file.openRead().pipe(request.response);
    } else {
      // SPA fallback: serve index.html for unknown routes.
      final index = File('$webClientPath/index.html');
      if (await index.exists()) {
        request.response.headers.contentType = ContentType.html;
        await index.openRead().pipe(request.response);
      } else {
        request.response.statusCode = 404;
        request.response.write('Not Found');
        await request.response.close();
      }
    }
  }

  /// Broadcast a message to all authenticated WebSocket clients.
  void broadcast(String event, Map<String, dynamic> data) {
    final msg = jsonEncode({'event': event, 'data': data});
    for (final client in _connectedClients.toList()) {
      if (!client.authenticated) continue;
      try {
        client.socket.add(msg);
      } catch (e) {
        _connectedClients.remove(client);
      }
    }
  }

  ContentType _contentType(String ext) => switch (ext) {
        'html' => ContentType.html,
        'css' => ContentType('text', 'css', charset: 'utf-8'),
        'js' => ContentType('application', 'javascript', charset: 'utf-8'),
        'json' => ContentType.json,
        'png' => ContentType('image', 'png'),
        'svg' => ContentType('image', 'svg+xml'),
        'ico' => ContentType('image', 'x-icon'),
        _ => ContentType.binary,
      };

  String _generatePin() {
    final rng = Random.secure();
    return List.generate(6, (_) => rng.nextInt(10)).join();
  }

  String _generateSessionToken() {
    final rng = Random.secure();
    final bytes = List.generate(48, (_) => rng.nextInt(256));
    return base64Url.encode(bytes);
  }

  String _generateNonce() {
    final rng = Random.secure();
    final bytes = List.generate(32, (_) => rng.nextInt(256));
    return base64Encode(bytes);
  }

  Future<String> _computeHmac(String pin, String nonce) async {
    final hmacAlgo = Hmac.sha256();
    final key = utf8.encode(pin);
    final data = utf8.encode(nonce);
    final mac = await hmacAlgo.calculateMac(data, secretKey: SecretKey(key));
    return base64Encode(mac.bytes);
  }

  Future<void> stop() async {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    for (final client in _connectedClients.toList()) {
      await client.socket.close();
    }
    _connectedClients.clear();
    _sessions.clear();
    await _server?.close();
    _server = null;
    await _incomingMessages.close();
    Log.i(_tag, 'Stopped');
  }
}
