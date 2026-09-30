import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../config/app_config.dart';

/// Serves WebRTC connection parameters to authenticated clients so ICE
/// negotiation (STUN/TURN) is configured in one place — on the server.
class RtcRoutes {
  Router get router => Router()
    ..get('/config', _getConfig);

  Future<Response> _getConfig(Request request) async {
    final iceServers = <Map<String, dynamic>>[
      {'urls': AppConfig.stunServers},
    ];

    final turnUrl = AppConfig.turnServerUrl;
    if (turnUrl != null && turnUrl.isNotEmpty) {
      iceServers.add({
        'urls': turnUrl,
        'username': AppConfig.turnUsername,
        'credential': AppConfig.turnCredential,
      });
    }

    return Response.ok(
      jsonEncode({'ice_servers': iceServers}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
