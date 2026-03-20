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
    String? senderName,
    String? hmac,
  }) {
    final payload = utf8.encode(content);
    return Message(
      type: MessageType.text,
      meta: {
        'id': id,
        'sender': senderId,
        if (senderName != null) 'senderName': senderName,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'encoding': 'utf-8',
        'size': payload.length,
        if (hmac != null) 'hmac': hmac,
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

  /// Create a reject message.
  factory Message.reject(String reason) => Message(
        type: MessageType.reject,
        meta: {'reason': reason},
        payload: Uint8List(0),
      );

  /// Initiator → Responder: "I want to pair".
  factory Message.pairRequest({
    required String senderId,
    required String senderName,
    required String platform,
    required int tcpPort,
    required int webPort,
  }) =>
      Message(
        type: MessageType.pairRequest,
        meta: {
          'sender': senderId,
          'senderName': senderName,
          'platform': platform,
          'tcpPort': tcpPort,
          'webPort': webPort,
        },
        payload: Uint8List(0),
      );

  /// Responder → Initiator: "Here's a challenge nonce".
  factory Message.pairChallenge({required String nonce}) => Message(
        type: MessageType.pairChallenge,
        meta: {'nonce': nonce},
        payload: Uint8List(0),
      );

  /// Initiator → Responder: "Here's my proof (HMAC of PIN+nonce)".
  factory Message.pairResponse({required String hmac}) => Message(
        type: MessageType.pairResponse,
        meta: {'hmac': hmac},
        payload: Uint8List(0),
      );

  /// Responder → Initiator: "Pairing confirmed, here's device info".
  factory Message.pairConfirm({
    required String senderId,
    required String senderName,
    required String platform,
    required int tcpPort,
    required int webPort,
  }) =>
      Message(
        type: MessageType.pairConfirm,
        meta: {
          'sender': senderId,
          'senderName': senderName,
          'platform': platform,
          'tcpPort': tcpPort,
          'webPort': webPort,
        },
        payload: Uint8List(0),
      );

  /// Disconnect notification.
  factory Message.disconnect(String senderId) => Message(
        type: MessageType.disconnect,
        meta: {'sender': senderId},
        payload: Uint8List(0),
      );

  /// Serialize message to bytes for TCP transmission.
  Uint8List toBytes() {
    final metaBytes = utf8.encode(jsonEncode(meta));
    final header = Header(
      version: kProtocolVersion,
      type: type,
      metaLength: metaBytes.length,
      payloadLength: payload.length,
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

  /// Deserialize message from raw bytes. Returns null if data is incomplete.
  static Message? fromBytes(Uint8List bytes) {
    final header = Header.fromBytes(bytes);
    if (header == null) return null;

    final metaStart = Header.size;
    final metaEnd = metaStart + header.metaLength;
    final payloadEnd = metaEnd + header.payloadLength;

    if (bytes.length < payloadEnd) return null;

    final metaBytes = bytes.sublist(metaStart, metaEnd);
    final meta =
        jsonDecode(utf8.decode(metaBytes)) as Map<String, dynamic>;
    final payload = bytes.sublist(metaEnd, payloadEnd);

    return Message(type: header.type, meta: meta, payload: payload);
  }
}
