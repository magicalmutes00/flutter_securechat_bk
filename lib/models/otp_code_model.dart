/// A single-use verification code for the legacy OTP flow.
///
/// Codes are never stored in plaintext: [codeHash] is SHA-256 of
/// `salt + code` with a per-code random [salt], so a database dump cannot be
/// replayed against the verification endpoint.
class OtpCodeModel {
  final String id; // UUID
  final String phone;
  final String codeHash;
  final String salt;
  final String purpose;
  final DateTime expiresAt;
  final bool isUsed;
  final DateTime createdAt;
  final int attempts;

  OtpCodeModel({
    required this.id,
    required this.phone,
    required this.codeHash,
    required this.salt,
    required this.purpose,
    required this.expiresAt,
    required this.isUsed,
    required this.createdAt,
    this.attempts = 0,
  });

  factory OtpCodeModel.fromMap(Map<String, dynamic> map) {
    return OtpCodeModel(
      id: map['id'] as String,
      phone: map['phone'] as String,
      codeHash: map['code_hash'] as String,
      salt: map['salt'] as String,
      purpose: map['purpose'] as String,
      expiresAt: (map['expires_at'] as DateTime).toUtc(),
      isUsed: map['is_used'] as bool,
      createdAt: (map['created_at'] as DateTime).toUtc(),
      attempts: (map['attempts'] as int?) ?? 0,
    );
  }

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt);
}
