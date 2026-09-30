import '../services/user_service.dart';
import '../services/jwt_service.dart';
import '../services/password_service.dart';

class PhoneAuthService {
  final UserService _userService = UserService();
  final JwtService _jwtService = JwtService();

  /// Registers the new refresh token's jti so previously issued refresh
  /// tokens for this user stop working (single active refresh session).
  Future<void> _storeRefreshJti(String userId, String refreshToken) async {
    final jti = _jwtService.getJwtId(refreshToken);
    if (jti != null) {
      await _userService.setCurrentRefreshJti(userId, jti);
    }
  }

  /// Register a new user with phone and password
  Future<Map<String, dynamic>> registerWithPhone({
    required String phone,
    required String password,
    String? displayName,
  }) async {
    try {
      // Check if user already exists
      final existingUser = await _userService.findUserByPhone(phone);
      if (existingUser != null) {
        return {
          'success': false,
          'error': 'An account already exists with this phone number'
        };
      }

      // Hash the password
      final passwordHash = PasswordService.hashPassword(password);

      // Create new user
      final user = await _userService.createUserWithPhone(
        phone: phone,
        passwordHash: passwordHash,
        displayName: displayName ?? phone,
      );

      // Generate tokens
      final accessToken = _jwtService.generateAccessToken(
        user.id,
        user.phone,
        email: user.email,
      );
      final refreshToken =
          _jwtService.generateRefreshToken(user.id);
      await _storeRefreshJti(user.id, refreshToken);

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

  /// Login with phone and password
  Future<Map<String, dynamic>> loginWithPhone({
    required String phone,
    required String password,
  }) async {
    try {
      final user = await _userService.findUserByPhoneWithPassword(phone);
      if (user == null) {
        return {
          'success': false,
          'error': 'No account found with this phone number'
        };
      }

      // Check password
      final storedHash = user.passwordHash;
      if (storedHash == null ||
          !PasswordService.verifyPassword(password, storedHash)) {
        return {
          'success': false,
          'error': 'Incorrect password. Please try again'
        };
      }

      // Generate tokens
      final accessToken = _jwtService.generateAccessToken(
        user.id,
        user.phone,
        email: user.email,
      );
      final refreshToken =
          _jwtService.generateRefreshToken(user.id);
      await _storeRefreshJti(user.id, refreshToken);

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
}
