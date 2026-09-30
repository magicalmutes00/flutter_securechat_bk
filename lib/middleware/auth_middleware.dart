import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../services/jwt_service.dart';
import '../services/user_service.dart';
import '../utils/validate.dart';

class AuthMiddleware {
  final JwtService _jwtService = JwtService();
  final UserService _userService = UserService();

  Middleware handler() {
    return (Handler innerHandler) {
      return (Request request) async {
        final authHeader = request.headers['authorization'];

        if (authHeader == null || !authHeader.startsWith('Bearer ')) {
          return Response.unauthorized(
            jsonEncode({'error': 'No authorization token provided'}),
            headers: {'Content-Type': 'application/json'},
          );
        }

        final token = authHeader.substring(7);
        final payload = _jwtService.verifyToken(token);

        if (payload == null) {
          return Response.unauthorized(
            jsonEncode({'error': 'Invalid or expired token'}),
            headers: {'Content-Type': 'application/json'},
          );
        }

        final userId = payload['sub'] as String?;
        if (userId == null || !isValidUuid(userId)) {
          return Response.unauthorized(
            jsonEncode({'error': 'Invalid token payload'}),
            headers: {'Content-Type': 'application/json'},
          );
        }

        final user = await _userService.findUserById(userId);
        if (user == null) {
          return Response.unauthorized(
            jsonEncode({'error': 'User not found'}),
            headers: {'Content-Type': 'application/json'},
          );
        }

        final updatedRequest = request.change(
          context: {
            'userId': userId,
            'user': user,
          },
        );

        return innerHandler(updatedRequest);
      };
    };
  }
}

Handler addAuthMiddleware(Handler handler) {
  final authMiddleware = AuthMiddleware();
  return authMiddleware.handler()(handler);
}
