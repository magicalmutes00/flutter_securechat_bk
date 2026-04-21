/// Application configuration for SecureChat Server
/// Sensitive values should be set via environment variables (see .env.example)

import 'env_config.dart';

class AppConfig {
  AppConfig._();

  // Server Configuration
  static String get serverHost => EnvConfig.get('SERVER_HOST') ?? '0.0.0.0';
  static int get serverPort => int.tryParse(EnvConfig.get('SERVER_PORT') ?? '8080') ?? 8080;
  static String get serverBaseUrl => EnvConfig.get('SERVER_BASE_URL') ?? 'http://localhost:8080';

  // WebSocket Configuration
  static String get wsPath => EnvConfig.get('WS_PATH') ?? '/ws';
  static int get wsPingIntervalSeconds => int.tryParse(EnvConfig.get('WS_PING_INTERVAL') ?? '30') ?? 30;
  static int get wsConnectionTimeoutSeconds => int.tryParse(EnvConfig.get('WS_CONNECTION_TIMEOUT') ?? '60') ?? 60;

  // MongoDB Configuration
  static String get mongoHost => EnvConfig.get('MONGO_HOST') ?? 'localhost';
  static int get mongoPort => int.tryParse(EnvConfig.get('MONGO_PORT') ?? '27017') ?? 27017;
  static String get mongoDatabase => EnvConfig.get('MONGO_DATABASE') ?? 'securechat';
  static String get mongoConnectionString => EnvConfig.get('MONGO_CONNECTION_STRING') ?? 'mongodb://localhost:27017/securechat';

  // JWT Configuration (REQUIRED - must be set via environment)
  static String get jwtSecret => EnvConfig.getRequired('JWT_SECRET');
  static String get jwtIssuer => EnvConfig.get('JWT_ISSUER') ?? 'securechat-server';
  static int get jwtAccessTokenExpiryMinutes => int.tryParse(EnvConfig.get('JWT_ACCESS_TOKEN_EXPIRY_MINUTES') ?? '1440') ?? 1440;
  static int get jwtRefreshTokenExpiryDays => int.tryParse(EnvConfig.get('JWT_REFRESH_TOKEN_EXPIRY_DAYS') ?? '30') ?? 30;
  static String get jwtAlgorithm => EnvConfig.get('JWT_ALGORITHM') ?? 'HS256';

  // OTP Configuration (MessageCentral API - REQUIRED)
  static String get messageCentralBaseUrl => EnvConfig.get('MESSAGE_CENTRAL_BASE_URL') ?? 'https://api.messagecentral.com';
  static String get messageCentralApiKey => EnvConfig.getRequired('MESSAGE_CENTRAL_API_KEY');
  static String get messageCentralCustomerId => EnvConfig.getRequired('MESSAGE_CENTRAL_CUSTOMER_ID');
  static int get otpLength => int.tryParse(EnvConfig.get('OTP_LENGTH') ?? '6') ?? 6;
  static int get otpExpiryMinutes => int.tryParse(EnvConfig.get('OTP_EXPIRY_MINUTES') ?? '5') ?? 5;
  static int get otpMaxAttempts => int.tryParse(EnvConfig.get('OTP_MAX_ATTEMPTS') ?? '3') ?? 3;

  // File Upload Configuration
  static String get uploadDirectory => EnvConfig.get('UPLOAD_DIRECTORY') ?? 'uploads';
  static Map<String, String> get uploadFolders => {
    'image': EnvConfig.get('UPLOAD_FOLDER_IMAGES') ?? 'uploads/images',
    'video': EnvConfig.get('UPLOAD_FOLDER_VIDEOS') ?? 'uploads/videos',
    'audio': EnvConfig.get('UPLOAD_FOLDER_AUDIO') ?? 'uploads/audio',
    'document': EnvConfig.get('UPLOAD_FOLDER_DOCS') ?? 'uploads/docs',
  };

  static int get maxFileSizeBytes => int.tryParse(EnvConfig.get('MAX_FILE_SIZE_BYTES') ?? '52428800') ?? 52428800;
  static Map<String, List<String>> get allowedFileExtensions => {
    'image': ['jpg', 'jpeg', 'png', 'gif', 'webp'],
    'video': ['mp4', 'mov', 'avi', 'mkv', 'webm'],
    'audio': ['mp3', 'wav', 'aac', 'm4a', 'ogg'],
    'document': ['pdf', 'doc', 'docx', 'txt', 'xls', 'xlsx', 'ppt', 'pptx'],
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
      'http://127.0.0.1:3000',
      'http://127.0.0.1:8080',
    ];
  }

  // Rate Limiting
  static int get rateLimitMaxRequests => int.tryParse(EnvConfig.get('RATE_LIMIT_MAX_REQUESTS') ?? '100') ?? 100;
  static int get rateLimitWindowMinutes => int.tryParse(EnvConfig.get('RATE_LIMIT_WINDOW_MINUTES') ?? '1') ?? 1;

  // Message Status Types
  static String get messageStatusSent => 'sent';
  static String get messageStatusDelivered => 'delivered';
  static String get messageStatusRead => 'read';

  // Message Types
  static String get messageTypeText => 'text';
  static String get messageTypeImage => 'image';
  static String get messageTypeVideo => 'video';
  static String get messageTypeAudio => 'audio';
  static String get messageTypeDocument => 'document';
}
