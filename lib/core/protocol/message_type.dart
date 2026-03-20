/// Message types for the binary TCP protocol (Desktop ↔ Desktop).
enum MessageType {
  text(0x01),
  image(0x02),
  file(0x03),
  files(0x04),
  ping(0x05),
  pong(0x06),
  ack(0x07),
  reject(0x08),
  // Pairing handshake.
  pairRequest(0x10),
  pairChallenge(0x11),
  pairResponse(0x12),
  pairConfirm(0x13),
  // Connection control.
  disconnect(0x14);

  final int code;
  const MessageType(this.code);

  static MessageType fromCode(int code) =>
      MessageType.values.firstWhere((t) => t.code == code,
          orElse: () => throw ArgumentError('Unknown message type: 0x${code.toRadixString(16)}'));
}
