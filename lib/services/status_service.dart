import '../models/status_model.dart';
import 'database_service.dart';

/// Handles persistence of ephemeral status posts ("stories").
class StatusService {
  final DatabaseService _db = DatabaseService();

  static const Duration _defaultLifetime = Duration(hours: 24);

  Duration get statusLifetime => _defaultLifetime;

  Future<StatusModel> createStatus({
    required String userId,
    String? text,
    String? mediaPath,
    String? mediaType,
  }) async {
    final expiresAt = DateTime.now().toUtc().add(_defaultLifetime);
    final row = await _db.queryOne(
      '''
      INSERT INTO statuses (user_id, text, media_path, media_type, expires_at)
      VALUES (@user_id:uuid, @text, @media_path, @media_type, @expires_at:timestamptz)
      RETURNING *
      ''',
      parameters: {
        'user_id': userId,
        'text': text,
        'media_path': mediaPath,
        'media_type': mediaType,
        'expires_at': expiresAt,
      },
    );
    return StatusModel.fromMap(row!);
  }

  /// Returns all statuses that have not yet expired, ordered newest first.
  Future<List<StatusModel>> getActiveStatuses() async {
    final rows = await _db.query(
      'SELECT * FROM statuses WHERE expires_at >= now() ORDER BY created_at DESC',
    );
    return rows.map(StatusModel.fromMap).toList();
  }

  Future<StatusModel?> getStatusById(String id) async {
    final row = await _db.queryOne(
      'SELECT * FROM statuses WHERE id = @id:uuid',
      parameters: {'id': id},
    );
    if (row == null) return null;
    return StatusModel.fromMap(row);
  }

  Future<List<StatusModel>> getStatusesByUser(String userId) async {
    final rows = await _db.query(
      '''
      SELECT * FROM statuses
      WHERE user_id = @user_id:uuid AND expires_at >= now()
      ORDER BY created_at DESC
      ''',
      parameters: {'user_id': userId},
    );
    return rows.map(StatusModel.fromMap).toList();
  }

  /// Records that [viewerId] saw the given status. Idempotent: the append is
  /// guarded by a NOT-contains check inside the same statement.
  Future<StatusModel?> markViewed(String statusId, String viewerId) async {
    await _db.execute(
      '''
      UPDATE statuses
      SET viewers = viewers || to_jsonb(ARRAY[@viewer_id:text])
      WHERE id = @id:uuid
        AND expires_at >= now()
        AND NOT viewers @> to_jsonb(ARRAY[@viewer_id:text])
      ''',
      parameters: {'id': statusId, 'viewer_id': viewerId},
    );
    return getStatusById(statusId);
  }

  Future<void> deleteStatus(String statusId, String userId) async {
    await _db.execute(
      'DELETE FROM statuses WHERE id = @id:uuid AND user_id = @user_id:uuid',
      parameters: {'id': statusId, 'user_id': userId},
    );
  }

  /// Returns true if the given file URL belongs to a status that is still
  /// active (not expired). Status media is ephemeral and broadcast to
  /// authenticated users for the status lifetime.
  Future<bool> isStatusFileSharedWithUser(String userId, String fileUrl) async {
    final row = await _db.queryOne(
      'SELECT 1 FROM statuses WHERE media_path = @file_url AND expires_at >= now() LIMIT 1',
      parameters: {'file_url': fileUrl},
    );
    return row != null;
  }
}
