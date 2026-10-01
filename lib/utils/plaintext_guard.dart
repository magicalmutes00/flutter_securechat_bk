/// Plaintext-only guard for message creation payloads.
///
/// The backend no longer implements application-layer end-to-end encryption.
/// All newly created 1:1 and group messages are stored and delivered as
/// plaintext (`encryption='none'` with NULL cipher fields). This helper
/// rejects any client-supplied crypto/control material so it is never
/// accepted or stored.
///
/// Rejected inputs:
/// - `encryption` values other than `'none'` (absent defaults to `'none'`).
/// - `cipher_type`, `cipher_body` (and any `cipher*` key).
/// - `distribution` / message-distribution envelopes.
/// - Key-bundle / identity / prekey material (`identity_*`, `signed_prekey_*`,
///   `one_time_prekey*`, `registration_id`, `device_id`, bundle markers).
/// - Media-envelope crypto (`media_key`, `media_nonce` and hyphen variants,
///   `sender_key`, `envelope`).
///
/// Historical `encryption`/`cipher_*` columns still exist on
/// `messages`/`group_messages` so old rows can be identified as legacy
/// encrypted history; this guard only constrains *new* writes.
///
/// REST callers return 400 with the returned message; WebSocket callers drop
/// the frame silently.
const Set<String> kForbiddenCryptoMessageKeys = {
  'cipher_type',
  'cipher_body',
  'cipher',
  'distribution',
  'identity_key_public',
  'identity',
  'signed_prekey_id',
  'signed_prekey_public',
  'signed_prekey_signature',
  'one_time_prekeys',
  'one_time_prekey_id',
  'one_time_prekey_public',
  'one_time_prekey_count',
  'prekey',
  'prekeys',
  'registration_id',
  'device_id',
  'media_key',
  'media_nonce',
  'media-key',
  'media-nonce',
  'sender_key',
  'envelope',
  'key_bundle',
  'bundle',
  'has_bundle',
};

/// Returns an error message when [data] carries crypto/control material, or
/// null when the payload is plaintext-safe.
///
/// - `encryption` may be absent or exactly `'none'`; anything else is
///   rejected (including null, empty, or encrypted markers such as
///   `'signal'`).
/// - Any key in [kForbiddenCryptoMessageKeys] with a non-null value is
///   rejected. Explicit nulls are treated as absent (nothing would be
///   stored), except for `encryption` which must be absent or `'none'`.
String? rejectCryptoMessagePayload(Map<String, dynamic> data) {
  if (data.containsKey('encryption')) {
    final value = data['encryption'];
    if (value != 'none') {
      return 'Encrypted messages are not supported; resend as plaintext';
    }
  }

  for (final key in kForbiddenCryptoMessageKeys) {
    if (!data.containsKey(key)) continue;
    final value = data[key];
    if (value == null) continue;
    if (value is String && value.isEmpty) continue;
    if (value is List && value.isEmpty) continue;
    return 'Field "$key" is not supported in plaintext mode';
  }

  // Defensive: reject any other `cipher*` prefixed key not listed above.
  for (final entry in data.entries) {
    final key = entry.key.toLowerCase();
    if (key.startsWith('cipher') && entry.value != null) {
      if (entry.value is String && (entry.value as String).isEmpty) continue;
      return 'Field "${entry.key}" is not supported in plaintext mode';
    }
  }

  return null;
}
