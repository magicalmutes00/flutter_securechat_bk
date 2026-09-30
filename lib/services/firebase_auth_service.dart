import 'dart:convert';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import 'user_service.dart';
import 'jwt_service.dart';

/// Verifies a Firebase ID Token sent from the mobile app and returns the
/// verified phone number extracted from the token claims.
///
/// Firebase ID Tokens are JWTs signed by Google. Instead of bundling the
/// Firebase Admin SDK (which has no official Dart package), we verify the
/// token by fetching Google's public keys and checking the signature
/// ourselves — the same approach used in the Firebase REST API docs.
class FirebaseAuthService {
  final UserService _userService = UserService();
  final JwtService _jwtService = JwtService();

  // Google's public key endpoint for Firebase tokens
  static const _certsUrl =
      'https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com';

  // Google's public certs are rotated rarely and served with a Cache-Control
  // max-age; caching avoids a network round trip on every login.
  static Map<String, dynamic>? _cachedCerts;
  static DateTime _certsFetchedAt = DateTime.fromMillisecondsSinceEpoch(0);
  static Duration _certsCacheTtl = const Duration(hours: 1);

  /// Verifies the [idToken] and returns an auth result map containing the
  /// access+refresh token pair and the user object.
  ///
  /// Throws a [FirebaseAuthException] on any verification failure.
  Future<Map<String, dynamic>> verifyTokenAndAuthenticate(
      String idToken) async {
    // 1. Decode the token header to find which key was used
    final parts = idToken.split('.');
    if (parts.length != 3) {
      throw FirebaseAuthException('Malformed token');
    }

    // Malformed base64/JSON in the header is a client error, not a server
    // fault — normalize it to the same 401 path as every other bad token.
    final Map<String, dynamic> header;
    try {
      final headerJson =
          utf8.decode(base64Url.decode(base64Url.normalize(parts[0])));
      header = jsonDecode(headerJson) as Map<String, dynamic>;
    } on FormatException {
      throw FirebaseAuthException('Malformed token');
    } on ArgumentError {
      throw FirebaseAuthException('Malformed token');
    }
    final kid = header['kid'] as String?;
    if (kid == null) {
      throw FirebaseAuthException('Token header missing kid');
    }

    // 2. Fetch Google's public certs (cached)
    final certs = await _fetchPublicCerts();
    final certPem = certs[kid] as String?;
    if (certPem == null) {
      throw FirebaseAuthException('No matching key found for kid: $kid');
    }

    // 3. Verify the JWT signature and claims
    JWT jwt;
    try {
      jwt = JWT.verify(
        idToken,
        RSAPublicKey.cert(certPem),
        // Firebase issues tokens with these standard claims
        checkHeaderType: false,
      );
    } on JWTExpiredException {
      throw FirebaseAuthException('Firebase token has expired');
    } on JWTException catch (e) {
      throw FirebaseAuthException('Token verification failed: ${e.message}');
    }

    final payload = jwt.payload as Map<String, dynamic>;

    // Google signs Firebase tokens for every project with the same keys, so
    // the signature only proves it is a Firebase token. The audience and
    // issuer must be checked to bind the token to THIS Firebase project.
    final projectId = AppConfig.firebaseProjectId;
    if (payload['aud'] != projectId) {
      throw FirebaseAuthException(
          'Firebase token audience does not match this project');
    }
    if (payload['iss'] != 'https://securetoken.google.com/$projectId') {
      throw FirebaseAuthException(
          'Firebase token issuer does not match this project');
    }

    // 4. Extract user identifiers from the token
    // Firebase UID is always present in Firebase tokens (as 'sub' or 'user_id')
    final firebaseUid = (payload['user_id'] ?? payload['sub']) as String?;
    if (firebaseUid == null || firebaseUid.isEmpty) {
      throw FirebaseAuthException(
          'Token does not contain a valid Firebase UID');
    }

    // Phone number may not be present (e.g., for email/password or Google login)
    final phone = payload['phone_number'] as String?;
    // Email may not be present (e.g., for phone-only login)
    final email = payload['email'] as String?;
    // Display name from Google or email auth
    final displayName = payload['name'] as String?;

    // 5. Get or create user using Firebase UID as the primary identifier
    // This supports all Firebase auth methods: phone, email/password, Google
    final user = await _userService.getOrCreateUserFromFirebase(
      firebaseUid: firebaseUid,
      phone: phone,
      email: email,
      displayName: displayName,
    );
    final accessToken = _jwtService.generateAccessToken(
        user.id, user.phone,
        email: user.email);
    final refreshToken = _jwtService.generateRefreshToken(user.id);
    // Single active refresh session: minting a new pair revokes the old one.
    final jti = _jwtService.getJwtId(refreshToken);
    if (jti != null) {
      await _userService.setCurrentRefreshJti(user.id, jti);
    }

    return {
      'success': true,
      'message': 'Authentication successful',
      'user': user.toJson(),
      'access_token': accessToken,
      'refresh_token': refreshToken,
    };
  }

  Future<Map<String, dynamic>> _fetchPublicCerts() async {
    final cached = _cachedCerts;
    if (cached != null &&
        DateTime.now().difference(_certsFetchedAt) < _certsCacheTtl) {
      return cached;
    }

    final certsResponse = await http.get(Uri.parse(_certsUrl));
    if (certsResponse.statusCode != 200) {
      throw FirebaseAuthException('Could not fetch Google public keys');
    }
    final certs = jsonDecode(certsResponse.body) as Map<String, dynamic>;

    // Respect Google's cache lifetime when advertised.
    final cacheControl = certsResponse.headers['cache-control'] ?? '';
    final maxAge = RegExp(r'max-age=(\d+)').firstMatch(cacheControl)?.group(1);
    if (maxAge != null) {
      _certsCacheTtl = Duration(seconds: int.parse(maxAge));
    }

    _certsFetchedAt = DateTime.now();
    _cachedCerts = certs;
    return certs;
  }
}

class FirebaseAuthException implements Exception {
  final String message;
  FirebaseAuthException(this.message);

  @override
  String toString() => 'FirebaseAuthException: $message';
}
