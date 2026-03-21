import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/clipboard_item.dart';
import '../utils/constants.dart';

const _uuid = Uuid();

/// Manages clipboard history.
class ClipboardNotifier extends StateNotifier<List<ClipboardItem>> {
  ClipboardNotifier() : super([]);

  void add(String content, {String? sourceDeviceId, String? sourceDeviceName}) {
    // Avoid duplicating the same content if it's the most recent.
    if (state.isNotEmpty && state.first.content == content) return;

    final item = ClipboardItem(
      id: _uuid.v4(),
      type: ClipboardItemType.text,
      content: content,
      sourceDeviceId: sourceDeviceId,
      sourceDeviceName: sourceDeviceName,
      timestamp: DateTime.now(),
    );

    state = [item, ...state.take(kMaxClipboardHistory - 1)];
  }

  void addImage(Uint8List imageData,
      {String? sourceDeviceId, String? sourceDeviceName, String? downloadId}) {
    final sizeStr = imageData.length < 1024
        ? '${imageData.length} B'
        : imageData.length < 1048576
            ? '${(imageData.length / 1024).toStringAsFixed(1)} KB'
            : '${(imageData.length / 1048576).toStringAsFixed(1)} MB';

    final item = ClipboardItem(
      id: _uuid.v4(),
      type: ClipboardItemType.image,
      content: '[Image: $sizeStr]',
      sourceDeviceId: sourceDeviceId,
      sourceDeviceName: sourceDeviceName,
      timestamp: DateTime.now(),
      imageData: imageData,
      downloadId: downloadId,
    );

    state = [item, ...state.take(kMaxClipboardHistory - 1)];
  }

  void remove(String id) {
    state = state.where((item) => item.id != id).toList();
  }

  void clear() {
    state = [];
  }
}

final clipboardProvider =
    StateNotifierProvider<ClipboardNotifier, List<ClipboardItem>>((ref) {
  return ClipboardNotifier();
});
