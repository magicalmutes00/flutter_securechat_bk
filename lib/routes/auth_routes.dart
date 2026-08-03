import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:mongo_dart/mongo_dart.dart';
import '../services/user_service.dart';
import '../services/jwt_service.dart';
import '../services/otp_service.dart';
import '../services/email_auth_service.dart';
import '../services/phone_auth_service.dart';

class AuthRoutes {
  final UserService _userService = UserService();
  final JwtService _jwtService = JwtService();
  final OtpService _otpService = OtpService();
  final EmailAuthService _emailAuthService = EmailAuthService();
  final PhoneAuthService _phoneAuthService = PhoneAuthService();

  // Public routes — no authentication required
  Router get publicRouter => Router()
    ..post('/refresh-token', _refreshToken)
    ..post('/send-otp', _sendOtp)
    ..post('/verify-otp', _verifyOtp)
    ..post('/register-email', _registerEmail)
    ..post('/login-email', _loginEmail)
    ..post('/register-phone', _registerPhone)
    ..post('/login-phone', _loginPhone)
    ..get('/users/search', _searchUsers);

  // Protected routes — require a valid Bearer token
  Router get protectedRouter => Router()
    ..get('/profile', _getProfile)
    ..put('/profile', _updateProfile)
    ..post('/contacts/sync', _syncContacts);

  Future<Response> _refreshToken(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final refreshToken = data['refresh_token'] as String?;

      if (refreshToken == null) {
        return Response(
          400,
          body: jsonEncode({'error': 'Refresh token is required'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final tokens = _jwtService.refreshTokens(refreshToken);
      if (tokens == null) {
        return Response.unauthorized(
          jsonEncode({'error': 'Invalid or expired refresh token'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      return Response.ok(
        jsonEncode(tokens),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response(
        500,
        body: jsonEncode({'error': 'Failed to refresh token: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _sendOtp(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final mobileNumber = data['mobile_number'] as String?;
      final countryCode = data['country_code'] as int? ?? 91;
      final message = data['message'] as String?;

      if (mobileNumber == null || mobileNumber.isEmpty) {
        return Response(
          400,
          body: jsonEncode({'error': 'Mobile number is required'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final result = await _otpService.sendOtp(
        mobileNumber: mobileNumber,
        countryCode: countryCode,
        message: message,
      );

      if (result['success'] == true) {
        return Response.ok(
          jsonEncode({
            'success': true,
            'correlation_id': result['correlationId'],
            'message': result['message'],
          }),
          headers: {'Content-Type': 'application/json'},
        );
      } else {
        return Response(
          400,
          body: jsonEncode({
            'success': false,
            'error': result['error'],
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }
    } catch (e) {
      return Response(
        500,
        body: jsonEncode({'error': 'Failed to send OTP: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _verifyOtp(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final mobileNumber = data['mobile_number'] as String?;
      final countryCode = data['country_code'] as int? ?? 91;
      final otpCode = data['otp_code'] as String?;
      final correlationId = data['correlation_id'] as String?;

      if (mobileNumber == null || mobileNumber.isEmpty) {
        return Response(
          400,
          body: jsonEncode({'error': 'Mobile number is required'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      if (otpCode == null || otpCode.isEmpty) {
        return Response(
          400,
          body: jsonEncode({'error': 'OTP code is required'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      if (correlationId == null || correlationId.isEmpty) {
        return Response(
          400,
          body: jsonEncode({'error': 'Correlation ID is required'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final result = await _otpService.verifyOtp(
        mobileNumber: mobileNumber,
        countryCode: countryCode,
        otpCode: otpCode,
        correlationId: correlationId,
      );

      if (result['success'] == true && result['verified'] == true) {
        // Get or create user and generate JWT tokens
        var user = await _userService.findUserByPhone(mobileNumber);
        if (user == null) {
          user = await _userService.createUser(mobileNumber);
        }

        final accessToken =
            _jwtService.generateAccessToken(user.id.toHexString(), user.phone);
        final refreshToken =
            _jwtService.generateRefreshToken(user.id.toHexString());

        return Response.ok(
          jsonEncode({
            'success': true,
            'verified': true,
            'user_id': user.id.toHexString(),
            'access_token': accessToken,
            'refresh_token': refreshToken,
          }),
          headers: {'Content-Type': 'application/json'},
        );
      } else {
        return Response(
          400,
          body: jsonEncode({
            'success': false,
            'verified': false,
            'error': result['error'] ?? 'OTP verification failed',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }
    } catch (e) {
      return Response(
        500,
        body: jsonEncode({'error': 'Failed to verify OTP: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _registerEmail(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final email = data['email'] as String?;
      final password = data['password'] as String?;
      final displayName = data['display_name'] as String?;

      if (email == null || email.isEmpty) {
        return Response(
          400,
          body: jsonEncode({'error': 'Email is required'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      if (password == null || password.isEmpty) {
        return Response(
          400,
          body: jsonEncode({'error': 'Password is required'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      if (password.length < 6) {
        return Response(
          400,
          body: jsonEncode({'error': 'Password must be at least 6 characters'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final result = await _emailAuthService.registerWithEmail(
        email: email,
        password: password,
        displayName: displayName,
      );

      if (result['success'] == true) {
        return Response.ok(
          jsonEncode({
            'success': true,
            'user': result['user'],
            'access_token': result['access_token'],
            'refresh_token': result['refresh_token'],
          }),
          headers: {'Content-Type': 'application/json'},
        );
      } else {
        return Response(
          400,
          body: jsonEncode({
            'success': false,
            'error': result['error'],
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }
    } catch (e) {
      return Response(
        500,
        body: jsonEncode({'error': 'Failed to register: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _loginEmail(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final email = data['email'] as String?;
      final password = data['password'] as String?;

      if (email == null || email.isEmpty) {
        return Response(
          400,
          body: jsonEncode({'error': 'Email is required'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      if (password == null || password.isEmpty) {
        return Response(
          400,
          body: jsonEncode({'error': 'Password is required'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final result = await _emailAuthService.loginWithEmail(
        email: email,
        password: password,
      );

      if (result['success'] == true) {
        return Response.ok(
          jsonEncode({
            'success': true,
            'user': result['user'],
            'access_token': result['access_token'],
            'refresh_token': result['refresh_token'],
          }),
          headers: {'Content-Type': 'application/json'},
        );
      } else {
        return Response(
          400,
          body: jsonEncode({
            'success': false,
            'error': result['error'],
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }
    } catch (e) {
      return Response(
        500,
        body: jsonEncode({'error': 'Failed to login: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _registerPhone(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final phone = data['phone'] as String?;
      final password = data['password'] as String?;
      final displayName = data['display_name'] as String?;

      if (phone == null || phone.isEmpty) {
        return Response(
          400,
          body: jsonEncode({'error': 'Phone number is required'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      if (password == null || password.isEmpty) {
        return Response(
          400,
          body: jsonEncode({'error': 'Password is required'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      if (password.length < 6) {
        return Response(
          400,
          body: jsonEncode({'error': 'Password must be at least 6 characters'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final result = await _phoneAuthService.registerWithPhone(
        phone: phone,
        password: password,
        displayName: displayName,
      );

      if (result['success'] == true) {
        return Response.ok(
          jsonEncode({
            'success': true,
            'user': result['user'],
            'access_token': result['access_token'],
            'refresh_token': result['refresh_token'],
          }),
          headers: {'Content-Type': 'application/json'},
        );
      } else {
        return Response(
          400,
          body: jsonEncode({
            'success': false,
            'error': result['error'],
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }
    } catch (e) {
      return Response(
        500,
        body: jsonEncode({'error': 'Failed to register: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _loginPhone(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final phone = data['phone'] as String?;
      final password = data['password'] as String?;

      if (phone == null || phone.isEmpty) {
        return Response(
          400,
          body: jsonEncode({'error': 'Phone number is required'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      if (password == null || password.isEmpty) {
        return Response(
          400,
          body: jsonEncode({'error': 'Password is required'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final result = await _phoneAuthService.loginWithPhone(
        phone: phone,
        password: password,
      );

      if (result['success'] == true) {
        return Response.ok(
          jsonEncode({
            'success': true,
            'user': result['user'],
            'access_token': result['access_token'],
            'refresh_token': result['refresh_token'],
          }),
          headers: {'Content-Type': 'application/json'},
        );
      } else {
        return Response(
          400,
          body: jsonEncode({
            'success': false,
            'error': result['error'],
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }
    } catch (e) {
      return Response(
        500,
        body: jsonEncode({'error': 'Failed to login: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _getProfile(Request request) async {
    try {
      final userId = request.context['userId'] as String?;
      if (userId == null) {
        return Response.unauthorized(
          jsonEncode({'error': 'Unauthorized'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final user =
          await _userService.findUserById(ObjectId.fromHexString(userId));
      if (user == null) {
        return Response.notFound(
          jsonEncode({'error': 'User not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      return Response.ok(
        jsonEncode(user.toJson()),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response(
        500,
        body: jsonEncode({'error': 'Failed to get profile: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _updateProfile(Request request) async {
    try {
      final userId = request.context['userId'] as String?;
      if (userId == null) {
        return Response.unauthorized(
          jsonEncode({'error': 'Unauthorized'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final user = await _userService.updateUser(
        ObjectId.fromHexString(userId),
        data,
      );

      if (user == null) {
        return Response.notFound(
          jsonEncode({'error': 'User not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      return Response.ok(
        jsonEncode(user.toJson()),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response(
        500,
        body: jsonEncode({'error': 'Failed to update profile: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _searchUsers(Request request) async {
    try {
      final query = request.url.queryParameters['q'] ?? '';
      if (query.isEmpty) {
        return Response(
          400,
          body: jsonEncode({'error': 'Search query is required'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final users = await _userService.searchUsers(query);
      return Response.ok(
        jsonEncode({'users': users.map((u) => u.toJson()).toList()}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response(
        500,
        body: jsonEncode({'error': 'Failed to search users: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _syncContacts(Request request) async {
    try {
      final userId = request.context['userId'];
      if (userId == null) {
        return Response.unauthorized(
          jsonEncode({'error': 'Unauthorized'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final hashes = (data['phone_hashes'] as List?)?.cast<String>() ?? [];

      if (hashes.isEmpty) {
        return Response.ok(
          jsonEncode({'registered': []}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final users = await _userService.findUsersByPhoneHashes(hashes.toSet());
      return Response.ok(
        jsonEncode({'registered': users.map((u) => u.toJson()).toList()}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response(
        500,
        body: jsonEncode({'error': 'Failed to sync contacts: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }
}
