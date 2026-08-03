import 'package:mongo_dart/mongo_dart.dart';

/// Group model for MongoDB.
class GroupModel {
  final ObjectId id;
  final String name;
  final String? avatarUrl;
  final ObjectId creatorId;
  final List<ObjectId> memberIds;
  final DateTime createdAt;
  final DateTime updatedAt;

  GroupModel({
    required this.id,
    required this.name,
    this.avatarUrl,
    required this.creatorId,
    required this.memberIds,
    required this.createdAt,
    required this.updatedAt,
  });

  factory GroupModel.fromMap(Map<String, dynamic> map) {
    return GroupModel(
      id: map['_id'] as ObjectId,
      name: map['name'] as String,
      avatarUrl: map['avatar_url'] as String?,
      creatorId: map['creator_id'] as ObjectId,
      memberIds: (map['member_ids'] as List<dynamic>? ?? [])
          .map((e) => e as ObjectId)
          .toList(),
      createdAt: map['created_at'] as DateTime,
      updatedAt: map['updated_at'] as DateTime,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      '_id': id,
      'name': name,
      'avatar_url': avatarUrl,
      'creator_id': creatorId,
      'member_ids': memberIds,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id.toHexString(),
      'name': name,
      'avatar_url': avatarUrl,
      'creator_id': creatorId.toHexString(),
      'member_ids': memberIds.map((m) => m.toHexString()).toList(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  bool isMember(ObjectId userId) => memberIds.contains(userId);
}
