/// Group chat message model backed by the Supabase `group_messages` table.
///
/// Group messages are stored once per group (sender_id + group_id), unlike 1:1
/// messages which are stored per sender/receiver pair.
class GroupMessageModel {
  final String id; // UUID
  final String groupId;
  final String senderId;
  final String messageType;
  final String content;
  final String? filePath;
  final String? fileName;
  final int? fileSize;
  final String? mediaType;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Reply target: id of the quoted group message. Stored as an id only —
  // never a quoted-text snapshot — so the server learns nothing about
  // encrypted message content.
  final String? replyToId;

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
    this.replyToId,
    this.encryption = 'none',
    this.cipherType,
    this.cipherBody,
  });

  factory GroupMessageModel.fromMap(Map<String, dynamic> map) {
    return GroupMessageModel(
      id: map['id'] as String,
      groupId: map['group_id'] as String,
      senderId: map['sender_id'] as String,
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
      'group_id': groupId,
      'sender_id': senderId,
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

  GroupMessageModel copyWith({
    String? id,
    String? groupId,
    String? senderId,
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
      replyToId: replyToId ?? this.replyToId,
      encryption: encryption ?? this.encryption,
      cipherType: cipherType ?? this.cipherType,
      cipherBody: cipherBody ?? this.cipherBody,
    );
  }
}
