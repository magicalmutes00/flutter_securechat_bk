import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:mongo_dart/mongo_dart.dart';
import '../services/push_service.dart';

class PushRoutes {
  final PushService _pushService = PushService();

  Router get router => Router()
    ..post('/register-token', _registerToken)
    ..post('/unregister-token', _unregisterToken);

  String? _currentUserId(Request request) =>
      request.context['userId'] as String?;

  Future<Response> _registerToken(Request request) async {
    try {
      final userId = _currentUserId(request);
      if (userId == null) {
        return Response.unauthorized(
          jsonEncode({'error': 'Unauthorized'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final token = (data['token'] as String?)?.trim() ?? '';
      if (token.isEmpty) {
        return Response(
          400,
          body: jsonEncode({'error': 'Push token is required'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      await _pushService.registerToken(
        userId: ObjectId.fromHexString(userId),
        token: token,
        platform: (data['platform'] as String?) ?? 'android',
      );

      return Response.ok(
        jsonEncode({'success': true}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response(
        500,
        body: jsonEncode({'error': 'Failed to register push token: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _unregisterToken(Request request) async {
    try {
      final userId = _currentUserId(request);
      if (userId == null) {
        return Response.unauthorized(
          jsonEncode({'error': 'Unauthorized'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final token = (data['token'] as String?)?.trim() ?? '';

      await _pushService.unregisterToken(
        userId: ObjectId.fromHexString(userId),
        token: token,
      );

      return Response.ok(
        jsonEncode({'success': true}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response(
        500,
        body: jsonEncode({'error': 'Failed to unregister push token: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }
}
