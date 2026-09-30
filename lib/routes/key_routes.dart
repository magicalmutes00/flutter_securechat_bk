import 'dart:convert';

import '../utils/validate.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../services/key_service.dart';
import '../utils/api_responses.dart';

class KeyRoutes {
  final KeyService _keyService = KeyService();

  Router get router => Router()
    ..put('/upload', _uploadBundle)
    ..post('/one-time-prekeys', _addOneTimePrekeys)
    ..get('/bundle/<userId>', _getBundle)
    ..get('/has-bundle', _hasBundle);

  Future<Response> _uploadBundle(Request request) async {
    try {
      final userId = request.context["userId"] as String?;
      if (userId == null) {
        return Response.unauthorized(
          jsonEncode({'error': 'Unauthorized'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final deviceId = data['device_id'] as String?;
      final registrationId = data['registration_id'] as int?;
      final identityKeyPublic = data['identity_key_public'] as String?;
      final signedPrekeyId = data['signed_prekey_id'] as int?;
      final signedPrekeyPublic = data['signed_prekey_public'] as String?;
      final signedPrekeySignature = data['signed_prekey_signature'] as String?;
      final oneTimePrekeys =
          (data['one_time_prekeys'] as List?)?.cast<String>() ?? [];

      if (deviceId == null ||
          identityKeyPublic == null ||
          signedPrekeyPublic == null ||
          signedPrekeySignature == null) {
        return Response(
          400,
          body: jsonEncode({'error': 'Incomplete key bundle'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      await _keyService.saveBundle(
        userId: userId,
        deviceId: deviceId,
        registrationId: registrationId ?? 0,
        identityKeyPublic: identityKeyPublic,
        signedPrekeyId: signedPrekeyId ?? 0,
        signedPrekeyPublic: signedPrekeyPublic,
        signedPrekeySignature: signedPrekeySignature,
        oneTimePrekeys: oneTimePrekeys,
      );

      return Response.ok(
        jsonEncode({'success': true}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return serverError('Failed to upload key bundle', e);
    }
  }

  Future<Response> _addOneTimePrekeys(Request request) async {
    try {
      final userId = request.context["userId"] as String?;
      if (userId == null) {
        return Response.unauthorized(
          jsonEncode({'error': 'Unauthorized'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final deviceId = data['device_id'] as String?;
      final oneTimePrekeys =
          (data['one_time_prekeys'] as List?)?.cast<String>() ?? [];

      if (deviceId == null || oneTimePrekeys.isEmpty) {
        return Response(
          400,
          body: jsonEncode(
              {'error': 'Device ID and one-time prekeys are required'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      await _keyService.addOneTimePrekeys(
        userId: userId,
        deviceId: deviceId,
        oneTimePrekeys: oneTimePrekeys,
      );

      return Response.ok(
        jsonEncode({'success': true}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return serverError('Failed to add one-time prekeys', e);
    }
  }

  Future<Response> _getBundle(Request request, String userId) async {
    try {
      final requesterId = request.context['userId'];
      if (requesterId == null) {
        return Response.unauthorized(
          jsonEncode({'error': 'Unauthorized'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      if (!isValidUuid(userId)) {
        return Response(
          400,
          body: jsonEncode({'error': 'Invalid user ID format'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final bundle = await _keyService.getBundle(userId: userId);
      if (bundle == null) {
        return Response.notFound(
          jsonEncode({'error': 'No key bundle for user'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      return Response.ok(
        jsonEncode(bundle),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return serverError('Failed to fetch key bundle', e);
    }
  }

  Future<Response> _hasBundle(Request request) async {
    try {
      final userId = request.context["userId"] as String?;
      if (userId == null) {
        return Response.unauthorized(
          jsonEncode({'error': 'Unauthorized'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final deviceId = request.url.queryParameters['device_id'] ?? '';
      final has = await _keyService.hasBundle(userId, deviceId);
      final count =
          await _keyService.remainingOneTimePrekeys(userId, deviceId);

      return Response.ok(
        jsonEncode({'has_bundle': has, 'one_time_prekey_count': count}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return serverError('Failed to check key bundle', e);
    }
  }
}
