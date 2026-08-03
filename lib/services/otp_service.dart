import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:mongo_dart/mongo_dart.dart';

import '../config/app_config.dart';
import '../models/otp_code_model.dart';
import 'database_service.dart';

class OtpService {
  final http.Client _client = http.Client();
  final DatabaseService _db = DatabaseService();

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
      'customerId': AppConfig.messageCentralCustomerId,
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
          'authToken': AppConfig.messageCentralApiKey,
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
      'customerId': AppConfig.messageCentralCustomerId,
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
          'authToken': AppConfig.messageCentralApiKey,
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
      final random = Random.secure();
      final code = List.generate(
        AppConfig.otpLength,
        (_) => random.nextInt(10),
      ).join();

      final otp = OtpCodeModel(
        id: ObjectId(),
        phone: mobileNumber,
        code: code,
        purpose: 'auth',
        expiresAt:
            DateTime.now().add(Duration(minutes: AppConfig.otpExpiryMinutes)),
        isUsed: false,
        createdAt: DateTime.now(),
      );

      await _db.otpCodes.insertOne(otp.toMap());

      return {
        'success': true,
        'correlationId': otp.id.toHexString(),
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
      final ObjectId otpId;
      try {
        otpId = ObjectId.fromHexString(correlationId);
      } catch (_) {
        return {
          'success': false,
          'verified': false,
          'error': 'Invalid correlation ID',
        };
      }

      final data = await _db.otpCodes.findOne({
        '_id': otpId,
        'phone': mobileNumber,
        'purpose': 'auth',
      });

      if (data == null) {
        return {
          'success': false,
          'verified': false,
          'error': 'OTP not found',
        };
      }

      final otp = OtpCodeModel.fromMap(data);

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

      if (otp.code != otpCode) {
        await _db.otpCodes.updateOne(
          where.eq('_id', otpId),
          modify.set('attempts', otp.attempts + 1),
        );
        return {
          'success': false,
          'verified': false,
          'error': 'Incorrect OTP',
        };
      }

      await _db.otpCodes.updateOne(
        where.eq('_id', otpId),
        modify.set('is_used', true),
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

  void dispose() {
    _client.close();
  }
}
