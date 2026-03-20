import 'dart:convert';
import 'dart:typed_data';
import '../../utils/constants.dart';
import 'header.dart';
import 'message_type.dart';

/// A complete protocol message: header + metadata + payload.
class Message {
  final MessageType type;
  final Map<String, dynamic> meta;
  final Uint8List payload;

  const Message({
    required this.type,
    required this.meta,
    required this.payload,
  });

  /// Create a text clipboard message.
  factory Message.text({
    required String id,
    required String senderId,
    required String content,
  }) {
    final payload = utf8.encode(content);
    return Message(
      type: MessageType.text,
      meta: {
        'id': id,
        'sender': senderId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'encoding': 'utf-8',
        'size': payload.length,
      },
      payload: Uint8List.fromList(payload),
    );
  }

  /// Create a ping message.
  factory Message.ping(String senderId) => Message(
        type: MessageType.ping,
        meta: {'sender': senderId},
        payload: Uint8List(0),
      );

  /// Create a pong (ping response) message.
  factory Message.pong(String senderId) => Message(
        type: MessageType.pong,
        meta: {'sender': senderId},
        payload: Uint8List(0),
      );

  /// Create an ACK message.
  factory Message.ack(String messageId) => Message(
        type: MessageType.ack,
        meta: {'messageId': messageId},
        payload: Uint8List(0),
      );

  /// Serialize message to bytes for TCP transmission.
  Uint8List toBytes() {
    final metaBytes = utf8.encode(jsonEncode(meta));
    final header = Header(
      version: kProtocolVersion,
      type: type,
      metaLength: metaBytes.length,
    );

    final headerBytes = header.toBytes();
    final total = Uint8List(
      headerBytes.length + metaBytes.length + payload.length,
    );

    total.setAll(0, headerBytes);
    total.setAll(headerBytes.length, metaBytes);
    total.setAll(headerBytes.length + metaBytes.length, payload);

    return total;
  }

  /// Deserialize message from raw bytes.
  static Message? fromBytes(Uint8List bytes) {
    final header = Header.fromBytes(bytes);
    if (header == null) return null;

    final metaStart = Header.size;
    final metaEnd = metaStart + header.metaLength;

    if (bytes.length < metaEnd) return null;

    final metaBytes = bytes.sublist(metaStart, metaEnd);
    final meta =
        jsonDecode(utf8.decode(metaBytes)) as Map<String, dynamic>;
    final payload = bytes.sublist(metaEnd);

    return Message(type: header.type, meta: meta, payload: payload);
  }
}
