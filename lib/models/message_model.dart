import 'package:mongo_dart/mongo_dart.dart';

/// Message model for MongoDB
/// Represents a chat message in SecureChat
class MessageModel {
  final ObjectId id;
  final ObjectId senderId;
  final ObjectId receiverId;
  final String messageType;
  final String content;
  final String? filePath;
  final String? fileName;
  final int? fileSize;
  final String? mediaType;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  MessageModel({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.messageType,
    required this.content,
    this.filePath,
    this.fileName,
    this.fileSize,
    this.mediaType,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory MessageModel.fromMap(Map<String, dynamic> map) {
    return MessageModel(
      id: map['_id'] as ObjectId,
      senderId: map['sender_id'] as ObjectId,
      receiverId: map['receiver_id'] as ObjectId,
      messageType: map['message_type'] as String,
      content: map['content'] as String,
      filePath: map['file_path'] as String?,
      fileName: map['file_name'] as String?,
      fileSize: map['file_size'] as int?,
      mediaType: map['media_type'] as String?,
      status: map['status'] as String,
      createdAt: map['created_at'] as DateTime,
      updatedAt: map['updated_at'] as DateTime,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      '_id': id,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'message_type': messageType,
      'content': content,
      'file_path': filePath,
      'file_name': fileName,
      'file_size': fileSize,
      'media_type': mediaType,
      'status': status,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id.toHexString(),
      'sender_id': senderId.toHexString(),
      'receiver_id': receiverId.toHexString(),
      'message_type': messageType,
      'content': content,
      'file_path': filePath,
      'file_name': fileName,
      'file_size': fileSize,
      'media_type': mediaType,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  MessageModel copyWith({
    ObjectId? id,
    ObjectId? senderId,
    ObjectId? receiverId,
    String? messageType,
    String? content,
    String? filePath,
    String? fileName,
    int? fileSize,
    String? mediaType,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return MessageModel(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      messageType: messageType ?? this.messageType,
      content: content ?? this.content,
      filePath: filePath ?? this.filePath,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      mediaType: mediaType ?? this.mediaType,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
