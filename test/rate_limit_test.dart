import 'package:test/test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:secure_chat_server/middleware/rate_limit_middleware.dart';

void main() {
  test('sliding window blocks exceeding requests', () async {
    final limiter = rateLimitMiddleware(
      limiter: RateLimiter(maxRequests: 3, window: Duration(seconds: 60)),
    );
    int calls = 0;
    final innerHandler = (shelf.Request req) async {
      calls++;
      return shelf.Response.ok('ok');
    };
    final handler = limiter(innerHandler);

    final req = shelf.Request('GET', Uri.parse('http://test/'));

    for (int i = 0; i < 3; i++) {
      final resp = await handler(req);
      expect(resp.statusCode, 200);
    }
    final blocked = await handler(req);
    expect(blocked.statusCode, 429);
    expect(blocked.headers['retry-after'], isNotNull);
    expect(calls, 3);
  });

  test('different IPs have independent limits', () async {
    final limiter = rateLimitMiddleware(
      limiter: RateLimiter(maxRequests: 1, window: Duration(seconds: 60)),
    );
    final handler = limiter((shelf.Request req) async => shelf.Response.ok('ok'));

    final reqA = shelf.Request('GET', Uri.parse('http://test/'),
      headers: {'x-forwarded-for': '1.2.3.4'});
    final reqB = shelf.Request('GET', Uri.parse('http://test/'),
      headers: {'x-forwarded-for': '5.6.7.8'});

    expect((await handler(reqA)).statusCode, 200);
    expect((await handler(reqB)).statusCode, 200);
    expect((await handler(reqA)).statusCode, 429);
    expect((await handler(reqB)).statusCode, 429);
  });

  test('window slides after timeout', () async {
    final limiter = rateLimitMiddleware(
      limiter: RateLimiter(maxRequests: 1, window: Duration(seconds: 1)),
    );
    final handler = limiter((shelf.Request req) async => shelf.Response.ok('ok'));

    final req = shelf.Request('GET', Uri.parse('http://test/'));
    expect((await handler(req)).statusCode, 200);

    await Future.delayed(const Duration(milliseconds: 1100));
    expect((await handler(req)).statusCode, 200);
  });
}