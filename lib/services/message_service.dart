import '../config/app_config.dart';
import '../models/message_model.dart';
import '../utils/validate.dart';
import 'database_service.dart';

class MessageService {
  final DatabaseService _db = DatabaseService();

  Future<MessageModel> sendMessage({
    required String senderId,
    required String receiverId,
    required String messageType,
    required String content,
    String? filePath,
    String? fileName,
    int? fileSize,
    String? mediaType,
    String? replyToId,
    String encryption = 'none',
    int? cipherType,
    String? cipherBody,
  }) async {
    final resolvedReplyToId =
        await _resolveReplyTarget(replyToId, senderId, receiverId);
    final row = await _db.queryOne(
      '''
      INSERT INTO messages
        (sender_id, receiver_id, message_type, content, file_path, file_name,
         file_size, media_type, status, reply_to_id, encryption, cipher_type, cipher_body)
      VALUES
        (@sender_id:uuid, @receiver_id:uuid, @message_type, @content, @file_path,
         @file_name, @file_size, @media_type, @status, @reply_to_id, @encryption, @cipher_type, @cipher_body)
      RETURNING *
      ''',
      parameters: {
        'sender_id': senderId,
        'receiver_id': receiverId,
        'message_type': messageType,
        'content': content,
        'file_path': filePath,
        'file_name': fileName,
        'file_size': fileSize,
        'media_type': mediaType,
        'status': AppConfig.messageStatusSent,
        'reply_to_id': resolvedReplyToId,
        'encryption': encryption,
        'cipher_type': cipherType,
        'cipher_body': cipherBody,
      },
    );
    return MessageModel.fromMap(row!);
  }

  /// Resolves a client-supplied `reply_to_id` to a persisted link, or null.
  ///
  /// The target must exist and belong to the same 1:1 conversation; anything
  /// else (malformed id, deleted message, id from an unrelated chat) is
  /// refused by dropping the link rather than failing the send.
  Future<String?> _resolveReplyTarget(
    String? replyToId,
    String senderId,
    String receiverId,
  ) async {
    if (replyToId == null || replyToId.isEmpty) return null;
    if (!isValidUuid(replyToId)) return null;
    final target = await getMessageById(replyToId);
    if (target == null) return null;
    final sameConversation =
        (target.senderId == senderId && target.receiverId == receiverId) ||
            (target.senderId == receiverId && target.receiverId == senderId);
    return sameConversation ? replyToId : null;
  }

  Future<List<MessageModel>> getMessages({
    required String userId1,
    required String userId2,
    int limit = 50,
    int skip = 0,
  }) async {
    final rows = await _db.query(
      '''
      SELECT * FROM messages
      WHERE (sender_id = @u1:uuid AND receiver_id = @u2:uuid)
         OR (sender_id = @u2:uuid AND receiver_id = @u1:uuid)
      ORDER BY created_at DESC
      LIMIT @limit OFFSET @skip
      ''',
      parameters: {'u1': userId1, 'u2': userId2, 'limit': limit, 'skip': skip},
    );
    return rows.map(MessageModel.fromMap).toList();
  }

  Future<MessageModel?> getMessageById(String id) async {
    final row = await _db.queryOne(
      'SELECT * FROM messages WHERE id = @id:uuid',
      parameters: {'id': id},
    );
    if (row == null) return null;
    return MessageModel.fromMap(row);
  }

  Future<void> updateMessageStatus(String id, String status) async {
    await _db.execute(
      'UPDATE messages SET status = @status, updated_at = now() WHERE id = @id:uuid',
      parameters: {'status': status, 'id': id},
    );
  }

  Future<void> markMessagesAsRead(String senderId, String receiverId) async {
    await _db.execute(
      '''
      UPDATE messages SET status = @status, updated_at = now()
      WHERE sender_id = @sender_id:uuid AND receiver_id = @receiver_id:uuid
      ''',
      parameters: {
        'status': AppConfig.messageStatusRead,
        'sender_id': senderId,
        'receiver_id': receiverId,
      },
    );
  }

  Future<void> deleteMessage(String id) async {
    await _db.execute(
      'DELETE FROM messages WHERE id = @id:uuid',
      parameters: {'id': id},
    );
  }

  /// Returns true if the file referenced by [fileUrl] belongs to a message in a
  /// conversation that [userId] is a participant of.
  Future<bool> isFileSharedWithUser(String userId, String fileUrl) async {
    final row = await _db.queryOne(
      '''
      SELECT 1 FROM messages
      WHERE file_path = @file_url
        AND (sender_id = @user_id:uuid OR receiver_id = @user_id:uuid)
      LIMIT 1
      ''',
      parameters: {'file_url': fileUrl, 'user_id': userId},
    );
    return row != null;
  }

  /// Searches plaintext message content across conversations [userId] is a
  /// participant of, newest first.
  ///
  /// The content match is scoped under the participant condition (AND), so a
  /// common substring can never surface another user's messages. User input
  /// is matched via an escaped ILIKE pattern — never regex.
  Future<List<MessageModel>> searchMessages({
    required String userId,
    required String query,
    int limit = 50,
  }) async {
    if (query.isEmpty) return [];

    final rows = await _db.query(
      '''
      SELECT * FROM messages
      WHERE (sender_id = @user_id:uuid OR receiver_id = @user_id:uuid)
        AND content ILIKE @pattern
      ORDER BY created_at DESC
      LIMIT @limit
      ''',
      parameters: {
        'user_id': userId,
        'pattern': '%${_escapeLike(query)}%',
        'limit': limit,
      },
    );
    return rows.map(MessageModel.fromMap).toList();
  }

  /// Marks [messageId] as delivered only when [receiverId] is the message's
  /// actual recipient. Returns false when the message does not exist or the
  /// claiming user is not its receiver, so delivery receipts cannot be
  /// spoofed for other users' messages.
  Future<bool> markDelivered(String messageId, String receiverId) async {
    final result = await _db.executeCount(
      '''
      UPDATE messages SET status = @status, updated_at = now()
      WHERE id = @message_id:uuid AND receiver_id = @receiver_id:uuid
      ''',
      parameters: {
        'status': AppConfig.messageStatusDelivered,
        'message_id': messageId,
        'receiver_id': receiverId,
      },
    );
    return result > 0;
  }

  /// Returns distinct conversation partners and their latest message for a
  /// user: rows of `{partner_id, last_message, unread_count}`.
  Future<List<Map<String, dynamic>>> getConversations(String userId) async {
    final rows = await _db.query(
      '''
      WITH scoped AS (
        SELECT
          CASE WHEN sender_id = @me:uuid THEN receiver_id ELSE sender_id END AS partner_id,
          id, receiver_id, status, created_at
        FROM messages
        WHERE sender_id = @me:uuid OR receiver_id = @me:uuid
      ),
      latest AS (
        SELECT DISTINCT ON (partner_id) partner_id, id
        FROM scoped
        ORDER BY partner_id, created_at DESC
      ),
      unread AS (
        SELECT partner_id, count(*)::int AS unread_count
        FROM scoped
        WHERE receiver_id = @me:uuid AND status <> 'read'
        GROUP BY partner_id
      )
      SELECT l.partner_id, m.*, COALESCE(u.unread_count, 0) AS unread_count
      FROM latest l
      JOIN messages m ON m.id = l.id
      LEFT JOIN unread u ON u.partner_id = l.partner_id
      ORDER BY m.created_at DESC
      ''',
      parameters: {'me': userId},
    );

    return rows.map((row) {
      // Pull the message columns out of the flat row; partner_id and
      // unread_count are not part of the message shape.
      final messageRow = Map<String, dynamic>.from(row)
        ..remove('partner_id')
        ..remove('unread_count');
      return <String, dynamic>{
        'partner_id': row['partner_id'] as String,
        'last_message': MessageModel.fromMap(messageRow).toJson(),
        'unread_count': (row['unread_count'] as num?)?.toInt() ?? 0,
      };
    }).toList();
  }

  /// Distinct users [userId] has exchanged at least one message with — used
  /// to scope presence broadcasts instead of notifying every connected user.
  Future<Set<String>> getConversationPartnerIds(String userId) async {
    final rows = await _db.query(
      '''
      SELECT DISTINCT CASE WHEN sender_id = @me:uuid THEN receiver_id ELSE sender_id END AS partner_id
      FROM messages
      WHERE sender_id = @me:uuid OR receiver_id = @me:uuid
      ''',
      parameters: {'me': userId},
    );
    return rows.map((r) => r['partner_id'] as String).toSet();
  }

  /// Escapes LIKE metacharacters so user-supplied search text is treated
  /// literally by the SQL pattern matcher.
  static String _escapeLike(String input) {
    return input
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
  }
}
