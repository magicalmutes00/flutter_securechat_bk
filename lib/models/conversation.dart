import 'package:mongo_dart/mongo_dart.dart';

/// One document per (au, peer). Stable identity, per-user unread counter,
/// per-user last_read_at used to render unread badges after app restarts.
class Conversation {
  final ObjectId id;
  final List<ObjectId> participants;
  final ObjectId createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Map of userId-hex -> last read timestamp for that user.
  final Map<String, DateTime> lastReadAt;

  /// Map of userId-hex -> count of messages not yet read.
  final Map<String, int> unreadCount;

  /// Last message snapshot for fast list rendering.
  final ObjectId? lastMessageId;
  final DateTime? lastMessageAt;

  Conversation({
    required this.id,
    required this.participants,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    Map<String, DateTime>? lastReadAt,
    Map<String, int>? unreadCount,
    this.lastMessageId,
    this.lastMessageAt,
  })  : lastReadAt = lastReadAt ?? <String, DateTime>{},
        unreadCount = unreadCount ?? <String, int>{};

  factory Conversation.fromMap(Map<String, dynamic> map) {
    final rawParticipants = (map['participants'] as List?) ?? const [];
    final parts = rawParticipants
        .whereType<ObjectId>()
        .toSet()
        .toList(growable: false);

    DateTime? parseDate(Object? v) =>
        v == null ? null : (v is DateTime ? v : DateTime.parse(v.toString()));

    final lr = <String, DateTime>{};
    final rawLr = (map['last_read_at'] as Map?) ?? const {};
    for (final entry in rawLr.entries) {
      final v = parseDate(entry.value);
      if (v != null) lr[entry.key.toString()] = v;
    }

    final ur = <String, int>{};
    final rawUr = (map['unread_count'] as Map?) ?? const {};
    for (final entry in rawUr.entries) {
      final v = entry.value;
      if (v is int) {
        ur[entry.key.toString()] = v;
      } else if (v != null) {
        ur[entry.key.toString()] = int.tryParse(v.toString()) ?? 0;
      }
    }

    return Conversation(
      id: map['_id'] as ObjectId,
      participants: parts,
      createdBy: map['created_by'] as ObjectId,
      createdAt: parseDate(map['created_at']) ?? DateTime.now(),
      updatedAt: parseDate(map['updated_at']) ?? DateTime.now(),
      lastReadAt: lr,
      unreadCount: ur,
      lastMessageId: map['last_message_id'] as ObjectId?,
      lastMessageAt: parseDate(map['last_message_at']),
    );
  }

  Map<String, dynamic> toMap() => {
        '_id': id,
        'participants': participants,
        'created_by': createdBy,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'last_read_at': lastReadAt,
        'unread_count': unreadCount,
        if (lastMessageId != null) 'last_message_id': lastMessageId,
        if (lastMessageAt != null) 'last_message_at': lastMessageAt,
      };

  ObjectId other(ObjectId self) {
    if (participants.length != 2) {
      throw StateError('Conversation does not have exactly two participants');
    }
    return participants.firstWhere((p) => p != self,
        orElse: () => throw StateError('Self not found in conversation'));
  }
}
