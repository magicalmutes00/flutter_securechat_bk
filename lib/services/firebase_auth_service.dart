import 'dart:convert';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;
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

    final headerJson =
        utf8.decode(base64Url.decode(base64Url.normalize(parts[0])));
    final header = jsonDecode(headerJson) as Map<String, dynamic>;
    final kid = header['kid'] as String?;
    if (kid == null) {
      throw FirebaseAuthException('Token header missing kid');
    }

    // 2. Fetch Google's public certs
    final certsResponse = await http.get(Uri.parse(_certsUrl));
    if (certsResponse.statusCode != 200) {
      throw FirebaseAuthException('Could not fetch Google public keys');
    }
    final certs = jsonDecode(certsResponse.body) as Map<String, dynamic>;
    final certPem = certs[kid] as String?;
    if (certPem == null) {
      throw FirebaseAuthException('No matching key found for kid: $kid');
    }

    // 3. Verify the JWT signature and claims
    JWT jwt;
    try {
      jwt = JWT.verify(
        idToken,
        RSAPublicKey(certPem),
        // Firebase issues tokens with these standard claims
        checkHeaderType: false,
      );
    } on JWTExpiredException {
      throw FirebaseAuthException('Firebase token has expired');
    } on JWTException catch (e) {
      throw FirebaseAuthException('Token verification failed: ${e.message}');
    }

    final payload = jwt.payload as Map<String, dynamic>;

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
        user.id.toHexString(), user.phone,
        email: user.email);
    final refreshToken =
        _jwtService.generateRefreshToken(user.id.toHexString());

    return {
      'success': true,
      'message': 'Authentication successful',
      'user': user.toJson(),
      'access_token': accessToken,
      'refresh_token': refreshToken,
    };
  }
}

class FirebaseAuthException implements Exception {
  final String message;
  FirebaseAuthException(this.message);

  @override
  String toString() => 'FirebaseAuthException: $message';
}
