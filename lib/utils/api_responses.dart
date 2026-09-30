import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';

/// Logs [error] server-side and returns a generic 500 response that never
/// leaks exception details to the client.
Response serverError(String context, Object error, [StackTrace? stackTrace]) {
  stderr.writeln('$context: $error');
  if (stackTrace != null) stderr.writeln(stackTrace);
  return Response(
    500,
    body: jsonEncode({'error': 'Internal server error'}),
    headers: {'Content-Type': 'application/json'},
  );
}
