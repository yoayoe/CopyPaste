import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Responder side: shows incoming pair request with PIN to share.
class PinDisplayDialog extends StatelessWidget {
  final String deviceName;
  final String platform;
  final String pin;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const PinDisplayDialog({
    super.key,
    required this.deviceName,
    required this.platform,
    required this.pin,
    required this.onApprove,
    required this.onReject,
  });

  IconData get _platformIcon => switch (platform) {
        'macos' => Icons.laptop_mac,
        'linux' => Icons.computer,
        'windows' => Icons.desktop_windows,
        _ => Icons.devices,
      };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pairing Request'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_platformIcon, size: 48, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(
            '$deviceName wants to pair',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Share this PIN with the other device:',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              pin.split('').join(' '),
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 4,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'The other device must enter this PIN to complete pairing.',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: onReject,
          child: const Text('Reject'),
        ),
        FilledButton(
          onPressed: onApprove,
          child: const Text('I shared the PIN'),
        ),
      ],
    );
  }
}

/// Initiator side: user must enter the PIN shown on the other device.
class PinInputDialog extends StatefulWidget {
  final String deviceName;
  final String platform;
  final void Function(String pin) onSubmit;
  final VoidCallback onCancel;

  const PinInputDialog({
    super.key,
    required this.deviceName,
    required this.platform,
    required this.onSubmit,
    required this.onCancel,
  });

  @override
  State<PinInputDialog> createState() => _PinInputDialogState();
}

class _PinInputDialogState extends State<PinInputDialog> {
  final _pinController = TextEditingController();

  IconData get _platformIcon => switch (widget.platform) {
        'macos' => Icons.laptop_mac,
        'linux' => Icons.computer,
        'windows' => Icons.desktop_windows,
        _ => Icons.devices,
      };

  void _submit() {
    final pin = _pinController.text.trim();
    if (pin.length == 6) {
      widget.onSubmit(pin);
    }
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enter PIN'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_platformIcon, size: 48, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(
            'Pairing with ${widget.deviceName}',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Enter the 6-digit PIN shown on the other device:',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 200,
            child: TextField(
              controller: _pinController,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 8,
                  ),
              decoration: const InputDecoration(
                hintText: '000000',
                border: OutlineInputBorder(),
                counterText: '',
              ),
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              autofocus: true,
              onSubmitted: (_) => _submit(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: widget.onCancel,
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Verify'),
        ),
      ],
    );
  }
}
