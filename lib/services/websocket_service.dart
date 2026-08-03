import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:mongo_dart/mongo_dart.dart';
import '../config/app_config.dart';
import '../models/message_model.dart';
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
    final connectionId = DateTime.now().millisecondsSinceEpoch.toString();
    _connections[connectionId] = channel;
    _connectionUsers[connectionId] = userId;
    _connectionAuthenticated[connectionId] =
        true; // Auth already verified in main.dart via token

    _userService.updateOnlineStatus(ObjectId.fromHexString(userId), true);

    channel.stream.listen(
      (message) => _handleMessage(connectionId, message),
      onDone: () => _handleDisconnect(connectionId),
      onError: (error) => _handleDisconnect(connectionId),
    );

    _broadcastUserStatus(userId, true);
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
      final senderId = authenticatedUserId;
      final receiverId = data['receiver_id'] as String;
      final messageType = data['message_type'] as String? ?? 'text';
      final content = data['content'] as String? ?? '';
      final fileUrl = data['file_url'] as String?;
      final fileName = data['file_name'] as String?;
      final fileSize = data['file_size'] as int?;
      final mediaType = data['media_type'] as String?;
      final encryption = data['encryption'] as String? ?? 'none';
      final cipherType = data['cipher_type'] as int?;
      final cipherBody = data['cipher_body'] as String?;

      if (receiverId == senderId) {
        return;
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
        encryption: encryption,
        cipherType: cipherType,
        cipherBody: cipherBody,
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
      final sender = await _userService.findUserById(
        ObjectId.fromHexString(senderId),
      );
      final senderName = sender?.displayName ?? 'Someone';

      final body = message.messageType == 'text'
          ? message.content
          : _messageTypeLabel(message.messageType);

      await _pushService.sendToUser(
        userId: ObjectId.fromHexString(receiverId),
        title: senderName,
        body: body,
        data: {
          'sender_id': senderId,
          'message_id': message.id.toHexString(),
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

  Future<void> _handleGroupMessage(
    Map<String, dynamic> data, {
    required String? authenticatedUserId,
  }) async {
    if (authenticatedUserId == null) return;

    try {
      final senderId = authenticatedUserId;
      final groupId = data['group_id'] as String;
      final group =
          await _groupService.getGroupById(ObjectId.fromHexString(groupId));
      if (group == null) return;
      if (!group.isMember(ObjectId.fromHexString(senderId))) return;

      final message = await _groupService.sendGroupMessage(
        groupId: group.id,
        senderId: ObjectId.fromHexString(senderId),
        messageType: data['message_type'] as String? ?? 'text',
        content: data['content'] as String? ?? '',
        filePath: data['file_url'] as String?,
        fileName: data['file_name'] as String?,
        fileSize: data['file_size'] as int?,
        mediaType: data['media_type'] as String?,
        encryption: data['encryption'] as String? ?? 'none',
        cipherType: data['cipher_type'] as int?,
        cipherBody: data['cipher_body'] as String?,
      );

      final messageData = message.toJson();
      for (final memberId in group.memberIds) {
        final memberStr = memberId.toHexString();
        if (memberStr == senderId) continue;
        _sendToUser(memberStr, {
          'type': 'group_message',
          'data': messageData,
        });
      }

      _sendToUser(senderId, {
        'type': 'message_sent',
        'data': messageData,
      });

      // Notify offline group members.
      final sender = await _userService.findUserById(
        ObjectId.fromHexString(senderId),
      );
      final senderName = sender?.displayName ?? 'Someone';
      final body = message.messageType == 'text'
          ? message.content
          : _messageTypeLabel(message.messageType);
      for (final memberId in group.memberIds) {
        final memberStr = memberId.toHexString();
        if (memberStr == senderId) continue;
        if (isUserConnected(memberStr)) continue;
        unawaited(_pushService.sendToUser(
          userId: memberId,
          title: senderName,
          body: body,
          data: {
            'group_id': group.id.toHexString(),
            'message_id': message.id.toHexString(),
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
    final groupId = data['group_id'] as String;
    final group =
        await _groupService.getGroupById(ObjectId.fromHexString(groupId));
    if (group == null) return;

    for (final memberId in group.memberIds) {
      final memberStr = memberId.toHexString();
      if (memberStr == authenticatedUserId) continue;
      _sendToUser(memberStr, {
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
    final receiverId = data['receiver_id'] as String;
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
    if (peerId == null) return;

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

    final senderId = data['sender_id'] as String;
    if (senderId == readerUserId) return;

    await _messageService.markMessagesAsRead(
      ObjectId.fromHexString(senderId),
      ObjectId.fromHexString(readerUserId),
    );

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
    if (senderId == null) return;

    await _messageService.updateMessageStatus(
      ObjectId.fromHexString(data['message_id'] as String),
      AppConfig.messageStatusDelivered,
    );

    _sendToUser(senderId, {
      'type': 'delivery_receipt',
      'receiver_id': receiverUserId,
    });
  }

  void _handleDisconnect(String connectionId) {
    final userId = _connectionUsers[connectionId];
    if (userId != null) {
      _userService.updateOnlineStatus(ObjectId.fromHexString(userId), false);
      _broadcastUserStatus(userId, false);
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

  void _broadcastUserStatus(String userId, bool isOnline) {
    final statusMessage = jsonEncode({
      'type': 'user_status',
      'user_id': userId,
      'is_online': isOnline,
    });

    for (final channel in _connections.values) {
      channel.sink.add(statusMessage);
    }
  }

  void broadcastMessage(Map<String, dynamic> message) {
    final encoded = jsonEncode(message);
    for (final channel in _connections.values) {
      channel.sink.add(encoded);
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
