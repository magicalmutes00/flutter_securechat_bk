import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

class OtpService {
  final http.Client _client = http.Client();

  Future<Map<String, dynamic>> sendOtp({
    required String mobileNumber,
    required int countryCode,
    String? message,
    String? flowType,
  }) async {
    final queryParams = {
      'countryCode': countryCode.toString(),
      'customerId': AppConfig.messageCentralCustomerId,
      'senderId': 'UTOMOB',
      'type': 'SMS',
      'flowType': flowType ?? 'SMS',
      'mobileNumber': mobileNumber,
      'message': message ?? 'Your SecureChat verification code is: {{OTP}}. Valid for 5 minutes.',
    };

    final uri = Uri.parse('${AppConfig.messageCentralBaseUrl}/verification/v3/send')
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
          'correlationId': body['correlationId'] ?? body['data']?['correlationId'],
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
    final queryParams = {
      'countryCode': countryCode.toString(),
      'customerId': AppConfig.messageCentralCustomerId,
      'type': 'SMS',
      'mobileNumber': mobileNumber,
      'otpCode': otpCode,
      'correlationId': correlationId,
    };

    final uri = Uri.parse('${AppConfig.messageCentralBaseUrl}/verification/v3/verify')
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

  void dispose() {
    _client.close();
  }
}
