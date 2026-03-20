import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// A parsed multipart part with headers and body data.
class MimePart {
  final Map<String, String> headers;
  final Uint8List body;

  MimePart({required this.headers, required this.body});

  String? get filename {
    final disposition = headers['content-disposition'] ?? '';
    final match = RegExp(r'filename="([^"]+)"').firstMatch(disposition);
    return match?.group(1);
  }
}

/// Simple multipart/form-data parser.
/// Reads the full body and splits by boundary.
Future<List<MimePart>> parseMultipart(Stream<List<int>> body, String boundary) async {
  final chunks = <int>[];
  await for (final chunk in body) {
    chunks.addAll(chunk);
  }
  final bytes = Uint8List.fromList(chunks);
  final content = bytes;

  final boundaryBytes = utf8.encode('--$boundary');
  final parts = <MimePart>[];

  // Find all boundary positions.
  final positions = <int>[];
  for (var i = 0; i <= content.length - boundaryBytes.length; i++) {
    bool match = true;
    for (var j = 0; j < boundaryBytes.length; j++) {
      if (content[i + j] != boundaryBytes[j]) {
        match = false;
        break;
      }
    }
    if (match) positions.add(i);
  }

  for (var p = 0; p < positions.length - 1; p++) {
    // Skip boundary + CRLF.
    var start = positions[p] + boundaryBytes.length;
    // Skip \r\n after boundary.
    if (start < content.length && content[start] == 0x0D) start++;
    if (start < content.length && content[start] == 0x0A) start++;

    final end = positions[p + 1];

    // Parse headers and body.
    final partBytes = content.sublist(start, end);
    final headerEnd = _findHeaderEnd(partBytes);
    if (headerEnd < 0) continue;

    final headerStr = utf8.decode(partBytes.sublist(0, headerEnd));
    final headers = <String, String>{};
    for (final line in headerStr.split(RegExp(r'\r?\n'))) {
      final idx = line.indexOf(':');
      if (idx > 0) {
        headers[line.substring(0, idx).trim().toLowerCase()] =
            line.substring(idx + 1).trim();
      }
    }

    // Body starts after \r\n\r\n.
    var bodyStart = headerEnd + 4; // skip \r\n\r\n
    var bodyEnd = partBytes.length;
    // Remove trailing \r\n before next boundary.
    if (bodyEnd >= 2 &&
        partBytes[bodyEnd - 2] == 0x0D &&
        partBytes[bodyEnd - 1] == 0x0A) {
      bodyEnd -= 2;
    }

    parts.add(MimePart(
      headers: headers,
      body: Uint8List.fromList(partBytes.sublist(bodyStart, bodyEnd)),
    ));
  }

  return parts;
}

int _findHeaderEnd(Uint8List bytes) {
  // Find \r\n\r\n.
  for (var i = 0; i < bytes.length - 3; i++) {
    if (bytes[i] == 0x0D &&
        bytes[i + 1] == 0x0A &&
        bytes[i + 2] == 0x0D &&
        bytes[i + 3] == 0x0A) {
      return i;
    }
  }
  return -1;
}
