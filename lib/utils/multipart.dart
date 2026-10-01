import 'dart:convert';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';

/// Thrown by [readCappedBody] the moment more than the allowed bytes arrive.
class BodyTooLargeException implements Exception {
  const BodyTooLargeException();
}

/// Reads the request body with a running cap: aborts the stream as soon as
/// more than [limit] bytes arrive, so an oversized (or lying content-length)
/// upload dies mid-stream instead of after buffering.
Future<Uint8List> readCappedBody(Request request, int limit) async {
  final builder = BytesBuilder(copy: false);
  var total = 0;
  await for (final chunk in request.read()) {
    total += chunk.length;
    if (total > limit) throw const BodyTooLargeException();
    builder.add(chunk);
  }
  return builder.takeBytes();
}

/// One parsed file part: the client-supplied filename and a zero-copy view
/// of its payload bytes.
typedef MultipartFilePart = ({String filename, Uint8List bytes});

/// Byte-level multipart scan for the first part carrying a filename.
/// Framing (pure ASCII) is located on the raw bytes and the payload is
/// sliced by index range — file bytes are never decoded to String (a 50 MB
/// body would otherwise balloon to a ~100 MB UTF-16 string plus two more
/// copies on the way back to bytes).
MultipartFilePart? extractMultipartFile(Uint8List body, String boundary) {
  final delimiter = latin1.encode('\r\n--$boundary');
  final preamble = latin1.encode('--$boundary');
  final closing = latin1.encode('--');
  final crlf = latin1.encode('\r\n');
  final headerEnd = latin1.encode('\r\n\r\n');

  int cursor;
  if (_startsWith(body, preamble, 0)) {
    cursor = preamble.length;
  } else {
    final at = _indexOf(body, delimiter, 0);
    if (at == -1) return null;
    cursor = at + delimiter.length;
  }

  while (true) {
    if (_startsWith(body, closing, cursor)) return null; // closing boundary
    if (_startsWith(body, crlf, cursor)) cursor += 2;

    final headersAt = _indexOf(body, headerEnd, cursor);
    if (headersAt == -1) return null;

    // Headers are tiny; only this slice is ever decoded.
    final headerBlock = latin1.decode(body.sublist(cursor, headersAt));
    final disposition = headerBlock
        .split('\r\n')
        .firstWhere(
          (line) => line.toLowerCase().startsWith('content-disposition:'),
          orElse: () => '',
        );
    final filename =
        disposition.isEmpty ? null : _headerParam(disposition, 'filename');
    final contentStart = headersAt + 4;

    final nextDelimiter = _indexOf(body, delimiter, contentStart);
    if (nextDelimiter == -1) return null; // truncated body

    if (filename != null && filename.isNotEmpty) {
      return (
        filename: filename,
        bytes: Uint8List.view(
          body.buffer,
          body.offsetInBytes + contentStart,
          nextDelimiter - contentStart,
        ),
      );
    }

    cursor = nextDelimiter + delimiter.length;
  }
}

/// Reads `param="value"` (quoted) or `param=value` (unquoted) from a
/// Content-Disposition header line.
String? _headerParam(String header, String param) {
  final quoted =
      RegExp('$param="([^"]*)"', caseSensitive: false).firstMatch(header);
  if (quoted != null) return quoted.group(1);
  final unquoted = RegExp('$param=([^;\r\n]+)', caseSensitive: false)
      .firstMatch(header);
  return unquoted?.group(1)?.trim();
}

int _indexOf(Uint8List haystack, List<int> needle, int start) {
  if (needle.isEmpty) return start;
  outer:
  for (var i = start; i <= haystack.length - needle.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return i;
  }
  return -1;
}

bool _startsWith(Uint8List haystack, List<int> prefix, int at) {
  if (at < 0 || at + prefix.length > haystack.length) return false;
  for (var j = 0; j < prefix.length; j++) {
    if (haystack[at + j] != prefix[j]) return false;
  }
  return true;
}
