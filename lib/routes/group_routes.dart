import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:mongo_dart/mongo_dart.dart';
import '../services/group_service.dart';
import '../services/user_service.dart';

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
      final groups = await _groupService.getGroupsForUser(
        ObjectId.fromHexString(userId),
      );
      return Response.ok(
        jsonEncode({'groups': groups.map((g) => g.toJson()).toList()}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response(
        500,
        body: jsonEncode({'error': 'Failed to load groups: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
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
      final group = await _groupService.getGroupById(
        ObjectId.fromHexString(groupId),
      );
      if (group == null) {
        return Response.notFound(
          jsonEncode({'error': 'Group not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      if (!group.isMember(ObjectId.fromHexString(userId))) {
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
      return Response(
        500,
        body: jsonEncode({'error': 'Failed to load group: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
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
          .map((e) => ObjectId.fromHexString(e as String))
          .toList();

      final group = await _groupService.createGroup(
        name: name,
        avatarUrl: data['avatar_url'] as String?,
        creatorId: ObjectId.fromHexString(userId),
        memberIds: memberIds,
      );

      return Response.ok(
        jsonEncode(group.toJson()),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response(
        500,
        body: jsonEncode({'error': 'Failed to create group: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
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

      final group = await _groupService.getGroupById(
        ObjectId.fromHexString(groupId),
      );
      if (group == null) {
        return Response.notFound(
          jsonEncode({'error': 'Group not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      if (!group.isMember(ObjectId.fromHexString(userId))) {
        return Response.forbidden(
          jsonEncode({'error': 'You are not a member of this group'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final newMembers = (data['member_ids'] as List<dynamic>? ?? [])
          .map((e) => ObjectId.fromHexString(e as String))
          .toList();

      final updated = await _groupService.addMembers(
        ObjectId.fromHexString(groupId),
        newMembers,
      );

      return Response.ok(
        jsonEncode(updated!.toJson()),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response(
        500,
        body: jsonEncode({'error': 'Failed to add members: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
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

      final group = await _groupService.getGroupById(
        ObjectId.fromHexString(groupId),
      );
      if (group == null) {
        return Response.notFound(
          jsonEncode({'error': 'Group not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Members may leave themselves; creators may remove others.
      final isSelf = userId == memberId;
      final isCreator = group.creatorId == ObjectId.fromHexString(userId);
      if (!isSelf && !isCreator) {
        return Response.forbidden(
          jsonEncode({'error': 'You cannot remove members from this group'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final updated = await _groupService.removeMember(
        ObjectId.fromHexString(groupId),
        ObjectId.fromHexString(memberId),
      );

      return Response.ok(
        jsonEncode(updated!.toJson()),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response(
        500,
        body: jsonEncode({'error': 'Failed to remove member: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
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

      final group = await _groupService.getGroupById(
        ObjectId.fromHexString(groupId),
      );
      if (group == null) {
        return Response.notFound(
          jsonEncode({'error': 'Group not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      if (!group.isMember(ObjectId.fromHexString(userId))) {
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
        groupId: ObjectId.fromHexString(groupId),
        limit: limit,
        skip: skip,
      );

      return Response.ok(
        jsonEncode({'messages': messages.map((m) => m.toJson()).toList()}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response(
        500,
        body: jsonEncode({'error': 'Failed to load group messages: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }
}
