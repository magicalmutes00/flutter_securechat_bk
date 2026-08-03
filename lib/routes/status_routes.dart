import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:mongo_dart/mongo_dart.dart';
import '../services/status_service.dart';
import '../services/user_service.dart';

class StatusRoutes {
  final StatusService _statusService = StatusService();
  final UserService _userService = UserService();

  Router get router => Router()
    ..get('/statuses', _getStatuses)
    ..post('/statuses', _createStatus)
    ..post('/statuses/<id>/view', _markViewed)
    ..delete('/statuses/<id>', _deleteStatus);

  String? _currentUserId(Request request) =>
      request.context['userId'] as String?;

  Future<Response> _getStatuses(Request request) async {
    try {
      final userId = _currentUserId(request);
      if (userId == null) {
        return Response.unauthorized(
          jsonEncode({'error': 'Unauthorized'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final statuses = await _statusService.getActiveStatuses();

      // Attach author user info to each status for display.
      final statusList = <Map<String, dynamic>>[];
      for (final status in statuses) {
        final author = await _userService.findUserById(status.userId);
        statusList.add({
          'status': status.toJson(),
          'author': author?.toJson(),
        });
      }

      return Response.ok(
        jsonEncode({'statuses': statusList}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response(
        500,
        body: jsonEncode({'error': 'Failed to load statuses: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _createStatus(Request request) async {
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
      final text = (data['text'] as String?)?.trim() ?? '';
      final mediaPath = data['media_path'] as String?;
      final mediaType = data['media_type'] as String?;

      if (text.isEmpty && (mediaPath == null || mediaPath.isEmpty)) {
        return Response(
          400,
          body: jsonEncode({'error': 'Status must have text or media'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final status = await _statusService.createStatus(
        userId: ObjectId.fromHexString(userId),
        text: text.isEmpty ? null : text,
        mediaPath: mediaPath,
        mediaType: mediaType,
      );

      return Response.ok(
        jsonEncode(status.toJson()),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response(
        500,
        body: jsonEncode({'error': 'Failed to create status: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _markViewed(Request request, String id) async {
    try {
      final userId = _currentUserId(request);
      if (userId == null) {
        return Response.unauthorized(
          jsonEncode({'error': 'Unauthorized'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final status = await _statusService.markViewed(
        ObjectId.fromHexString(id),
        ObjectId.fromHexString(userId),
      );
      if (status == null) {
        return Response.notFound(
          jsonEncode({'error': 'Status not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      return Response.ok(
        jsonEncode(status.toJson()),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response(
        500,
        body: jsonEncode({'error': 'Failed to update status: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _deleteStatus(Request request, String id) async {
    try {
      final userId = _currentUserId(request);
      if (userId == null) {
        return Response.unauthorized(
          jsonEncode({'error': 'Unauthorized'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Only the author may delete their own status.
      final status = await _statusService.getStatusById(
        ObjectId.fromHexString(id),
      );
      if (status == null) {
        return Response.notFound(
          jsonEncode({'error': 'Status not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      if (status.userId != ObjectId.fromHexString(userId)) {
        return Response.forbidden(
          jsonEncode({'error': 'You can only delete your own statuses'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      await _statusService.deleteStatus(
        ObjectId.fromHexString(id),
        ObjectId.fromHexString(userId),
      );

      return Response.ok(
        jsonEncode({'success': true}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response(
        500,
        body: jsonEncode({'error': 'Failed to delete status: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }
}
