import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

import '../config/app_config.dart';

/// Extension allow-list plus a content sniff: the first bytes must not
/// contradict the claimed extension. Unidentifiable content
/// (application/octet-stream) is allowed for container formats the sniffer
/// cannot fingerprint; plaintext media is validated by extension and, when
/// recognizable, by magic bytes.
///
/// Returns null when the file is acceptable, otherwise the user-facing
/// message and the machine-readable `code` the mobile app maps to its own
/// wording.
({String message, String code})? validateUploadFile(
  String filename,
  List<int> bytes,
  String type,
) {
  final extensions = AppConfig.allowedFileExtensions[type];
  if (extensions == null) {
    return (message: 'Invalid file type category', code: 'invalid_category');
  }

  final extension = p.extension(filename).toLowerCase().replaceFirst('.', '');
  if (!extensions.contains(extension)) {
    return (
      message: 'File extension not allowed for $type',
      code: 'extension_not_allowed'
    );
  }

  final detectedType = lookupMimeType(filename, headerBytes: bytes);
  final claimedType = lookupMimeType('x.$extension');
  if (detectedType != null &&
      claimedType != null &&
      detectedType != 'application/octet-stream' &&
      detectedType != claimedType) {
    return (
      message: 'File content does not match its extension',
      code: 'content_mismatch'
    );
  }
  return null;
}
