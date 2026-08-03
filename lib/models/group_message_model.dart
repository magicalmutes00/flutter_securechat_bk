import 'package:mongo_dart/mongo_dart.dart';

/// Group chat message model stored in the `group_messages` collection.
///
/// Group messages are stored once per group (sender_id + group_id), unlike 1:1
/// messages which are stored per sender/receiver pair.
class GroupMessageModel {
  final ObjectId id;
  final ObjectId groupId;
  final ObjectId senderId;
  final String messageType;
  final String content;
  final String? filePath;
  final String? fileName;
  final int? fileSize;
  final String? mediaType;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  // E2EE: opaque sender-key ciphertext fields relayed verbatim by the server.
  final String encryption;
  final int? cipherType;
  final String? cipherBody;

  GroupMessageModel({
    required this.id,
    required this.groupId,
    required this.senderId,
    required this.messageType,
    required this.content,
    this.filePath,
    this.fileName,
    this.fileSize,
    this.mediaType,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.encryption = 'none',
    this.cipherType,
    this.cipherBody,
  });

  factory GroupMessageModel.fromMap(Map<String, dynamic> map) {
    return GroupMessageModel(
      id: map['_id'] as ObjectId,
      groupId: map['group_id'] as ObjectId,
      senderId: map['sender_id'] as ObjectId,
      messageType: map['message_type'] as String,
      content: map['content'] as String? ?? '',
      filePath: map['file_path'] as String?,
      fileName: map['file_name'] as String?,
      fileSize: map['file_size'] as int?,
      mediaType: map['media_type'] as String?,
      status: map['status'] as String,
      createdAt: map['created_at'] as DateTime,
      updatedAt: map['updated_at'] as DateTime,
      encryption: map['encryption'] as String? ?? 'none',
      cipherType: map['cipher_type'] as int?,
      cipherBody: map['cipher_body'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      '_id': id,
      'group_id': groupId,
      'sender_id': senderId,
      'message_type': messageType,
      'content': content,
      'file_path': filePath,
      'file_name': fileName,
      'file_size': fileSize,
      'media_type': mediaType,
      'status': status,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'encryption': encryption,
      'cipher_type': cipherType,
      'cipher_body': cipherBody,
    };
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id.toHexString(),
      'group_id': groupId.toHexString(),
      'sender_id': senderId.toHexString(),
      'message_type': messageType,
      'content': content,
      'file_path': filePath,
      'file_name': fileName,
      'file_size': fileSize,
      'media_type': mediaType,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'encryption': encryption,
      'cipher_type': cipherType,
      'cipher_body': cipherBody,
    };
  }

  GroupMessageModel copyWith({
    ObjectId? id,
    ObjectId? groupId,
    ObjectId? senderId,
    String? messageType,
    String? content,
    String? filePath,
    String? fileName,
    int? fileSize,
    String? mediaType,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? encryption,
    int? cipherType,
    String? cipherBody,
  }) {
    return GroupMessageModel(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      senderId: senderId ?? this.senderId,
      messageType: messageType ?? this.messageType,
      content: content ?? this.content,
      filePath: filePath ?? this.filePath,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      mediaType: mediaType ?? this.mediaType,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      encryption: encryption ?? this.encryption,
      cipherType: cipherType ?? this.cipherType,
      cipherBody: cipherBody ?? this.cipherBody,
    );
  }
}
