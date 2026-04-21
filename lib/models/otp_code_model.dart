import 'package:mongo_dart/mongo_dart.dart';

class OtpCodeModel {
  final ObjectId id;
  final String phone;
  final String code;
  final String purpose;
  final DateTime expiresAt;
  final bool isUsed;
  final DateTime createdAt;
  final int attempts;

  OtpCodeModel({
    required this.id,
    required this.phone,
    required this.code,
    required this.purpose,
    required this.expiresAt,
    required this.isUsed,
    required this.createdAt,
    this.attempts = 0,
  });

  factory OtpCodeModel.fromMap(Map<String, dynamic> map) {
    return OtpCodeModel(
      id: map['_id'] as ObjectId,
      phone: map['phone'] as String,
      code: map['code'] as String,
      purpose: map['purpose'] as String,
      expiresAt: map['expires_at'] as DateTime,
      isUsed: map['is_used'] as bool,
      createdAt: map['created_at'] as DateTime,
      attempts: map['attempts'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      '_id': id,
      'phone': phone,
      'code': code,
      'purpose': purpose,
      'expires_at': expiresAt,
      'is_used': isUsed,
      'created_at': createdAt,
      'attempts': attempts,
    };
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id.toHexString(),
      'phone': phone,
      'code': code,
      'purpose': purpose,
      'expires_at': expiresAt.toIso8601String(),
      'is_used': isUsed,
      'created_at': createdAt.toIso8601String(),
      'attempts': attempts,
    };
  }

  Map<String, dynamic> toJsonForClient() {
    return {
      'id': id.toHexString(),
      'phone': phone,
      'purpose': purpose,
      'expires_at': expiresAt.toIso8601String(),
      'is_used': isUsed,
      'created_at': createdAt.toIso8601String(),
      'attempts': attempts,
    };
  }

  OtpCodeModel copyWith({
    ObjectId? id,
    String? phone,
    String? code,
    String? purpose,
    DateTime? expiresAt,
    bool? isUsed,
    DateTime? createdAt,
    int? attempts,
  }) {
    return OtpCodeModel(
      id: id ?? this.id,
      phone: phone ?? this.phone,
      code: code ?? this.code,
      purpose: purpose ?? this.purpose,
      expiresAt: expiresAt ?? this.expiresAt,
      isUsed: isUsed ?? this.isUsed,
      createdAt: createdAt ?? this.createdAt,
      attempts: attempts ?? this.attempts,
    );
  }

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
