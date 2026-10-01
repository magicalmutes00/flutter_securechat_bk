import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../middleware/request_id_middleware.dart';
import '../services/file_service.dart';
import '../services/message_service.dart';
import '../services/user_service.dart';
import '../utils/api_responses.dart';
import '../utils/plaintext_guard.dart';
import '../utils/validate.dart';
import '../config/app_config.dart';

class ChatRoutes {
  final FileService _fileService = FileService();
  final MessageService _messageService = MessageService();
  final UserService _userService = UserService();

  Router get router => Router()
    ..get('/messages/search', _searchMessages)
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

      if (!isValidUuid(userId) || !isValidUuid(currentUserId)) {
        return Response(
          400,
          body: jsonEncode({'error': 'Invalid user ID format'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final limit =
          int.tryParse(request.url.queryParameters['limit'] ?? '50') ?? 50;
      final skip =
          int.tryParse(request.url.queryParameters['skip'] ?? '0') ?? 0;

      final messages = await _messageService.getMessages(
        userId1: currentUserId,
        userId2: userId,
        limit: limit,
        skip: skip,
      );

      final authorizedMessages = messages
          .where((m) =>
              m.senderId == currentUserId || m.receiverId == currentUserId)
          .toList();

      return Response.ok(
        jsonEncode({
          'messages': authorizedMessages.map((m) => m.toJson()).toList(),
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return serverError('Failed to get messages', e);
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

      final conversations = await _messageService.getConversations(userId);

      final List<Map<String, dynamic>> result = [];
      for (final conv in conversations) {
        final partnerId = conv['partner_id'] as String?;
        if (partnerId != null) {
          final otherUser = await _userService.findUserById(partnerId);
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
      return serverError('Failed to get conversations', e);
    }
  }

  Future<Response> _searchMessages(Request request) async {
    try {
      final currentUserId = request.context['userId'] as String?;
      if (currentUserId == null) {
        return Response.unauthorized(
          jsonEncode({'error': 'Unauthorized'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final query = request.url.queryParameters['q'] ?? '';
      if (query.isEmpty) {
        return Response(
          400,
          body: jsonEncode({'error': 'Query parameter "q" is required'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final messages = await _messageService.searchMessages(
        userId: currentUserId,
        query: query,
      );

      return Response.ok(
        jsonEncode({
          'messages': messages.map((m) => m.toJson()).toList(),
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return serverError('Failed to search messages', e);
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
      final messageType =
          data['message_type'] as String? ?? AppConfig.messageTypeText;
      final content = data['content'] as String? ?? '';
      final fileUrl = data['file_url'] as String?;
      final fileName = data['file_name'] as String?;
      final fileSize = data['file_size'] as int?;
      final mediaType = data['media_type'] as String?;
      final replyToId = data['reply_to_id'] as String?;

      // Plaintext-only contract: reject any crypto/control material before
      // touching the database. Absent `encryption` defaults to 'none'.
      final cryptoRejection = rejectCryptoMessagePayload(data);
      if (cryptoRejection != null) {
        return Response(
          400,
          body: jsonEncode({'error': cryptoRejection}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      if (receiverId == null || !isValidUuid(receiverId)) {
        return Response(
          400,
          body: jsonEncode({'error': 'A valid receiver ID is required'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final message = await _messageService.sendMessage(
        senderId: senderId,
        receiverId: receiverId,
        messageType: messageType,
        content: content,
        filePath: fileUrl,
        fileName: fileName,
        fileSize: fileSize,
        mediaType: mediaType,
        replyToId: replyToId,
      );

      return Response.ok(
        jsonEncode(message.toJson()),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return serverError('Failed to send message', e);
    }
  }

  Future<Response> _updateMessageStatus(
      Request request, String messageId) async {
    try {
      final currentUserId = request.context['userId'] as String?;
      if (currentUserId == null) {
        return Response.unauthorized(
          jsonEncode({'error': 'Unauthorized'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      if (!isValidUuid(messageId) || !isValidUuid(currentUserId)) {
        return Response(
          400,
          body: jsonEncode({'error': 'Invalid ID format'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final message = await _messageService.getMessageById(messageId);
      if (message == null) {
        return Response.notFound(
          jsonEncode({'error': 'Message not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final isParticipant = message.senderId == currentUserId ||
          message.receiverId == currentUserId;
      if (!isParticipant) {
        return Response.forbidden(
          jsonEncode({'error': 'Not authorized to update this message'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final status = data['status'] as String?;

      const allowedStatuses = ['sent', 'delivered', 'read'];
      if (status == null || !allowedStatuses.contains(status)) {
        return Response(
          400,
          body: jsonEncode({'error': 'Status must be one of: $allowedStatuses'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Delivery/read receipts belong to the recipient; the sender has no
      // business flipping them (and vice versa for 'sent').
      final isReceiver = message.receiverId == currentUserId;
      final isSender = message.senderId == currentUserId;
      if (status == AppConfig.messageStatusSent && !isSender ||
          (status == AppConfig.messageStatusDelivered ||
                  status == AppConfig.messageStatusRead) &&
              !isReceiver) {
        return Response.forbidden(
          jsonEncode({'error': 'Not authorized to set this status'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      await _messageService.updateMessageStatus(
        messageId,
        status,
      );

      return Response.ok(
        jsonEncode({'success': true}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return serverError('Failed to update message status', e);
    }
  }

  Future<Response> _deleteMessage(Request request, String messageId) async {
    final requestId = requestIdOf(request);
    try {
      final currentUserId = request.context['userId'] as String?;
      if (currentUserId == null) {
        return Response.unauthorized(
          jsonEncode({'error': 'Unauthorized'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      if (!isValidUuid(messageId) || !isValidUuid(currentUserId)) {
        return Response(
          400,
          body: jsonEncode({'error': 'Invalid ID format'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final message = await _messageService.getMessageById(messageId);
      if (message == null) {
        return Response.notFound(
          jsonEncode({'error': 'Message not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      if (message.senderId != currentUserId) {
        return Response.forbidden(
          jsonEncode({'error': 'Only the sender can delete this message'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      await _messageService.deleteMessage(messageId);

      // Best-effort orphan cleanup: the row is gone, so an unreferenced
      // asset can go too. Never fails the delete — a Cloudinary hiccup
      // leaves the row for a later manual DELETE /api/files/<id>.
      final filePath = message.filePath;
      if (filePath != null && filePath.startsWith('/api/files/')) {
        final fileId = filePath.substring('/api/files/'.length);
        if (isValidUuid(fileId)) {
          try {
            await _fileService.deleteIfUnreferenced(
              fileId: fileId,
              ownerId: currentUserId,
            );
          } catch (e) {
            stderr.writeln(
                'Orphan file cleanup failed [request $requestId]: $e');
          }
        }
      }

      return Response.ok(
        jsonEncode({'success': true}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return serverError('Failed to delete message', e);
    }
  }
}
