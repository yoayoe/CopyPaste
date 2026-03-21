import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import '../core/network/peer_connection.dart';
import '../core/protocol/message.dart';
import '../core/protocol/message_type.dart';
import '../utils/logger.dart';
import 'secure_storage_service.dart';

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

  /// File message received from a paired peer.
  void Function(Message message)? onFileReceived;

  /// Pairing failed or rejected.
  void Function(String deviceId, String reason)? onPairFailed;

  final SecureStorageService? secureStorage;

  PairingService({
    required this.localDeviceId,
    required this.localDeviceName,
    required this.localPlatform,
    required this.localTcpPort,
    required this.localWebPort,
    this.secureStorage,
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

  /// Disconnect and unpair a specific peer.
  Future<void> disconnectPeer(String deviceId) async {
    final peer = _peers.remove(deviceId);
    if (peer != null) {
      await peer.close();
      onPeerDisconnected?.call(deviceId);
    }
    // Remove from secure storage (unpair).
    await secureStorage?.removePairedPeer(deviceId);
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
    Log.i(_tag, '<<< Message: ${message.type.name} from ${peer.ip} (${peer.deviceName})');

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
      case MessageType.file:
        if (peer.state == PeerState.paired) {
          onFileReceived?.call(message);
        } else {
          Log.w(_tag, 'File from unpaired peer ${peer.ip}, ignoring');
        }
      case MessageType.ping:
        peer.send(Message.pong(localDeviceId));
      case MessageType.pong:
        Log.d(_tag, 'Pong from ${peer.deviceName}');
      case MessageType.reconnectRequest:
        _handleReconnectRequest(message, peer);
      case MessageType.reconnectConfirm:
        _handleReconnectConfirm(message, peer);
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
    final tcpPort = message.meta['tcpPort'] as int? ?? 0;

    // Update peer info.
    peer.deviceName = senderName;
    peer.platform = platform;
    peer.remoteTcpPort = tcpPort;

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

    // Persist pairing for reconnection.
    _savePeerToStorage(matchedId, peer);
  }

  Future<void> _handlePairConfirm(Message message, PeerConnection peer) async {
    // We are the initiator — pairing confirmed by responder.
    final senderId = message.meta['sender'] as String;
    final senderName = message.meta['senderName'] as String? ?? 'Unknown';
    final platform = message.meta['platform'] as String? ?? 'unknown';
    final tcpPort = message.meta['tcpPort'] as int? ?? 0;

    peer.deviceName = senderName;
    peer.platform = platform;
    peer.remoteTcpPort = tcpPort;

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

    // Persist pairing for reconnection.
    _savePeerToStorage(senderId, peer);
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
    Log.i(_tag, 'Disconnected: ${peer.deviceName} (${peer.ip}:${peer.port}) state=${peer.state.name}');
    final deviceId =
        _peers.entries.where((e) => e.value == peer).map((e) => e.key).firstOrNull;
    if (deviceId != null) {
      _peers.remove(deviceId);
      onPeerDisconnected?.call(deviceId);
    }

    // Clean up pending reconnects.
    _pendingReconnects.removeWhere((key, value) {
      if (value.$1 == peer) {
        Log.i(_tag, 'Cleaned up pending reconnect for $key due to disconnect');
        return true;
      }
      return false;
    });

    // Clean up pending pairing.
    _pendingIncoming.removeWhere((_, v) => v.peer == peer);
    if (_pendingOutgoing == peer) {
      _pendingOutgoing = null;
      _pendingOutgoingNonce = null;
    }
  }

  // --- Reconnect logic ---

  /// Pending reconnect challenges we sent (keyed by remote deviceId).
  final Map<String, (PeerConnection, String challenge, List<int> sessionKey)>
      _pendingReconnects = {};

  /// Try to reconnect to all previously paired peers.
  Future<void> reconnectToKnownPeers() async {
    if (secureStorage == null) {
      Log.w(_tag, 'No secure storage — cannot reconnect');
      return;
    }
    final knownPeers = await secureStorage!.loadAllPairedPeers();
    if (knownPeers.isEmpty) {
      Log.i(_tag, 'No known peers to reconnect');
      return;
    }

    Log.i(_tag, 'Attempting reconnect to ${knownPeers.length} known peers');
    for (final entry in knownPeers.entries) {
      final info = entry.value.$1;
      final sessionKey = entry.value.$2;
      Log.i(_tag, 'Known peer: ${info.deviceName} (${info.lastKnownIp}:${info.lastKnownPort}), key length: ${sessionKey.length}');
      // Don't reconnect to peers already connected.
      if (_peers.containsKey(info.deviceId)) {
        Log.i(_tag, 'Peer ${info.deviceName} already connected, skipping');
        continue;
      }
      _attemptReconnectWithRetry(info, sessionKey);
    }
  }

  /// Attempt reconnect with retries (peer may not be ready yet).
  Future<void> _attemptReconnectWithRetry(
      PairedPeerInfo info, List<int> sessionKey) async {
    const retries = 3;
    const delays = [Duration(seconds: 0), Duration(seconds: 5), Duration(seconds: 10)];
    for (var i = 0; i < retries; i++) {
      if (_peers.containsKey(info.deviceId)) {
        Log.i(_tag, 'Peer ${info.deviceName} already connected (by incoming), stopping retry');
        return;
      }
      if (i > 0) {
        Log.i(_tag, 'Retry ${i + 1}/$retries for ${info.deviceName} after ${delays[i].inSeconds}s');
        await Future.delayed(delays[i]);
      }
      final success = await _attemptReconnect(info, sessionKey);
      if (success) return;
    }
    Log.w(_tag, 'All reconnect attempts to ${info.deviceName} failed');
  }

  /// Returns true if TCP connected and request sent (doesn't mean auth completed).
  Future<bool> _attemptReconnect(
      PairedPeerInfo info, List<int> sessionKey) async {
    Log.i(_tag,
        'Reconnecting to ${info.deviceName} (${info.lastKnownIp}:${info.lastKnownPort})');

    if (info.lastKnownPort <= 0) {
      Log.w(_tag, 'No port stored for ${info.deviceName}, skipping');
      return false;
    }

    try {
      final peer = PeerConnection(
        deviceId: info.deviceId,
        deviceName: info.deviceName,
        ip: info.lastKnownIp,
        port: info.lastKnownPort,
        platform: info.platform,
        state: PeerState.connecting,
      );
      peer.onMessage = _handleMessage;
      peer.onDisconnected = _handleDisconnected;

      Log.i(_tag, 'Attempting TCP connect to ${info.lastKnownIp}:${info.lastKnownPort}...');
      final connected = await peer.connect();
      if (!connected) {
        Log.w(_tag, 'Reconnect TCP failed to ${info.deviceName} — peer offline or port changed');
        return false;
      }
      Log.i(_tag, 'TCP connected to ${info.deviceName}, sending reconnect request...');

      // Send reconnect request with a challenge nonce.
      final challenge = _generateNonce();
      _pendingReconnects[info.deviceId] = (peer, challenge, sessionKey);

      final sent = await peer.send(Message.reconnectRequest(
        senderId: localDeviceId,
        senderName: localDeviceName,
        platform: localPlatform,
        tcpPort: localTcpPort,
        challenge: challenge,
      ));
      Log.i(_tag, 'Reconnect request sent to ${info.deviceName}: $sent');
      return sent;
    } catch (e) {
      Log.e(_tag, 'Reconnect attempt error for ${info.deviceName}', e);
      return false;
    }
  }

  Future<void> _handleReconnectRequest(
      Message message, PeerConnection peer) async {
    final senderId = message.meta['sender'] as String;
    final senderName = message.meta['senderName'] as String? ?? 'Unknown';
    final platform = message.meta['platform'] as String? ?? 'unknown';
    final challenge = message.meta['challenge'] as String;
    final tcpPort = message.meta['tcpPort'] as int? ?? 0;

    Log.i(_tag, '>>> Received reconnect REQUEST from $senderName ($senderId) tcpPort=$tcpPort');

    // Already connected to this peer? Ignore duplicate.
    if (_peers.containsKey(senderId)) {
      Log.i(_tag, 'Already connected to $senderId, ignoring duplicate reconnect request');
      await peer.send(Message.reject('Already connected'));
      return;
    }

    // Handle simultaneous reconnect: both sides try at the same time.
    // If we already have a pending outgoing reconnect to this device,
    // use device ID comparison as tiebreaker: higher ID becomes responder.
    final existingPending = _pendingReconnects[senderId];
    if (existingPending != null) {
      if (localDeviceId.compareTo(senderId) > 0) {
        // We have the higher ID — we become the responder.
        // Cancel our outgoing attempt and respond to theirs.
        Log.i(_tag, 'Simultaneous reconnect detected, we yield (higher ID = responder)');
        final oldPeer = existingPending.$1;
        oldPeer.close();
        _pendingReconnects.remove(senderId);
      } else {
        // We have the lower ID — we stay as initiator.
        // Ignore their request; they should respond to ours.
        Log.i(_tag, 'Simultaneous reconnect detected, we keep initiator role (lower ID)');
        return;
      }
    }

    // Look up session key for this device.
    if (secureStorage == null) {
      Log.w(_tag, 'No secure storage on this device — rejecting reconnect');
      await peer.send(Message.reject('No secure storage'));
      return;
    }

    final knownPeers = await secureStorage!.loadAllPairedPeers();
    Log.i(_tag, 'Known peers in storage: ${knownPeers.keys.toList()}');
    var known = knownPeers[senderId];
    String effectiveId = senderId;

    // Fallback: look up by IP if device ID changed (e.g. after reinstall).
    if (known == null) {
      Log.i(_tag, 'Device ID $senderId not found, trying IP lookup (${peer.ip})...');
      for (final entry in knownPeers.entries) {
        if (entry.value.$1.lastKnownIp == peer.ip) {
          Log.i(_tag, 'Found peer by IP match: old ID=${entry.key}, new ID=$senderId');
          known = entry.value;
          effectiveId = entry.key;
          break;
        }
      }
    }

    if (known == null) {
      Log.w(_tag, 'Reconnect from unknown device: $senderId (not in storage, no IP match)');
      await peer.send(Message.reject('Unknown device'));
      return;
    }
    Log.i(_tag, 'Found stored session key for $effectiveId, proceeding with auth');

    final sessionKey = known.$2;

    // If device ID changed, migrate storage now.
    if (effectiveId != senderId) {
      Log.i(_tag, 'Migrating device ID: $effectiveId → $senderId');
      peer.deviceName = senderName;
      peer.platform = platform;
      peer.remoteTcpPort = tcpPort;
      await _migrateDeviceId(effectiveId, senderId, peer, sessionKey);
    }

    // Prove we have the key: HMAC(sessionKey, challenge).
    final response = await _computeHmacBytes(sessionKey, utf8.encode(challenge));

    // Send our own challenge back for mutual auth.
    final ourChallenge = _generateNonce();

    peer.deviceName = senderName;
    peer.platform = platform;
    peer.remoteTcpPort = tcpPort;

    // Store temporarily to verify their response — use the real sender ID.
    _pendingReconnects[senderId] = (peer, ourChallenge, sessionKey);

    await peer.send(Message.reconnectConfirm(
      senderId: localDeviceId,
      senderName: localDeviceName,
      platform: localPlatform,
      tcpPort: localTcpPort,
      challengeResponse: response,
      challenge: ourChallenge,
    ));
  }

  Future<void> _handleReconnectConfirm(
      Message message, PeerConnection peer) async {
    final senderId = message.meta['sender'] as String;
    final senderName = message.meta['senderName'] as String? ?? 'Unknown';
    final platform = message.meta['platform'] as String? ?? 'unknown';
    final challengeResponse = message.meta['challengeResponse'] as String;
    final theirChallenge = message.meta['challenge'] as String?;
    final tcpPort = message.meta['tcpPort'] as int? ?? 0;

    Log.i(_tag, '>>> Received reconnect CONFIRM from $senderName ($senderId) tcpPort=$tcpPort');
    Log.i(_tag, 'Pending reconnects: ${_pendingReconnects.keys.toList()}');

    // Find our pending reconnect.
    final pending = _pendingReconnects.remove(senderId);
    if (pending == null) {
      Log.i(_tag, 'No pending reconnect by senderId=$senderId, checking by peer reference...');
      // Maybe we're the responder and this is the initiator's final confirm.
      // Check if senderId matches any pending reconnect by peer reference.
      String? matchedId;
      for (final entry in _pendingReconnects.entries) {
        if (entry.value.$1 == peer) {
          matchedId = entry.key;
          break;
        }
      }
      if (matchedId != null) {
        Log.i(_tag, 'Found pending reconnect by peer reference: stored=$matchedId, actual=$senderId');
        final p = _pendingReconnects.remove(matchedId)!;
        // Use the real sender ID, and migrate storage if ID changed.
        if (matchedId != senderId) {
          Log.i(_tag, 'Device ID changed: $matchedId → $senderId, migrating storage');
          await _migrateDeviceId(matchedId, senderId, peer, p.$3);
        }
        await _finalizeReconnect(
            senderId, peer, senderName, platform, p.$3, tcpPort);
        return;
      }

      Log.w(_tag, 'No pending reconnect for $senderId (neither by ID nor peer ref)');
      return;
    }

    final (_, ourChallenge, sessionKey) = pending;

    // Verify their response to our challenge.
    final expected =
        await _computeHmacBytes(sessionKey, utf8.encode(ourChallenge));
    if (challengeResponse != expected) {
      Log.w(_tag, 'Reconnect auth failed from $senderName');
      await peer.send(Message.reject('Auth failed'));
      peer.close();
      return;
    }

    // If they sent a challenge back, respond to it.
    if (theirChallenge != null) {
      final response =
          await _computeHmacBytes(sessionKey, utf8.encode(theirChallenge));
      await peer.send(Message.reconnectConfirm(
        senderId: localDeviceId,
        senderName: localDeviceName,
        platform: localPlatform,
        tcpPort: localTcpPort,
        challengeResponse: response,
        challenge: '', // No further challenge needed.
      ));
    }

    await _finalizeReconnect(
        senderId, peer, senderName, platform, sessionKey, tcpPort);
  }

  Future<void> _finalizeReconnect(String deviceId, PeerConnection peer,
      String name, String platform, List<int> sessionKey, int remoteTcpPort) async {
    peer.deviceName = name;
    peer.platform = platform;
    peer.sessionKey = sessionKey;
    peer.remoteTcpPort = remoteTcpPort;
    peer.state = PeerState.paired;
    _peers[deviceId] = peer;

    // Update stored IP/port with the remote device's TCP server port.
    if (remoteTcpPort > 0) {
      await secureStorage?.updatePeerAddress(deviceId, peer.ip, remoteTcpPort);
    }

    onPeerPaired?.call(deviceId, name, platform, peer.ip);
    Log.i(_tag, 'Reconnected with $name ($deviceId)');
  }

  /// Migrate storage when a peer's device ID changes (e.g. after reinstall).
  Future<void> _migrateDeviceId(
      String oldId, String newId, PeerConnection peer, List<int> sessionKey) async {
    if (secureStorage == null) return;
    // Remove old entry.
    await secureStorage!.removePairedPeer(oldId);
    // Save under new ID (savePairedPeer handles dedup by IP).
    await secureStorage!.savePairedPeer(
      PairedPeerInfo(
        deviceId: newId,
        deviceName: peer.deviceName,
        platform: peer.platform,
        lastKnownIp: peer.ip,
        lastKnownPort: peer.remoteTcpPort ?? peer.port,
      ),
      sessionKey,
    );
    // Also update _peers map.
    _peers.remove(oldId);
  }

  void _savePeerToStorage(String deviceId, PeerConnection peer) {
    if (secureStorage == null || peer.sessionKey == null) return;
    final port = peer.remoteTcpPort ?? peer.port;
    Log.i(_tag, 'Saving peer $deviceId to storage (${peer.ip}:$port)');
    secureStorage!.savePairedPeer(
      PairedPeerInfo(
        deviceId: deviceId,
        deviceName: peer.deviceName,
        platform: peer.platform,
        lastKnownIp: peer.ip,
        lastKnownPort: port,
      ),
      peer.sessionKey!,
    );
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
