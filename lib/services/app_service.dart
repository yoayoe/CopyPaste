import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../core/discovery/discovery_service.dart';
import '../core/network/tcp_server.dart';
import '../core/web_server/http_server.dart';
import '../models/session_info.dart';
import '../models/transfer_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/clipboard_service.dart';
import '../services/file_transfer_service.dart';
import '../services/pairing_service.dart';
import '../services/secure_storage_service.dart';
import '../utils/constants.dart';
import '../utils/logger.dart';
import '../utils/network_utils.dart';

const _tag = 'AppService';

/// Central service that orchestrates all components.
class AppService {
  late final String _deviceId;
  late final String _deviceName;
  late final String _webClientPath;
  late final SecureStorageService secureStorage;

  DiscoveryService? discovery;
  late final TcpServer tcpServer;
  late final EmbeddedWebServer webServer;
  late final ClipboardService clipboard;
  late final PairingService pairingService;
  late final FileTransferService fileTransfer;

  String get deviceId => _deviceId;
  String get deviceName => _deviceName;
  String get webUrl => 'http://$localIp:${webServer.port}';
  int get tcpPort => tcpServer.port;
  String localIp = '127.0.0.1';

  /// Flag to suppress local clipboard detection after writing from remote.
  bool _writingFromRemote = false;

  /// Clipboard history for syncing to new web clients.
  final List<Map<String, dynamic>> _clipboardHistory = [];

  /// Transfer history for syncing to new/reconnecting web clients.
  final List<Map<String, dynamic>> _transferHistory = [];

  // --- Callbacks for UI ---
  void Function(String deviceId, String deviceName, String platform, String ip)?
      onDeviceFound;
  void Function(String deviceId)? onDeviceLost;
  void Function(List<({String name, String ip})> clients)? onWebClientsChanged;
  void Function(String content, String? sourceDeviceId, String? sourceDeviceName)?
      onClipboardReceived;
  void Function(Uint8List imageData, String? sourceDeviceId,
      String? sourceDeviceName, String? downloadUrl)? onImageClipboardReceived;

  /// Pairing callbacks.
  void Function(String deviceId, String deviceName, String platform, String pin)?
      onPairRequestReceived;
  void Function(String deviceId, String deviceName, String platform)?
      onPairPinRequired;
  void Function(String deviceId, String deviceName, String platform, String ip)?
      onPeerPaired;
  void Function(String deviceId)? onPeerDisconnected;
  void Function(String deviceId, String reason)? onPairFailed;

  /// Called when a mobile web client needs PIN verification.
  void Function(String clientIp, String clientName, String pin)? onWebPinGenerated;

  /// Called when a mobile web client successfully authenticates.
  void Function(String clientIp, String clientName)? onWebClientAuthenticated;

  /// File transfer callbacks.
  void Function(TransferTask task)? onTransferProgress;
  void Function(TransferTask task, String filePath)? onTransferComplete;
  void Function(TransferTask task, String error)? onTransferFailed;

  /// Stream-based transfer updates (more reliable than callbacks).
  final StreamController<TransferTask> _transferStream =
      StreamController<TransferTask>.broadcast();
  Stream<TransferTask> get transferStream => _transferStream.stream;

  AppService();

  Future<void> start(String webClientPath) async {
    _webClientPath = webClientPath;
    _deviceName = Platform.localHostname;
    localIp = await getLocalIpAddress();

    // Persist device ID across restarts.
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString('device_id') ?? const Uuid().v4();
    await prefs.setString('device_id', _deviceId);

    // Initialize secure storage.
    secureStorage = SecureStorageService();

    Log.i(_tag, 'Device: $_deviceName ($_deviceId)');
    Log.i(_tag, 'Local IP: $localIp');

    // 1. Start TCP server (desktop ↔ desktop) on a stable port.
    tcpServer = TcpServer(onConnection: (socket) {
      // Hand off to pairing service.
      pairingService.handleIncomingConnection(socket);
    });
    final preferredTcpPort = await findAvailablePort(kTcpPortMin, kTcpPortMax);
    final tcpPort = await tcpServer.start(port: preferredTcpPort);

    // 2. Initialize pairing service.
    pairingService = PairingService(
      localDeviceId: _deviceId,
      localDeviceName: _deviceName,
      localPlatform: Platform.operatingSystem,
      localTcpPort: tcpPort,
      localWebPort: 0, // Will update after web server starts.
      secureStorage: secureStorage,
    );
    _wirePairingCallbacks();

    // 3. Start web server (desktop ↔ mobile).
    webServer = EmbeddedWebServer(webClientPath: _webClientPath);
    final webPort =
        await webServer.start(port: await findAvailablePort(kWebPortMin, kWebPortMax));

    // Wire WebSocket messages from mobile clients.
    webServer.onMessage.listen(_handleWebSocketMessage);

    // Wire mobile PIN verification callback.
    webServer.onPinGenerated = (clientIp, clientName, pin) {
      onWebPinGenerated?.call(clientIp, clientName, pin);
    };
    webServer.onClientAuthenticated = (clientIp, clientName) {
      onWebClientAuthenticated?.call(clientIp, clientName);
    };

    // When a mobile client connects/disconnects/identifies, update everything.
    webServer.onClientChanged = (clients) {
      _broadcastDeviceList();
      final clientList = clients
          .map((c) => (name: c.name, ip: c.ip))
          .toList();
      onWebClientsChanged?.call(clientList);
      // Send clipboard and transfer history to connected clients.
      if (clients.isNotEmpty) {
        webServer.broadcast('clipboard:history', {'items': _clipboardHistory});
        if (_transferHistory.isNotEmpty) {
          webServer.broadcast('transfer:history', {'items': _transferHistory});
        }
      }
    };

    // 4. Start clipboard monitoring (text + image).
    clipboard = ClipboardService(
      onClipboardChanged: _onClipboardChanged,
      onImageClipboardChanged: _onImageClipboardChanged,
    );
    clipboard.startMonitoring();

    // 5. Initialize file transfer service.
    fileTransfer = FileTransferService();
    await fileTransfer.init();
    _wireFileTransferCallbacks();

    // Wire file upload from mobile.
    webServer.onFileUploaded = (fileId, filename, size, checksum, savedPath) {
      Log.i(_tag, 'File uploaded from mobile: $filename ($size bytes) → $savedPath');
      final task = TransferTask(
        id: fileId,
        filename: filename,
        mimeType: 'application/octet-stream',
        totalBytes: size,
        transferredBytes: size,
        status: TransferStatus.completed,
        direction: TransferDirection.receive,
        deviceId: 'mobile',
        deviceName: 'Mobile Browser',
        startedAt: DateTime.now(),
        filePath: savedPath,
      );
      _transferStream.add(task);
      onTransferComplete?.call(task, savedPath);

      // Also make the uploaded file available for other mobile clients to download.
      final downloadId = webServer.addFileForDownload(savedPath, filename, checksum);
      _broadcastTransferComplete({
        'id': downloadId,
        'downloadId': downloadId,
        'filename': filename,
        'size': size,
        'status': 'completed',
      });
    };

    // 6. Start mDNS discovery (macOS only — nsd plugin doesn't support Linux).
    if (Platform.isMacOS) {
      discovery = DiscoveryService(
        onDeviceFound: (device) {
          onDeviceFound?.call(device.id, device.name, device.platform, device.ip);
        },
        onDeviceLost: (id) {
          onDeviceLost?.call(id);
        },
      );
      await discovery!.advertise(
        deviceId: _deviceId,
        deviceName: _deviceName,
        tcpPort: tcpPort,
        webPort: webPort,
      );
      await discovery!.startBrowsing(_deviceId);
    } else {
      debugPrint('[CopyPaste] mDNS discovery skipped (not supported on ${Platform.operatingSystem})');
    }

    Log.i(_tag, 'Started — TCP: $tcpPort, Web: $webPort');
    Log.i(_tag, 'Mobile URL: $webUrl');

    // 7. Reconnect to previously paired peers (with delay for peer startup).
    Future.delayed(const Duration(seconds: 3), () {
      pairingService.reconnectToKnownPeers();
    });
  }

  void _wirePairingCallbacks() {
    pairingService.onPairRequestReceived = (deviceId, name, platform, pin) {
      onPairRequestReceived?.call(deviceId, name, platform, pin);
    };
    pairingService.onPairPinRequired = (deviceId, name, platform) {
      onPairPinRequired?.call(deviceId, name, platform);
    };
    pairingService.onPeerPaired = (deviceId, name, platform, ip) {
      onPeerPaired?.call(deviceId, name, platform, ip);
      _broadcastDeviceList();
    };
    pairingService.onPeerDisconnected = (deviceId) {
      onPeerDisconnected?.call(deviceId);
      _broadcastDeviceList();
    };
    pairingService.onPairFailed = (deviceId, reason) {
      onPairFailed?.call(deviceId, reason);
    };
    pairingService.onFileReceived = (message) {
      fileTransfer.handleFileMessage(message);
    };
    pairingService.onImageClipboardReceived =
        (imageData, mimeType, sourceId, sourceName) async {
      Log.d(_tag, 'Image from paired desktop: $sourceName (${imageData.length} bytes)');
      _writingFromRemote = true;
      await clipboard.writeImage(imageData);
      // Keep flag for a bit to suppress re-detection.
      Future.delayed(const Duration(seconds: 3), () => _writingFromRemote = false);

      // Save to temp file for web serving.
      final downloadId = await _saveImageForWeb(imageData);

      final item = {
        'id': const Uuid().v4(),
        'type': 'image',
        'content': '[Image: ${_formatSize(imageData.length)}]',
        'sourceDeviceId': sourceId,
        'sourceDeviceName': sourceName,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        if (downloadId != null) 'downloadId': downloadId,
      };
      _addToHistory(item);
      webServer.broadcast('clipboard:update', item);
      onImageClipboardReceived?.call(imageData, sourceId, sourceName, downloadId);
    };

    pairingService.onClipboardReceived = (content, sourceId, sourceName) {
      Log.d(_tag, 'Clipboard from paired desktop: $sourceName (${content.length} chars)');
      _writingFromRemote = true;
      clipboard.write(content);
      Future.delayed(const Duration(seconds: 3), () => _writingFromRemote = false);
      onClipboardReceived?.call(content, sourceId, sourceName);

      final item = {
        'id': const Uuid().v4(),
        'type': 'text',
        'content': content,
        'sourceDeviceId': sourceId,
        'sourceDeviceName': sourceName,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      _addToHistory(item);

      // Also push to mobile browsers.
      webServer.broadcast('clipboard:update', item);
    };
  }

  /// Connect to a remote desktop by IP.
  Future<void> connectToDesktop(String ip, int port) async {
    await pairingService.initiateConnection(ip, port);
  }

  /// Submit PIN for ongoing pairing (initiator side).
  Future<void> submitPairingPin(String deviceId, String pin) async {
    await pairingService.submitPinAndDeriveKey(deviceId, pin);
  }

  /// Approve pairing request (responder side).
  Future<void> approvePairing(String deviceId) async {
    await pairingService.approvePairing(deviceId);
  }

  /// Reject pairing request (responder side).
  Future<void> rejectPairing(String deviceId) async {
    await pairingService.rejectPairing(deviceId);
  }

  /// Disconnect a paired desktop.
  Future<void> disconnectPeer(String deviceId) async {
    await pairingService.disconnectPeer(deviceId);
  }

  /// Active web client sessions.
  List<SessionInfo> get webClientSessions => webServer.activeSessions;

  /// Revoke a specific web client session.
  void revokeWebClientSession(String token) => webServer.revokeSession(token);

  /// Revoke all web client sessions.
  void revokeAllWebClientSessions() => webServer.revokeAllSessions();

  /// Send a file to a paired desktop.
  Future<void> sendFileToPeer(String filePath, String deviceId) async {
    final peer = pairingService.peers
        .where((p) => p.deviceId == deviceId)
        .firstOrNull;
    if (peer == null) {
      Log.w(_tag, 'Peer $deviceId not found for file transfer');
      return;
    }
    await fileTransfer.sendFile(filePath, peer,
        senderId: _deviceId, senderName: _deviceName);
  }

  /// Send a file to all paired desktops.
  Future<void> sendFileToAllPeers(String filePath) async {
    for (final peer in pairingService.peers) {
      await fileTransfer.sendFile(filePath, peer,
          senderId: _deviceId, senderName: _deviceName);
    }
  }

  /// Make a file available for mobile download and notify web clients.
  void shareFileToMobile(String filePath, String filename, int size) {
    final fileId = webServer.addFileForDownload(filePath, filename, '');
    _broadcastTransferComplete({
      'id': fileId,
      'downloadId': fileId,
      'filename': filename,
      'size': size,
      'status': 'completed',
    });
  }

  void _wireFileTransferCallbacks() {
    fileTransfer.onTransferProgress = (task) {
      _transferStream.add(task);
      onTransferProgress?.call(task);
    };
    fileTransfer.onTransferComplete = (task, path) {
      final updatedTask = task.filePath != null && task.filePath!.isNotEmpty
          ? task
          : task.copyWith(filePath: path);
      _transferStream.add(updatedTask);
      onTransferComplete?.call(updatedTask, path);

      // Register received files for mobile download.
      if (task.direction == TransferDirection.receive && path.isNotEmpty) {
        final fileId = webServer.addFileForDownload(path, task.filename, '');
        _broadcastTransferComplete({
          'id': fileId,
          'downloadId': fileId,
          'filename': task.filename,
          'size': task.totalBytes,
          'status': 'completed',
        });
        Log.i(_tag, 'File available for mobile download: ${task.filename} (id: $fileId)');
      }
    };
    fileTransfer.onTransferFailed = (task, error) {
      final failedTask = task.copyWith(status: TransferStatus.failed, error: error);
      _transferStream.add(failedTask);
      onTransferFailed?.call(task, error);
    };
  }

  void _addToHistory(Map<String, dynamic> item) {
    _clipboardHistory.insert(0, item);
    if (_clipboardHistory.length > 50) _clipboardHistory.removeLast();
  }

  /// Record a completed transfer and broadcast to mobile clients.
  void _broadcastTransferComplete(Map<String, dynamic> data) {
    _transferHistory.insert(0, data);
    if (_transferHistory.length > 50) _transferHistory.removeLast();
    webServer.broadcast('transfer:complete', data);
  }

  Future<void> _onImageClipboardChanged(Uint8List imageData) async {
    if (_writingFromRemote) {
      Log.d(_tag, 'Image clipboard changed (from remote, ignoring): ${imageData.length} bytes');
      return;
    }
    Log.d(_tag, 'Image clipboard changed: ${imageData.length} bytes');

    // Save to temp file for web serving.
    final downloadId = await _saveImageForWeb(imageData);

    final item = {
      'id': const Uuid().v4(),
      'type': 'image',
      'content': '[Image: ${_formatSize(imageData.length)}]',
      'sourceDeviceId': _deviceId,
      'sourceDeviceName': _deviceName,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      if (downloadId != null) 'downloadId': downloadId,
    };
    _addToHistory(item);

    // Push to mobile browsers.
    webServer.broadcast('clipboard:update', item);

    onImageClipboardReceived?.call(imageData, null, _deviceName, downloadId);

    // Send to paired desktops via TCP.
    pairingService.broadcastImage(imageData, _deviceId, _deviceName);
  }

  /// Save image bytes to temp file and register for web download.
  Future<String?> _saveImageForWeb(Uint8List imageData) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final fileName = 'clipboard_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('${tempDir.path}/copypaste_images/$fileName');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(imageData);
      return webServer.addFileForDownload(file.path, fileName, '');
    } catch (e) {
      Log.e(_tag, 'Failed to save image for web', e);
      return null;
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }

  void _onClipboardChanged(String content) {
    if (_writingFromRemote) {
      Log.d(_tag, 'Clipboard changed (from remote, ignoring): ${content.length} chars');
      return;
    }
    Log.d(_tag, 'Clipboard changed: ${content.length} chars');

    final item = {
      'id': const Uuid().v4(),
      'type': 'text',
      'content': content,
      'sourceDeviceId': _deviceId,
      'sourceDeviceName': _deviceName,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    _addToHistory(item);

    // Push to all connected mobile browsers.
    webServer.broadcast('clipboard:update', item);

    onClipboardReceived?.call(content, null, _deviceName);

    // Send to paired desktops via TCP.
    pairingService.broadcastClipboard(content, _deviceId, _deviceName);
  }

  void _handleWebSocketMessage(Map<String, dynamic> msg) {
    final event = msg['event'] as String?;
    final data = msg['data'] as Map<String, dynamic>?;

    if (event == null || data == null) return;

    switch (event) {
      case 'clipboard:send':
        final content = data['content'] as String?;
        if (content != null && content.isNotEmpty) {
          Log.d(_tag, 'Clipboard from mobile: ${content.length} chars');
          _writingFromRemote = true;
          clipboard.write(content);
          Future.delayed(const Duration(seconds: 3), () => _writingFromRemote = false);
          onClipboardReceived?.call(content, 'mobile', 'Mobile Browser');

          final item = {
            'id': const Uuid().v4(),
            'type': 'text',
            'content': content,
            'sourceDeviceId': 'mobile',
            'sourceDeviceName': 'Mobile Browser',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          };
          _addToHistory(item);

          // Broadcast to other mobile clients.
          webServer.broadcast('clipboard:update', item);

          // Also send to paired desktops.
          pairingService.broadcastClipboard(content, 'mobile', 'Mobile Browser');
        }
        break;

      case 'clipboard:fetch':
        clipboard.read().then((content) {
          webServer.broadcast('clipboard:update', {
            'id': const Uuid().v4(),
            'type': 'text',
            'content': content,
            'sourceDeviceId': _deviceId,
            'sourceDeviceName': _deviceName,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          });
        });
        break;
    }
  }

  /// Broadcast current device list to all web clients.
  void _broadcastDeviceList() {
    final devices = <Map<String, dynamic>>[
      // This desktop itself.
      {
        'id': _deviceId,
        'name': _deviceName,
        'platform': Platform.operatingSystem,
        'ip': localIp,
      },
    ];

    // Add paired desktops.
    for (final peer in pairingService.peers) {
      devices.add({
        'id': peer.deviceId,
        'name': peer.deviceName,
        'platform': peer.platform,
        'ip': peer.ip,
      });
    }

    webServer.broadcast('device:list', {
      'devices': devices,
      'webClients': webServer.clients.length,
    });
  }

  Future<void> stop() async {
    clipboard.dispose();
    fileTransfer.dispose();
    await _transferStream.close();
    await pairingService.disconnectAll();
    await discovery?.dispose();
    await tcpServer.stop();
    await webServer.stop();
    Log.i(_tag, 'Stopped');
  }
}
