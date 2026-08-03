import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:mime/mime.dart';
import 'package:uuid/uuid.dart';
import '../config/app_config.dart';

class FileService {
  final Uuid _uuid = Uuid();

  Future<Map<String, dynamic>> saveFile({
    required File file,
    required String type,
  }) async {
    try {
      final extension =
          p.extension(file.path).toLowerCase().replaceFirst('.', '');
      if (!AppConfig.allowedFileExtensions.containsKey(type)) {
        return {'success': false, 'message': 'Invalid file type category'};
      }

      if (!AppConfig.allowedFileExtensions[type]!.contains(extension)) {
        return {
          'success': false,
          'message': 'File extension not allowed for $type'
        };
      }

      final fileSize = await file.length();
      if (fileSize > AppConfig.maxFileSizeBytes) {
        return {
          'success': false,
          'message': 'File size exceeds maximum allowed size'
        };
      }

      final folder = AppConfig.uploadFolders[type];
      if (folder == null) {
        return {'success': false, 'message': 'Invalid upload type'};
      }

      final directory = Directory(folder);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      final uniqueFileName = '${_uuid.v4()}.$extension';
      final newPath = p.join(folder, uniqueFileName);
      await file.copy(newPath);

      final mimeType = lookupMimeType(newPath) ?? 'application/octet-stream';

      return {
        'success': true,
        'file_path': newPath,
        'file_name': p.basename(newPath),
        'file_size': fileSize,
        'media_type': mimeType,
        'url': '/api/files/$uniqueFileName',
      };
    } catch (e) {
      return {'success': false, 'message': 'Failed to save file: $e'};
    }
  }

  Future<File?> getFile(String fileName) async {
    if (fileName.contains('..') ||
        fileName.contains('/') ||
        fileName.contains('\\')) {
      return null;
    }

    for (final folder in AppConfig.uploadFolders.values) {
      final path = p.join(folder, fileName);
      final file = File(path);
      if (await file.exists()) {
        final resolvedPath = await file.resolveSymbolicLinks();
        if (!resolvedPath.startsWith(folder)) {
          return null;
        }
        return file;
      }
    }
    return null;
  }

  Future<Map<String, dynamic>> deleteFile(String fileName) async {
    try {
      final file = await getFile(fileName);
      if (file == null) {
        return {'success': false, 'message': 'File not found'};
      }
      await file.delete();
      return {'success': true, 'message': 'File deleted successfully'};
    } catch (e) {
      return {'success': false, 'message': 'Failed to delete file: $e'};
    }
  }
}
