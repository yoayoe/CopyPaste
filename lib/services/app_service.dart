import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../core/discovery/discovery_service.dart';
import '../core/network/tcp_server.dart';
import '../core/web_server/http_server.dart';
import '../services/clipboard_service.dart';
import '../utils/constants.dart';
import '../utils/logger.dart';
import '../utils/network_utils.dart';

const _tag = 'AppService';

/// Central service that orchestrates all components.
class AppService {
  final String _deviceId = const Uuid().v4();
  late final String _deviceName;
  late final String _webClientPath;

  DiscoveryService? discovery;
  late final TcpServer tcpServer;
  late final EmbeddedWebServer webServer;
  late final ClipboardService clipboard;

  String get deviceId => _deviceId;
  String get webUrl => 'http://$localIp:${webServer.port}';
  String localIp = '127.0.0.1';

  /// Clipboard history for syncing to new web clients.
  final List<Map<String, dynamic>> _clipboardHistory = [];

  /// Callbacks for UI updates.
  void Function(String deviceId, String deviceName, String platform, String ip)?
      onDeviceFound;
  void Function(String deviceId)? onDeviceLost;
  /// Called when web client list changes (connect/disconnect/name update).
  void Function(List<({String name, String ip})> clients)? onWebClientsChanged;
  void Function(String content, String? sourceDeviceId, String? sourceDeviceName)?
      onClipboardReceived;

  AppService();

  Future<void> start(String webClientPath) async {
    _webClientPath = webClientPath;
    _deviceName = Platform.localHostname;
    localIp = await getLocalIpAddress();

    Log.i(_tag, 'Device: $_deviceName ($_deviceId)');
    Log.i(_tag, 'Local IP: $localIp');

    // 1. Start TCP server (desktop ↔ desktop).
    tcpServer = TcpServer(onMessage: (message, remoteIp) {
      Log.d(_tag, 'TCP message: ${message.type.name} from $remoteIp');
      // TODO: Handle incoming TCP messages.
    });
    final tcpPort = await tcpServer.start();

    // 2. Start web server (desktop ↔ mobile).
    webServer = EmbeddedWebServer(webClientPath: _webClientPath);
    final webPort =
        await webServer.start(port: await findAvailablePort(kWebPortMin, kWebPortMax));

    // Wire WebSocket messages from mobile clients.
    webServer.onMessage.listen(_handleWebSocketMessage);

    // When a mobile client connects/disconnects/identifies, update everything.
    webServer.onClientChanged = (clients) {
      _broadcastDeviceList();
      final clientList = clients
          .map((c) => (name: c.name, ip: c.ip))
          .toList();
      onWebClientsChanged?.call(clientList);
      // Send clipboard history to connected clients.
      if (clients.isNotEmpty) {
        webServer.broadcast('clipboard:history', {'items': _clipboardHistory});
      }
    };

    // 3. Start clipboard monitoring.
    clipboard = ClipboardService(onClipboardChanged: _onClipboardChanged);
    clipboard.startMonitoring();

    // 4. Start mDNS discovery (macOS only — nsd plugin doesn't support Linux).
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
  }

  void _addToHistory(Map<String, dynamic> item) {
    _clipboardHistory.insert(0, item);
    if (_clipboardHistory.length > 50) _clipboardHistory.removeLast();
  }

  void _onClipboardChanged(String content) {
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

    // TODO: Send to paired desktops via TCP.
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
          clipboard.write(content);
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

    // TODO: Add other discovered desktops from discovery service.

    webServer.broadcast('device:list', {
      'devices': devices,
      'webClients': webServer.clients.length,
    });
  }

  Future<void> stop() async {
    clipboard.dispose();
    await discovery?.dispose();
    await tcpServer.stop();
    await webServer.stop();
    Log.i(_tag, 'Stopped');
  }
}
