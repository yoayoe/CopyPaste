import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../utils/logger.dart';

const _tag = 'WebServer';

/// Info about a connected web client.
class WebClientInfo {
  final WebSocket socket;
  final String ip;
  String name;

  WebClientInfo({required this.socket, required this.ip, this.name = 'Mobile Browser'});
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

  /// Stream of incoming WebSocket messages from mobile clients.
  Stream<Map<String, dynamic>> get onMessage => _incomingMessages.stream;

  /// Currently connected web clients info.
  List<WebClientInfo> get clients => List.unmodifiable(_connectedClients);

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
    onClientChanged?.call(_connectedClients);

    socket.listen(
      (data) {
        try {
          final msg = jsonDecode(data as String) as Map<String, dynamic>;

          // Handle device:info to update client name.
          if (msg['event'] == 'device:info') {
            final info = msg['data'] as Map<String, dynamic>?;
            if (info != null) {
              clientInfo.name = (info['name'] as String?) ?? 'Mobile Browser';
              Log.i(_tag, 'Client identified: ${clientInfo.name} ($clientIp)');
              onClientChanged?.call(_connectedClients);
            }
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

  Future<void> _handleApi(HttpRequest request) async {
    final path = request.uri.path;

    if (path == '/api/status') {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'status': 'ok',
        'clients': _connectedClients.length,
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

  /// Broadcast a message to all connected WebSocket clients.
  void broadcast(String event, Map<String, dynamic> data) {
    final msg = jsonEncode({'event': event, 'data': data});
    for (final client in _connectedClients.toList()) {
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
