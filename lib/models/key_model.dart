/// A single one-time prekey (public half) uploaded by a client.
class OneTimePrekey {
  final int keyId;
  final String publicKey;

  const OneTimePrekey({required this.keyId, required this.publicKey});

  factory OneTimePrekey.fromMap(Map<String, dynamic> map) {
    return OneTimePrekey(
      keyId: (map['key_id'] as num).toInt(),
      publicKey: map['public_key'] as String,
    );
  }

  Map<String, dynamic> toMap() => {
        'key_id': keyId,
        'public_key': publicKey,
      };
}

/// Server-side store of a user's public key material.
///
/// Only *public* keys are stored. Private keys never leave the client, so the
/// server cannot read any message plaintext (end-to-end encryption).
///
/// Backed by the Supabase `keys` table (primary key: user_id + device_id);
/// `one_time_prekeys` is a JSONB array of {key_id, public_key} objects.
class KeyModel {
  final String userId;
  final String deviceId;
  final int registrationId;
  final String identityKeyPublic;
  final int signedPrekeyId;
  final String signedPrekeyPublic;
  final String signedPrekeySignature;
  final List<OneTimePrekey> oneTimePrekeys;
  final DateTime createdAt;
  final DateTime updatedAt;

  KeyModel({
    required this.userId,
    required this.deviceId,
    required this.registrationId,
    required this.identityKeyPublic,
    required this.signedPrekeyId,
    required this.signedPrekeyPublic,
    required this.signedPrekeySignature,
    required this.oneTimePrekeys,
    required this.createdAt,
    required this.updatedAt,
  });

  factory KeyModel.fromMap(Map<String, dynamic> map) {
    return KeyModel(
      userId: map['user_id'] as String,
      deviceId: map['device_id'] as String,
      registrationId: (map['registration_id'] as num?)?.toInt() ?? 0,
      identityKeyPublic: map['identity_key_public'] as String,
      signedPrekeyId: (map['signed_prekey_id'] as num?)?.toInt() ?? 0,
      signedPrekeyPublic: map['signed_prekey_public'] as String,
      signedPrekeySignature: map['signed_prekey_signature'] as String,
      oneTimePrekeys: (map['one_time_prekeys'] as List?)
              ?.map((e) => OneTimePrekey.fromMap(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          const [],
      createdAt: (map['created_at'] as DateTime).toUtc(),
      updatedAt: (map['updated_at'] as DateTime).toUtc(),
    );
  }

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'device_id': deviceId,
        'registration_id': registrationId,
        'identity_key_public': identityKeyPublic,
        'signed_prekey_id': signedPrekeyId,
        'signed_prekey_public': signedPrekeyPublic,
        'signed_prekey_signature': signedPrekeySignature,
      };
}
