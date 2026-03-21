import 'dart:typed_data';

enum ClipboardItemType { text, image }

class ClipboardItem {
  final String id;
  final ClipboardItemType type;
  final String content;
  final String? sourceDeviceId;
  final String? sourceDeviceName;
  final DateTime timestamp;

  /// For image items: raw image bytes (for display).
  final Uint8List? imageData;

  /// For image items: download URL for web clients.
  final String? downloadId;

  const ClipboardItem({
    required this.id,
    required this.type,
    required this.content,
    this.sourceDeviceId,
    this.sourceDeviceName,
    required this.timestamp,
    this.imageData,
    this.downloadId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'content': content,
        'sourceDeviceId': sourceDeviceId,
        'sourceDeviceName': sourceDeviceName,
        'timestamp': timestamp.millisecondsSinceEpoch,
        if (downloadId != null) 'downloadId': downloadId,
      };

  factory ClipboardItem.fromJson(Map<String, dynamic> json) => ClipboardItem(
        id: json['id'] as String,
        type: ClipboardItemType.values.byName(json['type'] as String),
        content: json['content'] as String,
        sourceDeviceId: json['sourceDeviceId'] as String?,
        sourceDeviceName: json['sourceDeviceName'] as String?,
        timestamp:
            DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
        downloadId: json['downloadId'] as String?,
      );

  String get preview => type == ClipboardItemType.image
      ? content
      : content.length > 100
          ? '${content.substring(0, 100)}...'
          : content;
}
