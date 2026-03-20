import 'dart:io';
import 'dart:typed_data';
import '../protocol/header.dart';
import '../protocol/message.dart';
import '../../utils/logger.dart';

const _tag = 'TcpServer';

/// TCP server that listens for incoming messages from other desktop devices.
class TcpServer {
  ServerSocket? _server;
  final void Function(Message message, String remoteIp)? onMessage;

  TcpServer({this.onMessage});

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

    final chunks = <int>[];

    socket.listen(
      (data) {
        chunks.addAll(data);
        _tryParseMessage(Uint8List.fromList(chunks), remoteIp);
      },
      onDone: () {
        if (chunks.isNotEmpty) {
          _tryParseMessage(Uint8List.fromList(chunks), remoteIp);
        }
        socket.close();
      },
      onError: (error) {
        Log.e(_tag, 'Socket error from $remoteIp', error);
        socket.close();
      },
    );
  }

  void _tryParseMessage(Uint8List bytes, String remoteIp) {
    final message = Message.fromBytes(bytes);
    if (message != null) {
      onMessage?.call(message, remoteIp);
    }
  }

  Future<void> stop() async {
    await _server?.close();
    _server = null;
    Log.i(_tag, 'Stopped');
  }
}
