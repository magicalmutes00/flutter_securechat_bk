import 'package:mongo_dart/mongo_dart.dart';
import '../models/user_model.dart';
import 'database_service.dart';

class UserService {
  final DatabaseService _db = DatabaseService();

  Future<UserModel?> findUserByPhone(String phone) async {
    final userData = await _db.users.findOne({'phone': phone});
    if (userData == null) return null;
    return UserModel.fromMap(userData);
  }

  /// Find user by phone number with password
  Future<UserModel?> findUserByPhoneWithPassword(String phone) async {
    final userData = await _db.users.findOne({
      'phone': phone,
      'password_hash': {'\$exists': true, '\$ne': null},
    });
    if (userData == null) return null;
    return UserModel.fromMap(userData);
  }

  /// Find user by email
  Future<UserModel?> findUserByEmail(String email) async {
    // Try exact match first
    var userData = await _db.users.findOne({'email': email});
    if (userData == null) {
      // Try case-insensitive search
      userData = await _db.users.findOne({
        'email': RegExp(email, caseSensitive: false),
      });
    }
    if (userData == null) return null;
    return UserModel.fromMap(userData);
  }

  /// Find user by Firebase UID
  Future<UserModel?> findUserByFirebaseUid(String firebaseUid) async {
    final userData = await _db.users.findOne({'firebase_uid': firebaseUid});
    if (userData == null) return null;
    return UserModel.fromMap(userData);
  }

  Future<UserModel?> findUserById(ObjectId id) async {
    final userData = await _db.users.findOne({'_id': id});
    if (userData == null) return null;
    return UserModel.fromMap(userData);
  }

  Future<UserModel> createUser(String phone, {String? username, String? displayName}) async {
    final now = DateTime.now();
    final user = UserModel(
      id: ObjectId(),
      phone: phone,
      username: username,
      displayName: displayName ?? phone,
      createdAt: now,
      updatedAt: now,
    );
    await _db.users.insertOne(user.toMap());
    return user;
  }

  /// Create a new user with email/password authentication
  Future<UserModel> createUserWithEmail({
    required String email,
    required String passwordHash,
    String? displayName,
  }) async {
    final now = DateTime.now();
    final user = UserModel(
      id: ObjectId(),
      email: email,
      passwordHash: passwordHash,
      displayName: displayName ?? email.split('@').first,
      createdAt: now,
      updatedAt: now,
    );
    await _db.users.insertOne(user.toMap());
    return user;
  }

  /// Create a new user with phone/password authentication
  Future<UserModel> createUserWithPhone({
    required String phone,
    required String passwordHash,
    String? displayName,
  }) async {
    final now = DateTime.now();
    final user = UserModel(
      id: ObjectId(),
      phone: phone,
      passwordHash: passwordHash,
      displayName: displayName ?? phone,
      createdAt: now,
      updatedAt: now,
    );
    await _db.users.insertOne(user.toMap());
    return user;
  }

  /// Create a new user with full Firebase auth support
  Future<UserModel> createUserFromFirebase({
    required String firebaseUid,
    String? phone,
    String? email,
    String? displayName,
  }) async {
    final now = DateTime.now();
    final user = UserModel(
      id: ObjectId(),
      firebaseUid: firebaseUid,
      phone: phone,
      email: email,
      displayName: displayName ?? (email != null ? email.split('@').first : null),
      createdAt: now,
      updatedAt: now,
    );
    await _db.users.insertOne(user.toMap());
    return user;
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
      user = await _updateUserIfNeeded(user, phone: phone, email: email, displayName: displayName);
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
  Future<UserModel> _updateUserIfNeeded(UserModel user, {String? phone, String? email, String? displayName}) async {
    bool needsUpdate = false;
    final updates = <String, dynamic>{};

    if (user.phone == null && phone != null) {
      updates['phone'] = phone;
      needsUpdate = true;
    }

    if (user.email == null && email != null) {
      updates['email'] = email;
      needsUpdate = true;
    }

    if (user.displayName == null && displayName != null) {
      updates['display_name'] = displayName;
      needsUpdate = true;
    }

    if (needsUpdate) {
      updates['updated_at'] = DateTime.now();
      var modifier = modify.set('updated_at', updates['updated_at']);
      if (updates.containsKey('phone')) modifier = modifier.set('phone', updates['phone']);
      if (updates.containsKey('email')) modifier = modifier.set('email', updates['email']);
      if (updates.containsKey('display_name')) modifier = modifier.set('display_name', updates['display_name']);
      await _db.users.updateOne(
        where.eq('_id', user.id),
        modifier,
      );
      return (await findUserById(user.id))!;
    }

    return user;
  }

  /// Link an existing user to a Firebase UID
  Future<UserModel> _linkFirebaseUidToUser(ObjectId userId, String firebaseUid) async {
    await _db.users.updateOne(
      where.eq('_id', userId),
      modify.set('firebase_uid', firebaseUid).set('updated_at', DateTime.now()),
    );
    return (await findUserById(userId))!;
  }

  /// Legacy method - maintained for backward compatibility
  Future<UserModel> getOrCreateUser(String phone) async {
    var user = await findUserByPhone(phone);
    if (user == null) {
      user = await createUser(phone);
    }
    return user;
  }

  Future<UserModel?> updateUser(ObjectId id, Map<String, dynamic> updates) async {
    var modifyUpdate = modify.set('updated_at', DateTime.now());

    if (updates.containsKey('display_name') && updates['display_name'] != null) {
      modifyUpdate = modifyUpdate.set('display_name', updates['display_name']);
    }
    if (updates.containsKey('username') && updates['username'] != null) {
      modifyUpdate = modifyUpdate.set('username', updates['username']);
    }

    await _db.users.updateOne(where.eq('_id', id), modifyUpdate);
    return findUserById(id);
  }

  Future<void> updateOnlineStatus(ObjectId id, bool isOnline) async {
    await _db.users.updateOne(
      where.eq('_id', id),
      modify.set('is_online', isOnline).set('last_seen', DateTime.now()),
    );
  }

  /// Search users by phone, username, display name, or email
  Future<List<UserModel>> searchUsers(String query) async {
    final users = await _db.users.find(
      where
          .match('phone', query)
          .or(where.match('username', query))
          .or(where.match('display_name', query))
          .or(where.match('email', query)),
    ).toList();
    return users.map((u) => UserModel.fromMap(u)).toList();
  }

  Future<List<UserModel>> getAllUsers() async {
    final users = await _db.users.find().toList();
    return users.map((u) => UserModel.fromMap(u)).toList();
  }
}
