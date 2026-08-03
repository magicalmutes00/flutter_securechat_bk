import 'package:mongo_dart/mongo_dart.dart';
import '../models/status_model.dart';
import 'database_service.dart';

/// Handles persistence of ephemeral status posts ("stories").
class StatusService {
  final DatabaseService _db = DatabaseService();

  static const Duration _defaultLifetime = Duration(hours: 24);

  Duration get statusLifetime => _defaultLifetime;

  Future<StatusModel> createStatus({
    required ObjectId userId,
    String? text,
    String? mediaPath,
    String? mediaType,
  }) async {
    final now = DateTime.now();
    final status = StatusModel(
      id: ObjectId(),
      userId: userId,
      text: text,
      mediaPath: mediaPath,
      mediaType: mediaType,
      createdAt: now,
      expiresAt: now.add(_defaultLifetime),
    );
    await _db.statuses.insertOne(status.toMap());
    return status;
  }

  /// Returns all statuses that have not yet expired, ordered newest first.
  Future<List<StatusModel>> getActiveStatuses() async {
    final docs = await _db.statuses
        .find(
          where
              .gte('expires_at', DateTime.now())
              .sortBy('created_at', descending: true),
        )
        .toList();
    return docs.map((d) => StatusModel.fromMap(d)).toList();
  }

  Future<StatusModel?> getStatusById(ObjectId id) async {
    final doc = await _db.statuses.findOne({'_id': id});
    if (doc == null) return null;
    return StatusModel.fromMap(doc);
  }

  Future<List<StatusModel>> getStatusesByUser(ObjectId userId) async {
    final docs = await _db.statuses
        .find(
          where
              .eq('user_id', userId)
              .gte('expires_at', DateTime.now())
              .sortBy('created_at', descending: true),
        )
        .toList();
    return docs.map((d) => StatusModel.fromMap(d)).toList();
  }

  /// Records that [viewerId] saw the given status. Idempotent.
  Future<StatusModel?> markViewed(ObjectId statusId, ObjectId viewerId) async {
    final status = await getStatusById(statusId);
    if (status == null) return null;
    if (status.isViewedBy(viewerId)) return status;

    await _db.statuses.updateOne(
      where.eq('_id', statusId),
      modify.push('viewers', viewerId),
    );
    return getStatusById(statusId);
  }

  Future<void> deleteStatus(ObjectId statusId, ObjectId userId) async {
    await _db.statuses.deleteOne(
      where.eq('_id', statusId).eq('user_id', userId),
    );
  }

  /// Returns true if the given file URL belongs to a status that is still
  /// active (not expired). Status media is ephemeral and broadcast to
  /// authenticated users for the status lifetime.
  Future<bool> isStatusFileSharedWithUser(
      ObjectId userId, String fileUrl) async {
    final status = await _db.statuses.findOne({'media_path': fileUrl});
    if (status == null) return false;

    final expiresAt = status['expires_at'] as DateTime?;
    if (expiresAt == null) return false;

    return DateTime.now().isBefore(expiresAt);
  }
}
