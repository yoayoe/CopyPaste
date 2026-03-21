enum ClipboardItemType { text }

class ClipboardItem {
  final String id;
  final ClipboardItemType type;
  final String content;
  final String? sourceDeviceId;
  final String? sourceDeviceName;
  final DateTime timestamp;

  const ClipboardItem({
    required this.id,
    required this.type,
    required this.content,
    this.sourceDeviceId,
    this.sourceDeviceName,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'content': content,
        'sourceDeviceId': sourceDeviceId,
        'sourceDeviceName': sourceDeviceName,
        'timestamp': timestamp.millisecondsSinceEpoch,
      };

  factory ClipboardItem.fromJson(Map<String, dynamic> json) => ClipboardItem(
        id: json['id'] as String,
        type: ClipboardItemType.values.byName(json['type'] as String),
        content: json['content'] as String,
        sourceDeviceId: json['sourceDeviceId'] as String?,
        sourceDeviceName: json['sourceDeviceName'] as String?,
        timestamp:
            DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
      );

  String get preview => content.length > 100
      ? '${content.substring(0, 100)}...'
      : content;
}
