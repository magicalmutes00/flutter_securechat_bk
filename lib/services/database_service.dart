import 'package:postgres/postgres.dart';

import '../config/app_config.dart';

/// PostgreSQL access layer backed by a Supabase database.
///
/// The connection string comes from `SUPABASE_DB_URL` (Supabase → Project
/// Settings → Database → Connection string, session pooler / port 5432).
/// The schema below is created idempotently on startup, so pointing the
/// server at an empty Supabase project is enough — no manual SQL step.
class DatabaseService {
  static Pool? _pool;
  static final DatabaseService _instance = DatabaseService._internal();

  factory DatabaseService() => _instance;

  DatabaseService._internal();

  Pool get pool {
    final p = _pool;
    if (p == null) {
      throw Exception('Database not initialized. Call initialize() first.');
    }
    return p;
  }

  /// Runs [sql] with named `@param` placeholders and returns the raw result.
  Future<Result> execute(String sql, {Map<String, Object?>? parameters}) {
    return pool.execute(Sql.named(sql), parameters: parameters);
  }

  /// Runs [sql] and returns rows as plain column-name → value maps
  /// (snake_case column names, matching the previous Mongo document keys).
  Future<List<Map<String, dynamic>>> query(
    String sql, {
    Map<String, Object?>? parameters,
  }) async {
    final result = await execute(sql, parameters: parameters);
    return result.map((row) => row.toColumnMap()).toList();
  }

  /// Runs [sql] and returns the first row, or null.
  Future<Map<String, dynamic>?> queryOne(
    String sql, {
    Map<String, Object?>? parameters,
  }) async {
    final rows = await query(sql, parameters: parameters);
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> executeCount(String sql, {Map<String, Object?>? parameters}) async {
    final result = await execute(sql, parameters: parameters);
    return result.affectedRows;
  }

  Future<void> initialize() async {
    try {
      _pool = _createPool();
      // Force a real round trip so a bad URL/credentials fail fast at boot.
      await pool.execute('SELECT 1');
      await _createSchema();
      print('Supabase PostgreSQL connected successfully');
    } catch (e) {
      print('Failed to connect to Supabase PostgreSQL: $e');
      rethrow;
    }
  }

  Pool _createPool() {
    final uri = Uri.parse(AppConfig.supabaseDbUrl);
    final userInfo = uri.userInfo;
    final sep = userInfo.indexOf(':');
    if (sep == -1) {
      throw Exception(
          'SUPABASE_DB_URL must look like postgresql://user:password@host:5432/postgres');
    }
    final username = userInfo.substring(0, sep);
    final password = Uri.decodeComponent(userInfo.substring(sep + 1));
    final host = uri.host;
    final port = uri.port == 0 ? 5432 : uri.port;
    final database = uri.path.replaceFirst('/', '');
    if (host.isEmpty || database.isEmpty) {
      throw Exception('SUPABASE_DB_URL is missing host or database name');
    }

    // Local development databases usually have no TLS; Supabase requires it.
    final isLocal = host == 'localhost' || host == '127.0.0.1' || host == '::1';

    return Pool.withEndpoints(
      [
        Endpoint(
            host: host,
            port: port,
            database: database,
            username: username,
            password: password),
      ],
      settings: PoolSettings(
        sslMode: isLocal ? SslMode.disable : SslMode.require,
        connectTimeout: const Duration(seconds: 15),
        queryTimeout: const Duration(seconds: 30),
        // Supabase poolers close idle connections aggressively; keep the pool
        // small and let queries wait rather than multiplying connections.
        maxConnectionCount: 10,
      ),
    );
  }

  Future<void> _createSchema() async {
    await execute('CREATE EXTENSION IF NOT EXISTS pgcrypto');

    await execute('''
      CREATE TABLE IF NOT EXISTS users (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        phone TEXT UNIQUE,
        email TEXT UNIQUE,
        firebase_uid TEXT UNIQUE,
        username TEXT,
        display_name TEXT,
        avatar_url TEXT,
        about TEXT,
        password_hash TEXT,
        phone_hash TEXT UNIQUE,
        privacy JSONB NOT NULL DEFAULT '{}'::jsonb,
        current_refresh_jti TEXT,
        is_online BOOLEAN NOT NULL DEFAULT FALSE,
        last_seen TIMESTAMPTZ,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
      )
    ''');
    await execute('CREATE INDEX IF NOT EXISTS idx_users_username ON users (username)');

    // OTP codes are stored hashed (per-code random salt), never in plaintext.
    await execute('''
      CREATE TABLE IF NOT EXISTS otp_codes (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        phone TEXT NOT NULL,
        code_hash TEXT NOT NULL,
        salt TEXT NOT NULL,
        purpose TEXT NOT NULL DEFAULT 'auth',
        expires_at TIMESTAMPTZ NOT NULL,
        is_used BOOLEAN NOT NULL DEFAULT FALSE,
        attempts INT NOT NULL DEFAULT 0,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now()
      )
    ''');
    await execute('CREATE INDEX IF NOT EXISTS idx_otp_phone ON otp_codes (phone, purpose)');

    await execute('''
      CREATE TABLE IF NOT EXISTS messages (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        sender_id UUID NOT NULL,
        receiver_id UUID NOT NULL,
        message_type TEXT NOT NULL DEFAULT 'text',
        content TEXT NOT NULL DEFAULT '',
        file_path TEXT,
        file_name TEXT,
        file_size BIGINT,
        media_type TEXT,
        status TEXT NOT NULL DEFAULT 'sent',
        encryption TEXT NOT NULL DEFAULT 'none',
        cipher_type INT,
        cipher_body TEXT,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
      )
    ''');
    // Replies: nullable self-reference. An ALTER (not CREATE TABLE) because
    // deployed databases already have the table; idempotent on every boot.
    // ON DELETE SET NULL keeps replies renderable when the quoted message is
    // deleted.
    await execute(
        'ALTER TABLE messages ADD COLUMN IF NOT EXISTS reply_to_id UUID REFERENCES messages(id) ON DELETE SET NULL');
    await execute(
        'CREATE INDEX IF NOT EXISTS idx_messages_sender ON messages (sender_id, created_at DESC)');
    await execute(
        'CREATE INDEX IF NOT EXISTS idx_messages_reply_to ON messages (reply_to_id)');
    await execute(
        'CREATE INDEX IF NOT EXISTS idx_messages_receiver ON messages (receiver_id, created_at DESC)');
    await execute(
        'CREATE INDEX IF NOT EXISTS idx_messages_pair ON messages (sender_id, receiver_id, created_at DESC)');
    await execute('CREATE INDEX IF NOT EXISTS idx_messages_file ON messages (file_path)');

    // Metadata for Cloudinary-stored attachments. Bytes live in Cloudinary
    // (uploaded as `type=authenticated`); delivery uses short-lived signed
    // URLs minted after the authorization check.
    await execute('''
      CREATE TABLE IF NOT EXISTS files (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        owner_id UUID,
        cloudinary_public_id TEXT NOT NULL,
        delivery_path TEXT NOT NULL,
        file_name TEXT NOT NULL,
        file_size BIGINT NOT NULL,
        media_type TEXT NOT NULL,
        kind TEXT NOT NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now()
      )
    ''');

    await execute('''
      CREATE TABLE IF NOT EXISTS keys (
        user_id UUID NOT NULL,
        device_id TEXT NOT NULL,
        registration_id INT NOT NULL DEFAULT 0,
        identity_key_public TEXT NOT NULL,
        signed_prekey_id INT NOT NULL DEFAULT 0,
        signed_prekey_public TEXT NOT NULL,
        signed_prekey_signature TEXT NOT NULL,
        one_time_prekeys JSONB NOT NULL DEFAULT '[]'::jsonb,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        PRIMARY KEY (user_id, device_id)
      )
    ''');

    await execute('''
      CREATE TABLE IF NOT EXISTS groups (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        name TEXT NOT NULL UNIQUE,
        avatar_url TEXT,
        creator_id UUID NOT NULL,
        member_ids JSONB NOT NULL DEFAULT '[]'::jsonb,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
      )
    ''');

    await execute('''
      CREATE TABLE IF NOT EXISTS group_messages (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        group_id UUID NOT NULL,
        sender_id UUID NOT NULL,
        message_type TEXT NOT NULL DEFAULT 'text',
        content TEXT NOT NULL DEFAULT '',
        file_path TEXT,
        file_name TEXT,
        file_size BIGINT,
        media_type TEXT,
        status TEXT NOT NULL DEFAULT 'sent',
        encryption TEXT NOT NULL DEFAULT 'none',
        cipher_type INT,
        cipher_body TEXT,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
      )
    ''');
    // Same reply-link pattern as `messages`, keyed to the parent group table.
    await execute(
        'ALTER TABLE group_messages ADD COLUMN IF NOT EXISTS reply_to_id UUID REFERENCES group_messages(id) ON DELETE SET NULL');
    await execute(
        'CREATE INDEX IF NOT EXISTS idx_group_messages_group ON group_messages (group_id, created_at DESC)');
    await execute(
        'CREATE INDEX IF NOT EXISTS idx_group_messages_reply_to ON group_messages (reply_to_id)');
    await execute(
        'CREATE INDEX IF NOT EXISTS idx_group_messages_file ON group_messages (file_path)');

    await execute('''
      CREATE TABLE IF NOT EXISTS statuses (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL,
        text TEXT,
        media_path TEXT,
        media_type TEXT,
        viewers JSONB NOT NULL DEFAULT '[]'::jsonb,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        expires_at TIMESTAMPTZ NOT NULL
      )
    ''');
    await execute('CREATE INDEX IF NOT EXISTS idx_statuses_expiry ON statuses (expires_at)');
    await execute('CREATE INDEX IF NOT EXISTS idx_statuses_user ON statuses (user_id)');

    await execute('''
      CREATE TABLE IF NOT EXISTS push_tokens (
        token TEXT PRIMARY KEY,
        user_id UUID NOT NULL,
        platform TEXT NOT NULL DEFAULT 'android',
        updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
      )
    ''');
    await execute('CREATE INDEX IF NOT EXISTS idx_push_tokens_user ON push_tokens (user_id)');
  }

  Future<void> close() async {
    await _pool?.close();
    _pool = null;
    print('PostgreSQL connection closed');
  }
}
