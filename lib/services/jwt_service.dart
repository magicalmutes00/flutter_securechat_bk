import 'dart:convert';
import 'dart:math';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import '../config/app_config.dart';

class JwtService {
  final _secret = SecretKey(AppConfig.jwtSecret);

  final Random _random = Random.secure();

  /// A random unique token id. Without it, two tokens minted for the same
  /// user within the same second are byte-identical, which makes refresh
  /// rotation a no-op.
  String _newJwtId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return base64Url.encode(bytes);
  }

  String generateAccessToken(String userId, String? phone, {String? email}) {
    final now = DateTime.now();
    final expiry =
        now.add(Duration(minutes: AppConfig.jwtAccessTokenExpiryMinutes));

    final claims = <String, dynamic>{
      'sub': userId,
      'iat': now.millisecondsSinceEpoch ~/ 1000,
      'exp': expiry.millisecondsSinceEpoch ~/ 1000,
      'iss': AppConfig.jwtIssuer,
      'type': 'access',
      'jti': _newJwtId(),
    };

    // Only add optional fields if they are present
    if (phone != null) claims['phone'] = phone;
    if (email != null) claims['email'] = email;

    final jwt = JWT(claims);

    return jwt.sign(_secret);
  }

  String generateRefreshToken(String userId) {
    final now = DateTime.now();
    final expiry = now.add(Duration(days: AppConfig.jwtRefreshTokenExpiryDays));

    final jwt = JWT(
      {
        'sub': userId,
        'iat': now.millisecondsSinceEpoch ~/ 1000,
        'exp': expiry.millisecondsSinceEpoch ~/ 1000,
        'iss': AppConfig.jwtIssuer,
        'type': 'refresh',
        'jti': _newJwtId(),
      },
    );

    return jwt.sign(_secret);
  }

  Map<String, dynamic>? verifyToken(String token) {
    try {
      final jwt = JWT.verify(token, _secret);
      return jwt.payload as Map<String, dynamic>;
    } catch (e) {
      print('JWT verification failed: $e');
      return null;
    }
  }

  Map<String, String>? refreshTokens(String refreshToken) {
    try {
      final payload = verifyToken(refreshToken);
      if (payload == null || payload['type'] != 'refresh') {
        return null;
      }

      final userId = payload['sub'] as String;

      // Refresh tokens do not carry phone/email claims; the new access token
      // is issued without them (they are optional and unused for routing).
      final newAccessToken = generateAccessToken(userId, null);
      final newRefreshToken = generateRefreshToken(userId);

      return {
        'access_token': newAccessToken,
        'refresh_token': newRefreshToken,
      };
    } catch (e) {
      print('Token refresh failed: $e');
      return null;
    }
  }

  String? getUserIdFromToken(String token) {
    final payload = verifyToken(token);
    return payload?['sub'] as String?;
  }

  /// The jti (unique id) of a verified token, or null when invalid.
  String? getJwtId(String token) {
    final payload = verifyToken(token);
    return payload?['jti'] as String?;
  }
}
