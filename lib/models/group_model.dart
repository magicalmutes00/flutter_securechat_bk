/// Group model backed by the Supabase `groups` table.
///
/// `member_ids` is stored as a JSONB array of user UUIDs — groups are small,
/// so membership checks are done in Dart after a single-row fetch.
class GroupModel {
  final String id; // UUID
  final String name;
  final String? avatarUrl;
  final String creatorId;
  final List<String> memberIds;
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
      id: map['id'] as String,
      name: map['name'] as String,
      avatarUrl: map['avatar_url'] as String?,
      creatorId: map['creator_id'] as String,
      memberIds: _decodeIds(map['member_ids']),
      createdAt: (map['created_at'] as DateTime).toUtc(),
      updatedAt: (map['updated_at'] as DateTime).toUtc(),
    );
  }

  static List<String> _decodeIds(dynamic raw) {
    if (raw is List) {
      return raw.map((e) => e as String).toList();
    }
    return const [];
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'avatar_url': avatarUrl,
      'creator_id': creatorId,
      'member_ids': memberIds,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  bool isMember(String userId) => memberIds.contains(userId);
}
