import 'package:mongo_dart/mongo_dart.dart';
import '../config/app_config.dart';

class DatabaseService {
  static Db? _database;
  static final DatabaseService _instance = DatabaseService._internal();

  factory DatabaseService() => _instance;

  DatabaseService._internal();

  Db get database {
    if (_database == null) {
      throw Exception('Database not initialized. Call initialize() first.');
    }
    return _database!;
  }

  Future<void> initialize() async {
    try {
      _database = Db(AppConfig.mongoConnectionString);
      await _database!.open();
      await _createIndexes();
      print('MongoDB connected successfully');
    } catch (e) {
      print('Failed to connect to MongoDB: $e');
      rethrow;
    }
  }

  Future<void> _createIndexes() async {
    try {
      // Sparse unique indexes allow multiple auth providers without forcing
      // every user document to contain every credential field.
      await _ensureIndex('users', keys: {'phone': 1}, unique: true, sparse: true);
      await _ensureIndex('users', keys: {'email': 1}, unique: true, sparse: true);
      await _ensureIndex('users', keys: {'firebase_uid': 1}, unique: true, sparse: true);
      await _ensureIndex('users', keys: {'username': 1});
      // Sparse unique index so each user has at most one phone hash.
      await _ensureIndex('users', keys: {'phone_hash': 1}, unique: true, sparse: true);
      await _ensureIndex('messages', keys: {'sender_id': 1, 'created_at': -1});
      await _ensureIndex('messages', keys: {'receiver_id': 1, 'created_at': -1});
      await _ensureIndex('messages',
          keys: {'sender_id': 1, 'receiver_id': 1, 'created_at': -1});
      await _ensureIndex('otp_codes', keys: {'phone': 1, 'code': 1});
      // E2EE key bundles: one bundle per user per device.
      await _ensureIndex(
        'keys',
        keys: {'user_id': 1, 'device_id': 1},
        unique: true,
      );
      // Groups: index member arrays so "groups a user belongs to" is fast, and
      // unique index on the group name for O(1) title lookups.
      await _ensureIndex('groups', keys: {'member_ids': 1});
      await _ensureIndex('groups', keys: {'name': 1}, unique: true);
      await _ensureIndex('group_messages', keys: {'group_id': 1, 'created_at': -1});
      await _ensureIndex('group_messages', keys: {'sender_id': 1, 'created_at': -1});
      // Statuses: query active (non-expired) statuses efficiently.
      await _ensureIndex('statuses', keys: {'expires_at': 1, 'created_at': -1});
      await _ensureIndex('statuses', keys: {'user_id': 1, 'created_at': -1});
      // Push tokens: unique per device token, indexed by owner.
      await _ensureIndex('push_tokens', keys: {'token': 1}, unique: true);
      await _ensureIndex('push_tokens', keys: {'user_id': 1});
      print('Database indexes created successfully');
    } catch (e) {
      print('Error creating indexes: $e');
    }
  }

  /// Creates [collection]'s [keys] index, first dropping any existing index
  /// that shares the auto-generated name but has a different spec (e.g. one
  /// created by an older version without `sparse`). MongoDB rejects a new
  /// index whose name collides with an existing index of different options.
  Future<void> _ensureIndex(
    String collection, {
    required Map<String, dynamic> keys,
    bool unique = false,
    bool sparse = false,
  }) async {
    final name = keys.entries.map((e) => '${e.key}_${e.value}').join('_');

    try {
      final list = await _database!.runCommand({'listIndexes': collection});
      final batch = (list['cursor']?['firstBatch'] ?? const []) as List;
      for (final index in batch) {
        if (index is Map && index['name'] == name) {
          final keyMatches = _sameIndexKeys(index['key'], keys);
          final uniqueMatches = (index['unique'] ?? false) == unique;
          final sparseMatches = (index['sparse'] ?? false) == sparse;
          if (!keyMatches || !uniqueMatches || !sparseMatches) {
            await _database!.runCommand({
              'dropIndexes': collection,
              'index': name,
            });
            break;
          }
        }
      }
    } catch (_) {
      // Introspection failed (e.g. collection does not exist yet); let
      // createIndex surface any real error below.
    }

    await _database!
        .createIndex(collection, keys: keys, unique: unique, sparse: sparse);
  }

  bool _sameIndexKeys(dynamic existing, Map<String, dynamic> wanted) {
    if (existing is! Map || existing.length != wanted.length) return false;
    for (final entry in wanted.entries) {
      final value = existing[entry.key];
      if (value is! num || value.toInt() != (entry.value as num).toInt()) {
        return false;
      }
    }
    return true;
  }

  DbCollection get users => _database!.collection('users');
  DbCollection get messages => _database!.collection('messages');
  DbCollection get otpCodes => _database!.collection('otp_codes');
  DbCollection get keys => _database!.collection('keys');
  DbCollection get groups => _database!.collection('groups');
  DbCollection get groupMessages => _database!.collection('group_messages');
  DbCollection get statuses => _database!.collection('statuses');
  DbCollection get pushTokens => _database!.collection('push_tokens');

  Future<void> close() async {
    await _database?.close();
    _database = null;
    print('MongoDB connection closed');
  }
}
