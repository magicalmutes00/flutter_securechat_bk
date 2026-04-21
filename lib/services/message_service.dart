import 'package:mongo_dart/mongo_dart.dart';
import '../models/message_model.dart';
import '../config/app_config.dart';
import 'database_service.dart';

class MessageService {
  final DatabaseService _db = DatabaseService();

  Future<MessageModel> sendMessage({
    required ObjectId senderId,
    required ObjectId receiverId,
    required String messageType,
    required String content,
    String? filePath,
    String? fileName,
    int? fileSize,
    String? mediaType,
  }) async {
    final now = DateTime.now();
    final message = MessageModel(
      id: ObjectId(),
      senderId: senderId,
      receiverId: receiverId,
      messageType: messageType,
      content: content,
      filePath: filePath,
      fileName: fileName,
      fileSize: fileSize,
      mediaType: mediaType,
      status: AppConfig.messageStatusSent,
      createdAt: now,
      updatedAt: now,
    );
    await _db.messages.insertOne(message.toMap());
    return message;
  }

  Future<List<MessageModel>> getMessages({
    required ObjectId userId1,
    required ObjectId userId2,
    int limit = 50,
    int skip = 0,
  }) async {
    final query = where
        .oneFrom('sender_id', [userId1, userId2])
        .oneFrom('receiver_id', [userId1, userId2])
        .sortBy('created_at', descending: true)
        .limit(limit)
        .skip(skip);
    final messages = await _db.messages.find(query).toList();
    return messages.map((m) => MessageModel.fromMap(m)).toList();
  }

  Future<MessageModel?> getMessageById(ObjectId id) async {
    final messageData = await _db.messages.findOne({'_id': id});
    if (messageData == null) return null;
    return MessageModel.fromMap(messageData);
  }

  Future<void> updateMessageStatus(ObjectId id, String status) async {
    await _db.messages.updateOne(
      where.eq('_id', id),
      modify.set('status', status).set('updated_at', DateTime.now()),
    );
  }

  Future<void> markMessagesAsRead(ObjectId senderId, ObjectId receiverId) async {
    await _db.messages.updateMany(
      where.eq('sender_id', senderId).eq('receiver_id', receiverId),
      modify.set('status', AppConfig.messageStatusRead),
    );
  }

  Future<void> deleteMessage(ObjectId id) async {
    await _db.messages.deleteOne(where.eq('_id', id));
  }

  /// Returns distinct conversation partners and their latest message for a user.
  Future<List<Map<String, dynamic>>> getConversations(ObjectId userId) async {
    final pipeline = [
      {
        '\$match': {
          '\$or': [
            {'sender_id': userId},
            {'receiver_id': userId},
          ]
        }
      },
      {'\$sort': {'created_at': -1}},
      {
        '\$group': {
          '_id': {
            '\$cond': [
              {'\$eq': ['\$sender_id', userId]},
              '\$receiver_id',
              '\$sender_id',
            ]
          },
          'last_message': {'\$first': '\$\$ROOT'},
          'unread_count': {
            '\$sum': {
              '\$cond': [
                {
                  '\$and': [
                    {'\$eq': ['\$receiver_id', userId]},
                    {'\$ne': ['\$status', AppConfig.messageStatusRead]},
                  ]
                },
                1,
                0,
              ]
            }
          }
        }
      },
    ];

    final result = await _db.messages.aggregateToStream(pipeline).toList();
    return result.cast<Map<String, dynamic>>();
  }
}