import 'cloudinary_service.dart';
import 'database_service.dart';

/// Derives the Cloudinary resource type from a stored delivery path
/// (`<type>/authenticated/v…/…`). Unknown prefixes fall back to `raw` — the
/// type every current upload uses.
String resourceTypeOfDeliveryPath(String deliveryPath) {
  final slash = deliveryPath.indexOf('/');
  final type = slash == -1 ? '' : deliveryPath.substring(0, slash);
  if (type == 'image' || type == 'video' || type == 'raw') return type;
  return 'raw';
}

/// Owns the lifecycle of `files` rows and their Cloudinary assets.
class FileService {
  final DatabaseService _db = DatabaseService();
  final CloudinaryService _cloudinary = CloudinaryService();

  /// Deletes the file row plus its Cloudinary asset when [fileId] is owned
  /// by [ownerId] and no live row still references its URL. Returns true
  /// when something was deleted.
  ///
  /// Ownership and liveness failures are deliberately indistinguishable
  /// (false either way) so the endpoint can't be used to probe other users'
  /// files or to break conversations by deleting in-use assets.
  Future<bool> deleteIfUnreferenced({
    required String fileId,
    required String ownerId,
  }) async {
    final row = await _db.queryOne(
      'SELECT cloudinary_public_id, delivery_path FROM files '
      'WHERE id = @id:uuid AND owner_id = @owner_id:uuid',
      parameters: {'id': fileId, 'owner_id': ownerId},
    );
    if (row == null) return false;

    final fileUrl = '/api/files/$fileId';
    final stillReferenced = await _db.queryOne(
      '''
      SELECT EXISTS (SELECT 1 FROM messages WHERE file_path = @url) OR
             EXISTS (SELECT 1 FROM group_messages WHERE file_path = @url) OR
             EXISTS (SELECT 1 FROM statuses
                      WHERE media_path = @url AND expires_at >= now()) OR
             EXISTS (SELECT 1 FROM users WHERE avatar_url = @url) OR
             EXISTS (SELECT 1 FROM groups WHERE avatar_url = @url)
             AS referenced
      ''',
      parameters: {'url': fileUrl},
    );
    if (stillReferenced?['referenced'] as bool? ?? true) return false;

    // Cloudinary first: if the destroy throws, the row stays and a later
    // attempt can retry — never the reverse (row gone, bytes leaked).
    await _cloudinary.destroy(
      publicId: row['cloudinary_public_id'] as String,
      resourceType:
          resourceTypeOfDeliveryPath(row['delivery_path'] as String),
    );
    await _db.execute(
      'DELETE FROM files WHERE id = @id:uuid',
      parameters: {'id': fileId},
    );
    return true;
  }
}
