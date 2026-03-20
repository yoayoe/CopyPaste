import 'dart:io';
import 'dart:typed_data';
import '../protocol/header.dart';
import '../protocol/message.dart';
import '../../utils/logger.dart';

const _tag = 'PeerConn';

enum PeerState { connecting, waitingPin, paired, disconnected }

/// A persistent TCP connection to a paired desktop peer.
class PeerConnection {
  final String deviceId;
  String deviceName;
  final String ip;
  final int port;
  String platform;

  Socket? _socket;
  final List<int> _buffer = [];
  PeerState state;

  /// HMAC session key derived from PIN pairing.
  List<int>? sessionKey;

  /// Called when a complete message is received on this connection.
  void Function(Message message, PeerConnection peer)? onMessage;

  /// Called when the connection is closed.
  void Function(PeerConnection peer)? onDisconnected;

  PeerConnection({
    required this.deviceId,
    this.deviceName = 'Unknown',
    required this.ip,
    required this.port,
    this.platform = 'unknown',
    this.state = PeerState.connecting,
    this.onMessage,
    this.onDisconnected,
  });

  bool get isConnected => _socket != null && state == PeerState.paired;

  /// Connect to the remote peer's TCP server.
  Future<bool> connect() async {
    try {
      _socket = await Socket.connect(ip, port,
          timeout: const Duration(seconds: 5));
      _listenSocket();
      Log.i(_tag, 'Connected to $deviceName ($ip:$port)');
      return true;
    } catch (e) {
      Log.e(_tag, 'Failed to connect to $ip:$port', e);
      state = PeerState.disconnected;
      return false;
    }
  }

  /// Adopt an existing socket (from server-side accept).
  void adoptSocket(Socket socket) {
    _socket = socket;
    _listenSocket();
    Log.i(_tag, 'Adopted socket from $ip');
  }

  void _listenSocket() {
    _socket!.listen(
      (data) {
        _buffer.addAll(data);
        _processBuffer();
      },
      onDone: () {
        Log.i(_tag, 'Connection closed: $deviceName ($ip)');
        _cleanup();
      },
      onError: (error) {
        Log.e(_tag, 'Socket error from $deviceName', error);
        _cleanup();
      },
    );
  }

  void _processBuffer() {
    while (_buffer.length >= Header.size) {
      final bytes = Uint8List.fromList(_buffer);
      final header = Header.fromBytes(bytes);
      if (header == null) {
        // Invalid data — clear buffer.
        _buffer.clear();
        return;
      }

      final totalNeeded = header.totalSize;
      if (_buffer.length < totalNeeded) {
        // Wait for more data.
        return;
      }

      // Extract one complete message.
      final msgBytes = Uint8List.fromList(_buffer.sublist(0, totalNeeded));
      _buffer.removeRange(0, totalNeeded);

      final message = Message.fromBytes(msgBytes);
      if (message != null) {
        onMessage?.call(message, this);
      }
    }
  }

  /// Send a message over this persistent connection.
  Future<bool> send(Message message) async {
    if (_socket == null) return false;
    try {
      _socket!.add(message.toBytes());
      await _socket!.flush();
      return true;
    } catch (e) {
      Log.e(_tag, 'Send failed to $deviceName', e);
      _cleanup();
      return false;
    }
  }

  void _cleanup() {
    final wasConnected = state != PeerState.disconnected;
    state = PeerState.disconnected;
    _buffer.clear();
    try {
      _socket?.destroy();
    } catch (_) {}
    _socket = null;
    if (wasConnected) {
      onDisconnected?.call(this);
    }
  }

  Future<void> close() async {
    if (_socket != null) {
      try {
        _socket!.add(Message.disconnect(deviceId).toBytes());
        await _socket!.flush();
      } catch (_) {}
    }
    _cleanup();
  }
}
