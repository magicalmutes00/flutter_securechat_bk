import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/pbkdf2.dart';
import 'package:pointycastle/macs/hmac.dart';

/// Password hashing built on PBKDF2-HMAC-SHA256 with a per-user random salt.
///
/// Stored format: `pbkdf2$<iterations>$<saltBase64>$<hashBase64>`
///
/// Legacy unsalted SHA-256 hashes (from the original implementation) are still
/// accepted for verification so existing accounts keep working, but all new
/// hashes use the PBKDF2 format.
class PasswordService {
  PasswordService._();

  static const int iterations = 31000;
  static const int saltLength = 16;
  static const int derivedKeyLength = 32;
  static final Random _random = Random.secure();

  static String hashPassword(String password) {
    final salt = List<int>.generate(saltLength, (_) => _random.nextInt(256));
    final derived = _derive(password, salt, iterations);
    return 'pbkdf2\$'
        '$iterations\$'
        '${base64Encode(salt)}\$'
        '${base64Encode(derived)}';
  }

  static bool verifyPassword(String password, String stored) {
    if (stored.startsWith('pbkdf2\$')) {
      final parts = stored.split('\$');
      if (parts.length != 4) return false;

      final iters = int.tryParse(parts[1]);
      if (iters == null) return false;

      final List<int> salt;
      final List<int> expected;
      try {
        salt = base64Decode(parts[2]);
        expected = base64Decode(parts[3]);
      } catch (_) {
        return false;
      }

      final derived = _derive(password, salt, iters);
      return _constantTimeEquals(derived, expected);
    }

    // Legacy: unsalted single-pass SHA-256.
    final legacyHash = crypto.sha256.convert(utf8.encode(password)).toString();
    return legacyHash == stored;
  }

  static List<int> _derive(String password, List<int> salt, int iterations) {
    final keyDerivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
    keyDerivator.init(
      Pbkdf2Parameters(Uint8List.fromList(salt), iterations, derivedKeyLength),
    );
    return keyDerivator.process(Uint8List.fromList(utf8.encode(password)));
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
