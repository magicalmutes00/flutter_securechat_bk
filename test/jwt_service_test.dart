import 'package:test/test.dart';
import 'package:secure_chat_server/services/jwt_service.dart';

void main() {
  late JwtService svc;

  setUp(() {
    svc = JwtService(
      secret: 'abcdefghijklmnopabcdefghijklmnop',
      issuer: 'test-server',
      audience: 'test-mobile',
    );
  });

  test('issue and verify access token', () {
    final token = svc.generateAccessToken('user123', '+14155551234');
    expect(token, isNotEmpty);

    final payload = svc.verifyToken(token);
    expect(payload, isNotNull);
    expect(payload!['sub'], 'user123');
    expect(payload['phone'], '+14155551234');
    expect(payload['type'], 'access');
    expect(payload['iss'], 'test-server');
    expect(payload['aud'], 'test-mobile');
  });

  test('rejects expired token', () {
    svc = JwtService(
      secret: 'abcdefghijklmnopabcdefghijklmnop',
      issuer: 'test-server',
      audience: 'test-mobile',
    );
    final result = svc.verifyToken('garbage.garbage.garbage');
    expect(result, isNull);
  });

  test('refresh token rotation', () {
    final refresh = svc.generateRefreshToken('user123');
    expect(refresh, isNotEmpty);

    final tokens = svc.refreshTokens(refresh);
    expect(tokens, isNotNull);
    expect(tokens!['access_token'], isNotEmpty);
    expect(tokens['refresh_token'], isNotEmpty);
    expect(tokens['refresh_token'], isNot(refresh));

    final payload = svc.verifyToken(refresh);
    expect(payload, isNotNull);
    expect(payload!['sub'], 'user123');
  });

  test('rejects token with wrong audience', () {
    final target = JwtService(
      secret: 'abcdefghijklmnopabcdefghijklmnop',
      issuer: 'test-server',
      audience: 'test-mobile',
    );
    final token = target.generateAccessToken('user1', '+14155551234');

    // Use a service with a different audience
    final wrongAudience = JwtService(
      secret: 'abcdefghijklmnopabcdefghijklmnop',
      issuer: 'test-server',
      audience: 'other-app',
    );
    expect(wrongAudience.verifyToken(token), isNull);
  });
}