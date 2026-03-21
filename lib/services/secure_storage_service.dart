import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../utils/logger.dart';

const _tag = 'SecureStorage';

/// Info about a previously paired peer, for reconnection.
class PairedPeerInfo {
  final String deviceId;
  final String deviceName;
  final String platform;
  final String lastKnownIp;
  final int lastKnownPort;

  PairedPeerInfo({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.lastKnownIp,
    required this.lastKnownPort,
  });

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'platform': platform,
        'lastKnownIp': lastKnownIp,
        'lastKnownPort': lastKnownPort,
      };

  factory PairedPeerInfo.fromJson(Map<String, dynamic> json) => PairedPeerInfo(
        deviceId: json['deviceId'] as String,
        deviceName: json['deviceName'] as String? ?? 'Unknown',
        platform: json['platform'] as String? ?? 'unknown',
        lastKnownIp: json['lastKnownIp'] as String,
        lastKnownPort: json['lastKnownPort'] as int? ?? 0,
      );
}

/// Manages secure storage of session keys and paired peer info.
class SecureStorageService {
  static const _peerListKey = 'paired_peers';
  static const _sessionKeyPrefix = 'session_key_';

  final FlutterSecureStorage _storage;

  SecureStorageService()
      : _storage = const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
          mOptions: MacOsOptions(
            useDataProtectionKeyChain: false,
          ),
        );

  /// Save a paired peer's info and session key.
  Future<void> savePairedPeer(PairedPeerInfo info, List<int> sessionKey) async {
    try {
      Log.i(_tag, 'Saving peer: ${info.deviceName} (${info.deviceId}) at ${info.lastKnownIp}:${info.lastKnownPort}');

      // Save session key separately.
      final keyB64 = base64Encode(sessionKey);
      await _storage.write(
        key: '$_sessionKeyPrefix${info.deviceId}',
        value: keyB64,
      );

      // Verify key was written.
      final verifyKey = await _storage.read(key: '$_sessionKeyPrefix${info.deviceId}');
      Log.i(_tag, 'Session key saved: ${verifyKey != null ? 'YES' : 'NO (FAILED!)'}');

      // Update peer list.
      final peers = await _loadPeerMap();
      peers[info.deviceId] = info.toJson();
      final peerJson = jsonEncode(peers);
      await _storage.write(key: _peerListKey, value: peerJson);

      // Verify peer list was written.
      final verifyPeers = await _storage.read(key: _peerListKey);
      Log.i(_tag, 'Peer list saved: ${verifyPeers != null ? 'YES (${verifyPeers.length} bytes)' : 'NO (FAILED!)'}');

      Log.i(_tag, 'Saved peer: ${info.deviceName} (${info.deviceId})');
    } catch (e) {
      Log.e(_tag, 'Failed to save peer', e);
    }
  }

  /// Update a peer's last known IP and port.
  Future<void> updatePeerAddress(
      String deviceId, String ip, int port) async {
    try {
      final peers = await _loadPeerMap();
      if (peers.containsKey(deviceId)) {
        peers[deviceId]!['lastKnownIp'] = ip;
        peers[deviceId]!['lastKnownPort'] = port;
        await _storage.write(key: _peerListKey, value: jsonEncode(peers));
      }
    } catch (e) {
      Log.e(_tag, 'Failed to update peer address', e);
    }
  }

  /// Load all paired peers with their session keys.
  Future<Map<String, (PairedPeerInfo, List<int>)>> loadAllPairedPeers() async {
    final result = <String, (PairedPeerInfo, List<int>)>{};
    try {
      final peers = await _loadPeerMap();
      Log.i(_tag, 'Raw peer map has ${peers.length} entries: ${peers.keys.toList()}');

      for (final entry in peers.entries) {
        final info = PairedPeerInfo.fromJson(
            entry.value as Map<String, dynamic>);
        final keyB64 = await _storage.read(
            key: '$_sessionKeyPrefix${info.deviceId}');
        if (keyB64 != null) {
          final sessionKey = base64Decode(keyB64);
          result[info.deviceId] = (info, sessionKey);
          Log.i(_tag, 'Loaded peer: ${info.deviceName} (${info.deviceId}) at ${info.lastKnownIp}:${info.lastKnownPort}');
        } else {
          Log.w(_tag, 'No session key found for ${info.deviceName} (${info.deviceId})');
        }
      }

      Log.i(_tag, 'Loaded ${result.length} paired peers');
    } catch (e) {
      Log.e(_tag, 'Failed to load peers', e);
    }
    return result;
  }

  /// Remove a paired peer (unpair).
  Future<void> removePairedPeer(String deviceId) async {
    try {
      await _storage.delete(key: '$_sessionKeyPrefix$deviceId');

      final peers = await _loadPeerMap();
      peers.remove(deviceId);
      await _storage.write(key: _peerListKey, value: jsonEncode(peers));

      Log.i(_tag, 'Removed peer: $deviceId');
    } catch (e) {
      Log.e(_tag, 'Failed to remove peer', e);
    }
  }

  /// Clear all stored data.
  Future<void> clearAll() async {
    try {
      await _storage.deleteAll();
      Log.i(_tag, 'All data cleared');
    } catch (e) {
      Log.e(_tag, 'Failed to clear', e);
    }
  }

  Future<Map<String, dynamic>> _loadPeerMap() async {
    try {
      final raw = await _storage.read(key: _peerListKey);
      if (raw != null && raw.isNotEmpty) {
        return Map<String, dynamic>.from(jsonDecode(raw) as Map);
      }
    } catch (e) {
      debugPrint('[$_tag] Failed to parse peer list: $e');
    }
    return {};
  }
}
