import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

class QrCodePanel extends StatefulWidget {
  final String url;
  final bool isTls;
  final Future<void> Function(bool enabled)? onTlsToggle;

  const QrCodePanel({
    super.key,
    required this.url,
    this.isTls = false,
    this.onTlsToggle,
  });

  @override
  State<QrCodePanel> createState() => _QrCodePanelState();
}

class _QrCodePanelState extends State<QrCodePanel> {
  late bool _tlsPref;

  @override
  void initState() {
    super.initState();
    _tlsPref = widget.isTls;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Connect Mobile'),
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 200,
              height: 200,
              child: QrImageView(
                data: widget.url,
                version: QrVersions.auto,
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.isTls
                  ? 'Scan QR, then accept the certificate warning\non your phone to connect securely'
                  : 'Scan this QR code with your phone\nto open CopyPaste in browser',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  widget.isTls ? Icons.lock : Icons.lock_open,
                  size: 16,
                  color: widget.isTls
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(width: 4),
                SelectableText(
                  widget.url,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const Divider(height: 24),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('HTTPS (TLS)'),
              subtitle: Text(
                _tlsPref == widget.isTls
                    ? (widget.isTls
                        ? 'Secure — clipboard read enabled'
                        : 'Off — clipboard read may not work')
                    : 'Restart app to apply',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              value: _tlsPref,
              onChanged: widget.onTlsToggle != null
                  ? (value) {
                      setState(() => _tlsPref = value);
                      widget.onTlsToggle!(value);
                    }
                  : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
