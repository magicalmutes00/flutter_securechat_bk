import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../config/app_config.dart';

class JwtService {
  final _secret = SecretKey(AppConfig.jwtSecret);

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
      final phone = payload['phone'] as String?;
      final email = payload['email'] as String?;
      final newAccessToken = generateAccessToken(userId, phone, email: email);
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

  String hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  bool verifyPassword(String password, String hash) {
    return hashPassword(password) == hash;
  }
}
