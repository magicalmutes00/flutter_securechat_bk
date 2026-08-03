import 'package:secure_chat_server/services/password_service.dart';
import 'package:test/test.dart';

void main() {
  group('PasswordService', () {
    test('hashes and verifies a password', () {
      final hash = PasswordService.hashPassword('hunter2');
      expect(hash, startsWith('pbkdf2\$'));
      expect(PasswordService.verifyPassword('hunter2', hash), isTrue);
      expect(PasswordService.verifyPassword('wrong', hash), isFalse);
    });

    test('produces a unique salt per hash', () {
      final a = PasswordService.hashPassword('same');
      final b = PasswordService.hashPassword('same');
      expect(a, isNot(equals(b)));
      expect(PasswordService.verifyPassword('same', a), isTrue);
      expect(PasswordService.verifyPassword('same', b), isTrue);
    });

    test('rejects malformed hashes', () {
      expect(PasswordService.verifyPassword('x', ''), isFalse);
      expect(PasswordService.verifyPassword('x', 'pbkdf2\$bad'), isFalse);
      expect(
          PasswordService.verifyPassword('x', 'pbkdf2\$\$not\$valid'), isFalse);
    });
  });
}
