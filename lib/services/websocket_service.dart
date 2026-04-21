import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:mongo_dart/mongo_dart.dart';
import '../config/app_config.dart';
import 'message_service.dart';
import 'user_service.dart';

class WebSocketService {
  final Map<String, WebSocketChannel> _connections = {};
  final Map<String, String> _connectionUsers = {};
  final Map<String, bool> _connectionAuthenticated = {};
  final MessageService _messageService = MessageService();
  final UserService _userService = UserService();

  void handleConnection(WebSocketChannel channel, String userId) {
    final connectionId = DateTime.now().millisecondsSinceEpoch.toString();
    _connections[connectionId] = channel;
    _connectionUsers[connectionId] = userId;
    _connectionAuthenticated[connectionId] = true; // Auth already verified in main.dart via token

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
        _sendToConnection(connectionId, {'type': 'error', 'message': 'Not authenticated'});
        return;
      }
    }

    try {
      final data = jsonDecode(message as String) as Map<String, dynamic>;
      final type = data['type'] as String?;

      switch (type) {
        case 'message':
          _handleChatMessage(data);
          break;
        case 'typing':
          _handleTyping(data);
          break;
        case 'read':
          _handleReadReceipt(data);
          break;
        case 'delivered':
          _handleDeliveryReceipt(data);
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

  Future<void> _handleChatMessage(Map<String, dynamic> data) async {
    try {
      final senderId = data['sender_id'] as String;
      final receiverId = data['receiver_id'] as String;
      final messageType = data['message_type'] as String? ?? 'text';
      final content = data['content'] as String? ?? '';
      final fileUrl = data['file_url'] as String?;
      final fileName = data['file_name'] as String?;
      final fileSize = data['file_size'] as int?;
      final mediaType = data['media_type'] as String?;

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

      final messageData = message.toJson();
      _sendToUser(receiverId, {
        'type': 'message',
        'data': messageData,
      });

      _sendToUser(senderId, {
        'type': 'message_sent',
        'data': messageData,
      });
    } catch (e) {
      print('Error handling chat message: $e');
    }
  }

  void _handleTyping(Map<String, dynamic> data) {
    final receiverId = data['receiver_id'] as String;
    final senderId = data['sender_id'] as String;
    _sendToUser(receiverId, {
      'type': 'typing',
      'sender_id': senderId,
      'is_typing': data['is_typing'] ?? true,
    });
  }

  Future<void> _handleReadReceipt(Map<String, dynamic> data) async {
    final senderId = data['sender_id'] as String;
    final receiverId = data['receiver_id'] as String;

    await _messageService.markMessagesAsRead(
      ObjectId.fromHexString(senderId),
      ObjectId.fromHexString(receiverId),
    );

    _sendToUser(senderId, {
      'type': 'read_receipt',
      'receiver_id': receiverId,
    });
  }

  Future<void> _handleDeliveryReceipt(Map<String, dynamic> data) async {
    final senderId = data['sender_id'] as String;
    final receiverId = data['receiver_id'] as String;

    await _messageService.updateMessageStatus(
      ObjectId.fromHexString(data['message_id'] as String),
      AppConfig.messageStatusDelivered,
    );

    _sendToUser(senderId, {
      'type': 'delivery_receipt',
      'receiver_id': receiverId,
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
