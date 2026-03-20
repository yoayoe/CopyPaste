import 'package:flutter/material.dart';
import '../../../models/device.dart';
import 'device_tile.dart';

class DeviceList extends StatelessWidget {
  final List<Device> devices;
  final VoidCallback? onConnectPressed;
  final void Function(String deviceId)? onDisconnect;

  const DeviceList({
    super.key,
    required this.devices,
    this.onConnectPressed,
    this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (devices.isEmpty)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.devices, size: 64, color: Theme.of(context).disabledColor),
                const SizedBox(height: 16),
                Text(
                  'No devices connected',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Connect a desktop or scan QR from mobile',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: onConnectPressed,
                  icon: const Icon(Icons.add_link),
                  label: const Text('Connect to Desktop'),
                ),
              ],
            ),
          )
        else
          ListView.builder(
            padding: const EdgeInsets.only(left: 8, right: 8, top: 8, bottom: 80),
            itemCount: devices.length,
            itemBuilder: (context, index) => DeviceTile(
              device: devices[index],
              onDisconnect: onDisconnect,
            ),
          ),
        if (devices.isNotEmpty)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton(
              onPressed: onConnectPressed,
              tooltip: 'Connect to Desktop',
              child: const Icon(Icons.add_link),
            ),
          ),
      ],
    );
  }
}
