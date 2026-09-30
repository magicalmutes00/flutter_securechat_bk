import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';

/// Thrown when a Cloudinary API call fails.
class CloudinaryException implements Exception {
  CloudinaryException(this.message);
  final String message;

  @override
  String toString() => 'CloudinaryException: $message';
}

/// Result of uploading one attachment to Cloudinary.
class CloudinaryUploadResult {
  CloudinaryUploadResult({
    required this.publicId,
    required this.version,
    required this.resourceType,
    required this.format,
    required this.bytes,
  });

  final String publicId;
  final int version;
  final String resourceType; // image | video | raw
  final String? format; // e.g. jpg, mp4; absent for raw
  final int bytes;

  /// Path (relative to https://res.cloudinary.com/{cloud}/) under which the
  /// asset is delivered, e.g. `image/authenticated/v1698/securechat/abc.jpg`.
  /// Signed delivery URLs are minted from this path on download.
  String get deliveryPath {
    final suffix = (format == null || format!.isEmpty || resourceType == 'raw')
        ? ''
        : '.$format';
    return '$resourceType/authenticated/v$version/$publicId$suffix';
  }
}

/// Stores attachments in Cloudinary as **authenticated** (private) assets.
///
/// Uploads are signed with the API secret; downloads are only possible via
/// short server-minted signed URLs, which the API issues after its own
/// participant authorization check — there is no public URL for any file.
/// End-to-end encrypted attachments are uploaded as opaque ciphertext; their
/// AES keys travel inside the Signal-encrypted message, never to the server.
class CloudinaryService {
  final Uuid _uuid = const Uuid();

  String get _cloudName => AppConfig.cloudinaryCloudName;
  String get _apiKey => AppConfig.cloudinaryApiKey;
  String get _apiSecret => AppConfig.cloudinaryApiSecret;

  /// Uploads [bytes] as a private asset and returns where to find it.
  Future<CloudinaryUploadResult> upload({
    required List<int> bytes,
    required String filename,
  }) async {
    final publicId = 'securechat/${_uuid.v4()}';
    final timestamp =
        (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();

    // Cloudinary signs every parameter except file/api_key/resource_type.
    // Params are sorted alphabetically: public_id, timestamp, type.
    final toSign =
        'public_id=$publicId&timestamp=$timestamp&type=authenticated$_apiSecret';
    final signature = crypto.sha1.convert(utf8.encode(toSign)).toString();

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('https://api.cloudinary.com/v1_1/$_cloudName/auto/upload'),
    )
      ..fields['public_id'] = publicId
      ..fields['timestamp'] = timestamp
      ..fields['type'] = 'authenticated'
      ..fields['api_key'] = _apiKey
      ..fields['signature'] = signature
      ..files.add(http.MultipartFile.fromBytes('file', bytes,
          filename: filename));

    try {
      final streamed = await request.send().timeout(
            const Duration(minutes: 5),
          );
      final body = await streamed.stream.bytesToString();
      final decoded = jsonDecode(body) as Map<String, dynamic>;

      if (streamed.statusCode != 200) {
        final error = decoded['error'];
        final message = error is Map ? error['message'] : 'upload failed';
        throw CloudinaryException('Cloudinary upload failed: $message');
      }

      return CloudinaryUploadResult(
        publicId: decoded['public_id'] as String,
        version: (decoded['version'] as num).toInt(),
        resourceType: decoded['resource_type'] as String? ?? 'raw',
        format: decoded['format'] as String?,
        bytes: (decoded['bytes'] as num?)?.toInt() ?? bytes.length,
      );
    } on CloudinaryException {
      rethrow;
    } catch (e) {
      throw CloudinaryException('Cloudinary upload failed: $e');
    }
  }

  /// Mints a signed delivery URL for a stored [deliveryPath].
  ///
  /// Signature = first 8 chars of URL-safe base64(SHA1(path + api_secret)).
  String signedDeliveryUrl(String deliveryPath) {
    const marker = '/authenticated/';
    final idx = deliveryPath.indexOf(marker);
    if (idx == -1) {
      throw CloudinaryException('Invalid delivery path: $deliveryPath');
    }
    final prefix = deliveryPath.substring(0, idx + marker.length);
    final pathPart = deliveryPath.substring(idx + marker.length);

    final digest =
        crypto.sha1.convert(utf8.encode('$pathPart$_apiSecret')).bytes;
    final sig = base64Url.encode(digest).replaceAll('=', '').substring(0, 8);

    return 'https://res.cloudinary.com/$_cloudName/$prefix'
        's--$sig--/$pathPart';
  }
}
