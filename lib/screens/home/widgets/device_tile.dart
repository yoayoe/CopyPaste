import 'package:flutter/material.dart';
import '../../../models/device.dart';

class DeviceTile extends StatelessWidget {
  final Device device;
  final void Function(String deviceId)? onDisconnect;

  const DeviceTile({super.key, required this.device, this.onDisconnect});

  IconData get _platformIcon => switch (device.platform) {
        'macos' => Icons.laptop_mac,
        'linux' => Icons.computer,
        'windows' => Icons.desktop_windows,
        'browser' => Icons.phone_android,
        _ => Icons.devices,
      };

  Color _stateColor(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return switch (device.pairingState) {
      PairingState.paired => Colors.green,
      PairingState.pairing => colors.primary,
      PairingState.discovered => colors.outline,
      PairingState.disconnected => colors.error,
    };
  }

  String get _stateLabel => switch (device.pairingState) {
        PairingState.paired => 'Connected',
        PairingState.pairing => 'Pairing...',
        PairingState.discovered => device.platform == 'browser' ? 'Web Client' : 'Discovered',
        PairingState.disconnected => 'Disconnected',
      };

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Stack(
          children: [
            Icon(_platformIcon, size: 32),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _stateColor(context),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).cardColor,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
        title: Text(device.name),
        subtitle: Text(
          '${device.ip.isNotEmpty ? '${device.ip} • ' : ''}$_stateLabel',
          style: TextStyle(
            color: _stateColor(context),
            fontSize: 12,
          ),
        ),
        trailing: _buildTrailing(context),
      ),
    );
  }

  Widget? _buildTrailing(BuildContext context) {
    if (device.platform == 'browser') {
      return const Icon(Icons.open_in_browser, size: 20);
    }

    if (device.pairingState == PairingState.pairing) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (device.pairingState == PairingState.paired && onDisconnect != null) {
      return IconButton(
        icon: const Icon(Icons.link_off, size: 20),
        tooltip: 'Disconnect',
        onPressed: () => onDisconnect?.call(device.id),
      );
    }

    return null;
  }
}
