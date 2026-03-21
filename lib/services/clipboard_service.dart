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

  /// Counter-based suppression: absorb the next N image change detections.
  /// This is NOT time-dependent — it absorbs re-detections caused by OS
  /// re-encoding after writeImage, regardless of how long the OS takes.
  int _absorbImageChanges = 0;

  /// Counter-based suppression for text changes after writing.
  int _absorbTextChanges = 0;

  final void Function(String content)? onClipboardChanged;
  final void Function(Uint8List imageData)? onImageClipboardChanged;

  ClipboardService({this.onClipboardChanged, this.onImageClipboardChanged});

  /// Start polling the clipboard for changes.
  void startMonitoring() {
    _pollTimer = Timer.periodic(kClipboardPollInterval, (_) => _poll());
    Log.i(_tag, 'Monitoring started');
  }

  /// Called by AppService when a local image is detected, to suppress the
  /// text representation that accompanies image clipboard data.
  void suppressTextDetection() {
    _absorbTextChanges = 5;
    Log.d(_tag, 'Text detection suppressed (5 cycles)');
  }

  Future<void> _poll() async {
    try {
      // Check image clipboard first (higher priority).
      if (onImageClipboardChanged != null) {
        final imageChanged = await _pollImage();
        if (imageChanged) return; // Image changed — skip text check.
      }

      // Check text.
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final content = data?.text ?? '';

      if (content.isNotEmpty && content != _lastContent) {
        _lastContent = content;

        // Absorb text changes after image write or local image detection.
        if (_absorbTextChanges > 0) {
          _absorbTextChanges--;
          Log.d(_tag, 'Absorbed text change ($_absorbTextChanges remaining)');
          return;
        }

        onClipboardChanged?.call(content);
      }
    } catch (e) {
      // Clipboard may be unavailable momentarily.
    }
  }

  /// Returns true if a new image was detected (or absorbed).
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

      // Hash changed — either genuine user copy or re-encoded write.
      _lastImageHash = hash;

      // Capture text representation to prevent double-fire.
      try {
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        _lastContent = data?.text ?? _lastContent;
      } catch (_) {}

      // If we're absorbing changes after a writeImage, consume silently.
      if (_absorbImageChanges > 0) {
        _absorbImageChanges--;
        Log.d(_tag, 'Absorbed image re-detection: ${imageBytes.length} bytes ($_absorbImageChanges remaining)');
        return true; // Return true to also skip text check.
      }

      Log.i(_tag, 'Image clipboard changed: ${imageBytes.length} bytes');
      onImageClipboardChanged?.call(imageBytes);

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Write text to the system clipboard.
  Future<void> write(String text) async {
    _lastContent = text;
    _absorbTextChanges = 3;
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
    // Set absorb counters BEFORE writing — any poll that sees the change
    // will be absorbed, regardless of timing.
    _absorbImageChanges = 5;
    _absorbTextChanges = 5;

    await Pasteboard.writeImage(imageData);

    // Wait for OS clipboard to settle (macOS re-encodes PNG).
    await Future.delayed(const Duration(milliseconds: 500));

    // Read back the actual hash so future polls see "no change".
    try {
      final readBack = await Pasteboard.image;
      if (readBack != null) {
        _lastImageHash = await _hashBytes(readBack);
        Log.d(_tag, 'writeImage readback: ${readBack.length} bytes');
      } else {
        Log.w(_tag, 'writeImage readback returned null');
      }
    } catch (e) {
      Log.w(_tag, 'writeImage readback failed: $e');
    }

    // Also capture text representation.
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
