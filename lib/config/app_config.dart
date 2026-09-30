/// Application configuration for SecureChat Server
/// Sensitive values should be set via environment variables (see .env.example)

import 'env_config.dart';

class AppConfig {
  AppConfig._();

  // Server Configuration
  static String get serverHost => EnvConfig.get('SERVER_HOST') ?? '0.0.0.0';
  static int get serverPort =>
      int.tryParse(EnvConfig.get('SERVER_PORT') ?? '8080') ?? 8080;
  static String get serverBaseUrl =>
      EnvConfig.get('SERVER_BASE_URL') ?? 'http://192.168.1.14:8081';

  // WebSocket Configuration
  static String get wsPath => EnvConfig.get('WS_PATH') ?? '/ws';
  static int get wsPingIntervalSeconds =>
      int.tryParse(EnvConfig.get('WS_PING_INTERVAL') ?? '30') ?? 30;
  static int get wsConnectionTimeoutSeconds =>
      int.tryParse(EnvConfig.get('WS_CONNECTION_TIMEOUT') ?? '60') ?? 60;

  // Supabase (PostgreSQL) Configuration (REQUIRED)
  // Connection string from Supabase → Project Settings → Database.
  // Use the session pooler URI (port 5432), e.g.
  // postgresql://postgres.<ref>:<password>@aws-0-<region>.pooler.supabase.com:5432/postgres
  static String get supabaseDbUrl => EnvConfig.getRequired('SUPABASE_DB_URL');

  // JWT Configuration (REQUIRED - must be set via environment)
  static String get jwtSecret => EnvConfig.getRequired('JWT_SECRET');
  static String get jwtIssuer =>
      EnvConfig.get('JWT_ISSUER') ?? 'securechat-server';
  static int get jwtAccessTokenExpiryMinutes =>
      int.tryParse(
          EnvConfig.get('JWT_ACCESS_TOKEN_EXPIRY_MINUTES') ?? '1440') ??
      1440;
  static int get jwtRefreshTokenExpiryDays =>
      int.tryParse(EnvConfig.get('JWT_REFRESH_TOKEN_EXPIRY_DAYS') ?? '30') ??
      30;
  static String get jwtAlgorithm => EnvConfig.get('JWT_ALGORITHM') ?? 'HS256';

  // OTP Configuration (MessageCentral API — legacy fallback flow)
  static String get messageCentralBaseUrl =>
      EnvConfig.get('MESSAGE_CENTRAL_BASE_URL') ??
      'https://api.messagecentral.com';
  static String? get messageCentralApiKey =>
      EnvConfig.get('MESSAGE_CENTRAL_API_KEY');
  static String? get messageCentralCustomerId =>
      EnvConfig.get('MESSAGE_CENTRAL_CUSTOMER_ID');
  static int get otpLength =>
      int.tryParse(EnvConfig.get('OTP_LENGTH') ?? '6') ?? 6;
  static int get otpExpiryMinutes =>
      int.tryParse(EnvConfig.get('OTP_EXPIRY_MINUTES') ?? '5') ?? 5;
  static int get otpMaxAttempts =>
      int.tryParse(EnvConfig.get('OTP_MAX_ATTEMPTS') ?? '3') ?? 3;
  static bool get otpDevMode => EnvConfig.get('OTP_DEV_MODE') == 'true';

  // Cloudinary Configuration (REQUIRED — all attachments are stored there)
  static String get cloudinaryCloudName =>
      EnvConfig.getRequired('CLOUDINARY_CLOUD_NAME');
  static String get cloudinaryApiKey =>
      EnvConfig.getRequired('CLOUDINARY_API_KEY');
  static String get cloudinaryApiSecret =>
      EnvConfig.getRequired('CLOUDINARY_API_SECRET');

  static int get maxFileSizeBytes =>
      int.tryParse(EnvConfig.get('MAX_FILE_SIZE_BYTES') ?? '52428800') ??
      52428800;
  static Map<String, List<String>> get allowedFileExtensions => {
        // 'enc' covers end-to-end encrypted attachments whose original
        // extension was lost; their content is opaque ciphertext.
        'image': ['jpg', 'jpeg', 'png', 'gif', 'webp', 'enc'],
        'video': ['mp4', 'mov', 'avi', 'mkv', 'webm', 'enc'],
        'audio': ['mp3', 'wav', 'aac', 'm4a', 'ogg', 'enc'],
        'document': [
          'pdf',
          'doc',
          'docx',
          'txt',
          'xls',
          'xlsx',
          'ppt',
          'pptx',
          'enc'
        ],
      };

  // CORS Configuration
  static List<String> get corsAllowedOrigins {
    final origins = EnvConfig.get('CORS_ALLOWED_ORIGINS');
    if (origins != null && origins.isNotEmpty) {
      return origins.split(',').map((e) => e.trim()).toList();
    }
    return [
      'http://localhost:3000',
      'http://localhost:8080',
      'http://localhost:8081',
      'http://127.0.0.1:3000',
      'http://127.0.0.1:8080',
      'http://127.0.0.1:8081',
      'http://192.168.1.14:8081',
    ];
  }

  // Rate Limiting
  static int get rateLimitMaxRequests =>
      int.tryParse(EnvConfig.get('RATE_LIMIT_MAX_REQUESTS') ?? '100') ?? 100;
  static int get rateLimitWindowMinutes =>
      int.tryParse(EnvConfig.get('RATE_LIMIT_WINDOW_MINUTES') ?? '1') ?? 1;

  /// Set to true when running behind a reverse proxy (ngrok, nginx, a cloud
  /// LB) so the rate limiter keys on the client's `X-Forwarded-For` address
  /// instead of the proxy's — otherwise every client shares one bucket.
  static bool get rateLimitTrustProxy =>
      EnvConfig.get('RATE_LIMIT_TRUST_PROXY') == 'true';

  // Message Status Types
  static String get messageStatusSent => 'sent';
  static String get messageStatusDelivered => 'delivered';
  static String get messageStatusRead => 'read';

  // WebRTC / Call Configuration
  // STUN servers help peers discover their public IPs; TURN (coturn) relays
  // media when a direct peer-to-peer connection is blocked by NAT/firewalls.
  static List<String> get stunServers {
    final stun = EnvConfig.get('STUN_SERVERS');
    if (stun != null && stun.isNotEmpty) {
      return stun.split(',').map((e) => e.trim()).toList();
    }
    return [
      'stun:stun.l.google.com:19302',
      'stun:stun1.l.google.com:19302',
    ];
  }

  static String? get turnServerUrl => EnvConfig.get('TURN_SERVER_URL');
  static String? get turnUsername => EnvConfig.get('TURN_USERNAME');
  static String? get turnCredential => EnvConfig.get('TURN_CREDENTIAL');

  // Message Types
  static String get messageTypeText => 'text';
  static String get messageTypeImage => 'image';
  static String get messageTypeVideo => 'video';
  static String get messageTypeAudio => 'audio';
  static String get messageTypeDocument => 'document';

  // Push Notifications (FCM legacy HTTP API; optional)
  static String get fcmEndpoint =>
      EnvConfig.get('FCM_ENDPOINT') ?? 'https://fcm.googleapis.com/fcm/send';
  static String? get fcmServerKey => EnvConfig.get('FCM_SERVER_KEY');

  // Firebase Authentication
  // Project ID bound to Firebase ID tokens: tokens whose audience/issuer do
  // not match are rejected (Google signs tokens for ALL Firebase projects
  // with the same keys, so the signature alone proves nothing).
  static String get firebaseProjectId =>
      EnvConfig.getRequired('FIREBASE_PROJECT_ID');

  // TLS
  static String? get tlsCertPath => EnvConfig.get('TLS_CERT_PATH');
  static String? get tlsKeyPath => EnvConfig.get('TLS_KEY_PATH');
}
