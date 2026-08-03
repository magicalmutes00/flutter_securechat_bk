import 'package:mongo_dart/mongo_dart.dart';

/// Status model (ephemeral "stories") for MongoDB.
///
/// A status is a short-lived post (text and/or media) that expires after
/// [expiresAt]. Viewers are tracked per status for "seen by" reporting.
class StatusModel {
  final ObjectId id;
  final ObjectId userId;
  final String? text;
  final String? mediaPath;
  final String? mediaType;
  final DateTime createdAt;
  final DateTime expiresAt;
  final List<ObjectId> viewers;

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
      id: map['_id'] as ObjectId,
      userId: map['user_id'] as ObjectId,
      text: map['text'] as String?,
      mediaPath: map['media_path'] as String?,
      mediaType: map['media_type'] as String?,
      createdAt: map['created_at'] as DateTime,
      expiresAt: map['expires_at'] as DateTime,
      viewers: (map['viewers'] as List<dynamic>? ?? [])
          .map((e) => e as ObjectId)
          .toList(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      '_id': id,
      'user_id': userId,
      'text': text,
      'media_path': mediaPath,
      'media_type': mediaType,
      'created_at': createdAt,
      'expires_at': expiresAt,
      'viewers': viewers,
    };
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id.toHexString(),
      'user_id': userId.toHexString(),
      'text': text,
      'media_path': mediaPath,
      'media_type': mediaType,
      'created_at': createdAt.toIso8601String(),
      'expires_at': expiresAt.toIso8601String(),
      'viewers': viewers.map((v) => v.toHexString()).toList(),
    };
  }

  bool isExpired([DateTime? now]) => (now ?? DateTime.now()).isAfter(expiresAt);

  bool isViewedBy(ObjectId viewerId) => viewers.contains(viewerId);
}
