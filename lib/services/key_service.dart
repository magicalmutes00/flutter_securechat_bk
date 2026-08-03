import 'package:mongo_dart/mongo_dart.dart';
import '../models/key_model.dart';
import 'database_service.dart';

class KeyService {
  final DatabaseService _db = DatabaseService();

  DbCollection get _keys => _db.keys;

  /// Upserts a user's public key bundle for a device.
  Future<void> saveBundle({
    required ObjectId userId,
    required String deviceId,
    required int registrationId,
    required String identityKeyPublic,
    required int signedPrekeyId,
    required String signedPrekeyPublic,
    required String signedPrekeySignature,
    required List<String> oneTimePrekeys,
  }) async {
    final now = DateTime.now();

    final oneTimePrekeyModels = <OneTimePrekey>[];
    for (var i = 0; i < oneTimePrekeys.length; i++) {
      oneTimePrekeyModels.add(
        OneTimePrekey(keyId: i + 1, publicKey: oneTimePrekeys[i]),
      );
    }

    final keyModel = KeyModel(
      id: ObjectId(),
      userId: userId,
      deviceId: deviceId,
      registrationId: registrationId,
      identityKeyPublic: identityKeyPublic,
      signedPrekeyId: signedPrekeyId,
      signedPrekeyPublic: signedPrekeyPublic,
      signedPrekeySignature: signedPrekeySignature,
      oneTimePrekeys: oneTimePrekeyModels,
      createdAt: now,
      updatedAt: now,
    );

    await _keys.updateOne(
      where.eq('user_id', userId).eq('device_id', deviceId),
      modify
          .set('registration_id', keyModel.registrationId)
          .set('identity_key_public', keyModel.identityKeyPublic)
          .set('signed_prekey_id', keyModel.signedPrekeyId)
          .set('signed_prekey_public', keyModel.signedPrekeyPublic)
          .set('signed_prekey_signature', keyModel.signedPrekeySignature)
          .set('one_time_prekeys',
              oneTimePrekeyModels.map((k) => k.toMap()).toList())
          .set('updated_at', now)
          .set('created_at', now),
      upsert: true,
    );
  }

  /// Appends additional one-time prekeys for a user/device.
  Future<void> addOneTimePrekeys({
    required ObjectId userId,
    required String deviceId,
    required List<String> oneTimePrekeys,
  }) async {
    final existing = await _keys.findOne(
      where.eq('user_id', userId).eq('device_id', deviceId),
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

    await _keys.updateOne(
      where.eq('_id', keyModel.id),
      modify
          .pushAll('one_time_prekeys', additions)
          .set('updated_at', DateTime.now()),
    );
  }

  /// Returns the key bundle for a user's device along with a single one-time
  /// prekey. The one-time prekey is consumed (removed) after retrieval as it
  /// can only be used once.
  Future<Map<String, dynamic>?> getBundle({
    required ObjectId userId,
    String? deviceId,
  }) async {
    final selector = deviceId == null || deviceId.isEmpty
        ? where.eq('user_id', userId)
        : where.eq('user_id', userId).eq('device_id', deviceId);
    final data = await _keys.findOne(selector);
    if (data == null) return null;

    final keyModel = KeyModel.fromMap(data);

    OneTimePrekey? oneTime;
    if (keyModel.oneTimePrekeys.isNotEmpty) {
      oneTime = keyModel.oneTimePrekeys.first;
      await _keys.updateOne(
        where.eq('_id', keyModel.id),
        modify.pull('one_time_prekeys', where.eq('key_id', oneTime.keyId)),
      );
    }

    return {
      ...keyModel.toJson(),
      'one_time_prekey_id': oneTime?.keyId,
      'one_time_prekey_public': oneTime?.publicKey,
    };
  }

  /// Whether a user/device has uploaded a key bundle.
  Future<bool> hasBundle(ObjectId userId, String deviceId) async {
    final count = await _keys.count(
      where.eq('user_id', userId).eq('device_id', deviceId),
    );
    return count > 0;
  }

  /// Number of one-time prekeys remaining on the server for a user/device.
  Future<int> remainingOneTimePrekeys(ObjectId userId, String deviceId) async {
    final data = await _keys.findOne(
      where.eq('user_id', userId).eq('device_id', deviceId),
    );
    if (data == null) return 0;
    final keyModel = KeyModel.fromMap(data);
    return keyModel.oneTimePrekeys.length;
  }
}
