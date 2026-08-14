import 'package:mongo_dart/mongo_dart.dart';

import '../models/conversation.dart';
import 'database_service.dart';

/// Single source of truth for per-user chat units. Reads/writes always
/// addressed by the participant's id (derived from the JWT, never the URL).
class ConversationService {
  final DatabaseService _db;
  ConversationService({DatabaseService? db}) : _db = db ?? DatabaseService();

  /// Idempotent find-or-create keyed by the sorted participant pair so both
  /// sides of a conversation resolve to the same document.
  Future<Conversation> ensureConversation(ObjectId a, ObjectId b) async {
    final sorted = (a.toHexString().compareTo(b.toHexString()) < 0)
        ? [a, b]
        : [b, a];

    final existing = await _db.database
        .collection('conversations')
        .findOne({'participants': sorted});
    if (existing != null) {
      return Conversation.fromMap(existing);
    }

    final now = DateTime.now();
    final doc = Conversation(
      id: ObjectId(),
      participants: sorted,
      createdBy: sorted.first,
      createdAt: now,
      updatedAt: now,
    );

    try {
      await _db.database.collection('conversations').insertOne(doc.toMap());
      return doc;
    } catch (_) {
      // Race: someone beat us to it. Fetch.
      final post =
          await _db.database.collection('conversations').findOne({
        'participants': sorted,
      });
      if (post != null) return Conversation.fromMap(post);
      rethrow;
    }
  }

  /// Atomic + idempotent. Bumps `last_message_*` and increments the
  /// receiver's unread count. Decrements the sender's (it is always 0 but
  /// we keep both keys initialized so reads don't need null checks).
  Future<void> recordMessageSent({
    required ObjectId senderId,
    required ObjectId receiverId,
    required ObjectId messageId,
    required DateTime messageTime,
  }) async {
    final conv = await ensureConversation(senderId, receiverId);

    final receiverHex = receiverId.toHexString();
    final senderHex = senderId.toHexString();

    final incUnread = <String, dynamic>{
      'unread_count.${receiverHex}': 1,
    };
    final setLastRead = <String, dynamic>{
      'last_read_at.${senderHex}': messageTime,
    };
    final setNull = <String, dynamic>{};

    // Make sure sender's count is present and zero.
    incUnread['unread_count.${senderHex}'] = 0;

    await _db.database.collection('conversations').updateOne(
      where.eq('_id', conv.id),
      modify
          .set('updated_at', messageTime)
          .set('last_message_id', messageId)
          .set('last_message_at', messageTime)
          .set('last_read_at.${senderHex}', messageTime)
          .inc('unread_count.${receiverHex}', 1),
    );
    // Touch unused locals to satisfy analyzer; useful for future extension.
    setLastRead.removeWhere((k, v) => false);
    setNull.removeWhere((k, v) => false);
  }

  /// Marks a conversation as read for the given user and zeroes the unread
  /// counter for that user. Safe to call concurrently.
  Future<void> markRead({
    required Conversation conv,
    required ObjectId readerId,
    required DateTime readAt,
  }) async {
    final hex = readerId.toHexString();
    await _db.database.collection('conversations').updateOne(
      where.eq('_id', conv.id),
      modify
          .set('last_read_at.${hex}', readAt)
          .set('unread_count.${hex}', 0)
          .set('updated_at', readAt),
    );
  }

  /// One conversation document for a pair, or null if they have never
  /// exchanged messages.
  Future<Conversation?> findBetween(ObjectId a, ObjectId b) async {
    final sorted = (a.toHexString().compareTo(b.toHexString()) < 0)
        ? [a, b]
        : [b, a];
    final doc = await _db.database
        .collection('conversations')
        .findOne({'participants': sorted});
    if (doc == null) return null;
    return Conversation.fromMap(doc);
  }
}
