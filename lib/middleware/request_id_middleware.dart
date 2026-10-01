import 'package:shelf/shelf.dart';
import 'package:uuid/uuid.dart';

/// Assigns every request an id: honors an incoming `X-Request-Id`, otherwise
/// mints a short one. The id is echoed on the response and readable via
/// [requestIdOf], so a client-side error `code` maps to an exact stderr line
/// in the server logs.
Middleware requestIdMiddleware() {
  const uuid = Uuid();
  return (Handler innerHandler) {
    return (Request request) async {
      final incoming = request.headers['x-request-id']?.trim();
      final requestId = (incoming != null && incoming.isNotEmpty)
          ? incoming
          : uuid.v4().substring(0, 8);
      final response = await innerHandler(
        request.change(context: {'requestId': requestId}),
      );
      return response.change(headers: {'X-Request-Id': requestId});
    };
  };
}

/// Request id assigned by [requestIdMiddleware], or 'unknown' outside it.
String requestIdOf(Request request) =>
    request.context['requestId'] as String? ?? 'unknown';
