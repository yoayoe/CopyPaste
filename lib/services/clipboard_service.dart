import 'dart:async';
import 'package:flutter/services.dart';
import '../utils/constants.dart';
import '../utils/logger.dart';

const _tag = 'Clipboard';

/// Monitors system clipboard for changes and provides read/write access.
class ClipboardService {
  Timer? _pollTimer;
  String _lastContent = '';

  /// Timestamp-based suppression: ignore changes until this time.
  DateTime _suppressUntil = DateTime(0);

  final void Function(String content)? onClipboardChanged;

  ClipboardService({this.onClipboardChanged});

  /// Start polling the clipboard for changes.
  void startMonitoring() {
    _pollTimer = Timer.periodic(kClipboardPollInterval, (_) => _poll());
    Log.i(_tag, 'Monitoring started');
  }

  bool get _isSuppressed => DateTime.now().isBefore(_suppressUntil);

  Future<void> _poll() async {
    if (_isSuppressed) return;

    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final content = data?.text ?? '';

      if (content.isNotEmpty && content != _lastContent) {
        _lastContent = content;
        onClipboardChanged?.call(content);
      }
    } catch (e) {
      // Clipboard may be unavailable momentarily.
    }
  }

  /// Write text to the system clipboard.
  Future<void> write(String text) async {
    _lastContent = text;
    _suppress();
    await Clipboard.setData(ClipboardData(text: text));
    Log.d(_tag, 'Written ${text.length} chars');
  }

  /// Read current clipboard text.
  Future<String> read() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return data?.text ?? '';
  }

  /// Suppress all change detection for a short window.
  void _suppress() {
    _suppressUntil = DateTime.now().add(const Duration(seconds: 2));
  }

  void stopMonitoring() {
    _pollTimer?.cancel();
    _pollTimer = null;
    Log.i(_tag, 'Monitoring stopped');
  }

  void dispose() {
    stopMonitoring();
  }
}
