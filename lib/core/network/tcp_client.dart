import 'dart:io';
import '../protocol/message.dart';
import '../../utils/logger.dart';

const _tag = 'TcpClient';

/// TCP client for sending messages to other desktop devices.
class TcpClient {
  /// Send a message to a remote device.
  static Future<bool> send(Message message, String ip, int port) async {
    try {
      final socket = await Socket.connect(ip, port,
          timeout: const Duration(seconds: 5));

      socket.add(message.toBytes());
      await socket.flush();
      await socket.close();

      Log.d(_tag, 'Sent ${message.type.name} to $ip:$port');
      return true;
    } catch (e) {
      Log.e(_tag, 'Failed to send to $ip:$port', e);
      return false;
    }
  }
}
