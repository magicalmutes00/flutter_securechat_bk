import 'dart:io';

import 'package:test/test.dart';

import 'package:secure_chat_server/config/app_config.dart';
import 'package:secure_chat_server/models/group_message_model.dart';
import 'package:secure_chat_server/models/message_model.dart';
import 'package:secure_chat_server/services/websocket_service.dart';
import 'package:secure_chat_server/utils/file_validation.dart';
import 'package:secure_chat_server/utils/plaintext_guard.dart';

void main() {
  group('plaintext contract: no new encrypted writes', () {
    test('allowed extensions contain no .enc wrappers', () {
      final extensions = AppConfig.allowedFileExtensions;
      for (final entry in extensions.entries) {
        expect(entry.value, isNot(contains('enc')),
            reason: '${entry.key} must not allow .enc in plaintext mode');
      }
    });

    test('validateUploadFile rejects .enc filenames', () {
      expect(validateUploadFile('a.enc', [1, 2, 3], 'image'), isNotNull);
      expect(validateUploadFile('a.enc', [1, 2, 3], 'video'), isNotNull);
      expect(validateUploadFile('a.enc', [1, 2, 3], 'audio'), isNotNull);
      expect(validateUploadFile('a.enc', [1, 2, 3], 'document'), isNotNull);
    });

    test('plaintext payloads pass the crypto guard', () {
      expect(rejectCryptoMessagePayload({}), isNull);
      expect(
        rejectCryptoMessagePayload({
          'content': 'hello',
          'message_type': 'text',
        }),
        isNull,
      );
      // Explicit 'none' is the only accepted encryption value.
      expect(rejectCryptoMessagePayload({'encryption': 'none'}), isNull);
      // Explicit null cipher fields carry nothing and are ignored.
      expect(
        rejectCryptoMessagePayload({'cipher_type': null, 'cipher_body': null}),
        isNull,
      );
    });

    test('encrypted / crypto-control payloads are rejected', () {
      expect(
        rejectCryptoMessagePayload({'encryption': 'signal'}),
        isNotNull,
      );
      expect(rejectCryptoMessagePayload({'encryption': ''}), isNotNull);
      expect(rejectCryptoMessagePayload({'encryption': null}), isNotNull);
      expect(
        rejectCryptoMessagePayload({'cipher_type': 1}),
        isNotNull,
      );
      expect(
        rejectCryptoMessagePayload({'cipher_body': 'opaque'}),
        isNotNull,
      );
      expect(
        rejectCryptoMessagePayload({
          'distribution': {'a': 1}
        }),
        isNotNull,
      );
      expect(
        rejectCryptoMessagePayload({'identity_key_public': 'x'}),
        isNotNull,
      );
      expect(
        rejectCryptoMessagePayload({'signed_prekey_public': 'x'}),
        isNotNull,
      );
      expect(
        rejectCryptoMessagePayload({
          'one_time_prekeys': ['x']
        }),
        isNotNull,
      );
      expect(
        rejectCryptoMessagePayload({'registration_id': 1}),
        isNotNull,
      );
      expect(
        rejectCryptoMessagePayload({'device_id': 'd1'}),
        isNotNull,
      );
      expect(
        rejectCryptoMessagePayload({'media_key': 'k'}),
        isNotNull,
      );
      expect(
        rejectCryptoMessagePayload({'media_nonce': 'n'}),
        isNotNull,
      );
      expect(
        rejectCryptoMessagePayload({'media-key': 'k'}),
        isNotNull,
      );
      expect(
        rejectCryptoMessagePayload({'sender_key': 'k'}),
        isNotNull,
      );
    });

    test('new message models default to plaintext', () {
      final now = DateTime.now().toUtc();
      final message = MessageModel(
        id: '00000000-0000-0000-0000-000000000001',
        senderId: '00000000-0000-0000-0000-000000000002',
        receiverId: '00000000-0000-0000-0000-000000000003',
        messageType: 'text',
        content: 'hello plaintext',
        status: 'sent',
        createdAt: now,
        updatedAt: now,
      );
      expect(message.encryption, 'none');
      expect(message.cipherType, isNull);
      expect(message.cipherBody, isNull);

      final groupMessage = GroupMessageModel(
        id: '00000000-0000-0000-0000-000000000001',
        groupId: '00000000-0000-0000-0000-000000000004',
        senderId: '00000000-0000-0000-0000-000000000002',
        messageType: 'text',
        content: 'hello group',
        status: 'sent',
        createdAt: now,
        updatedAt: now,
      );
      expect(groupMessage.encryption, 'none');
      expect(groupMessage.cipherType, isNull);
      expect(groupMessage.cipherBody, isNull);
    });

    test('legacy encrypted rows remain readable for identification', () {
      final now = DateTime.now().toUtc();
      final row = {
        'id': '00000000-0000-0000-0000-000000000010',
        'sender_id': '00000000-0000-0000-0000-000000000002',
        'receiver_id': '00000000-0000-0000-0000-000000000003',
        'message_type': 'text',
        'content': '',
        'status': 'sent',
        'created_at': now,
        'updated_at': now,
        'encryption': 'signal',
        'cipher_type': 3,
        'cipher_body': 'legacy-opaque',
      };
      final message = MessageModel.fromMap(row);
      expect(message.encryption, 'signal');
      expect(message.cipherType, 3);
      expect(message.cipherBody, 'legacy-opaque');
      // Still surfaced in JSON so old data is identifiable as legacy.
      expect(message.toJson()['encryption'], 'signal');
    });

    test('copyWith cannot introduce new encrypted values', () {
      final now = DateTime.now().toUtc();
      final message = MessageModel(
        id: '00000000-0000-0000-0000-000000000001',
        senderId: '00000000-0000-0000-0000-000000000002',
        receiverId: '00000000-0000-0000-0000-000000000003',
        messageType: 'text',
        content: 'hi',
        status: 'sent',
        createdAt: now,
        updatedAt: now,
      );
      final copied = message.copyWith(content: 'edited');
      expect(copied.encryption, 'none');
      expect(copied.cipherType, isNull);
      expect(copied.cipherBody, isNull);
    });

    test('push bodies show plaintext for text, labels for media', () {
      final service = WebSocketService();
      expect(service.plaintextPushBody('text', 'hello world'), 'hello world');
      expect(service.plaintextPushBody('text', '   '), 'Sent you a message');
      expect(service.plaintextPushBody('image', 'x'), 'Photo');
      expect(service.plaintextPushBody('video', 'x'), 'Video');
      expect(service.plaintextPushBody('audio', 'x'), 'Voice message');
      expect(service.plaintextPushBody('document', 'x'), 'Document');
    });
  });

  group('plaintext contract: key-bundle endpoints are gone', () {
    test('key files are deleted', () {
      expect(File('lib/routes/key_routes.dart').existsSync(), isFalse);
      expect(File('lib/services/key_service.dart').existsSync(), isFalse);
      expect(File('lib/models/key_model.dart').existsSync(), isFalse);
    });

    test('router no longer mounts /api/keys', () {
      final mainSource = File('lib/main.dart').readAsStringSync();
      expect(mainSource.contains('/api/keys/'), isFalse);
      expect(mainSource.contains('KeyRoutes'), isFalse);
      expect(mainSource.contains('key_routes'), isFalse);
    });

    test('schema no longer creates the keys table', () {
      final schema =
          File('lib/services/database_service.dart').readAsStringSync();
      expect(schema.contains('CREATE TABLE IF NOT EXISTS keys'), isFalse);
      expect(schema.contains('DROP TABLE IF EXISTS keys'), isTrue);
      expect(schema.contains('identity_key_public'), isFalse);
      expect(schema.contains('signed_prekey_public'), isFalse);
      expect(schema.contains('one_time_prekeys'), isFalse);
      // Legacy message columns are retained for old-row identification.
      expect(schema.contains('encryption TEXT NOT NULL'), isTrue);
    });

    test('message services accept no crypto parameters', () {
      final messageService =
          File('lib/services/message_service.dart').readAsStringSync();
      expect(messageService.contains('cipherType'), isFalse);
      expect(messageService.contains('cipherBody'), isFalse);
      expect(messageService.contains('cipher_type'), isTrue,
          reason: 'historical INSERT columns remain, but always NULL');
      expect(messageService.contains("'encryption': 'none'"), isTrue);

      final groupService =
          File('lib/services/group_service.dart').readAsStringSync();
      expect(groupService.contains('cipherType'), isFalse);
      expect(groupService.contains('cipherBody'), isFalse);
      expect(groupService.contains("'encryption': 'none'"), isTrue);
    });

    test('REST chat route rejects crypto payloads explicitly', () {
      final chatRoutes = File('lib/routes/chat_routes.dart').readAsStringSync();
      expect(chatRoutes.contains('rejectCryptoMessagePayload'), isTrue);
      expect(chatRoutes.contains("data['cipher_type']"), isFalse);
      expect(chatRoutes.contains("data['cipher_body']"), isFalse);
      expect(chatRoutes.contains("data['encryption']"), isFalse);
    });

    test('websocket drops crypto frames and has no session-reset relay', () {
      final ws = File('lib/services/websocket_service.dart').readAsStringSync();
      expect(ws.contains('rejectCryptoMessagePayload'), isTrue);
      expect(ws.contains('_handleResetSession'), isFalse);
      expect(ws.contains("'reset_session'"), isFalse);
      expect(ws.contains('"reset_session"'), isFalse);
      expect(ws.contains('reset_session'), isFalse);
      expect(ws.contains('X3DH'), isFalse);
    });
  });
}
