import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../main.dart';
import '../../models/device.dart';
import '../../providers/device_provider.dart';
import '../../providers/clipboard_provider.dart';
import '../../providers/web_client_provider.dart';
import 'widgets/device_list.dart';
import 'widgets/clipboard_history.dart';
import 'widgets/qr_code_panel.dart';
import 'widgets/connect_dialog.dart';
import 'widgets/pin_dialog.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _selectedTab = 0;
  bool _callbacksWired = false;

  @override
  Widget build(BuildContext context) {
    final ready = ref.watch(servicesReadyProvider);
    final devices = ref.watch(deviceProvider);
    final clipboardItems = ref.watch(clipboardProvider);
    final webClients = ref.watch(webClientsProvider);

    if (ready && !_callbacksWired) {
      _callbacksWired = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _wireCallbacks());
    }

    // Build combined device list: discovered desktops + paired desktops + web clients.
    final allDevices = <Device>[...devices];
    for (var i = 0; i < webClients.length; i++) {
      final client = webClients[i];
      allDevices.add(Device(
        id: 'web-client-$i',
        name: client.name,
        platform: 'browser',
        ip: client.ip,
        tcpPort: 0,
        webPort: 0,
        protocolVersion: 1,
      ));
    }

    final appService = ref.read(appServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('CopyPaste'),
        actions: [
          if (ready) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Center(
                child: SelectableText(
                  'TCP: ${appService.tcpPort}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Center(
                child: Text(
                  appService.webUrl,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ),
            ),
          ],
          IconButton(
            icon: const Icon(Icons.qr_code),
            tooltip: 'Show QR for mobile',
            onPressed: () {
              if (ready) {
                _showQrCode(context);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Services still starting...')),
                );
              }
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedTab,
        children: [
          DeviceList(
            devices: allDevices,
            onConnectPressed: ready ? () => _showConnectDialog(context) : null,
          ),
          ClipboardHistory(items: clipboardItems),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) {
          setState(() => _selectedTab = index);
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.devices),
            label: 'Devices (${allDevices.length})',
          ),
          NavigationDestination(
            icon: const Icon(Icons.content_paste),
            label: 'Clipboard (${clipboardItems.length})',
          ),
        ],
      ),
    );
  }

  void _wireCallbacks() {
    final appService = ref.read(appServiceProvider);

    appService.onDeviceFound = (id, name, platform, ip) {
      ref.read(deviceProvider.notifier).addOrUpdate(
            Device(
              id: id,
              name: name,
              platform: platform,
              ip: ip,
              tcpPort: 0,
              webPort: 0,
              protocolVersion: 1,
            ),
          );
    };

    appService.onDeviceLost = (id) {
      ref.read(deviceProvider.notifier).remove(id);
    };

    appService.onClipboardReceived = (content, sourceId, sourceName) {
      ref.read(clipboardProvider.notifier).add(
            content,
            sourceDeviceId: sourceId,
            sourceDeviceName: sourceName,
          );
    };

    appService.onWebClientsChanged = (clients) {
      ref.read(webClientsProvider.notifier).state = clients
          .map((c) => WebClientState(name: c.name, ip: c.ip))
          .toList();
    };

    // Pairing callbacks.
    appService.onPairRequestReceived = (deviceId, name, platform, pin) {
      _showPinDisplayDialog(deviceId, name, platform, pin);
    };

    appService.onPairPinRequired = (deviceId, name, platform) {
      _showPinInputDialog(deviceId, name, platform);
    };

    appService.onPeerPaired = (deviceId, name, platform, ip) {
      ref.read(deviceProvider.notifier).addOrUpdate(
            Device(
              id: deviceId,
              name: name,
              platform: platform,
              ip: ip,
              tcpPort: 0,
              webPort: 0,
              protocolVersion: 2,
              pairingState: PairingState.paired,
            ),
          );
      // Dismiss any open pairing dialogs.
      Navigator.of(context).popUntil((route) => route.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Paired with $name')),
      );
    };

    appService.onPeerDisconnected = (deviceId) {
      ref.read(deviceProvider.notifier).remove(deviceId);
    };

    appService.onPairFailed = (deviceId, reason) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pairing failed: $reason')),
      );
    };
  }

  void _showConnectDialog(BuildContext context) {
    final appService = ref.read(appServiceProvider);
    showDialog(
      context: context,
      builder: (_) => ConnectDialog(
        defaultPort: appService.tcpPort,
        onConnect: (ip, port) => appService.connectToDesktop(ip, port),
      ),
    );
  }

  void _showPinDisplayDialog(String deviceId, String name, String platform, String pin) {
    final appService = ref.read(appServiceProvider);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PinDisplayDialog(
        deviceName: name,
        platform: platform,
        pin: pin,
        onApprove: () {
          Navigator.of(context).pop();
          appService.approvePairing(deviceId);
        },
        onReject: () {
          Navigator.of(context).pop();
          appService.rejectPairing(deviceId);
        },
      ),
    );
  }

  void _showPinInputDialog(String deviceId, String name, String platform) {
    final appService = ref.read(appServiceProvider);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PinInputDialog(
        deviceName: name,
        platform: platform,
        onSubmit: (pin) {
          Navigator.of(context).pop();
          appService.submitPairingPin(deviceId, pin);
        },
        onCancel: () {
          Navigator.of(context).pop();
        },
      ),
    );
  }

  void _showQrCode(BuildContext context) {
    final appService = ref.read(appServiceProvider);
    showDialog(
      context: context,
      builder: (_) => QrCodePanel(url: appService.webUrl),
    );
  }
}
