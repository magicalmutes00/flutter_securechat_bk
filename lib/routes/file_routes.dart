import 'dart:convert';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../config/app_config.dart';
import '../services/cloudinary_service.dart';
import '../services/database_service.dart';
import '../services/group_service.dart';
import '../services/message_service.dart';
import '../services/status_service.dart';
import '../utils/api_responses.dart';
import '../utils/validate.dart';

class FileRoutes {
  final CloudinaryService _cloudinaryService = CloudinaryService();
  final MessageService _messageService = MessageService();
  final GroupService _groupService = GroupService();
  final StatusService _statusService = StatusService();
  final DatabaseService _db = DatabaseService();

  int get maxFileSizeBytes => AppConfig.maxFileSizeBytes;

  Router get router => Router()
    ..post('/upload/image', _uploadImage)
    ..post('/upload/video', _uploadVideo)
    ..post('/upload/audio', _uploadAudio)
    ..post('/upload/document', _uploadDocument)
    ..get('/<fileId>', _getFile);

  Future<Response> _uploadImage(Request request) async {
    return _uploadFile(request, 'image');
  }

  Future<Response> _uploadVideo(Request request) async {
    return _uploadFile(request, 'video');
  }

  Future<Response> _uploadAudio(Request request) async {
    return _uploadFile(request, 'audio');
  }

  Future<Response> _uploadDocument(Request request) async {
    return _uploadFile(request, 'document');
  }

  Future<Response> _uploadFile(Request request, String type) async {
    try {
      final userId = request.context['userId'] as String?;
      if (userId == null) {
        return Response.unauthorized(
          jsonEncode({'error': 'Unauthorized'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final contentType = request.headers['content-type'] ?? '';
      if (!contentType.contains('multipart/form-data')) {
        return Response(
          400,
          body: jsonEncode(
              {'error': 'Invalid content type. Expected multipart/form-data'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final boundary = _boundaryFromContentType(contentType);
      if (boundary == null || boundary.isEmpty) {
        return Response(
          400,
          body: jsonEncode({'error': 'Missing multipart boundary'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Reject oversized uploads before buffering when the client declared
      // its body length (multipart framing adds a few hundred bytes at most).
      final declaredLength =
          int.tryParse(request.headers['content-length'] ?? '');
      if (declaredLength != null && declaredLength > maxFileSizeBytes + 65536) {
        return Response(
          413,
          body: jsonEncode({'error': 'File size exceeds maximum allowed size'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final bytes = await request.read().expand((chunk) => chunk).toList();

      final part = _extractMultipartFile(bytes, boundary);
      if (part == null || part.bytes.isEmpty) {
        return Response(
          400,
          body: jsonEncode({'error': 'No file provided'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      if (part.bytes.length > maxFileSizeBytes) {
        return Response(
          413,
          body: jsonEncode({'error': 'File size exceeds maximum allowed size'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Keep only the file name so the extension reaches the allow-list;
      // basename also strips any client-supplied path segments.
      final originalName =
          p.basename(part.filename.replaceAll('\\', '/')).trim();
      final safeName = originalName.isEmpty ? 'file' : originalName;

      final validationError = _validateFile(safeName, part.bytes, type);
      if (validationError != null) {
        return Response(
          400,
          body: jsonEncode({'success': false, 'message': validationError}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Bytes go straight to Cloudinary as a private (authenticated) asset —
      // nothing is ever written to the server's local disk.
      final upload = await _cloudinaryService.upload(
        bytes: part.bytes,
        filename: safeName,
      );

      final mediaType =
          lookupMimeType(safeName, headerBytes: part.bytes.take(512).toList()) ??
              'application/octet-stream';

      final row = await _db.queryOne(
        '''
        INSERT INTO files (owner_id, cloudinary_public_id, delivery_path, file_name, file_size, media_type, kind)
        VALUES (@owner_id:uuid, @public_id, @delivery_path, @file_name, @file_size, @media_type, @kind)
        RETURNING id
        ''',
        parameters: {
          'owner_id': userId,
          'public_id': upload.publicId,
          'delivery_path': upload.deliveryPath,
          'file_name': safeName,
          'file_size': upload.bytes,
          'media_type': mediaType,
          'kind': type,
        },
      );

      final fileId = row!['id'] as String;

      // Same response shape the mobile app already consumes; `url` is the
      // authorized download route (it redirects to a signed Cloudinary URL).
      return Response.ok(
        jsonEncode({
          'success': true,
          'file_path': upload.deliveryPath,
          'file_name': safeName,
          'file_size': upload.bytes,
          'media_type': mediaType,
          'url': '/api/files/$fileId',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return serverError('Failed to upload file', e);
    }
  }

  /// Extension allow-list plus a content sniff: the first 512 bytes must not
  /// contradict the claimed extension. Unidentifiable content
  /// (application/octet-stream) is allowed — that is what end-to-end
  /// encrypted attachments look like; their keys travel in the message.
  String? _validateFile(String filename, List<int> bytes, String type) {
    final extensions = AppConfig.allowedFileExtensions[type];
    if (extensions == null) return 'Invalid file type category';

    final extension =
        p.extension(filename).toLowerCase().replaceFirst('.', '');
    if (!extensions.contains(extension)) {
      return 'File extension not allowed for $type';
    }

    final detectedType = lookupMimeType(filename, headerBytes: bytes);
    final claimedType = lookupMimeType('x.$extension');
    if (detectedType != null &&
        claimedType != null &&
        detectedType != 'application/octet-stream' &&
        detectedType != claimedType) {
      return 'File content does not match its extension';
    }
    return null;
  }

  Future<Response> _getFile(Request request, String fileId) async {
    try {
      final userId = request.context['userId'] as String?;
      if (userId == null) {
        return Response.unauthorized(
          jsonEncode({'error': 'Unauthorized'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      if (!isValidUuid(fileId)) {
        return Response(
          400,
          body: jsonEncode({'error': 'Invalid file ID format'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final fileUrl = '/api/files/$fileId';

      // Only participants of a conversation referencing this file may download it.
      final isAuthorized = await _messageService.isFileSharedWithUser(
        userId,
        fileUrl,
      );

      // Group media is additionally accessible to group members.
      final isGroupAuthorized = isAuthorized
          ? false
          : await _groupService.isGroupFileSharedWithUser(
              userId,
              fileUrl,
            );

      // Status media is accessible to the author and viewers.
      final isStatusAuthorized = isAuthorized || isGroupAuthorized
          ? false
          : await _statusService.isStatusFileSharedWithUser(
              userId,
              fileUrl,
            );

      // Avatars (user profile pictures and group pictures) are referenced by
      // profile/group data that any authenticated user can already see, so
      // they are downloadable by any authenticated user.
      final isAvatarAuthorized = isAuthorized || isGroupAuthorized || isStatusAuthorized
          ? false
          : await _isReferencedAsAvatar(fileUrl);

      if (!isAuthorized &&
          !isGroupAuthorized &&
          !isStatusAuthorized &&
          !isAvatarAuthorized) {
        return Response.forbidden(
          jsonEncode({'error': 'Not authorized to access this file'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final row = await _db.queryOne(
        'SELECT delivery_path FROM files WHERE id = @id:uuid',
        parameters: {'id': fileId},
      );
      if (row == null) {
        return Response.notFound(
          jsonEncode({'error': 'File not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final signedUrl =
          _cloudinaryService.signedDeliveryUrl(row['delivery_path'] as String);

      // Redirect to the short signed Cloudinary URL. The client never sees a
      // permanent/public link — the signature only unlocks this one asset.
      return Response.found(
        signedUrl,
        headers: {'Cache-Control': 'private, max-age=3600'},
      );
    } catch (e) {
      return serverError('Failed to get file', e);
    }
  }

  /// True when [fileUrl] is referenced as a user's or group's avatar.
  Future<bool> _isReferencedAsAvatar(String fileUrl) async {
    final row = await _db.queryOne(
      '''
      SELECT
        EXISTS (SELECT 1 FROM users WHERE avatar_url = @file_url) OR
        EXISTS (SELECT 1 FROM groups WHERE avatar_url = @file_url) AS referenced
      ''',
      parameters: {'file_url': fileUrl},
    );
    return row?['referenced'] as bool? ?? false;
  }

  /// Extracts the first file part (a part carrying a filename) from a
  /// multipart/form-data body. Delimiters and headers are located on a
  /// latin-1 decoded view — a lossless byte↔codepoint mapping — so binary
  /// payloads are sliced out intact.
  static _MultipartFilePart? _extractMultipartFile(
    List<int> body,
    String boundary,
  ) {
    final text = latin1.decode(body);
    final delimiter = '\r\n--$boundary';

    // The first boundary usually sits at the very start of the body with no
    // preamble CRLF before it (curl, dio and most clients send it that way).
    final preamble = '--$boundary';
    var cursor;
    if (text.startsWith(preamble)) {
      cursor = preamble.length;
    } else {
      cursor = text.indexOf(delimiter);
      if (cursor == -1) return null;
      cursor += delimiter.length;
    }

    while (true) {
      if (text.startsWith('--', cursor)) return null; // closing boundary
      if (text.startsWith('\r\n', cursor)) cursor += 2;

      final headerEnd = text.indexOf('\r\n\r\n', cursor);
      if (headerEnd == -1) return null;

      final headerBlock = text.substring(cursor, headerEnd);
      final disposition = headerBlock
          .split('\r\n')
          .firstWhere(
            (line) =>
                line.toLowerCase().startsWith('content-disposition:'),
            orElse: () => '',
          );
      final filename = disposition.isEmpty
          ? null
          : _headerParam(disposition, 'filename');
      final contentStart = headerEnd + 4;

      final nextDelimiter = text.indexOf(delimiter, contentStart);
      if (nextDelimiter == -1) return null; // truncated body

      if (filename != null && filename.isNotEmpty) {
        return _MultipartFilePart(
          filename: filename,
          bytes: latin1.encode(text.substring(contentStart, nextDelimiter)),
        );
      }

      cursor = nextDelimiter + delimiter.length;
    }
  }

  /// Reads `param="value"` (quoted) or `param=value` (unquoted) from a
  /// Content-Disposition header line.
  static String? _headerParam(String header, String param) {
    final quoted =
        RegExp('$param="([^"]*)"', caseSensitive: false).firstMatch(header);
    if (quoted != null) return quoted.group(1);
    final unquoted = RegExp('$param=([^;\r\n]+)', caseSensitive: false)
        .firstMatch(header);
    return unquoted?.group(1)?.trim();
  }

  static String? _boundaryFromContentType(String contentType) {
    final match = RegExp(
      r'boundary=(?:"([^"]+)"|([^;,\s]+))',
      caseSensitive: false,
    ).firstMatch(contentType);
    if (match == null) return null;
    return match.group(1) ?? match.group(2);
  }
}

class _MultipartFilePart {
  final String filename;
  final List<int> bytes;

  _MultipartFilePart({required this.filename, required this.bytes});
}
