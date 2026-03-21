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
  bool _suppressNextImage = false;
  bool _suppressNextText = false;

  final void Function(String content)? onClipboardChanged;
  final void Function(Uint8List imageData)? onImageClipboardChanged;

  ClipboardService({this.onClipboardChanged, this.onImageClipboardChanged});

  /// Start polling the clipboard for changes.
  void startMonitoring() {
    _pollTimer = Timer.periodic(kClipboardPollInterval, (_) => _poll());
    Log.i(_tag, 'Monitoring started');
  }

  Future<void> _poll() async {
    try {
      // Check text first.
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final content = data?.text ?? '';

      if (content.isNotEmpty && content != _lastContent) {
        _lastContent = content;
        if (_suppressNextText) {
          _suppressNextText = false;
        } else {
          onClipboardChanged?.call(content);
          return; // Text changed — skip image check this cycle.
        }
      }

      // Check image clipboard.
      if (onImageClipboardChanged != null) {
        await _pollImage();
      }
    } catch (e) {
      // Clipboard may be unavailable momentarily.
    }
  }

  Future<void> _pollImage() async {
    try {
      final imageBytes = await Pasteboard.image;
      if (imageBytes == null || imageBytes.isEmpty) return;

      if (imageBytes.length > kMaxImageClipboardSize) {
        Log.w(_tag, 'Image too large: ${imageBytes.length} bytes, skipping');
        return;
      }

      // Hash-based change detection.
      final hash = await _hashBytes(imageBytes);
      if (hash == _lastImageHash) return;

      _lastImageHash = hash;

      if (_suppressNextImage) {
        _suppressNextImage = false;
        return;
      }

      Log.i(_tag, 'Image clipboard changed: ${imageBytes.length} bytes');
      onImageClipboardChanged?.call(imageBytes);
    } catch (e) {
      // Image clipboard may not be available.
    }
  }

  /// Write text to the system clipboard.
  Future<void> write(String text) async {
    _lastContent = text; // Prevent triggering our own change callback.
    _suppressNextText = true;
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
    _lastImageHash = await _hashBytes(imageData);
    _suppressNextImage = true;
    await Pasteboard.writeImage(imageData);
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
