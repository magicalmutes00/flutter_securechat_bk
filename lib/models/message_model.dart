/// Message model backed by the Supabase `messages` table.
class MessageModel {
  final String id; // UUID
  final String senderId;
  final String receiverId;
  final String messageType;
  final String content;
  final String? filePath;
  final String? fileName;
  final int? fileSize;
  final String? mediaType;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Reply target: id of the quoted message in the same conversation.
  // Nullable; null when the reply has no target or the target was deleted.
  // Only the id is stored — never a quoted-text snapshot — so the server
  // learns nothing about encrypted message content.
  final String? replyToId;

  // E2EE: for encrypted messages the server relays these opaque fields and
  // never reads/parses the ciphertext. `content` stays empty.
  final String encryption;
  final int? cipherType;
  final String? cipherBody;

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
    this.replyToId,
    this.encryption = 'none',
    this.cipherType,
    this.cipherBody,
  });

  factory MessageModel.fromMap(Map<String, dynamic> map) {
    return MessageModel(
      id: map['id'] as String,
      senderId: map['sender_id'] as String,
      receiverId: map['receiver_id'] as String,
      messageType: map['message_type'] as String,
      content: map['content'] as String? ?? '',
      filePath: map['file_path'] as String?,
      fileName: map['file_name'] as String?,
      fileSize: (map['file_size'] as num?)?.toInt(),
      mediaType: map['media_type'] as String?,
      status: map['status'] as String,
      createdAt: (map['created_at'] as DateTime).toUtc(),
      updatedAt: (map['updated_at'] as DateTime).toUtc(),
      replyToId: map['reply_to_id'] as String?,
      encryption: map['encryption'] as String? ?? 'none',
      cipherType: (map['cipher_type'] as num?)?.toInt(),
      cipherBody: map['cipher_body'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'message_type': messageType,
      'content': content,
      'file_path': filePath,
      'file_name': fileName,
      'file_size': fileSize,
      'media_type': mediaType,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'reply_to_id': replyToId,
      'encryption': encryption,
      'cipher_type': cipherType,
      'cipher_body': cipherBody,
    };
  }

  MessageModel copyWith({
    String? id,
    String? senderId,
    String? receiverId,
    String? messageType,
    String? content,
    String? filePath,
    String? fileName,
    int? fileSize,
    String? mediaType,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? replyToId,
    String? encryption,
    int? cipherType,
    String? cipherBody,
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
      replyToId: replyToId ?? this.replyToId,
      encryption: encryption ?? this.encryption,
      cipherType: cipherType ?? this.cipherType,
      cipherBody: cipherBody ?? this.cipherBody,
    );
  }
}
