import '../config/app_config.dart';
import '../models/group_message_model.dart';
import '../models/group_model.dart';
import 'database_service.dart';

class GroupService {
  final DatabaseService _db = DatabaseService();

  Future<GroupModel> createGroup({
    required String name,
    String? avatarUrl,
    required String creatorId,
    required List<String> memberIds,
  }) async {
    // Creator is always a member.
    final allMembers = <String>{creatorId, ...memberIds}.toList();
    final row = await _db.queryOne(
      '''
      INSERT INTO groups (name, avatar_url, creator_id, member_ids)
      VALUES (@name, @avatar_url, @creator_id:uuid, @member_ids:jsonb)
      RETURNING *
      ''',
      parameters: {
        'name': name,
        'avatar_url': avatarUrl,
        'creator_id': creatorId,
        'member_ids': allMembers,
      },
    );
    return GroupModel.fromMap(row!);
  }

  Future<GroupModel?> getGroupById(String groupId) async {
    final row = await _db.queryOne(
      'SELECT * FROM groups WHERE id = @id:uuid',
      parameters: {'id': groupId},
    );
    if (row == null) return null;
    return GroupModel.fromMap(row);
  }

  /// Returns groups the user is a member of.
  Future<List<GroupModel>> getGroupsForUser(String userId) async {
    final rows = await _db.query(
      '''
      SELECT * FROM groups
      WHERE member_ids @> to_jsonb(ARRAY[@user_id:text])
      ORDER BY created_at DESC
      ''',
      parameters: {'user_id': userId},
    );
    return rows.map(GroupModel.fromMap).toList();
  }

  Future<GroupModel?> addMembers(
    String groupId,
    List<String> newMemberIds,
  ) async {
    final group = await getGroupById(groupId);
    if (group == null) return null;

    final updated = <String>{...group.memberIds, ...newMemberIds}.toList();
    await _db.execute(
      'UPDATE groups SET member_ids = @member_ids:jsonb, updated_at = now() WHERE id = @id:uuid',
      parameters: {'member_ids': updated, 'id': groupId},
    );
    return getGroupById(groupId);
  }

  Future<GroupModel?> removeMember(
    String groupId,
    String memberId,
  ) async {
    final group = await getGroupById(groupId);
    if (group == null) return null;

    final updated = group.memberIds.where((m) => m != memberId).toList();
    await _db.execute(
      'UPDATE groups SET member_ids = @member_ids:jsonb, updated_at = now() WHERE id = @id:uuid',
      parameters: {'member_ids': updated, 'id': groupId},
    );
    return getGroupById(groupId);
  }

  Future<GroupModel?> updateName(String groupId, String name) async {
    await _db.execute(
      'UPDATE groups SET name = @name, updated_at = now() WHERE id = @id:uuid',
      parameters: {'name': name, 'id': groupId},
    );
    return getGroupById(groupId);
  }

  // ---------------------------------------------------------------------------
  // Group messages
  // ---------------------------------------------------------------------------

  Future<GroupMessageModel> sendGroupMessage({
    required String groupId,
    required String senderId,
    required String messageType,
    required String content,
    String? filePath,
    String? fileName,
    int? fileSize,
    String? mediaType,
    String encryption = 'none',
    int? cipherType,
    String? cipherBody,
  }) async {
    final row = await _db.queryOne(
      '''
      INSERT INTO group_messages
        (group_id, sender_id, message_type, content, file_path, file_name,
         file_size, media_type, status, encryption, cipher_type, cipher_body)
      VALUES
        (@group_id:uuid, @sender_id:uuid, @message_type, @content, @file_path,
         @file_name, @file_size, @media_type, @status, @encryption, @cipher_type, @cipher_body)
      RETURNING *
      ''',
      parameters: {
        'group_id': groupId,
        'sender_id': senderId,
        'message_type': messageType,
        'content': content,
        'file_path': filePath,
        'file_name': fileName,
        'file_size': fileSize,
        'media_type': mediaType,
        'status': AppConfig.messageStatusSent,
        'encryption': encryption,
        'cipher_type': cipherType,
        'cipher_body': cipherBody,
      },
    );
    return GroupMessageModel.fromMap(row!);
  }

  Future<List<GroupMessageModel>> getGroupMessages({
    required String groupId,
    int limit = 50,
    int skip = 0,
  }) async {
    final rows = await _db.query(
      '''
      SELECT * FROM group_messages
      WHERE group_id = @group_id:uuid
      ORDER BY created_at DESC
      LIMIT @limit OFFSET @skip
      ''',
      parameters: {'group_id': groupId, 'limit': limit, 'skip': skip},
    );
    return rows.map(GroupMessageModel.fromMap).toList();
  }

  /// Returns true if the file is referenced by a group message in a group the
  /// user is a member of.
  Future<bool> isGroupFileSharedWithUser(
    String userId,
    String fileUrl,
  ) async {
    final groupMessage = await _db.queryOne(
      'SELECT group_id FROM group_messages WHERE file_path = @file_url LIMIT 1',
      parameters: {'file_url': fileUrl},
    );
    if (groupMessage == null) return false;

    final group = await getGroupById(groupMessage['group_id'] as String);
    return group?.isMember(userId) ?? false;
  }

  /// Searches plaintext group message content across groups the user belongs
  /// to. The user input is matched with an escaped ILIKE pattern (never regex).
  Future<List<GroupMessageModel>> searchGroupMessages({
    required String userId,
    required String query,
    int limit = 50,
  }) async {
    if (query.isEmpty) return [];

    final groups = await getGroupsForUser(userId);
    if (groups.isEmpty) return [];

    final parameters = <String, Object?>{
      'pattern': '%${_escapeLike(query)}%',
      'limit': limit,
    };
    final placeholders = <String>[];
    for (var i = 0; i < groups.length; i++) {
      parameters['g$i'] = groups[i].id;
      placeholders.add('@g$i::uuid');
    }

    final rows = await _db.query(
      '''
      SELECT * FROM group_messages
      WHERE group_id IN (${placeholders.join(', ')})
        AND content ILIKE @pattern
      ORDER BY created_at DESC
      LIMIT @limit
      ''',
      parameters: parameters,
    );
    return rows.map(GroupMessageModel.fromMap).toList();
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
