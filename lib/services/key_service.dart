import '../models/key_model.dart';
import 'database_service.dart';

class KeyService {
  final DatabaseService _db = DatabaseService();

  /// Upserts a user's public key bundle for a device.
  Future<void> saveBundle({
    required String userId,
    required String deviceId,
    required int registrationId,
    required String identityKeyPublic,
    required int signedPrekeyId,
    required String signedPrekeyPublic,
    required String signedPrekeySignature,
    required List<String> oneTimePrekeys,
  }) async {
    final oneTimePrekeyModels = <Map<String, dynamic>>[];
    for (var i = 0; i < oneTimePrekeys.length; i++) {
      oneTimePrekeyModels.add(
        OneTimePrekey(keyId: i + 1, publicKey: oneTimePrekeys[i]).toMap(),
      );
    }

    await _db.execute(
      '''
      INSERT INTO keys
        (user_id, device_id, registration_id, identity_key_public,
         signed_prekey_id, signed_prekey_public, signed_prekey_signature, one_time_prekeys)
      VALUES
        (@user_id:uuid, @device_id, @registration_id, @identity_key_public,
         @signed_prekey_id, @signed_prekey_public, @signed_prekey_signature, @prekeys:jsonb)
      ON CONFLICT (user_id, device_id) DO UPDATE SET
        registration_id = EXCLUDED.registration_id,
        identity_key_public = EXCLUDED.identity_key_public,
        signed_prekey_id = EXCLUDED.signed_prekey_id,
        signed_prekey_public = EXCLUDED.signed_prekey_public,
        signed_prekey_signature = EXCLUDED.signed_prekey_signature,
        one_time_prekeys = EXCLUDED.one_time_prekeys,
        updated_at = now()
      ''',
      parameters: {
        'user_id': userId,
        'device_id': deviceId,
        'registration_id': registrationId,
        'identity_key_public': identityKeyPublic,
        'signed_prekey_id': signedPrekeyId,
        'signed_prekey_public': signedPrekeyPublic,
        'signed_prekey_signature': signedPrekeySignature,
        'prekeys': oneTimePrekeyModels,
      },
    );
  }

  /// Appends additional one-time prekeys for a user/device.
  Future<void> addOneTimePrekeys({
    required String userId,
    required String deviceId,
    required List<String> oneTimePrekeys,
  }) async {
    final existing = await _db.queryOne(
      'SELECT * FROM keys WHERE user_id = @user_id:uuid AND device_id = @device_id',
      parameters: {'user_id': userId, 'device_id': deviceId},
    );
    if (existing == null) {
      throw Exception('No key bundle found. Upload a bundle first.');
    }

    final keyModel = KeyModel.fromMap(existing);
    var nextId = keyModel.oneTimePrekeys.fold<int>(
      0,
      (max, k) => k.keyId > max ? k.keyId : max,
    );
    final additions = oneTimePrekeys.map((public) {
      nextId++;
      return OneTimePrekey(keyId: nextId, publicKey: public).toMap();
    }).toList();

    await _db.execute(
      '''
      UPDATE keys SET one_time_prekeys = one_time_prekeys || @additions:jsonb, updated_at = now()
      WHERE user_id = @user_id:uuid AND device_id = @device_id
      ''',
      parameters: {
        'additions': additions,
        'user_id': userId,
        'device_id': deviceId,
      },
    );
  }

  /// Returns the key bundle for a user along with a single one-time prekey.
  ///
  /// The prekey is consumed atomically (row-locked CTE) as it can only be
  /// used once — concurrent fetches can never receive the same prekey.
  Future<Map<String, dynamic>?> getBundle({
    required String userId,
    String? deviceId,
  }) async {
    final row = await _db.queryOne(
      '''
      WITH target AS (
        SELECT user_id, device_id, one_time_prekeys->0 AS popped
        FROM keys
        WHERE user_id = @user_id:uuid
          AND (@device_id = '' OR device_id = @device_id)
          AND jsonb_array_length(one_time_prekeys) > 0
        -- Reinstalls leave stale device rows behind; the live device keeps
        -- touching its row (uploads, replenishes, prekey pops bump
        -- updated_at), so the freshest row is the reachable one.
        ORDER BY updated_at DESC
        LIMIT 1
        FOR UPDATE
      ),
      updated AS (
        UPDATE keys k
        SET one_time_prekeys = k.one_time_prekeys - 0, updated_at = now()
        FROM target t
        WHERE k.user_id = t.user_id AND k.device_id = t.device_id
        RETURNING k.*
      )
      SELECT u.*, t.popped
      FROM updated u CROSS JOIN target t
      ''',
      parameters: {'user_id': userId, 'device_id': deviceId ?? ''},
    );

    if (row != null) {
      return _bundleResponse(row);
    }

    // No consumable prekey — return the bundle itself (freshest row first,
    // same reinstall reasoning as above).
    final bundleRow = await _db.queryOne(
      'SELECT * FROM keys WHERE user_id = @user_id:uuid AND (@device_id = \'\' OR device_id = @device_id) ORDER BY updated_at DESC LIMIT 1',
      parameters: {'user_id': userId, 'device_id': deviceId ?? ''},
    );
    if (bundleRow == null) return null;
    return _bundleResponse(bundleRow);
  }

  Map<String, dynamic> _bundleResponse(Map<String, dynamic> row) {
    final keyModel = KeyModel.fromMap(row);
    final popped = row['popped'];
    OneTimePrekey? oneTime;
    if (popped is Map) {
      oneTime = OneTimePrekey.fromMap(Map<String, dynamic>.from(popped));
    }

    return {
      ...keyModel.toJson(),
      'one_time_prekey_id': oneTime?.keyId,
      'one_time_prekey_public': oneTime?.publicKey,
    };
  }

  /// Whether a user/device has uploaded a key bundle.
  Future<bool> hasBundle(String userId, String deviceId) async {
    final row = await _db.queryOne(
      'SELECT 1 FROM keys WHERE user_id = @user_id:uuid AND device_id = @device_id',
      parameters: {'user_id': userId, 'device_id': deviceId},
    );
    return row != null;
  }

  /// Number of one-time prekeys remaining on the server for a user/device.
  Future<int> remainingOneTimePrekeys(String userId, String deviceId) async {
    final row = await _db.queryOne(
      '''
      SELECT jsonb_array_length(one_time_prekeys) AS n
      FROM keys WHERE user_id = @user_id:uuid AND device_id = @device_id
      ''',
      parameters: {'user_id': userId, 'device_id': deviceId},
    );
    return (row?['n'] as int?) ?? 0;
  }
}
