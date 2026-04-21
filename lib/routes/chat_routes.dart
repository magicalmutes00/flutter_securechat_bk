import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:mongo_dart/mongo_dart.dart';
import '../services/message_service.dart';
import '../services/user_service.dart';
import '../config/app_config.dart';

class ChatRoutes {
  final MessageService _messageService = MessageService();
  final UserService _userService = UserService();

  Router get router => Router()
    ..get('/messages/<userId>', _getMessages)
    ..get('/conversations', _getConversations)
    ..post('/message', _sendMessage)
    ..put('/message/<messageId>/status', _updateMessageStatus)
    ..delete('/message/<messageId>', _deleteMessage);

  Future<Response> _getMessages(Request request, String userId) async {
    try {
      final currentUserId = request.context['userId'] as String?;
      if (currentUserId == null) {
        return Response.unauthorized(
          jsonEncode({'error': 'Unauthorized'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final ObjectId currentUserOid;
      final ObjectId otherUserOid;
      try {
        currentUserOid = ObjectId.fromHexString(currentUserId);
        otherUserOid = ObjectId.fromHexString(userId);
      } catch (e) {
        return Response(400,
          body: jsonEncode({'error': 'Invalid user ID format'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      if (currentUserOid != currentUserOid || otherUserOid != otherUserOid) {
        return Response.forbidden(
          jsonEncode({'error': 'Not authorized to access these messages'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final limit = int.tryParse(request.url.queryParameters['limit'] ?? '50') ?? 50;
      final skip = int.tryParse(request.url.queryParameters['skip'] ?? '0') ?? 0;

      final messages = await _messageService.getMessages(
        userId1: currentUserOid,
        userId2: otherUserOid,
        limit: limit,
        skip: skip,
      );

      final authorizedMessages = messages.where((m) =>
        m.senderId == currentUserOid || m.receiverId == currentUserOid
      ).toList();

      return Response.ok(
        jsonEncode({
          'messages': authorizedMessages.map((m) => m.toJson()).toList(),
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response(500,
        body: jsonEncode({'error': 'Failed to get messages: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _getConversations(Request request) async {
    try {
      final userId = request.context['userId'] as String?;
      if (userId == null) {
        return Response.unauthorized(
          jsonEncode({'error': 'Unauthorized'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final conversations = await _messageService.getConversations(
        ObjectId.fromHexString(userId),
      );

      final List<Map<String, dynamic>> result = [];
      for (final conv in conversations) {
        final otherUserId = conv['_id'];
        if (otherUserId != null) {
          final otherUser = await _userService.findUserById(otherUserId as ObjectId);
          if (otherUser != null) {
            result.add({
              'user': otherUser.toJson(),
              'last_message': conv['last_message'],
              'unread_count': conv['unread_count'] ?? 0,
            });
          }
        }
      }

      return Response.ok(
        jsonEncode({'conversations': result}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response(500,
        body: jsonEncode({'error': 'Failed to get conversations: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _sendMessage(Request request) async {
    try {
      final senderId = request.context['userId'] as String?;
      if (senderId == null) {
        return Response.unauthorized(
          jsonEncode({'error': 'Unauthorized'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final receiverId = data['receiver_id'] as String?;
      final messageType = data['message_type'] as String? ?? AppConfig.messageTypeText;
      final content = data['content'] as String? ?? '';
      final fileUrl = data['file_url'] as String?;
      final fileName = data['file_name'] as String?;
      final fileSize = data['file_size'] as int?;
      final mediaType = data['media_type'] as String?;

      if (receiverId == null) {
        return Response(400,
          body: jsonEncode({'error': 'Receiver ID is required'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final message = await _messageService.sendMessage(
        senderId: ObjectId.fromHexString(senderId),
        receiverId: ObjectId.fromHexString(receiverId),
        messageType: messageType,
        content: content,
        filePath: fileUrl,
        fileName: fileName,
        fileSize: fileSize,
        mediaType: mediaType,
      );

      return Response.ok(
        jsonEncode(message.toJson()),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response(500,
        body: jsonEncode({'error': 'Failed to send message: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _updateMessageStatus(Request request, String messageId) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final status = data['status'] as String?;

      if (status == null) {
        return Response(400,
          body: jsonEncode({'error': 'Status is required'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      await _messageService.updateMessageStatus(
        ObjectId.fromHexString(messageId),
        status,
      );

      return Response.ok(
        jsonEncode({'success': true}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response(500,
        body: jsonEncode({'error': 'Failed to update message status: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _deleteMessage(Request request, String messageId) async {
    try {
      await _messageService.deleteMessage(ObjectId.fromHexString(messageId));

      return Response.ok(
        jsonEncode({'success': true}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response(500,
        body: jsonEncode({'error': 'Failed to delete message: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }
}
