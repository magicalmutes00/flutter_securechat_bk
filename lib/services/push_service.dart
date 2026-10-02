import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'database_service.dart';

/// Device push token registry and Firebase Cloud Messaging dispatcher.
///
/// Tokens are registered by authenticated clients via `/api/push/`. When an
/// offline user receives a message the server dispatches a notification
/// through FCM. If FCM credentials are not configured the service silently
/// no-ops so the server still works without push infrastructure.
class PushService {
  final DatabaseService _db = DatabaseService();

  // ---------------------------------------------------------------------------
  // Token registry
  // ---------------------------------------------------------------------------

  Future<void> registerToken({
    required String userId,
    required String token,
    String platform = 'android',
  }) async {
    if (token.trim().isEmpty) return;

    await _db.execute(
      '''
      INSERT INTO push_tokens (token, user_id, platform, updated_at)
      VALUES (@token, @user_id:uuid, @platform, now())
      ON CONFLICT (token) DO UPDATE SET
        user_id = EXCLUDED.user_id,
        platform = EXCLUDED.platform,
        updated_at = now()
      ''',
      parameters: {
        'token': token,
        'user_id': userId,
        'platform': platform,
      },
    );
  }

  Future<void> unregisterToken(
      {required String userId, required String token}) async {
    await _db.execute(
      'DELETE FROM push_tokens WHERE token = @token AND user_id = @user_id:uuid',
      parameters: {'token': token, 'user_id': userId},
    );
  }

  /// All FCM tokens belonging to [userId].
  Future<List<String>> tokensForUser(String userId) async {
    final rows = await _db.query(
      'SELECT token FROM push_tokens WHERE user_id = @user_id:uuid',
      parameters: {'user_id': userId},
    );
    return rows.map((r) => r['token'] as String).toList();
  }

  /// Removes a token that FCM reported as invalid (expired/unregistered).
  Future<void> removeInvalidToken(String token) async {
    await _db.execute(
      'DELETE FROM push_tokens WHERE token = @token',
      parameters: {'token': token},
    );
  }

  // ---------------------------------------------------------------------------
  // Dispatch
  // ---------------------------------------------------------------------------

  /// Sends a push notification to every device token registered to [userId].
  /// Returns false when FCM is not configured or the user has no tokens.
  Future<bool> sendToUser({
    required String userId,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    final tokens = await tokensForUser(userId);
    if (tokens.isEmpty) return false;

    var sent = false;
    for (final token in tokens) {
      if (await _send(token, title: title, body: body, data: data)) {
        sent = true;
      }
    }
    return sent;
  }

  Future<bool> _send(
    String token, {
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    final serverKey = AppConfig.fcmServerKey;
    if (serverKey == null || serverKey.isEmpty) return false;

    final payload = {
      'to': token,
      'notification': {'title': title, 'body': body},
      'data': {
        'click_action': 'FLUTTER_NOTIFICATION_CLICK',
        ...?data,
      },
      // Wakes iOS in the background so the Dart background handler runs;
      // ignored on Android.
      'content_available': true,
      'priority': 'high',
    };

    try {
      final response = await http.post(
        Uri.parse(AppConfig.fcmEndpoint),
        headers: {
          'Authorization': 'key=$serverKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );

      if (response.statusCode != 200) {
        return false;
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      // {"message_id": "..."} on success; otherwise an error code.
      if (decoded.containsKey('message_id')) {
        return true;
      }

      final results = decoded['results'] as List? ?? const [];
      final error = results.isNotEmpty ? results.first : null;
      if (error is Map && error['error'] != null) {
        // Registration token not valid anymore -> drop it.
        if (error['error'] == 'InvalidRegistration' ||
            error['error'] == 'NotRegistered') {
          await removeInvalidToken(token);
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
