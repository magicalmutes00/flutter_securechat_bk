import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'config/app_config.dart';
import 'config/env_config.dart';
import 'services/database_service.dart';
import 'services/websocket_service.dart';
import 'services/jwt_service.dart';
import 'routes/auth_routes.dart';
import 'routes/chat_routes.dart';
import 'routes/file_routes.dart';
import 'middleware/auth_middleware.dart';

void main() async {
  await EnvConfig.load();

  await DatabaseService().initialize();
  print('Database initialized');

  final websocketService = WebSocketService();

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_corsMiddleware())
      .addHandler(_router(websocketService));

  final server = await shelf_io.serve(
    handler,
    AppConfig.serverHost,
    AppConfig.serverPort,
  );

  print('Server running on ws://${server.address.host}:${server.port}');
}

Middleware _corsMiddleware() {
  final allowedOrigins = AppConfig.corsAllowedOrigins;

  Map<String, String> buildCorsHeaders(String? origin) {
    final isAllowed = origin != null && allowedOrigins.contains(origin);
    return {
      'Access-Control-Allow-Origin': isAllowed ? origin : (allowedOrigins.isNotEmpty ? allowedOrigins.first : '*'),
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Origin, Content-Type, Authorization, Accept',
    };
  }

  return (Handler innerHandler) {
    return (Request request) async {
      if (request.method == 'OPTIONS') {
        return Response.ok('', headers: buildCorsHeaders(request.headers['origin']));
      }

      final response = await innerHandler(request);
      return response.change(headers: buildCorsHeaders(request.headers['origin']));
    };
  };
}

Handler _router(WebSocketService websocketService) {
  final authRoutes = AuthRoutes();
  final chatRoutes = ChatRoutes();
  final fileRoutes = FileRoutes();

  // Wrap protected route handlers with auth middleware
  final protectedChatHandler = const Pipeline()
      .addMiddleware(addAuthMiddleware)
      .addHandler(chatRoutes.router);

  final protectedFileHandler = const Pipeline()
      .addMiddleware(addAuthMiddleware)
      .addHandler(fileRoutes.router);

  // Auth profile routes are protected; OTP/refresh routes are public
  final protectedAuthHandler = const Pipeline()
      .addMiddleware(addAuthMiddleware)
      .addHandler(authRoutes.protectedRouter);

  final jwtService = JwtService();

  final router = Router()
    ..get('/ws', (Request request) {
      // WebSocket auth via subprotocol (token passed as second protocol) or Authorization header
      String? token;

      // Try Authorization header first
      final authHeader = request.headers['authorization'];
      if (authHeader != null && authHeader.startsWith('Bearer ')) {
        token = authHeader.substring(7);
      }

      // Try Sec-WebSocket-Protocol header (subprotocol contains "Bearer,<token>")
      if (token == null) {
        final protocols = request.headers['sec-websocket-protocol'];
        if (protocols != null) {
          final parts = protocols.split(',');
          if (parts.length >= 2 && parts[0].trim() == 'Bearer') {
            token = parts[1].trim();
          }
        }
      }

      if (token == null) {
        return Response.unauthorized(
          '{"error": "No authorization token provided"}',
          headers: {'Content-Type': 'application/json'},
        );
      }

      final payload = jwtService.verifyToken(token);
      if (payload == null) {
        return Response.unauthorized(
          '{"error": "Invalid or expired token"}',
          headers: {'Content-Type': 'application/json'},
        );
      }

      final userId = payload['sub'] as String?;
      if (userId == null) {
        return Response.unauthorized(
          '{"error": "Invalid token payload"}',
          headers: {'Content-Type': 'application/json'},
        );
      }

      return webSocketHandler((WebSocketChannel channel) {
        websocketService.handleConnection(channel, userId);
      })(request);
    })
    // Public auth routes (send-otp, verify-otp, refresh-token)
    ..mount('/api/auth/public/', authRoutes.publicRouter)
    // Protected auth routes (profile)
    ..mount('/api/auth/', protectedAuthHandler)
    // Chat and file routes require a valid Bearer token
    ..mount('/api/chat/', protectedChatHandler)
    ..mount('/api/files/', protectedFileHandler)
    ..get('/health', (Request request) => Response.ok('{"status": "ok"}'));

  return router.call;
}
