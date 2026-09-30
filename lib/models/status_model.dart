/// Status model (ephemeral "stories") backed by the Supabase `statuses` table.
///
/// A status is a short-lived post (text and/or media) that expires after
/// [expiresAt]. Viewers are tracked per status for "seen by" reporting.
class StatusModel {
  final String id; // UUID
  final String userId;
  final String? text;
  final String? mediaPath;
  final String? mediaType;
  final DateTime createdAt;
  final DateTime expiresAt;
  final List<String> viewers;

  StatusModel({
    required this.id,
    required this.userId,
    this.text,
    this.mediaPath,
    this.mediaType,
    required this.createdAt,
    required this.expiresAt,
    this.viewers = const [],
  });

  factory StatusModel.fromMap(Map<String, dynamic> map) {
    return StatusModel(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      text: map['text'] as String?,
      mediaPath: map['media_path'] as String?,
      mediaType: map['media_type'] as String?,
      createdAt: (map['created_at'] as DateTime).toUtc(),
      expiresAt: (map['expires_at'] as DateTime).toUtc(),
      viewers: (map['viewers'] as List?)?.map((e) => e as String).toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'text': text,
      'media_path': mediaPath,
      'media_type': mediaType,
      'created_at': createdAt.toIso8601String(),
      'expires_at': expiresAt.toIso8601String(),
      'viewers': viewers,
    };
  }

  bool isExpired([DateTime? now]) => (now ?? DateTime.now()).isAfter(expiresAt);

  bool isViewedBy(String viewerId) => viewers.contains(viewerId);
}
