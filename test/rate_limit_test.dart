import 'package:test/test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:secure_chat_server/middleware/rate_limit_middleware.dart';

void main() {
  group('RateLimiter', () {
    test('blocks requests beyond the limit for the same key', () {
      final limiter = RateLimiter(
        maxRequests: 3,
        window: const Duration(seconds: 60),
      );
      expect(limiter.allow('ip-a'), isTrue);
      expect(limiter.allow('ip-a'), isTrue);
      expect(limiter.allow('ip-a'), isTrue);
      expect(limiter.allow('ip-a'), isFalse);
      expect(limiter.allow('ip-a'), isFalse);
    });

    test('keys have independent limits', () {
      final limiter = RateLimiter(
        maxRequests: 1,
        window: const Duration(seconds: 60),
      );
      expect(limiter.allow('ip-a'), isTrue);
      expect(limiter.allow('ip-a'), isFalse);
      expect(limiter.allow('ip-b'), isTrue);
      expect(limiter.allow('ip-b'), isFalse);
    });

    test('window slides after expiry', () async {
      final limiter = RateLimiter(
        maxRequests: 1,
        window: const Duration(milliseconds: 100),
      );
      expect(limiter.allow('ip-a'), isTrue);
      expect(limiter.allow('ip-a'), isFalse);

      await Future.delayed(const Duration(milliseconds: 150));
      expect(limiter.allow('ip-a'), isTrue);
    });
  });

  group('rateLimitMiddleware', () {
    test('passes requests under the limit and returns 429 beyond it',
        () async {
      final limiter = RateLimiter(
        maxRequests: 2,
        window: const Duration(seconds: 60),
      );
      final middleware = rateLimitMiddleware(limiter);
      final handler =
          middleware((shelf.Request req) async => shelf.Response.ok('ok'));

      shelf.Request request() =>
          shelf.Request('GET', Uri.parse('http://test/'));

      // Without connection info every request keys to the same bucket.
      expect((await handler(request())).statusCode, 200);
      expect((await handler(request())).statusCode, 200);

      var calls = 0;
      final countingHandler = middleware((shelf.Request req) async {
        calls++;
        return shelf.Response.ok('ok');
      });
      final blocked = await countingHandler(request());
      expect(blocked.statusCode, 429);
      expect(blocked.headers['retry-after'], isNotNull);
      expect(calls, 0);
    });
  });
}
