import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../main.dart';
import '../../models/session_info.dart';
import '../../providers/clipboard_provider.dart';
import '../../providers/transfer_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/secure_storage_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _nameController;
  List<PairedPeerInfo> _pairedPeers = [];
  List<SessionInfo> _webSessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final appService = ref.read(appServiceProvider);
    _nameController = TextEditingController(text: appService.deviceName);
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final appService = ref.read(appServiceProvider);
    final peers = await appService.secureStorage.loadAllPairedPeers();
    setState(() {
      _pairedPeers = peers.values.map((e) => e.$1).toList();
      _webSessions = appService.webClientSessions;
      _loading = false;
    });
  }

  Future<void> _saveDeviceName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final appService = ref.read(appServiceProvider);
    await appService.updateDeviceName(name);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Device name updated')),
    );
  }

  Future<void> _unpairDevice(String deviceId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unpair device?'),
        content: const Text('This will remove the pairing and disconnect the device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Unpair')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final appService = ref.read(appServiceProvider);
    await appService.disconnectPeer(deviceId);
    await _load();
  }

  void _revokeSession(String token) {
    final appService = ref.read(appServiceProvider);
    appService.revokeWebClientSession(token);
    setState(() {
      _webSessions = appService.webClientSessions;
    });
  }

  void _revokeAllSessions() {
    final appService = ref.read(appServiceProvider);
    appService.revokeAllWebClientSessions();
    setState(() {
      _webSessions = [];
    });
  }

  void _clearClipboardHistory() {
    ref.read(clipboardProvider.notifier).clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Clipboard history cleared')),
    );
  }

  void _clearTransferHistory() {
    ref.read(transferProvider.notifier).clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Transfer history cleared')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appService = ref.read(appServiceProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                // ── Device Info ──────────────────────────────────────
                _sectionHeader('Device'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Device name',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onSubmitted: (_) => _saveDeviceName(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _saveDeviceName,
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                ),
                _infoTile('Device ID', appService.deviceId, copyable: true),
                _infoTile('Local IP', appService.localIp),
                _infoTile('TCP Port', '${appService.tcpPort}'),
                _infoTile('Web URL', appService.webUrl, copyable: true),

                const Divider(),

                // ── Appearance ───────────────────────────────────────
                _sectionHeader('Appearance'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode),
                        label: Text('Light'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.system,
                        icon: Icon(Icons.brightness_auto),
                        label: Text('System'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        icon: Icon(Icons.dark_mode),
                        label: Text('Dark'),
                      ),
                    ],
                    selected: {ref.watch(themeModeProvider)},
                    onSelectionChanged: (modes) =>
                        ref.read(themeModeProvider.notifier).set(modes.first),
                  ),
                ),

                const Divider(),

                // ── Paired Desktops ──────────────────────────────────
                _sectionHeader('Paired Desktops'),
                if (_pairedPeers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Text('No paired desktops',
                        style: TextStyle(color: Colors.grey)),
                  )
                else
                  ..._pairedPeers.map((peer) => ListTile(
                        leading: Icon(_platformIcon(peer.platform)),
                        title: Text(peer.deviceName),
                        subtitle: Text('${peer.lastKnownIp}:${peer.lastKnownPort}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.link_off),
                          tooltip: 'Unpair',
                          onPressed: () => _unpairDevice(peer.deviceId),
                        ),
                      )),

                const Divider(),

                // ── Web Sessions ─────────────────────────────────────
                _sectionHeader(
                  'Mobile Web Sessions',
                  action: _webSessions.isNotEmpty
                      ? TextButton(
                          onPressed: _revokeAllSessions,
                          child: const Text('Revoke all'),
                        )
                      : null,
                ),
                if (_webSessions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Text('No active sessions',
                        style: TextStyle(color: Colors.grey)),
                  )
                else
                  ..._webSessions.map((s) => ListTile(
                        leading: const Icon(Icons.phone_android),
                        title: Text(s.clientName),
                        subtitle: Text(s.clientIp),
                        trailing: IconButton(
                          icon: const Icon(Icons.block),
                          tooltip: 'Revoke',
                          onPressed: () => _revokeSession(s.token),
                        ),
                      )),

                const Divider(),

                // ── Data ─────────────────────────────────────────────
                _sectionHeader('Data'),
                ListTile(
                  leading: const Icon(Icons.content_paste_off),
                  title: const Text('Clear clipboard history'),
                  onTap: _clearClipboardHistory,
                ),
                ListTile(
                  leading: const Icon(Icons.folder_off),
                  title: const Text('Clear transfer history'),
                  onTap: _clearTransferHistory,
                ),

                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _sectionHeader(String title, {Widget? action}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
                letterSpacing: 0.8,
              ),
            ),
          ),
          if (action != null) action,
        ],
      ),
    );
  }

  Widget _infoTile(String label, String value, {bool copyable = false}) {
    return ListTile(
      dense: true,
      title: Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
      subtitle: Text(value, style: const TextStyle(fontSize: 14)),
      trailing: copyable
          ? IconButton(
              icon: const Icon(Icons.copy, size: 18),
              tooltip: 'Copy',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$label copied')),
                );
              },
            )
          : null,
    );
  }

  IconData _platformIcon(String platform) {
    switch (platform.toLowerCase()) {
      case 'macos':
        return Icons.laptop_mac;
      case 'windows':
        return Icons.laptop_windows;
      default:
        return Icons.computer;
    }
  }
}
