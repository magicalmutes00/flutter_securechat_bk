import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/message_model.dart';
import '../utils/plaintext_guard.dart';
import '../utils/validate.dart';
import 'group_service.dart';
import 'message_service.dart';
import 'push_service.dart';
import 'user_service.dart';

class WebSocketService {
  final Map<String, WebSocketChannel> _connections = {};
  final Map<String, String> _connectionUsers = {};
  final Map<String, bool> _connectionAuthenticated = {};
  final MessageService _messageService = MessageService();
  final GroupService _groupService = GroupService();
  final UserService _userService = UserService();
  final PushService _pushService = PushService();

  void handleConnection(WebSocketChannel channel, String userId) {
    final connectionId = '${DateTime.now().microsecondsSinceEpoch}_$userId';
    _connections[connectionId] = channel;
    _connectionUsers[connectionId] = userId;
    _connectionAuthenticated[connectionId] =
        true; // Auth already verified in main.dart via token

    unawaited(_userService.updateOnlineStatus(userId, true));

    channel.stream.listen(
      (message) => _handleMessage(connectionId, message),
      onDone: () => _handleDisconnect(connectionId),
      onError: (error) => _handleDisconnect(connectionId),
    );

    unawaited(_broadcastUserStatus(userId, true));
  }

  void _handleMessage(String connectionId, dynamic message) {
    // Check authentication for non-pong messages
    if (!_connectionAuthenticated[connectionId]!) {
      final data = jsonDecode(message as String) as Map<String, dynamic>;
      if (data['type'] != 'pong') {
        _sendToConnection(
            connectionId, {'type': 'error', 'message': 'Not authenticated'});
        return;
      }
    }

    final authenticatedUserId = _connectionUsers[connectionId];

    try {
      final data = jsonDecode(message as String) as Map<String, dynamic>;
      final type = data['type'] as String?;

      switch (type) {
        case 'message':
          _handleChatMessage(data, authenticatedUserId: authenticatedUserId);
          break;
        case 'group_message':
          _handleGroupMessage(data, authenticatedUserId: authenticatedUserId);
          break;
        case 'typing':
          _handleTyping(data, authenticatedUserId: authenticatedUserId);
          break;
        case 'group_typing':
          _handleGroupTyping(data, authenticatedUserId: authenticatedUserId);
          break;
        case 'read':
          _handleReadReceipt(data, readerUserId: authenticatedUserId);
          break;
        // NOTE: no session-reset case. Legacy crypto-control frames fall
        // through to `default` and are silently ignored/dropped — they are
        // never relayed.
        case 'delivered':
          _handleDeliveryReceipt(data, receiverUserId: authenticatedUserId);
          break;
        case 'call_ring':
        case 'call_offer':
        case 'call_answer':
        case 'call_ice':
        case 'call_accept':
        case 'call_decline':
        case 'call_end':
          _handleCallSignal(data, authenticatedUserId: authenticatedUserId);
          break;
        case 'pong':
          break;
        default:
          break;
      }
    } catch (e) {
      // Silently ignore malformed messages
    }
  }

  void _sendToConnection(String connectionId, Map<String, dynamic> data) {
    final channel = _connections[connectionId];
    if (channel != null) {
      channel.sink.add(jsonEncode(data));
    }
  }

  Future<void> _handleChatMessage(
    Map<String, dynamic> data, {
    required String? authenticatedUserId,
  }) async {
    if (authenticatedUserId == null) return;

    try {
      // Plaintext-only: drop any frame carrying crypto/control material.
      if (rejectCryptoMessagePayload(data) != null) return;

      final senderId = authenticatedUserId;
      final receiverId = data['receiver_id'] as String?;
      if (receiverId == null || !isValidUuid(receiverId)) return;
      final messageType = data['message_type'] as String? ?? 'text';
      final content = data['content'] as String? ?? '';
      final fileUrl = data['file_url'] as String?;
      final fileName = data['file_name'] as String?;
      final fileSize = data['file_size'] as int?;
      final mediaType = data['media_type'] as String?;
      final replyToId = data['reply_to_id'] as String?;

      if (receiverId == senderId) {
        return;
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

      final messageData = message.toJson();
      _sendToUser(receiverId, {
        'type': 'message',
        'data': messageData,
      });

      _sendToUser(senderId, {
        'type': 'message_sent',
        'data': messageData,
      });

      // Push notifications: only when the receiver is not connected so we do
      // not duplicate what the live WebSocket already delivers.
      if (!isUserConnected(receiverId)) {
        unawaited(_sendChatPush(senderId, receiverId, message));
      }
    } catch (e) {
      print('Error handling chat message: $e');
    }
  }

  Future<void> _sendChatPush(
    String senderId,
    String receiverId,
    MessageModel message,
  ) async {
    try {
      final sender = await _userService.findUserById(senderId);
      final senderName = sender?.displayName ?? 'Someone';

      // Plaintext mode: push bodies show the actual text content.
      final body = plaintextPushBody(message.messageType, message.content);

      await _pushService.sendToUser(
        userId: receiverId,
        title: senderName,
        body: body,
        data: {
          'sender_id': senderId,
          'message_id': message.id,
          'type': 'message',
        },
      );
    } catch (_) {
      // Best-effort push; failures must never break message delivery.
    }
  }

  String _messageTypeLabel(String type) {
    switch (type) {
      case 'image':
        return 'Photo';
      case 'video':
        return 'Video';
      case 'audio':
        return 'Voice message';
      case 'document':
        return 'Document';
      default:
        return 'New message';
    }
  }

  /// Push body for plaintext messages: actual text content for `text`
  /// messages (truncated), generic media labels otherwise.
  String plaintextPushBody(String messageType, String content) {
    if (messageType == 'text') {
      final trimmed = content.trim();
      if (trimmed.isEmpty) return 'Sent you a message';
      const maxLength = 120;
      if (trimmed.length <= maxLength) return trimmed;
      return '${trimmed.substring(0, maxLength)}…';
    }
    return _messageTypeLabel(messageType);
  }

  Future<void> _handleGroupMessage(
    Map<String, dynamic> data, {
    required String? authenticatedUserId,
  }) async {
    if (authenticatedUserId == null) return;

    try {
      // Plaintext-only: drop any frame carrying crypto/control material.
      if (rejectCryptoMessagePayload(data) != null) return;

      final senderId = authenticatedUserId;
      final groupId = data['group_id'] as String?;
      if (groupId == null || !isValidUuid(groupId)) return;
      final group = await _groupService.getGroupById(groupId);
      if (group == null) return;
      if (!group.isMember(senderId)) return;

      final message = await _groupService.sendGroupMessage(
        groupId: group.id,
        senderId: senderId,
        messageType: data['message_type'] as String? ?? 'text',
        content: data['content'] as String? ?? '',
        filePath: data['file_url'] as String?,
        fileName: data['file_name'] as String?,
        fileSize: data['file_size'] as int?,
        mediaType: data['media_type'] as String?,
        replyToId: data['reply_to_id'] as String?,
      );

      final messageData = message.toJson();
      for (final memberId in group.memberIds) {
        if (memberId == senderId) continue;
        _sendToUser(memberId, {
          'type': 'group_message',
          'data': messageData,
        });
      }

      _sendToUser(senderId, {
        'type': 'message_sent',
        'data': messageData,
      });

      // Notify offline group members. Plaintext mode shows actual text.
      final sender = await _userService.findUserById(senderId);
      final senderName = sender?.displayName ?? 'Someone';
      final body =
          plaintextPushBody(message.messageType, message.content);
      for (final memberId in group.memberIds) {
        if (memberId == senderId) continue;
        if (isUserConnected(memberId)) continue;
        unawaited(_pushService.sendToUser(
          userId: memberId,
          title: senderName,
          body: body,
          data: {
            'group_id': group.id,
            'message_id': message.id,
            'type': 'group_message',
          },
        ));
      }
    } catch (e) {
      print('Error handling group message: $e');
    }
  }

  Future<void> _handleGroupTyping(
    Map<String, dynamic> data, {
    required String? authenticatedUserId,
  }) async {
    if (authenticatedUserId == null) return;
    final groupId = data['group_id'] as String?;
    if (groupId == null || !isValidUuid(groupId)) return;
    final group = await _groupService.getGroupById(groupId);
    if (group == null) return;
    // Only members may trigger typing events for a group.
    if (!group.isMember(authenticatedUserId)) return;

    for (final memberId in group.memberIds) {
      if (memberId == authenticatedUserId) continue;
      _sendToUser(memberId, {
        'type': 'group_typing',
        'group_id': groupId,
        'sender_id': authenticatedUserId,
        'is_typing': data['is_typing'] ?? true,
      });
    }
  }

  void _handleTyping(
    Map<String, dynamic> data, {
    required String? authenticatedUserId,
  }) {
    if (authenticatedUserId == null) return;
    final receiverId = data['receiver_id'] as String?;
    if (receiverId == null || !isValidUuid(receiverId)) return;
    _sendToUser(receiverId, {
      'type': 'typing',
      'sender_id': authenticatedUserId,
      'is_typing': data['is_typing'] ?? true,
    });
  }

  /// Relays a WebRTC call signaling message (SDP offer/answer or ICE candidate)
  /// and lifecycle events to the intended callee/caller.
  ///
  /// The server only routes signaling bytes between the two participants; media
  /// flows peer-to-peer (or through TURN) and is never relayed through us.
  void _handleCallSignal(
    Map<String, dynamic> data, {
    required String? authenticatedUserId,
  }) {
    if (authenticatedUserId == null) return;
    final peerId = data['receiver_id'] as String?;
    if (peerId == null || !isValidUuid(peerId)) return;

    final payload = Map<String, dynamic>.from(data)
      ..['sender_id'] = authenticatedUserId;

    // ICE candidates and SDP are fragile to reordering; failing fast here is
    // better than silently dropping a call setup.
    _sendToUser(peerId, payload);
  }

  Future<void> _handleReadReceipt(
    Map<String, dynamic> data, {
    required String? readerUserId,
  }) async {
    if (readerUserId == null) return;

    final senderId = data['sender_id'] as String?;
    if (senderId == null || !isValidUuid(senderId)) return;
    if (senderId == readerUserId) return;

    await _messageService.markMessagesAsRead(senderId, readerUserId);

    _sendToUser(senderId, {
      'type': 'read_receipt',
      'receiver_id': readerUserId,
    });
  }

  Future<void> _handleDeliveryReceipt(
    Map<String, dynamic> data, {
    required String? receiverUserId,
  }) async {
    if (receiverUserId == null) return;

    final senderId = data['sender_id'] as String?;
    final messageId = data['message_id'] as String?;
    if (senderId == null ||
        messageId == null ||
        !isValidUuid(senderId) ||
        !isValidUuid(messageId)) {
      return;
    }

    // Only the message's actual receiver may mark it delivered; otherwise any
    // authenticated user could flip the status of any message by id.
    final delivered = await _messageService.markDelivered(
      messageId,
      receiverUserId,
    );
    if (!delivered) return;

    _sendToUser(senderId, {
      'type': 'delivery_receipt',
      'receiver_id': receiverUserId,
    });
  }

  void _handleDisconnect(String connectionId) {
    final userId = _connectionUsers[connectionId];
    if (userId != null) {
      unawaited(_userService.updateOnlineStatus(userId, false));
      unawaited(_broadcastUserStatus(userId, false));
      _connectionUsers.remove(connectionId);
    }
    _connections.remove(connectionId);
  }

  void _sendToUser(String userId, Map<String, dynamic> data) {
    for (final entry in _connectionUsers.entries) {
      if (entry.value == userId) {
        final channel = _connections[entry.key];
        channel?.sink.add(jsonEncode(data));
      }
    }
  }

  /// Broadcasts online/offline presence only to users who share a
  /// conversation with [userId] — presence of strangers is nobody's business.
  Future<void> _broadcastUserStatus(String userId, bool isOnline) async {
    final statusMessage = jsonEncode({
      'type': 'user_status',
      'user_id': userId,
      'is_online': isOnline,
    });

    final Set<String> audience;
    try {
      audience = await _messageService.getConversationPartnerIds(userId);
    } catch (_) {
      return; // Presence is best-effort; never break the connection path.
    }

    for (final entry in _connectionUsers.entries) {
      if (entry.value != userId && audience.contains(entry.value)) {
        final channel = _connections[entry.key];
        channel?.sink.add(statusMessage);
      }
    }
  }

  int get connectedUsers => _connections.length;

  bool isUserConnected(String userId) {
    return _connectionUsers.containsValue(userId);
  }

  Future<void> close() async {
    for (final channel in _connections.values) {
      await channel.sink.close();
    }
    _connections.clear();
    _connectionUsers.clear();
  }
}
