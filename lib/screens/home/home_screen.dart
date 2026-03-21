import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../main.dart';
import '../../models/device.dart';
import '../../models/transfer_task.dart';
import '../../providers/device_provider.dart';
import '../../providers/clipboard_provider.dart';
import '../../providers/transfer_provider.dart';
import '../../providers/web_client_provider.dart';
import 'widgets/device_list.dart';
import 'widgets/clipboard_history.dart';
import 'widgets/transfer_list.dart';
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
  StreamSubscription<dynamic>? _transferSub;

  @override
  void dispose() {
    _transferSub?.cancel();
    super.dispose();
  }

  void _listenTransferStream() {
    final appService = ref.read(appServiceProvider);
    _transferSub?.cancel();
    _transferSub = appService.transferStream.listen((task) {
      if (!mounted) return;
      ref.read(transferProvider.notifier).addOrUpdate(task);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ready = ref.watch(servicesReadyProvider);
    final devices = ref.watch(deviceProvider);
    final clipboardItems = ref.watch(clipboardProvider);
    final transfers = ref.watch(transferProvider);
    final webClients = ref.watch(webClientsProvider);

    if (ready && !_callbacksWired) {
      _callbacksWired = true;
      // Listen to transfer stream immediately — no frame delay.
      _listenTransferStream();
      WidgetsBinding.instance.addPostFrameCallback((_) => _wireCallbacks());
    }

    // Build combined device list: discovered desktops + paired desktops + web clients.
    final allDevices = <Device>[...devices];
    for (final client in webClients) {
      allDevices.add(Device(
        id: client.sessionToken ?? 'web-${client.ip}',
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
            onDisconnect: ready ? (deviceId) => _disconnectDevice(deviceId) : null,
          ),
          ClipboardHistory(items: clipboardItems),
          TransferList(transfers: transfers),
        ],
      ),
      floatingActionButton: _selectedTab == 2 && ready
          ? FloatingActionButton(
              onPressed: () => _pickAndSendFile(context),
              tooltip: 'Send file',
              child: const Icon(Icons.attach_file),
            )
          : null,
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
          NavigationDestination(
            icon: const Icon(Icons.folder),
            label: 'Files (${transfers.length})',
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
      // Use session info for richer client state.
      final sessions = appService.webClientSessions;
      ref.read(webClientsProvider.notifier).state = sessions
          .map((s) => WebClientState(
                name: s.clientName,
                ip: s.clientIp,
                sessionToken: s.token,
                connectedAt: s.createdAt,
                lastSeenAt: s.lastSeenAt,
              ))
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

    // Mobile web client PIN callback.
    appService.onWebPinGenerated = (clientIp, clientName, pin) {
      _showMobilePinDialog(clientIp, clientName, pin);
    };

    // Auto-close PIN dialog when mobile client authenticates.
    appService.onWebClientAuthenticated = (clientIp, clientName) {
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$clientName connected')),
      );
    };

    // File transfer callbacks — only for snackbar notifications.
    // The actual provider updates happen via transferStream listener above.
    appService.onTransferComplete = (task, path) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${task.direction == TransferDirection.receive ? 'Received' : 'Sent'}: ${task.filename}')),
      );
    };
    appService.onTransferFailed = (task, error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Transfer failed: ${task.filename}')),
      );
    };
  }

  void _disconnectDevice(String deviceId) {
    final appService = ref.read(appServiceProvider);
    // Web client sessions use the token as device ID.
    final webClients = ref.read(webClientsProvider);
    final isWebClient = webClients.any((c) => c.sessionToken == deviceId);
    if (isWebClient) {
      appService.revokeWebClientSession(deviceId);
    } else {
      appService.disconnectPeer(deviceId);
    }
  }

  Future<void> _pickAndSendFile(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.path == null) return;

    final appService = ref.read(appServiceProvider);
    final hasPeers = appService.pairingService.peers.isNotEmpty;

    // Send to all paired desktops (creates transfer task in Files tab).
    await appService.sendFileToAllPeers(file.path!);

    // Also share to mobile web clients for download.
    // Only add to desktop Files tab if no peer transfer already created it.
    appService.shareFileToMobile(file.path!, file.name, file.size,
        addToDesktopList: !hasPeers);
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

  void _showMobilePinDialog(String clientIp, String clientName, String pin) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Mobile PIN'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.phone_android, size: 48),
            const SizedBox(height: 12),
            Text(
              '$clientName ($clientIp)',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text('Share this PIN with the mobile device:'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                pin.split('').join(' '),
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4,
                    ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Enter this PIN on the mobile browser to authenticate.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showQrCode(BuildContext context) {
    final appService = ref.read(appServiceProvider);
    showDialog(
      context: context,
      builder: (_) => QrCodePanel(
        url: appService.webUrl,
        isTls: appService.isTlsEnabled,
        onTlsToggle: (enabled) async {
          await appService.setTlsEnabled(enabled);
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('TLS ${enabled ? 'enabled' : 'disabled'} — restart app to apply'),
              action: SnackBarAction(label: 'OK', onPressed: () {}),
            ),
          );
        },
      ),
    );
  }
}
