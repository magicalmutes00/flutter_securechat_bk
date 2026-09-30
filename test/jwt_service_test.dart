import 'package:test/test.dart';
import 'package:secure_chat_server/config/env_config.dart';
import 'package:secure_chat_server/services/jwt_service.dart';

void main() {
  late JwtService svc;

  setUpAll(() {
    EnvConfig.setForTesting(
      'JWT_SECRET',
      'test-secret-0123456789abcdef0123456789abcdef',
    );
    EnvConfig.setForTesting('JWT_ISSUER', 'test-server');
  });

  setUp(() {
    svc = JwtService();
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
  });

  test('garbage and empty tokens are rejected', () {
    expect(svc.verifyToken('garbage.garbage.garbage'), isNull);
    expect(svc.verifyToken(''), isNull);
    expect(svc.verifyToken('not-a-jwt'), isNull);
  });

  test('refresh token rotation issues a new pair', () {
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
    expect(payload['type'], 'refresh');
  });

  test('refresh flow rejects access tokens', () {
    final access = svc.generateAccessToken('user123', null);
    expect(svc.refreshTokens(access), isNull);
  });

  test('tokens from a different secret are rejected', () {
    final token = svc.generateAccessToken('user123', null);

    EnvConfig.setForTesting(
      'JWT_SECRET',
      'another-secret-0123456789abcdef012345678',
    );
    final other = JwtService();
    expect(other.verifyToken(token), isNull);

    // Restore for the remaining tests.
    EnvConfig.setForTesting(
      'JWT_SECRET',
      'test-secret-0123456789abcdef0123456789abcdef',
    );
  });
}
