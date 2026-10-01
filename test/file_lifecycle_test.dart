import 'package:test/test.dart';

import 'package:secure_chat_server/services/file_service.dart';

void main() {
  group('resourceTypeOfDeliveryPath', () {
    test('parses stored image/video/raw prefixes', () {
      expect(
        resourceTypeOfDeliveryPath(
            'image/authenticated/v1698/securechat/abc.jpg'),
        'image',
      );
      expect(
        resourceTypeOfDeliveryPath('video/authenticated/v12/securechat/x'),
        'video',
      );
      expect(
        resourceTypeOfDeliveryPath('raw/authenticated/v12/securechat/x'),
        'raw',
      );
    });

    test('falls back to raw for unknown or missing prefixes', () {
      // Destroy must target a real endpoint: unknown prefixes resolve to
      // `raw`, the type every current upload uses.
      expect(resourceTypeOfDeliveryPath('auto/authenticated/v1/x'), 'raw');
      expect(resourceTypeOfDeliveryPath('no-slash-here'), 'raw');
      expect(resourceTypeOfDeliveryPath(''), 'raw');
    });
  });
}
