/// Message types for the binary TCP protocol (Desktop ↔ Desktop).
enum MessageType {
  text(0x01),
  image(0x02),
  file(0x03),
  files(0x04),
  ping(0x05),
  pong(0x06),
  ack(0x07),
  reject(0x08);

  final int code;
  const MessageType(this.code);

  static MessageType fromCode(int code) =>
      MessageType.values.firstWhere((t) => t.code == code);
}
