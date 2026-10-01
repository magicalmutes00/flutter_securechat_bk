import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'package:secure_chat_server/middleware/request_id_middleware.dart';
import 'package:secure_chat_server/utils/api_responses.dart';
import 'package:secure_chat_server/utils/file_validation.dart';

void main() {
  group('validateUploadFile', () {
    test('accepts opaque ciphertext under a real extension', () {
      // Random bytes: lookupMimeType finds no magic, so ciphertext passes.
      final cipher = List<int>.generate(256, (i) => (i * 37 + 11) % 256);
      expect(validateUploadFile('photo.jpg', cipher, 'image'), isNull);
    });

    test('accepts matching content and extension', () {
      // Minimal PNG: 8-byte signature + IHDR chunk header is enough for the
      // mime sniffer to report image/png.
      final png = <int>[
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
      ];
      expect(validateUploadFile('pic.png', png, 'image'), isNull);
    });

    test('rejects content that contradicts the extension', () {
      final png = <int>[
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
      ];
      final result = validateUploadFile('pic.jpg', png, 'image');
      expect(result, isNotNull);
      expect(result!.code, 'content_mismatch');
    });

    test('rejects extensions outside the allow-list', () {
      final result = validateUploadFile('run.exe', [1, 2, 3], 'image');
      expect(result, isNotNull);
      expect(result!.code, 'extension_not_allowed');
    });

    test('rejects unknown type categories', () {
      final result = validateUploadFile('a.jpg', [1], 'hologram');
      expect(result, isNotNull);
      expect(result!.code, 'invalid_category');
    });
  });

  group('requestIdOf', () {
    test('reads the id assigned by the middleware', () {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/health'),
        context: {'requestId': 'abc123'},
      );
      expect(requestIdOf(request), 'abc123');
    });

    test('falls back to unknown outside the middleware', () {
      final request = Request('GET', Uri.parse('http://localhost/health'));
      expect(requestIdOf(request), 'unknown');
    });
  });

  group('error response shapes', () {
    test('clientError carries code and request id', () async {
      final response = clientError(
        413,
        message: 'File size exceeds maximum allowed size',
        code: 'file_too_large',
        requestId: 'req-1',
      );
      expect(response.statusCode, 413);
      final body = jsonDecode(await response.readAsString());
      expect(body['success'], isFalse);
      expect(body['code'], 'file_too_large');
      expect(body['request_id'], 'req-1');
    });

    test('serverError carries code and request id without leaking details', () async {
      final response = serverError(
        'Failed to upload file',
        Exception('db exploded'),
        requestId: 'req-2',
        code: 'upload_failed',
      );
      expect(response.statusCode, 500);
      final body = jsonDecode(await response.readAsString());
      expect(body['code'], 'upload_failed');
      expect(body['request_id'], 'req-2');
      expect(body['error'], isNotNull);
      expect(jsonEncode(body).contains('exploded'), isFalse);
    });
  });
}
