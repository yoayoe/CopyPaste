import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import '../core/network/peer_connection.dart';
import '../core/protocol/message.dart';
import '../core/protocol/message_type.dart';
import '../utils/logger.dart';

const _tag = 'Pairing';

/// Pending pairing state for incoming requests.
class _PendingPair {
  final PeerConnection peer;
  final String pin;
  final String nonce;

  _PendingPair({required this.peer, required this.pin, required this.nonce});
}

/// Manages desktop-to-desktop pairing and authenticated communication.
class PairingService {
  final String localDeviceId;
  final String localDeviceName;
  final String localPlatform;
  final int localTcpPort;
  final int localWebPort;

  /// Active paired connections keyed by device ID.
  final Map<String, PeerConnection> _peers = {};

  /// Pending incoming pair requests keyed by device ID.
  final Map<String, _PendingPair> _pendingIncoming = {};

  /// Pending outgoing pair — waiting for PIN input.
  PeerConnection? _pendingOutgoing;
  String? _pendingOutgoingNonce;

  // --- Callbacks ---

  /// UI should show PIN dialog (responder side).
  /// params: deviceId, deviceName, platform, pin
  void Function(String deviceId, String deviceName, String platform, String pin)?
      onPairRequestReceived;

  /// UI should show PIN input (initiator side).
  /// params: deviceId, deviceName, platform
  void Function(String deviceId, String deviceName, String platform)?
      onPairPinRequired;

  /// Pairing completed.
  void Function(String deviceId, String deviceName, String platform, String ip)?
      onPeerPaired;

  /// Peer disconnected.
  void Function(String deviceId)? onPeerDisconnected;

  /// Clipboard received from a paired peer.
  void Function(String content, String sourceDeviceId, String sourceDeviceName)?
      onClipboardReceived;

  /// Pairing failed or rejected.
  void Function(String deviceId, String reason)? onPairFailed;

  PairingService({
    required this.localDeviceId,
    required this.localDeviceName,
    required this.localPlatform,
    required this.localTcpPort,
    required this.localWebPort,
  });

  List<PeerConnection> get peers => _peers.values.toList();

  bool hasPeer(String deviceId) => _peers.containsKey(deviceId);

  /// Handle incoming TCP connection from the server.
  /// Called when a new socket connects to our TCP server.
  void handleIncomingConnection(Socket socket) {
    final remoteIp = socket.remoteAddress.address;
    Log.i(_tag, 'Incoming connection from $remoteIp');

    // Create a temporary peer to handle the handshake.
    final tempPeer = PeerConnection(
      deviceId: 'unknown-$remoteIp',
      ip: remoteIp,
      port: socket.remotePort,
      state: PeerState.connecting,
    );
    tempPeer.onMessage = _handleMessage;
    tempPeer.onDisconnected = _handleDisconnected;
    tempPeer.adoptSocket(socket);
  }

  /// Initiate connection to a remote desktop (user typed IP:port).
  Future<void> initiateConnection(String ip, int port) async {
    Log.i(_tag, 'Initiating connection to $ip:$port');

    final peer = PeerConnection(
      deviceId: 'pending-$ip',
      ip: ip,
      port: port,
      state: PeerState.connecting,
    );
    peer.onMessage = _handleMessage;
    peer.onDisconnected = _handleDisconnected;

    final connected = await peer.connect();
    if (!connected) {
      onPairFailed?.call(peer.deviceId, 'Connection failed');
      return;
    }

    // Send pair request.
    await peer.send(Message.pairRequest(
      senderId: localDeviceId,
      senderName: localDeviceName,
      platform: localPlatform,
      tcpPort: localTcpPort,
      webPort: localWebPort,
    ));

    _pendingOutgoing = peer;
  }

  /// User entered PIN on initiator side.
  Future<void> submitPin(String deviceId, String pin) async {
    final peer = _pendingOutgoing;
    final nonce = _pendingOutgoingNonce;
    if (peer == null || nonce == null) {
      onPairFailed?.call(deviceId, 'No pending pairing');
      return;
    }

    final hmac = await _computeHmac(pin, nonce);
    await peer.send(Message.pairResponse(hmac: hmac));
  }

  /// User approved pairing on responder side (confirms PIN was shared).
  Future<void> approvePairing(String deviceId) async {
    final pending = _pendingIncoming[deviceId];
    if (pending == null) return;

    // The PIN was already shown and sent as challenge.
    // Now we wait for the initiator to send the correct HMAC.
    // (The approval means "I showed the PIN to the other user")
    // Nothing to send here — we wait for pairResponse.
    Log.i(_tag, 'Pairing approved, waiting for PIN verification from $deviceId');
  }

  /// User rejected pairing on responder side.
  Future<void> rejectPairing(String deviceId) async {
    final pending = _pendingIncoming.remove(deviceId);
    if (pending != null) {
      await pending.peer.send(Message.reject('Pairing rejected'));
      await pending.peer.close();
    }
  }

  /// Send clipboard text to all paired peers.
  Future<void> broadcastClipboard(String content, String senderId, String senderName) async {
    for (final peer in _peers.values.toList()) {
      if (peer.state != PeerState.paired) continue;

      final hmac = peer.sessionKey != null
          ? await _computeHmacBytes(peer.sessionKey!, utf8.encode(content))
          : null;

      final msg = Message.text(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        senderId: senderId,
        content: content,
        senderName: senderName,
        hmac: hmac,
      );
      await peer.send(msg);
    }
  }

  /// Disconnect a specific peer.
  Future<void> disconnectPeer(String deviceId) async {
    final peer = _peers.remove(deviceId);
    if (peer != null) {
      await peer.close();
      onPeerDisconnected?.call(deviceId);
    }
  }

  /// Disconnect all peers.
  Future<void> disconnectAll() async {
    for (final peer in _peers.values.toList()) {
      await peer.close();
    }
    _peers.clear();
    _pendingIncoming.clear();
    _pendingOutgoing = null;
  }

  // --- Message handlers ---

  void _handleMessage(Message message, PeerConnection peer) {
    Log.d(_tag, 'Message: ${message.type.name} from ${peer.ip}');

    switch (message.type) {
      case MessageType.pairRequest:
        _handlePairRequest(message, peer);
      case MessageType.pairChallenge:
        _handlePairChallenge(message, peer);
      case MessageType.pairResponse:
        _handlePairResponse(message, peer);
      case MessageType.pairConfirm:
        _handlePairConfirm(message, peer);
      case MessageType.text:
        _handleText(message, peer);
      case MessageType.ping:
        peer.send(Message.pong(localDeviceId));
      case MessageType.pong:
        Log.d(_tag, 'Pong from ${peer.deviceName}');
      case MessageType.disconnect:
        _handleDisconnectMsg(peer);
      case MessageType.reject:
        _handleReject(message, peer);
      default:
        Log.w(_tag, 'Unhandled message type: ${message.type.name}');
    }
  }

  void _handlePairRequest(Message message, PeerConnection peer) {
    final senderId = message.meta['sender'] as String;
    final senderName = message.meta['senderName'] as String? ?? 'Unknown';
    final platform = message.meta['platform'] as String? ?? 'unknown';

    // Update peer info.
    peer.deviceName = senderName;
    peer.platform = platform;

    // Generate 6-digit PIN and nonce.
    final pin = _generatePin();
    final nonce = _generateNonce();

    _pendingIncoming[senderId] = _PendingPair(
      peer: peer,
      pin: pin,
      nonce: nonce,
    );

    // Send challenge nonce to initiator.
    peer.send(Message.pairChallenge(nonce: nonce));

    // Show PIN to responder user.
    onPairRequestReceived?.call(senderId, senderName, platform, pin);
    Log.i(_tag, 'Pair request from $senderName ($senderId). PIN: $pin');
  }

  void _handlePairChallenge(Message message, PeerConnection peer) {
    // We are the initiator — received challenge from responder.
    final nonce = message.meta['nonce'] as String;
    _pendingOutgoingNonce = nonce;

    // Ask UI for PIN input.
    final deviceId = peer.deviceId;
    onPairPinRequired?.call(deviceId, peer.deviceName, peer.platform);
    Log.i(_tag, 'Challenge received, waiting for user PIN input');
  }

  Future<void> _handlePairResponse(Message message, PeerConnection peer) async {
    // We are the responder — verify the HMAC.
    final receivedHmac = message.meta['hmac'] as String;

    // Find the pending pairing for this peer.
    String? matchedId;
    _PendingPair? pending;
    for (final entry in _pendingIncoming.entries) {
      if (entry.value.peer == peer) {
        matchedId = entry.key;
        pending = entry.value;
        break;
      }
    }

    if (pending == null || matchedId == null) {
      await peer.send(Message.reject('No pending pairing'));
      return;
    }

    // Verify: HMAC(PIN, nonce) should match.
    final expectedHmac = await _computeHmac(pending.pin, pending.nonce);

    if (receivedHmac != expectedHmac) {
      Log.w(_tag, 'PIN verification failed from ${peer.deviceName}');
      await peer.send(Message.reject('Invalid PIN'));
      _pendingIncoming.remove(matchedId);
      onPairFailed?.call(matchedId, 'Invalid PIN');
      await peer.close();
      return;
    }

    // PIN verified! Derive session key.
    final sessionKey = await _deriveSessionKey(pending.pin, pending.nonce);
    peer.sessionKey = sessionKey;
    peer.state = PeerState.paired;

    // Move from pending to active peers.
    // Update deviceId from the actual sender ID.
    _pendingIncoming.remove(matchedId);
    _peers[matchedId] = peer;

    // Send confirmation with our device info.
    await peer.send(Message.pairConfirm(
      senderId: localDeviceId,
      senderName: localDeviceName,
      platform: localPlatform,
      tcpPort: localTcpPort,
      webPort: localWebPort,
    ));

    onPeerPaired?.call(matchedId, peer.deviceName, peer.platform, peer.ip);
    Log.i(_tag, 'Paired with ${peer.deviceName} ($matchedId)');
  }

  Future<void> _handlePairConfirm(Message message, PeerConnection peer) async {
    // We are the initiator — pairing confirmed by responder.
    final senderId = message.meta['sender'] as String;
    final senderName = message.meta['senderName'] as String? ?? 'Unknown';
    final platform = message.meta['platform'] as String? ?? 'unknown';

    peer.deviceName = senderName;
    peer.platform = platform;

    // Session key was pre-derived in submitPinAndDeriveKey().
    if (_pendingOutgoing == peer && _lastSessionKey != null) {
      peer.sessionKey = _lastSessionKey;
    }

    peer.state = PeerState.paired;
    _peers[senderId] = peer;
    _pendingOutgoing = null;
    _pendingOutgoingNonce = null;

    onPeerPaired?.call(senderId, senderName, platform, peer.ip);
    Log.i(_tag, 'Pairing confirmed with $senderName ($senderId)');
  }

  List<int>? _lastSessionKey;

  // Override submitPin to also derive the session key.
  Future<void> submitPinAndDeriveKey(String deviceId, String pin) async {
    final peer = _pendingOutgoing;
    final nonce = _pendingOutgoingNonce;
    if (peer == null || nonce == null) {
      onPairFailed?.call(deviceId, 'No pending pairing');
      return;
    }

    final hmac = await _computeHmac(pin, nonce);
    _lastSessionKey = await _deriveSessionKey(pin, nonce);
    await peer.send(Message.pairResponse(hmac: hmac));
  }

  Future<void> _handleText(Message message, PeerConnection peer) async {
    if (peer.state != PeerState.paired) {
      Log.w(_tag, 'Text from unpaired peer ${peer.ip}, ignoring');
      return;
    }

    // Verify HMAC if session key exists.
    if (peer.sessionKey != null) {
      final receivedHmac = message.meta['hmac'] as String?;
      if (receivedHmac == null) {
        Log.w(_tag, 'No HMAC in message from ${peer.deviceName}');
        return;
      }

      final expectedHmac = await _computeHmacBytes(
          peer.sessionKey!, message.payload);
      if (receivedHmac != expectedHmac) {
        Log.w(_tag, 'Invalid HMAC from ${peer.deviceName}');
        return;
      }
    }

    final content = utf8.decode(message.payload);
    final senderId = message.meta['sender'] as String? ?? peer.deviceId;
    final senderName = message.meta['senderName'] as String? ?? peer.deviceName;

    onClipboardReceived?.call(content, senderId, senderName);
  }

  void _handleDisconnectMsg(PeerConnection peer) {
    final deviceId =
        _peers.entries.where((e) => e.value == peer).map((e) => e.key).firstOrNull;
    if (deviceId != null) {
      _peers.remove(deviceId);
      onPeerDisconnected?.call(deviceId);
    }
    peer.state = PeerState.disconnected;
  }

  void _handleReject(Message message, PeerConnection peer) {
    final reason = message.meta['reason'] as String? ?? 'Rejected';
    Log.w(_tag, 'Rejected by ${peer.deviceName}: $reason');

    if (_pendingOutgoing == peer) {
      final deviceId = peer.deviceId;
      _pendingOutgoing = null;
      _pendingOutgoingNonce = null;
      onPairFailed?.call(deviceId, reason);
    }

    peer.close();
  }

  void _handleDisconnected(PeerConnection peer) {
    final deviceId =
        _peers.entries.where((e) => e.value == peer).map((e) => e.key).firstOrNull;
    if (deviceId != null) {
      _peers.remove(deviceId);
      onPeerDisconnected?.call(deviceId);
    }

    // Clean up pending.
    _pendingIncoming.removeWhere((_, v) => v.peer == peer);
    if (_pendingOutgoing == peer) {
      _pendingOutgoing = null;
      _pendingOutgoingNonce = null;
    }
  }

  // --- Crypto helpers ---

  String _generatePin() {
    final rng = Random.secure();
    return List.generate(6, (_) => rng.nextInt(10)).join();
  }

  String _generateNonce() {
    final rng = Random.secure();
    final bytes = Uint8List(32);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = rng.nextInt(256);
    }
    return base64Encode(bytes);
  }

  Future<String> _computeHmac(String pin, String nonce) async {
    final hmacAlgo = Hmac.sha256();
    final key = utf8.encode(pin);
    final data = utf8.encode(nonce);
    final mac = await hmacAlgo.calculateMac(data, secretKey: SecretKey(key));
    return base64Encode(mac.bytes);
  }

  Future<String> _computeHmacBytes(List<int> key, List<int> data) async {
    final hmacAlgo = Hmac.sha256();
    final mac = await hmacAlgo.calculateMac(data, secretKey: SecretKey(key));
    return base64Encode(mac.bytes);
  }

  Future<List<int>> _deriveSessionKey(String pin, String nonce) async {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final derivedKey = await hkdf.deriveKey(
      secretKey: SecretKey(utf8.encode(pin)),
      nonce: utf8.encode(nonce),
      info: utf8.encode('copypaste-session'),
    );
    return await derivedKey.extractBytes();
  }
}
