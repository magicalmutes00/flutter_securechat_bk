/// User model backed by the Supabase `users` table.
///
/// Supports multiple login methods: phone, email/password, and Firebase
/// (phone/email/Google) — each identifier column is nullable and unique.
class UserModel {
  final String id; // UUID
  final String? phone;
  final String? email;
  final String? firebaseUid;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final String? about;
  final String? passwordHash; // For email/password auth
  final String?
      phoneHash; // SHA-256 of canonical phone, used for contacts discovery
  final String? currentRefreshJti; // Server-side refresh token revocation
  final Map<String, String> privacy; // last_seen / avatar / about
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
    this.about,
    this.passwordHash,
    this.phoneHash,
    this.currentRefreshJti,
    this.privacy = const {
      'last_seen': 'everyone',
      'avatar': 'everyone',
      'about': 'everyone',
    },
    required this.createdAt,
    required this.updatedAt,
    this.isOnline = false,
    this.lastSeen,
  });

  /// Create UserModel from a Postgres row (column-name map).
  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'] as String,
      phone: map['phone'] as String?,
      email: map['email'] as String?,
      firebaseUid: map['firebase_uid'] as String?,
      username: map['username'] as String?,
      displayName: map['display_name'] as String?,
      avatarUrl: map['avatar_url'] as String?,
      about: map['about'] as String?,
      passwordHash: map['password_hash'] as String?,
      phoneHash: map['phone_hash'] as String?,
      currentRefreshJti: map['current_refresh_jti'] as String?,
      privacy: _decodePrivacy(map['privacy']),
      createdAt: (map['created_at'] as DateTime).toUtc(),
      updatedAt: (map['updated_at'] as DateTime).toUtc(),
      isOnline: map['is_online'] as bool? ?? false,
      lastSeen: (map['last_seen'] as DateTime?)?.toUtc(),
    );
  }

  static Map<String, String> _decodePrivacy(dynamic raw) {
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k as String, v as String));
    }
    return const {};
  }

  /// Convert to JSON for API response
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'phone': phone,
      'email': email,
      'firebase_uid': firebaseUid,
      'username': username,
      'display_name': displayName,
      'avatar_url': avatarUrl,
      'about': about,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'is_online': isOnline,
      'last_seen': lastSeen?.toIso8601String(),
      'privacy': privacy,
    };
  }

  /// Public projection for user search and contact discovery: omits phone
  /// (unless explicitly included, e.g. contact matching where the requester
  /// already knows the number), email, and Firebase identifiers.
  Map<String, dynamic> toPublicJson({bool includePhone = false}) {
    return {
      if (includePhone && phone != null) 'phone': phone,
      'id': id,
      'username': username,
      'display_name': displayName,
      'avatar_url': avatarUrl,
      'about': about,
      'created_at': createdAt.toIso8601String(),
      'is_online': isOnline,
      'last_seen': lastSeen?.toIso8601String(),
    };
  }

  /// Create a copy with updated fields
  UserModel copyWith({
    String? id,
    String? phone,
    String? email,
    String? firebaseUid,
    String? username,
    String? displayName,
    String? avatarUrl,
    String? about,
    String? passwordHash,
    String? phoneHash,
    String? currentRefreshJti,
    Map<String, String>? privacy,
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
      about: about ?? this.about,
      passwordHash: passwordHash ?? this.passwordHash,
      phoneHash: phoneHash ?? this.phoneHash,
      currentRefreshJti: currentRefreshJti ?? this.currentRefreshJti,
      privacy: privacy ?? this.privacy,
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
