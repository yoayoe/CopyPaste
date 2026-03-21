import 'dart:async';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:cryptography/cryptography.dart';
import '../utils/constants.dart';
import '../utils/logger.dart';

const _tag = 'Clipboard';

/// Monitors system clipboard for changes and provides read/write access.
class ClipboardService {
  Timer? _pollTimer;
  String _lastContent = '';
  String _lastImageHash = '';

  /// Timestamp-based suppression: ignore changes until this time.
  DateTime _suppressUntil = DateTime(0);

  final void Function(String content)? onClipboardChanged;
  final void Function(Uint8List imageData)? onImageClipboardChanged;

  ClipboardService({this.onClipboardChanged, this.onImageClipboardChanged});

  /// Start polling the clipboard for changes.
  void startMonitoring() {
    _pollTimer = Timer.periodic(kClipboardPollInterval, (_) => _poll());
    Log.i(_tag, 'Monitoring started');
  }

  bool get _isSuppressed => DateTime.now().isBefore(_suppressUntil);

  Future<void> _poll() async {
    if (_isSuppressed) return;

    try {
      // Check image clipboard first (higher priority).
      if (onImageClipboardChanged != null) {
        final imageChanged = await _pollImage();
        if (imageChanged) return; // Image changed — skip text check.
      }

      // Re-check suppression — writeImage may have been called while we were
      // awaiting _pollImage above.
      if (_isSuppressed) return;

      // Check text.
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final content = data?.text ?? '';

      // Final suppression check before firing callback.
      if (_isSuppressed) return;

      if (content.isNotEmpty && content != _lastContent) {
        _lastContent = content;
        onClipboardChanged?.call(content);
      }
    } catch (e) {
      // Clipboard may be unavailable momentarily.
    }
  }

  /// Returns true if a new image was detected.
  Future<bool> _pollImage() async {
    try {
      final imageBytes = await Pasteboard.image;
      if (imageBytes == null || imageBytes.isEmpty) return false;

      if (imageBytes.length > kMaxImageClipboardSize) {
        return false;
      }

      // Hash-based change detection.
      final hash = await _hashBytes(imageBytes);
      if (hash == _lastImageHash) return false;

      _lastImageHash = hash;

      // Re-check suppression — writeImage may have been called while we were
      // awaiting hash computation.
      if (_isSuppressed) return false;

      Log.i(_tag, 'Image clipboard changed: ${imageBytes.length} bytes');
      onImageClipboardChanged?.call(imageBytes);

      // Also update _lastContent to whatever text is on clipboard now,
      // so we don't double-fire a text event for the image's text representation.
      try {
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        _lastContent = data?.text ?? _lastContent;
      } catch (_) {}

      return true;
    } catch (e) {
      return false;
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

  /// Write image (PNG) to the system clipboard.
  Future<void> writeImage(Uint8List imageData) async {
    _suppress();
    await Pasteboard.writeImage(imageData);

    // Read back the actual hash (pasteboard may re-encode).
    try {
      final readBack = await Pasteboard.image;
      if (readBack != null) {
        _lastImageHash = await _hashBytes(readBack);
      }
    } catch (_) {}

    // Also capture whatever text representation was set.
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data?.text != null) _lastContent = data!.text!;
    } catch (_) {}

    Log.d(_tag, 'Written image: ${imageData.length} bytes');
  }

  /// Read current clipboard image.
  Future<Uint8List?> readImage() async {
    return await Pasteboard.image;
  }

  /// Suppress all change detection for a short window.
  void _suppress() {
    _suppressUntil = DateTime.now().add(const Duration(seconds: 3));
  }

  Future<String> _hashBytes(Uint8List data) async {
    final algo = Sha256();
    final hash = await algo.hash(data);
    return hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
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
