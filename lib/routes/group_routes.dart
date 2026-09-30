import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../utils/validate.dart';
import '../services/group_service.dart';
import '../services/user_service.dart';
import '../utils/api_responses.dart';

class GroupRoutes {
  final GroupService _groupService = GroupService();
  final UserService _userService = UserService();

  Router get router => Router()
    ..get('/groups', _getGroups)
    ..get('/groups/<groupId>', _getGroup)
    ..post('/groups', _createGroup)
    ..post('/groups/<groupId>/members', _addMembers)
    ..delete('/groups/<groupId>/members/<memberId>', _removeMember)
    ..get('/groups/<groupId>/messages', _getGroupMessages);

  String? _currentUserId(Request request) =>
      request.context['userId'] as String?;

  Future<Response> _getGroups(Request request) async {
    try {
      final userId = _currentUserId(request);
      if (userId == null) {
        return Response.unauthorized(
          jsonEncode({'error': 'Unauthorized'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      final groups = await _groupService.getGroupsForUser(userId);
      return Response.ok(
        jsonEncode({'groups': groups.map((g) => g.toJson()).toList()}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return serverError('Failed to load groups', e);
    }
  }

  Future<Response> _getGroup(Request request, String groupId) async {
    try {
      final userId = _currentUserId(request);
      if (userId == null) {
        return Response.unauthorized(
          jsonEncode({'error': 'Unauthorized'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      if (!isValidUuid(groupId)) {
        return Response(
          400,
          body: jsonEncode({'error': 'Invalid group ID format'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      final group = await _groupService.getGroupById(groupId);
      if (group == null) {
        return Response.notFound(
          jsonEncode({'error': 'Group not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      if (!group.isMember(userId)) {
        return Response.forbidden(
          jsonEncode({'error': 'You are not a member of this group'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Resolve member details for display.
      final members = <Map<String, dynamic>>[];
      for (final m in group.memberIds) {
        final user = await _userService.findUserById(m);
        if (user != null) members.add(user.toJson());
      }

      return Response.ok(
        jsonEncode({'group': group.toJson(), 'members': members}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return serverError('Failed to load group', e);
    }
  }

  Future<Response> _createGroup(Request request) async {
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
      final name = (data['name'] as String?)?.trim() ?? '';
      if (name.isEmpty) {
        return Response(
          400,
          body: jsonEncode({'error': 'Group name is required'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final memberIds = (data['member_ids'] as List<dynamic>? ?? [])
          .map((e) => e as String)
          .where(isValidUuid)
          .toList();

      final group = await _groupService.createGroup(
        name: name,
        avatarUrl: data['avatar_url'] as String?,
        creatorId: userId,
        memberIds: memberIds,
      );

      return Response.ok(
        jsonEncode(group.toJson()),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return serverError('Failed to create group', e);
    }
  }

  Future<Response> _addMembers(Request request, String groupId) async {
    try {
      final userId = _currentUserId(request);
      if (userId == null) {
        return Response.unauthorized(
          jsonEncode({'error': 'Unauthorized'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      if (!isValidUuid(groupId)) {
        return Response(
          400,
          body: jsonEncode({'error': 'Invalid group ID format'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      final group = await _groupService.getGroupById(groupId);
      if (group == null) {
        return Response.notFound(
          jsonEncode({'error': 'Group not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      if (!group.isMember(userId)) {
        return Response.forbidden(
          jsonEncode({'error': 'You are not a member of this group'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final newMembers = (data['member_ids'] as List<dynamic>? ?? [])
          .map((e) => e as String)
          .where(isValidUuid)
          .toList();

      final updated = await _groupService.addMembers(groupId, newMembers);

      return Response.ok(
        jsonEncode(updated!.toJson()),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return serverError('Failed to add members', e);
    }
  }

  Future<Response> _removeMember(
      Request request, String groupId, String memberId) async {
    try {
      final userId = _currentUserId(request);
      if (userId == null) {
        return Response.unauthorized(
          jsonEncode({'error': 'Unauthorized'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      if (!isValidUuid(groupId)) {
        return Response(
          400,
          body: jsonEncode({'error': 'Invalid group ID format'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      final group = await _groupService.getGroupById(groupId);
      if (group == null) {
        return Response.notFound(
          jsonEncode({'error': 'Group not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Members may leave themselves; creators may remove others.
      final isSelf = userId == memberId;
      final isCreator = group.creatorId == userId;
      if (!isSelf && !isCreator) {
        return Response.forbidden(
          jsonEncode({'error': 'You cannot remove members from this group'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final updated = await _groupService.removeMember(groupId, memberId);

      return Response.ok(
        jsonEncode(updated!.toJson()),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return serverError('Failed to remove member', e);
    }
  }

  Future<Response> _getGroupMessages(Request request, String groupId) async {
    try {
      final userId = _currentUserId(request);
      if (userId == null) {
        return Response.unauthorized(
          jsonEncode({'error': 'Unauthorized'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      if (!isValidUuid(groupId)) {
        return Response(
          400,
          body: jsonEncode({'error': 'Invalid group ID format'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      final group = await _groupService.getGroupById(groupId);
      if (group == null) {
        return Response.notFound(
          jsonEncode({'error': 'Group not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      if (!group.isMember(userId)) {
        return Response.forbidden(
          jsonEncode({'error': 'You are not a member of this group'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final limit =
          int.tryParse(request.url.queryParameters['limit'] ?? '50') ?? 50;
      final skip =
          int.tryParse(request.url.queryParameters['skip'] ?? '0') ?? 0;

      final messages = await _groupService.getGroupMessages(
        groupId: groupId,
        limit: limit,
        skip: skip,
      );

      return Response.ok(
        jsonEncode({'messages': messages.map((m) => m.toJson()).toList()}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return serverError('Failed to load group messages', e);
    }
  }
}
