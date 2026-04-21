import 'package:mongo_dart/mongo_dart.dart';

/// User model for MongoDB
/// Represents a user in the SecureChat application
/// Supports multiple login methods: phone, email/password, and Google sign-in
class UserModel {
  final ObjectId id;
  final String? phone; // Nullable - may not be available for all login methods
  final String? email; // Nullable - email/password and Google login
  final String? firebaseUid; // Firebase UID for cross-referencing users
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final String? passwordHash; // For email/password auth
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isOnline;
  final DateTime? lastSeen;

  UserModel({
    required this.id,
    this.phone,
    this.email,
    this.firebaseUid,
    this.username,
    this.displayName,
    this.avatarUrl,
    this.passwordHash,
    required this.createdAt,
    required this.updatedAt,
    this.isOnline = false,
    this.lastSeen,
  });

  /// Create UserModel from MongoDB document
  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['_id'] as ObjectId,
      phone: map['phone'] as String?,
      email: map['email'] as String?,
      firebaseUid: map['firebase_uid'] as String?,
      username: map['username'] as String?,
      displayName: map['display_name'] as String?,
      avatarUrl: map['avatar_url'] as String?,
      passwordHash: map['password_hash'] as String?,
      createdAt: map['created_at'] as DateTime,
      updatedAt: map['updated_at'] as DateTime,
      isOnline: map['is_online'] as bool? ?? false,
      lastSeen: map['last_seen'] as DateTime?,
    );
  }

  /// Convert UserModel to MongoDB document
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      '_id': id,
      'username': username,
      'display_name': displayName,
      'avatar_url': avatarUrl,
      'password_hash': passwordHash,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'is_online': isOnline,
      'last_seen': lastSeen,
    };
    // Only add nullable fields if they have values
    if (phone != null) map['phone'] = phone;
    if (email != null) map['email'] = email;
    if (firebaseUid != null) map['firebase_uid'] = firebaseUid;
    return map;
  }

  /// Convert to JSON for API response
  Map<String, dynamic> toJson() {
    return {
      'id': id.toHexString(),
      'phone': phone,
      'email': email,
      'firebase_uid': firebaseUid,
      'username': username,
      'display_name': displayName,
      'avatar_url': avatarUrl,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'is_online': isOnline,
      'last_seen': lastSeen?.toIso8601String(),
    };
  }

  /// Create a copy with updated fields
  UserModel copyWith({
    ObjectId? id,
    String? phone,
    String? email,
    String? firebaseUid,
    String? username,
    String? displayName,
    String? avatarUrl,
    String? passwordHash,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isOnline,
    DateTime? lastSeen,
  }) {
    return UserModel(
      id: id ?? this.id,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      firebaseUid: firebaseUid ?? this.firebaseUid,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      passwordHash: passwordHash ?? this.passwordHash,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  @override
  String toString() {
    return 'UserModel(id: $id, phone: $phone, email: $email, firebaseUid: $firebaseUid, username: $username, displayName: $displayName)';
  }
}
