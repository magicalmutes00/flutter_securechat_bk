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
      await _database!.createIndex(
        'users',
        keys: {'phone': 1},
        unique: true,
        sparse: true,
      );
      await _database!.createIndex(
        'users',
        keys: {'email': 1},
        unique: true,
        sparse: true,
      );
      await _database!.createIndex(
        'users',
        keys: {'firebase_uid': 1},
        unique: true,
        sparse: true,
      );
      await _database!.createIndex('users', keys: {'username': 1});
      await _database!.createIndex('messages', keys: {'sender_id': 1, 'created_at': -1});
      await _database!.createIndex('messages', keys: {'receiver_id': 1, 'created_at': -1});
      await _database!.createIndex('messages', keys: {'sender_id': 1, 'receiver_id': 1, 'created_at': -1});
      await _database!.createIndex('otp_codes', keys: {'phone': 1, 'code': 1});
      // TTL index for OTP expiry requires MongoDB server-side setup
      print('Database indexes created successfully');
    } catch (e) {
      print('Error creating indexes: $e');
    }
  }

  DbCollection get users => _database!.collection('users');
  DbCollection get messages => _database!.collection('messages');
  DbCollection get otpCodes => _database!.collection('otp_codes');

  Future<void> close() async {
    await _database?.close();
    _database = null;
    print('MongoDB connection closed');
  }
}
