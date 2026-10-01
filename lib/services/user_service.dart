import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/user_model.dart';
import 'database_service.dart';

class UserService {
  final DatabaseService _db = DatabaseService();

  Future<UserModel?> findUserByPhone(String phone) async {
    final row = await _db
        .queryOne('SELECT * FROM users WHERE phone = @phone', parameters: {
      'phone': phone,
    });
    if (row == null) return null;
    return UserModel.fromMap(row);
  }

  /// Find user by phone number with password
  Future<UserModel?> findUserByPhoneWithPassword(String phone) async {
    final row = await _db.queryOne(
      'SELECT * FROM users WHERE phone = @phone AND password_hash IS NOT NULL',
      parameters: {'phone': phone},
    );
    if (row == null) return null;
    return UserModel.fromMap(row);
  }

  /// Find user by email (case-insensitive)
  Future<UserModel?> findUserByEmail(String email) async {
    final row = await _db.queryOne(
      'SELECT * FROM users WHERE lower(email) = lower(@email)',
      parameters: {'email': email},
    );
    if (row == null) return null;
    return UserModel.fromMap(row);
  }

  /// Find user by Firebase UID
  Future<UserModel?> findUserByFirebaseUid(String firebaseUid) async {
    final row = await _db.queryOne(
      'SELECT * FROM users WHERE firebase_uid = @uid',
      parameters: {'uid': firebaseUid},
    );
    if (row == null) return null;
    return UserModel.fromMap(row);
  }

  Future<UserModel?> findUserById(String id) async {
    final row = await _db.queryOne(
      'SELECT * FROM users WHERE id = @id:uuid',
      parameters: {'id': id},
    );
    if (row == null) return null;
    return UserModel.fromMap(row);
  }

  Future<UserModel> createUser(String phone,
      {String? username, String? displayName}) async {
    return _insertUser(
      columns: 'phone, display_name, phone_hash',
      parameters: {
        'phone': phone,
        'display_name': displayName ?? phone,
        'phone_hash': _hashPhone(phone),
      },
    );
  }

  /// Create a new user with email/password authentication
  Future<UserModel> createUserWithEmail({
    required String email,
    required String passwordHash,
    String? displayName,
  }) async {
    return _insertUser(
      columns: 'email, password_hash, display_name',
      parameters: {
        'email': email,
        'password_hash': passwordHash,
        'display_name': displayName ?? email.split('@').first,
      },
    );
  }

  /// Create a new user with phone/password authentication
  Future<UserModel> createUserWithPhone({
    required String phone,
    required String passwordHash,
    String? displayName,
  }) async {
    return _insertUser(
      columns: 'phone, password_hash, display_name, phone_hash',
      parameters: {
        'phone': phone,
        'password_hash': passwordHash,
        'display_name': displayName ?? phone,
        'phone_hash': _hashPhone(phone),
      },
    );
  }

  /// Create a new user with full Firebase auth support
  Future<UserModel> createUserFromFirebase({
    required String firebaseUid,
    String? phone,
    String? email,
    String? displayName,
  }) async {
    return _insertUser(
      columns: 'firebase_uid, phone, email, display_name',
      parameters: {
        'firebase_uid': firebaseUid,
        'phone': phone,
        'email': email,
        'display_name':
            displayName ?? (email != null ? email.split('@').first : null),
      },
    );
  }

  Future<UserModel> _insertUser({
    required String columns,
    required Map<String, Object?> parameters,
  }) async {
    final row = await _db.queryOne(
      'INSERT INTO users ($columns) VALUES (${_placeholders(columns)}) RETURNING *',
      parameters: parameters,
    );
    return UserModel.fromMap(row!);
  }

  static String _placeholders(String columns) {
    return columns
        .split(',')
        .map((c) => '@${c.trim()}')
        .join(', ');
  }

  /// Get or create user based on Firebase authentication
  Future<UserModel> getOrCreateUserFromFirebase({
    required String firebaseUid,
    String? phone,
    String? email,
    String? displayName,
  }) async {
    // First, try to find user by Firebase UID (most reliable)
    var user = await findUserByFirebaseUid(firebaseUid);

    if (user != null) {
      user = await _updateUserIfNeeded(user,
          phone: phone, email: email, displayName: displayName);
      return user;
    }

    // Try to find by phone or email first to handle edge cases
    if (phone != null) {
      user = await findUserByPhone(phone);
      if (user != null) {
        return await _linkFirebaseUidToUser(user.id, firebaseUid);
      }
    }

    if (email != null) {
      user = await findUserByEmail(email);
      if (user != null) {
        return await _linkFirebaseUidToUser(user.id, firebaseUid);
      }
    }

    // Create new user
    return await createUserFromFirebase(
      firebaseUid: firebaseUid,
      phone: phone,
      email: email,
      displayName: displayName,
    );
  }

  /// Update user with new information if available
  Future<UserModel> _updateUserIfNeeded(UserModel user,
      {String? phone, String? email, String? displayName}) async {
    final sets = <String>['updated_at = now()'];
    final parameters = <String, Object?>{'id': user.id};

    if (user.phone == null && phone != null) {
      sets.add('phone = @phone');
      parameters['phone'] = phone;
    }
    if (user.email == null && email != null) {
      sets.add('email = @email');
      parameters['email'] = email;
    }
    if (user.displayName == null && displayName != null) {
      sets.add('display_name = @display_name');
      parameters['display_name'] = displayName;
    }

    if (sets.length == 1) return user;

    await _db.execute(
      'UPDATE users SET ${sets.join(', ')} WHERE id = @id:uuid',
      parameters: parameters,
    );
    return (await findUserById(user.id))!;
  }

  /// Link an existing user to a Firebase UID
  Future<UserModel> _linkFirebaseUidToUser(
      String userId, String firebaseUid) async {
    await _db.execute(
      'UPDATE users SET firebase_uid = @uid, updated_at = now() WHERE id = @id:uuid',
      parameters: {'uid': firebaseUid, 'id': userId},
    );
    return (await findUserById(userId))!;
  }

  Future<UserModel?> updateUser(String id, Map<String, dynamic> updates) async {
    final sets = <String>['updated_at = now()'];
    final parameters = <String, Object?>{'id': id};

    if (updates.containsKey('display_name') &&
        updates['display_name'] != null) {
      sets.add('display_name = @display_name');
      parameters['display_name'] = updates['display_name'];
    }
    if (updates.containsKey('username') && updates['username'] != null) {
      sets.add('username = @username');
      parameters['username'] = updates['username'];
    }
    if (updates.containsKey('avatar_url') && updates['avatar_url'] != null) {
      sets.add('avatar_url = @avatar_url');
      parameters['avatar_url'] = updates['avatar_url'];
    }
    if (updates.containsKey('about') && updates['about'] != null) {
      sets.add('about = @about');
      parameters['about'] = updates['about'];
    }
    if (updates.containsKey('privacy') && updates['privacy'] is Map) {
      sets.add('privacy = @privacy:jsonb');
      parameters['privacy'] = updates['privacy'];
    }

    await _db.execute(
      'UPDATE users SET ${sets.join(', ')} WHERE id = @id:uuid',
      parameters: parameters,
    );
    return findUserById(id);
  }

  /// Returns registered users whose phone numbers match any of the supplied
  /// SHA-256 hashes. Used for privacy-preserving contact discovery.
  Future<List<UserModel>> findUsersByPhoneHashes(Set<String> hashes) async {
    if (hashes.isEmpty) return [];
    final params = <String, Object?>{};
    final placeholders = <String>[];
    var i = 0;
    for (final hash in hashes) {
      params['h$i'] = hash;
      placeholders.add('@h$i');
      i++;
    }
    final rows = await _db.query(
      'SELECT * FROM users WHERE phone_hash IN (${placeholders.join(', ')})',
      parameters: params,
    );
    return rows.map(UserModel.fromMap).toList();
  }

  static String _hashPhone(String phone) {
    return sha256.convert(utf8.encode(phone.trim())).toString();
  }

  Future<void> updateOnlineStatus(String id, bool isOnline) async {
    await _db.execute(
      'UPDATE users SET is_online = @online, last_seen = now() WHERE id = @id:uuid',
      parameters: {'online': isOnline, 'id': id},
    );
  }

  /// Search users by phone, username, display name, or email.
  ///
  /// The query is matched with an escaped `ILIKE` pattern (no regex), so
  /// user-supplied text can never become a query-language injection.
  Future<List<UserModel>> searchUsers(String query, {int limit = 20}) async {
    final pattern = _escapeLike(query);
    final rows = await _db.query(
      '''
      SELECT * FROM users
      WHERE phone ILIKE @pattern
         OR username ILIKE @pattern
         OR display_name ILIKE @pattern
         OR email ILIKE @pattern
      ORDER BY created_at DESC
      LIMIT @limit
      ''',
      parameters: {'pattern': '%$pattern%', 'limit': limit},
    );
    return rows.map(UserModel.fromMap).toList();
  }

  /// Escapes LIKE metacharacters so user-supplied search text is treated
  /// literally by the SQL pattern matcher.
  static String _escapeLike(String input) {
    return input.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
  }

  // ---------------------------------------------------------------------------
  // Refresh token revocation
  // ---------------------------------------------------------------------------

  /// Stores the jti of the only refresh token allowed to rotate the session.
  /// Minting a new refresh token overwrites this, invalidating every older
  /// one (single active refresh session per user). A fresh login also clears
  /// any rotation-grace state: the new session supersedes everything prior.
  Future<void> setCurrentRefreshJti(String userId, String jti) async {
    await _db.execute(
      'UPDATE users SET current_refresh_jti = @jti, prev_refresh_jti = NULL, '
      'prev_refresh_jti_set_at = NULL WHERE id = @id:uuid',
      parameters: {'jti': jti, 'id': userId},
    );
  }

  /// Rotates forward: the outgoing jti becomes the grace-accepted previous
  /// one (timestamped), and [jti] becomes current. A client killed between
  /// the server's rotation and its own storage write can still present the
  /// previous token once, instead of being signed out.
  Future<void> rotateRefreshJti(String userId, String jti) async {
    await _db.execute(
      'UPDATE users SET prev_refresh_jti = current_refresh_jti, '
      'prev_refresh_jti_set_at = now(), current_refresh_jti = @jti '
      'WHERE id = @id:uuid',
      parameters: {'jti': jti, 'id': userId},
    );
  }

  Future<String?> getRefreshJti(String userId) async {
    final row = await _db.queryOne(
      'SELECT current_refresh_jti FROM users WHERE id = @id:uuid',
      parameters: {'id': userId},
    );
    return row?['current_refresh_jti'] as String?;
  }

  /// Clears the stored refresh jti — used on logout so a stolen refresh token
  /// can no longer mint new sessions.
  Future<void> clearRefreshJti(String userId) async {
    await _db.execute(
      'UPDATE users SET current_refresh_jti = NULL WHERE id = @id:uuid',
      parameters: {'id': userId},
    );
  }
}
