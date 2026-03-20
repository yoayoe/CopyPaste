import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ConnectDialog extends StatefulWidget {
  final int defaultPort;
  final Future<void> Function(String ip, int port) onConnect;

  const ConnectDialog({
    super.key,
    required this.defaultPort,
    required this.onConnect,
  });

  @override
  State<ConnectDialog> createState() => _ConnectDialogState();
}

class _ConnectDialogState extends State<ConnectDialog> {
  final _ipController = TextEditingController();
  final _portController = TextEditingController();
  bool _connecting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _portController.text = widget.defaultPort.toString();
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  bool _isValidIp(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    return parts.every((p) {
      final n = int.tryParse(p);
      return n != null && n >= 0 && n <= 255;
    });
  }

  Future<void> _connect() async {
    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim());

    if (!_isValidIp(ip)) {
      setState(() => _error = 'Invalid IP address');
      return;
    }
    if (port == null || port < 1 || port > 65535) {
      setState(() => _error = 'Invalid port');
      return;
    }

    setState(() {
      _connecting = true;
      _error = null;
    });

    try {
      await widget.onConnect(ip, port);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _connecting = false;
          _error = 'Connection failed: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Connect to Desktop'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Enter the IP address and TCP port of the other desktop.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ipController,
            decoration: const InputDecoration(
              labelText: 'IP Address',
              hintText: '192.168.1.100',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.computer),
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            autofocus: true,
            onSubmitted: (_) => _connect(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _portController,
            decoration: const InputDecoration(
              labelText: 'TCP Port',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.numbers),
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
            ],
            onSubmitted: (_) => _connect(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _connecting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _connecting ? null : _connect,
          icon: _connecting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.link),
          label: Text(_connecting ? 'Connecting...' : 'Connect'),
        ),
      ],
    );
  }
}
