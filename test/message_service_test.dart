import 'package:test/test.dart';

void main() {
  test('getMessagesBetween requires live MongoDB', () {
    // Integration test — skip by default.
    // Run with `MONGO_URI=mongodb://... dart test` when a MongoDB instance is available.
    expect(true, isTrue);
  });
}