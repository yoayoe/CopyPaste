import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import '../../utils/logger.dart';

const _tag = 'WebServer';

/// Info about a connected web client.
class WebClientInfo {
  final WebSocket socket;
  final String ip;
  String name;
  bool authenticated;
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

  /// Called when a web client connects or disconnects.
  void Function(List<WebClientInfo> clients)? onClientChanged;

  /// Called when a new web client needs PIN verification.
  /// The desktop should display this PIN to the user.
  void Function(String clientIp, String clientName, String pin)? onPinGenerated;

  /// Stream of incoming WebSocket messages from authenticated mobile clients.
  Stream<Map<String, dynamic>> get onMessage => _incomingMessages.stream;

  /// Currently connected web clients info (authenticated only for external use).
  List<WebClientInfo> get clients =>
      List.unmodifiable(_connectedClients.where((c) => c.authenticated));

  /// All connected clients including unauthenticated.
  List<WebClientInfo> get allClients => List.unmodifiable(_connectedClients);

  int get port => _server?.port ?? 0;
  bool get isRunning => _server != null;

  EmbeddedWebServer({required this.webClientPath});

  /// Start the HTTP + WebSocket server.
  Future<int> start({int port = 0}) async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    Log.i(_tag, 'Listening on port ${_server!.port}');

    _server!.listen(_handleRequest);
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
    final clientInfo = WebClientInfo(socket: socket, ip: clientIp);
    _connectedClients.add(clientInfo);

    Log.i(_tag, 'WebSocket connected from $clientIp (${_connectedClients.length} clients)');

    // Generate PIN and nonce for this client.
    final pin = _generatePin();
    final nonce = _generateNonce();
    clientInfo._pin = pin;
    clientInfo._nonce = nonce;

    // Send auth challenge to web client.
    _sendToClient(clientInfo, 'auth:challenge', {'nonce': nonce});

    // Notify desktop to display the PIN.
    onPinGenerated?.call(clientIp, clientInfo.name, pin);

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
    if (data == null || client._pin == null || client._nonce == null) {
      _sendToClient(client, 'auth:failed', {'message': 'Invalid request'});
      return;
    }

    final receivedHmac = data['hmac'] as String?;
    if (receivedHmac == null) {
      _sendToClient(client, 'auth:failed', {'message': 'Missing HMAC'});
      return;
    }

    // Compute expected HMAC(PIN, nonce).
    final expectedHmac = await _computeHmac(client._pin!, client._nonce!);

    if (receivedHmac != expectedHmac) {
      Log.w(_tag, 'PIN verification failed from ${client.name} (${client.ip})');
      _sendToClient(client, 'auth:failed', {'message': 'Invalid PIN'});
      return;
    }

    // PIN verified!
    client.authenticated = true;
    client._pin = null;
    client._nonce = null;

    Log.i(_tag, 'Client authenticated: ${client.name} (${client.ip})');
    _sendToClient(client, 'auth:success', {'message': 'Authenticated'});
    onClientChanged?.call(_connectedClients);
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
    // TODO: Implement file upload handling.
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'status': 'not_implemented'}));
    await request.response.close();
  }

  Future<void> _handleDownload(HttpRequest request) async {
    // TODO: Implement file download handling.
    request.response.statusCode = 404;
    request.response.write('Not Found');
    await request.response.close();
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
    for (final client in _connectedClients.toList()) {
      await client.socket.close();
    }
    _connectedClients.clear();
    await _server?.close();
    _server = null;
    await _incomingMessages.close();
    Log.i(_tag, 'Stopped');
  }
}
