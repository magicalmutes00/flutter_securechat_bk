import 'dart:io';

/// Environment variable loader for SecureChat Server
/// Supports loading from .env file and system environment variables

class EnvConfig {
  static final Map<String, String> _env = {};
  static bool _loaded = false;

  /// Load environment from .env file
  static Future<void> load({String path = '.env'}) async {
    if (_loaded) return;

    try {
      final file = File(path);
      if (await file.exists()) {
        final contents = await file.readAsString();
        for (final line in contents.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

          final eqIndex = trimmed.indexOf('=');
          if (eqIndex > 0) {
            final key = trimmed.substring(0, eqIndex).trim();
            var value = trimmed.substring(eqIndex + 1).trim();

            if ((value.startsWith('"') && value.endsWith('"')) ||
                (value.startsWith("'") && value.endsWith("'"))) {
              value = value.substring(1, value.length - 1);
            }

            _env[key] = value;
          }
        }
      }
    } catch (_) {
      // Fall back to system env vars only
    }
    _loaded = true;
  }

  /// Get environment variable value
  static String? get(String key, {String? defaultValue}) {
    return _env[key] ?? Platform.environment[key] ?? defaultValue;
  }

  /// Get required environment variable (throws if not found)
  static String getRequired(String key) {
    final value = get(key);
    if (value == null || value.isEmpty) {
      throw EnvironmentError('Required environment variable "$key" is not set');
    }
    return value;
  }
}

class EnvironmentError extends Error {
  final String message;
  EnvironmentError(this.message);
  @override
  String toString() => message;
}
