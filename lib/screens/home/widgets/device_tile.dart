import 'package:flutter/material.dart';
import '../../../models/device.dart';

class DeviceTile extends StatelessWidget {
  final Device device;

  const DeviceTile({super.key, required this.device});

  IconData get _platformIcon => switch (device.platform) {
        'macos' => Icons.laptop_mac,
        'linux' => Icons.computer,
        'windows' => Icons.desktop_windows,
        'browser' => Icons.phone_android,
        _ => Icons.devices,
      };

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(_platformIcon, size: 32),
        title: Text(device.name),
        subtitle: Text(
          device.ip.isNotEmpty
              ? '${device.platform} • ${device.ip}'
              : device.platform,
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            // TODO: Handle actions
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'send_clipboard',
              child: Text('Send clipboard'),
            ),
            const PopupMenuItem(
              value: 'send_file',
              child: Text('Send file'),
            ),
          ],
        ),
      ),
    );
  }
}
