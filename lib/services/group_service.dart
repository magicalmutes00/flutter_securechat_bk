import 'package:mongo_dart/mongo_dart.dart';
import '../models/group_model.dart';
import '../models/group_message_model.dart';
import '../config/app_config.dart';
import 'database_service.dart';

class GroupService {
  final DatabaseService _db = DatabaseService();

  Future<GroupModel> createGroup({
    required String name,
    String? avatarUrl,
    required ObjectId creatorId,
    required List<ObjectId> memberIds,
  }) async {
    final now = DateTime.now();
    // Creator is always a member.
    final allMembers = <ObjectId>{creatorId, ...memberIds}.toList();
    final group = GroupModel(
      id: ObjectId(),
      name: name,
      avatarUrl: avatarUrl,
      creatorId: creatorId,
      memberIds: allMembers,
      createdAt: now,
      updatedAt: now,
    );
    await _db.groups.insertOne(group.toMap());
    return group;
  }

  Future<GroupModel?> getGroupById(ObjectId groupId) async {
    final doc = await _db.groups.findOne({'_id': groupId});
    if (doc == null) return null;
    return GroupModel.fromMap(doc);
  }

  /// Returns groups the user is a member of.
  Future<List<GroupModel>> getGroupsForUser(ObjectId userId) async {
    final docs = await _db.groups.find(where.eq('member_ids', userId)).toList();
    return docs.map((d) => GroupModel.fromMap(d)).toList();
  }

  Future<GroupModel?> addMembers(
    ObjectId groupId,
    List<ObjectId> newMemberIds,
  ) async {
    final group = await getGroupById(groupId);
    if (group == null) return null;

    final updated = {...group.memberIds, ...newMemberIds}.toList();
    await _db.groups.updateOne(
      where.eq('_id', groupId),
      modify.set('member_ids', updated).set('updated_at', DateTime.now()),
    );
    return getGroupById(groupId);
  }

  Future<GroupModel?> removeMember(
    ObjectId groupId,
    ObjectId memberId,
  ) async {
    final group = await getGroupById(groupId);
    if (group == null) return null;

    final updated = group.memberIds.where((m) => m != memberId).toList();
    await _db.groups.updateOne(
      where.eq('_id', groupId),
      modify.set('member_ids', updated).set('updated_at', DateTime.now()),
    );
    return getGroupById(groupId);
  }

  Future<GroupModel?> updateName(ObjectId groupId, String name) async {
    await _db.groups.updateOne(
      where.eq('_id', groupId),
      modify.set('name', name).set('updated_at', DateTime.now()),
    );
    return getGroupById(groupId);
  }

  // ---------------------------------------------------------------------------
  // Group messages
  // ---------------------------------------------------------------------------

  Future<GroupMessageModel> sendGroupMessage({
    required ObjectId groupId,
    required ObjectId senderId,
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
    final now = DateTime.now();
    final message = GroupMessageModel(
      id: ObjectId(),
      groupId: groupId,
      senderId: senderId,
      messageType: messageType,
      content: content,
      filePath: filePath,
      fileName: fileName,
      fileSize: fileSize,
      mediaType: mediaType,
      status: AppConfig.messageStatusSent,
      createdAt: now,
      updatedAt: now,
      encryption: encryption,
      cipherType: cipherType,
      cipherBody: cipherBody,
    );
    await _db.groupMessages.insertOne(message.toMap());
    return message;
  }

  Future<List<GroupMessageModel>> getGroupMessages({
    required ObjectId groupId,
    int limit = 50,
    int skip = 0,
  }) async {
    final query = where
        .eq('group_id', groupId)
        .sortBy('created_at', descending: true)
        .limit(limit)
        .skip(skip);
    final docs = await _db.groupMessages.find(query).toList();
    return docs.map((d) => GroupMessageModel.fromMap(d)).toList();
  }

  /// Returns true if the file is referenced by a group message in a group the
  /// user is a member of.
  Future<bool> isGroupFileSharedWithUser(
    ObjectId userId,
    String fileUrl,
  ) async {
    final groupMessage = await _db.groupMessages.findOne({
      'file_path': fileUrl,
    });
    if (groupMessage == null) return false;

    final groupId = groupMessage['group_id'] as ObjectId?;
    if (groupId == null) return false;

    final group = await getGroupById(groupId);
    return group?.isMember(userId) ?? false;
  }

  /// Searches plaintext group message content across groups the user belongs to.
  Future<List<GroupMessageModel>> searchGroupMessages({
    required ObjectId userId,
    required String query,
    int limit = 50,
  }) async {
    if (query.isEmpty) return [];

    final groups = await getGroupsForUser(userId);
    if (groups.isEmpty) return [];

    final groupIds = groups.map((g) => g.id).toList();
    final search = where
        .oneFrom('group_id', groupIds)
        .match('content', RegExp(query, caseSensitive: false).pattern)
        .sortBy('created_at', descending: true)
        .limit(limit);

    final docs = await _db.groupMessages.find(search).toList();
    return docs.map((d) => GroupMessageModel.fromMap(d)).toList();
  }
}
