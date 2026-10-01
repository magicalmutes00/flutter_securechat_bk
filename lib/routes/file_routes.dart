import 'dart:convert';
import 'dart:typed_data';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../config/app_config.dart';
import '../middleware/request_id_middleware.dart';
import '../services/cloudinary_service.dart';
import '../services/database_service.dart';
import '../services/file_service.dart';
import '../services/group_service.dart';
import '../services/message_service.dart';
import '../services/status_service.dart';
import '../utils/api_responses.dart';
import '../utils/file_validation.dart';
import '../utils/multipart.dart';
import '../utils/validate.dart';

class FileRoutes {
  final CloudinaryService _cloudinaryService = CloudinaryService();
  final FileService _fileService = FileService();
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
    ..get('/<fileId>', _getFile)
    ..delete('/<fileId>', _deleteFile);

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
    final requestId = requestIdOf(request);
    try {
      final userId = request.context['userId'] as String?;
      if (userId == null) {
        return clientError(
          401,
          message: 'Unauthorized',
          code: 'unauthorized',
          requestId: requestId,
        );
      }

      final contentType = request.headers['content-type'] ?? '';
      if (!contentType.contains('multipart/form-data')) {
        return clientError(
          400,
          message: 'Invalid content type. Expected multipart/form-data',
          code: 'invalid_content_type',
          requestId: requestId,
        );
      }

      final boundary = _boundaryFromContentType(contentType);
      if (boundary == null || boundary.isEmpty) {
        return clientError(
          400,
          message: 'Missing multipart boundary',
          code: 'missing_boundary',
          requestId: requestId,
        );
      }

      // Reject oversized uploads before buffering when the client declared
      // its body length (multipart framing adds a few hundred bytes at most).
      final declaredLength =
          int.tryParse(request.headers['content-length'] ?? '');
      if (declaredLength != null && declaredLength > maxFileSizeBytes + 65536) {
        return clientError(
          413,
          message: 'File size exceeds maximum allowed size',
          code: 'file_too_large',
          requestId: requestId,
        );
      }

      // Stream the body with a running cap: an oversized upload dies here,
      // mid-stream, instead of after buffering the whole body in RAM (the
      // old path transiently held ~4-5x the file size across the buffer,
      // the decoded string, and the re-encoded slice).
      late final Uint8List body;
      try {
        body = await readCappedBody(request, maxFileSizeBytes + 65536);
      } on BodyTooLargeException {
        return clientError(
          413,
          message: 'File size exceeds maximum allowed size',
          code: 'file_too_large',
          requestId: requestId,
        );
      }

      final part = extractMultipartFile(body, boundary);
      if (part == null || part.bytes.isEmpty) {
        return clientError(
          400,
          message: 'No file provided',
          code: 'no_file',
          requestId: requestId,
        );
      }

      if (part.bytes.length > maxFileSizeBytes) {
        return clientError(
          413,
          message: 'File size exceeds maximum allowed size',
          code: 'file_too_large',
          requestId: requestId,
        );
      }

      // Keep only the file name so the extension reaches the allow-list;
      // basename also strips any client-supplied path segments.
      final originalName =
          p.basename(part.filename.replaceAll('\\', '/')).trim();
      final safeName = originalName.isEmpty ? 'file' : originalName;

      final validationError = validateUploadFile(safeName, part.bytes, type);
      if (validationError != null) {
        return clientError(
          400,
          message: validationError.message,
          code: validationError.code,
          requestId: requestId,
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
      return serverError(
        'Failed to upload file',
        e,
        requestId: requestId,
        code: 'upload_failed',
      );
    }
  }

  Future<Response> _getFile(Request request, String fileId) async {
    final requestId = requestIdOf(request);
    try {
      final userId = request.context['userId'] as String?;
      if (userId == null) {
        return clientError(
          401,
          message: 'Unauthorized',
          code: 'unauthorized',
          requestId: requestId,
        );
      }

      if (!isValidUuid(fileId)) {
        return clientError(
          400,
          message: 'Invalid file ID format',
          code: 'invalid_file_id',
          requestId: requestId,
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
        return clientError(
          403,
          message: 'Not authorized to access this file',
          code: 'forbidden',
          requestId: requestId,
        );
      }

      final row = await _db.queryOne(
        'SELECT delivery_path FROM files WHERE id = @id:uuid',
        parameters: {'id': fileId},
      );
      if (row == null) {
        return clientError(
          404,
          message: 'File not found',
          code: 'not_found',
          requestId: requestId,
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
      return serverError(
        'Failed to get file',
        e,
        requestId: requestId,
        code: 'download_failed',
      );
    }
  }

  Future<Response> _deleteFile(Request request, String fileId) async {
    final requestId = requestIdOf(request);
    try {
      final userId = request.context['userId'] as String?;
      if (userId == null) {
        return clientError(
          401,
          message: 'Unauthorized',
          code: 'unauthorized',
          requestId: requestId,
        );
      }

      if (!isValidUuid(fileId)) {
        return clientError(
          400,
          message: 'Invalid file ID format',
          code: 'invalid_file_id',
          requestId: requestId,
        );
      }

      final deleted = await _fileService.deleteIfUnreferenced(
        fileId: fileId,
        ownerId: userId,
      );
      if (!deleted) {
        return clientError(
          404,
          message: 'File not found or still in use',
          code: 'not_deletable',
          requestId: requestId,
        );
      }

      return Response.ok(
        jsonEncode({'success': true}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return serverError(
        'Failed to delete file',
        e,
        requestId: requestId,
        code: 'delete_failed',
      );
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

  static String? _boundaryFromContentType(String contentType) {
    final match = RegExp(
      r'boundary=(?:"([^"]+)"|([^;,\s]+))',
      caseSensitive: false,
    ).firstMatch(contentType);
    if (match == null) return null;
      return match.group(1) ?? match.group(2);
  }
}
