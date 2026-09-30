import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/otp_code_model.dart';
import 'database_service.dart';

class OtpService {
  final http.Client _client = http.Client();
  final DatabaseService _db = DatabaseService();

  final Random _random = Random.secure();

  Future<Map<String, dynamic>> sendOtp({
    required String mobileNumber,
    required int countryCode,
    String? message,
    String? flowType,
  }) async {
    // Dev mode: generate and store the OTP locally so the app is testable
    // without MessageCentral SMS credits. The code is returned to the caller.
    if (AppConfig.otpDevMode) {
      return _sendLocalOtp(mobileNumber);
    }

    final queryParams = {
      'countryCode': countryCode.toString(),
      'customerId': AppConfig.messageCentralCustomerId ?? '',
      'senderId': 'UTOMOB',
      'type': 'SMS',
      'flowType': flowType ?? 'SMS',
      'mobileNumber': mobileNumber,
      'message': message ??
          'Your SecureChat verification code is: {{OTP}}. Valid for 5 minutes.',
    };

    final uri =
        Uri.parse('${AppConfig.messageCentralBaseUrl}/verification/v3/send')
            .replace(queryParameters: queryParams);

    try {
      final response = await _client.post(
        uri,
        headers: {
          'authToken': AppConfig.messageCentralApiKey ?? '',
          'Content-Type': 'application/json',
        },
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && body['status'] == 'success') {
        return {
          'success': true,
          'correlationId':
              body['correlationId'] ?? body['data']?['correlationId'],
          'message': body['message'] ?? 'OTP sent successfully',
        };
      } else {
        return {
          'success': false,
          'error': body['message'] ?? 'Failed to send OTP',
          'statusCode': response.statusCode,
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to send OTP: $e',
      };
    }
  }

  Future<Map<String, dynamic>> verifyOtp({
    required String mobileNumber,
    required int countryCode,
    required String otpCode,
    required String correlationId,
  }) async {
    if (AppConfig.otpDevMode) {
      return _verifyLocalOtp(
        mobileNumber: mobileNumber,
        otpCode: otpCode,
        correlationId: correlationId,
      );
    }

    final queryParams = {
      'countryCode': countryCode.toString(),
      'customerId': AppConfig.messageCentralCustomerId ?? '',
      'type': 'SMS',
      'mobileNumber': mobileNumber,
      'otpCode': otpCode,
      'correlationId': correlationId,
    };

    final uri =
        Uri.parse('${AppConfig.messageCentralBaseUrl}/verification/v3/verify')
            .replace(queryParameters: queryParams);

    try {
      final response = await _client.post(
        uri,
        headers: {
          'authToken': AppConfig.messageCentralApiKey ?? '',
          'Content-Type': 'application/json',
        },
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && body['status'] == 'success') {
        return {
          'success': true,
          'verified': true,
          'message': body['message'] ?? 'OTP verified successfully',
        };
      } else {
        return {
          'success': false,
          'verified': false,
          'error': body['message'] ?? 'OTP verification failed',
          'statusCode': response.statusCode,
        };
      }
    } catch (e) {
      return {
        'success': false,
        'verified': false,
        'error': 'Failed to verify OTP: $e',
      };
    }
  }

  Future<Map<String, dynamic>> _sendLocalOtp(String mobileNumber) async {
    try {
      final code = List.generate(
        AppConfig.otpLength,
        (_) => _random.nextInt(10),
      ).join();

      // Store only a salted hash of the code — a database dump must not be
      // replayable against the verification endpoint.
      final salt = base64Url
          .encode(List<int>.generate(16, (_) => _random.nextInt(256)))
          .replaceAll('=', '');
      final codeHash = _hashCode(salt, code);

      final expiresAt = DateTime.now()
          .toUtc()
          .add(Duration(minutes: AppConfig.otpExpiryMinutes));
      final row = await _db.queryOne(
        '''
        INSERT INTO otp_codes (phone, code_hash, salt, purpose, expires_at)
        VALUES (@phone, @code_hash, @salt, 'auth', @expires_at:timestamptz)
        RETURNING id
        ''',
        parameters: {
          'phone': mobileNumber,
          'code_hash': codeHash,
          'salt': salt,
          'expires_at': expiresAt,
        },
      );

      return {
        'success': true,
        'correlationId': row!['id'] as String,
        'message': 'OTP sent successfully',
        // Exposed only in dev mode so the client can autofill it.
        'dev_code': code,
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to send OTP: $e',
      };
    }
  }

  Future<Map<String, dynamic>> _verifyLocalOtp({
    required String mobileNumber,
    required String otpCode,
    required String correlationId,
  }) async {
    try {
      final row = await _db.queryOne(
        '''
        SELECT * FROM otp_codes
        WHERE id = @id:uuid AND phone = @phone AND purpose = 'auth'
        ''',
        parameters: {'id': correlationId, 'phone': mobileNumber},
      );

      if (row == null) {
        return {
          'success': false,
          'verified': false,
          'error': 'OTP not found',
        };
      }

      final otp = OtpCodeModel.fromMap(row);

      if (otp.isUsed) {
        return {
          'success': false,
          'verified': false,
          'error': 'OTP has already been used',
        };
      }

      if (otp.isExpired) {
        return {
          'success': false,
          'verified': false,
          'error': 'OTP has expired',
        };
      }

      if (otp.attempts >= AppConfig.otpMaxAttempts) {
        return {
          'success': false,
          'verified': false,
          'error': 'Too many incorrect attempts',
        };
      }

      if (_hashCode(otp.salt, otpCode) != otp.codeHash) {
        await _db.execute(
          'UPDATE otp_codes SET attempts = attempts + 1 WHERE id = @id:uuid',
          parameters: {'id': otp.id},
        );
        return {
          'success': false,
          'verified': false,
          'error': 'Incorrect OTP',
        };
      }

      await _db.execute(
        'UPDATE otp_codes SET is_used = TRUE WHERE id = @id:uuid',
        parameters: {'id': otp.id},
      );

      return {
        'success': true,
        'verified': true,
        'message': 'OTP verified successfully',
      };
    } catch (e) {
      return {
        'success': false,
        'verified': false,
        'error': 'Failed to verify OTP: $e',
      };
    }
  }

  static String _hashCode(String salt, String code) {
    return crypto.sha256.convert(utf8.encode('$salt$code')).toString();
  }

  void dispose() {
    _client.close();
  }
}
