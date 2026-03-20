import 'dart:io';
import '../../utils/logger.dart';

const _tag = 'TcpServer';

/// TCP server that listens for incoming connections from other desktop devices.
/// Hands off sockets to the PairingService for persistent connections.
class TcpServer {
  ServerSocket? _server;

  /// Called when a new socket connects. The receiver owns the socket lifecycle.
  final void Function(Socket socket)? onConnection;

  TcpServer({this.onConnection});

  int get port => _server?.port ?? 0;
  bool get isRunning => _server != null;

  /// Start listening on the given port (0 = auto-assign).
  Future<int> start({int port = 0}) async {
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    Log.i(_tag, 'Listening on port ${_server!.port}');

    _server!.listen(_handleConnection);
    return _server!.port;
  }

  void _handleConnection(Socket socket) {
    final remoteIp = socket.remoteAddress.address;
    Log.d(_tag, 'Connection from $remoteIp:${socket.remotePort}');
    onConnection?.call(socket);
  }

  Future<void> stop() async {
    await _server?.close();
    _server = null;
    Log.i(_tag, 'Stopped');
  }
}
