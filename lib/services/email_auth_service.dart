import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../services/user_service.dart';
import '../services/jwt_service.dart';

class EmailAuthService {
  final UserService _userService = UserService();
  final JwtService _jwtService = JwtService();

  /// Register a new user with email and password
  Future<Map<String, dynamic>> registerWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    try {
      // Check if user already exists
      final existingUser = await _userService.findUserByEmail(email);
      if (existingUser != null) {
        return {'success': false, 'error': 'An account already exists with this email address'};
      }

      // Hash the password
      final passwordHash = _hashPassword(password);

      // Create new user
      final user = await _userService.createUserWithEmail(
        email: email,
        passwordHash: passwordHash,
        displayName: displayName ?? email.split('@').first,
      );

      // Generate tokens
      final accessToken = _jwtService.generateAccessToken(
        user.id.toHexString(),
        user.phone,
        email: user.email,
      );
      final refreshToken = _jwtService.generateRefreshToken(user.id.toHexString());

      return {
        'success': true,
        'user': user.toJson(),
        'access_token': accessToken,
        'refresh_token': refreshToken,
      };
    } catch (e) {
      return {'success': false, 'error': 'Registration failed: $e'};
    }
  }

  /// Login with email and password
  Future<Map<String, dynamic>> loginWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final user = await _userService.findUserByEmail(email);
      if (user == null) {
        return {'success': false, 'error': 'No account found with this email address'};
      }

      // Check password
      final storedHash = user.passwordHash;
      if (storedHash == null || !_verifyPassword(password, storedHash)) {
        return {'success': false, 'error': 'Incorrect password. Please try again'};
      }

      // Generate tokens
      final accessToken = _jwtService.generateAccessToken(
        user.id.toHexString(),
        user.phone,
        email: user.email,
      );
      final refreshToken = _jwtService.generateRefreshToken(user.id.toHexString());

      return {
        'success': true,
        'user': user.toJson(),
        'access_token': accessToken,
        'refresh_token': refreshToken,
      };
    } catch (e) {
      return {'success': false, 'error': 'Login failed: $e'};
    }
  }

  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  bool _verifyPassword(String password, String hash) {
    return _hashPassword(password) == hash;
  }
}
