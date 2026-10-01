import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';

/// Logs [error] server-side and returns a generic 500 response that never
/// leaks exception details to the client. The machine-readable [code] and
/// [requestId] travel in the body so the client can show an actionable
/// message and the log line can be found from a screenshot.
Response serverError(
  String context,
  Object error, {
  StackTrace? stackTrace,
  String? requestId,
  String code = 'internal_error',
}) {
  final id = requestId ?? 'unknown';
  stderr.writeln('$context [request $id]: $error');
  if (stackTrace != null) stderr.writeln(stackTrace);
  return Response(
    500,
    body: jsonEncode(
        {'error': 'Internal server error', 'code': code, 'request_id': id}),
    headers: {'Content-Type': 'application/json'},
  );
}

/// Coded client error (4xx): user-facing [message] plus the machine-readable
/// [code] the mobile app maps to its own wording, and the [requestId] that
/// ties this response to its server log line.
Response clientError(
  int statusCode, {
  required String message,
  required String code,
  required String requestId,
}) {
  return Response(
    statusCode,
    body: jsonEncode({
      'success': false,
      'message': message,
      'code': code,
      'request_id': requestId,
    }),
    headers: {'Content-Type': 'application/json'},
  );
}
