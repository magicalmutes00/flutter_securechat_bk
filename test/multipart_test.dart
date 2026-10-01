import 'dart:convert';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'package:secure_chat_server/utils/multipart.dart';

/// Builds a multipart body dio-style: preamble at offset 0, one header
/// block per part, closing delimiter at the end.
Uint8List multipartBody(
  String boundary,
  List<({String headers, List<int> content})> parts, {
  List<int> prefix = const [],
  bool closing = true,
}) {
  final builder = BytesBuilder();
  builder.add(prefix);
  for (final part in parts) {
    builder.add(latin1.encode('--$boundary\r\n'));
    builder.add(latin1.encode(part.headers));
    builder.add(latin1.encode('\r\n\r\n'));
    builder.add(part.content);
    builder.add(latin1.encode('\r\n'));
  }
  if (closing) builder.add(latin1.encode('--$boundary--\r\n'));
  return builder.takeBytes();
}

bool _equalBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void main() {
  const boundary = '----dart-test-boundary-abc123';

  group('extractMultipartFile', () {
    test('extracts filename and exact binary bytes', () {
      // Binary soup: NULs, high-bit bytes, lone CR/LF pairs — everything
      // except the actual delimiter.
      final content = <int>[
        0x00, 0xFF, 0x80, 0x0D, 0x0A, 0x0D, 0x0D, 0x0A, 0xFF, 0x00, 0x7F,
        ...List<int>.generate(256, (i) => i),
      ];
      final body = multipartBody(boundary, [
        (
          headers: 'Content-Disposition: form-data; name="file"; '
              'filename="photo.jpg"\r\n'
              'Content-Type: image/jpeg',
          content: content,
        ),
      ]);

      final part = extractMultipartFile(body, boundary);
      expect(part, isNotNull);
      expect(part!.filename, 'photo.jpg');
      expect(_equalBytes(part.bytes, content), isTrue);
    });

    test('skips field parts without a filename', () {
      final body = multipartBody(boundary, [
        (
          headers: 'Content-Disposition: form-data; name="note"',
          content: latin1.encode('hello'),
        ),
        (
          headers: 'Content-Disposition: form-data; name="file"; '
              'filename="a.txt"',
          content: latin1.encode('payload'),
        ),
      ]);

      final part = extractMultipartFile(body, boundary);
      expect(part, isNotNull);
      expect(part!.filename, 'a.txt');
      expect(latin1.decode(part.bytes), 'payload');
    });

    test('tolerates junk before the first delimiter', () {
      final body = multipartBody(
        boundary,
        [
          (
            headers: 'Content-Disposition: form-data; name="file"; '
                'filename="b.bin"',
            content: [1, 2, 3],
          ),
        ],
        prefix: latin1.encode('preamble-junk\r\n'),
      );

      final part = extractMultipartFile(body, boundary);
      expect(part, isNotNull);
      expect(part!.filename, 'b.bin');
    });

    test('reads unquoted filename params', () {
      final body = multipartBody(boundary, [
        (
          headers: 'Content-Disposition: form-data; name=file; '
              'filename=plain.txt',
          content: [9],
        ),
      ]);

      expect(extractMultipartFile(body, boundary)?.filename, 'plain.txt');
    });

    test('preserves client path segments for the caller to sanitize', () {
      final body = multipartBody(boundary, [
        (
          headers: 'Content-Disposition: form-data; name="file"; '
              'filename="C:\\fakepath\\evil.jpg"',
          content: [9],
        ),
      ]);

      // The route strips this via basename; the parser must not mangle it.
      expect(
        extractMultipartFile(body, boundary)?.filename,
        r'C:\fakepath\evil.jpg',
      );
    });

    test('returns the empty part instead of skipping it', () {
      final body = multipartBody(boundary, [
        (
          headers: 'Content-Disposition: form-data; name="file"; '
              'filename="empty.jpg"',
          content: [],
        ),
      ]);

      final part = extractMultipartFile(body, boundary);
      expect(part, isNotNull);
      expect(part!.bytes, isEmpty);
    });

    test('returns null on truncated bodies', () {
      final body = multipartBody(
        boundary,
        [
          (
            headers: 'Content-Disposition: form-data; name="file"; '
                'filename="cut.jpg"',
            content: [1, 2, 3],
          ),
        ],
        closing: false,
      );

      expect(extractMultipartFile(body, boundary), isNull);
    });

    test('returns null with no boundary and on immediate close', () {
      expect(
        extractMultipartFile(Uint8List.fromList([1, 2, 3]), boundary),
        isNull,
      );
      final closed = multipartBody(boundary, [], closing: true);
      expect(extractMultipartFile(closed, boundary), isNull);
    });
  });

  group('readCappedBody', () {
    Request streamed(List<List<int>> chunks) {
      return Request(
        'POST',
        Uri.parse('http://localhost/api/files/upload/image'),
        body: Stream.fromIterable(chunks),
      );
    }

    test('passes small bodies through intact across chunks', () async {
      final body =
          await readCappedBody(streamed([[1, 2], [3], [], [4, 5]]), 1024);
      expect(_equalBytes(body, [1, 2, 3, 4, 5]), isTrue);
    });

    test('throws the moment the cap is exceeded', () async {
      expect(
        readCappedBody(streamed([List.filled(600, 1), List.filled(600, 2)]), 1000),
        throwsA(isA<BodyTooLargeException>()),
      );
    });

    test('a body exactly at the limit passes', () async {
      final body = await readCappedBody(streamed([[1, 2, 3]]), 3);
      expect(_equalBytes(body, [1, 2, 3]), isTrue);
    });
  });
}
