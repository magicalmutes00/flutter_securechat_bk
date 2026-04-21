import 'dart:io';
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:mime/mime.dart';
import '../services/file_service.dart';

class FileRoutes {
  final FileService _fileService = FileService();

  Router get router => Router()
    ..post('/upload/image', _uploadImage)
    ..post('/upload/video', _uploadVideo)
    ..post('/upload/audio', _uploadAudio)
    ..post('/upload/document', _uploadDocument)
    ..get('/<fileName>', _getFile);

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
      final userId = request.context['userId'];
      if (userId == null) {
        return Response.unauthorized(
          jsonEncode({'error': 'Unauthorized'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final contentType = request.headers['content-type'] ?? '';
      if (!contentType.contains('multipart/form-data')) {
        return Response(400,
          body: jsonEncode({'error': 'Invalid content type. Expected multipart/form-data'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final reader = request.read();
      final bytes = await reader.expand((e) => e).toList();

      if (bytes.isEmpty) {
        return Response(400,
          body: jsonEncode({'error': 'No file provided'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final tempDir = Directory.systemTemp.createTempSync('upload_');
      final tempFile = File('${tempDir.path}/file');
      await tempFile.writeAsBytes(bytes);

      final result = await _fileService.saveFile(
        file: tempFile,
        type: type,
      );

      await tempFile.delete();
      await tempDir.delete();

      if (result['success'] != true) {
        return Response(400,
          body: jsonEncode(result),
          headers: {'Content-Type': 'application/json'},
        );
      }

      return Response.ok(
        jsonEncode(result),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response(500,
        body: jsonEncode({'error': 'Failed to upload file: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _getFile(Request request, String fileName) async {
    try {
      final file = await _fileService.getFile(fileName);
      if (file == null) {
        return Response.notFound(
          jsonEncode({'error': 'File not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final bytes = await file.readAsBytes();
      final mimeType = lookupMimeType(file.path) ?? 'application/octet-stream';

      return Response.ok(
        bytes,
        headers: {
          'Content-Type': mimeType,
          'Content-Length': bytes.length.toString(),
        },
      );
    } catch (e) {
      return Response(500,
        body: jsonEncode({'error': 'Failed to get file: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }
}
