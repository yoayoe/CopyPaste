import 'dart:typed_data';
import '../../utils/constants.dart';
import 'message_type.dart';

/// Binary protocol header (8 bytes total).
///
/// Layout:
///   [0]   magic byte 1 (0x43 = 'C')
///   [1]   magic byte 2 (0x50 = 'P')
///   [2]   protocol version
///   [3]   message type code
///   [4-7] metadata length (uint32, big-endian)
class Header {
  final int version;
  final MessageType type;
  final int metaLength;

  static const int size = 8;

  const Header({
    required this.version,
    required this.type,
    required this.metaLength,
  });

  Uint8List toBytes() {
    final bytes = Uint8List(size);
    bytes[0] = kMagicByte1;
    bytes[1] = kMagicByte2;
    bytes[2] = version;
    bytes[3] = type.code;
    final bd = ByteData.view(bytes.buffer);
    bd.setUint32(4, metaLength, Endian.big);
    return bytes;
  }

  static Header? fromBytes(Uint8List bytes) {
    if (bytes.length < size) return null;
    if (bytes[0] != kMagicByte1 || bytes[1] != kMagicByte2) return null;

    final bd = ByteData.view(bytes.buffer, bytes.offsetInBytes);
    return Header(
      version: bytes[2],
      type: MessageType.fromCode(bytes[3]),
      metaLength: bd.getUint32(4, Endian.big),
    );
  }
}
