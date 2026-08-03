import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';

/// A simple in-memory fixed-window rate limiter keyed by an arbitrary string
/// (typically the client IP address).
class RateLimiter {
  final int maxRequests;
  final Duration window;

  final Map<String, List<DateTime>> _hits = {};

  RateLimiter({required this.maxRequests, required this.window});

  /// Returns true if [key] is within the allowed limit for the current window.
  bool allow(String key) {
    final now = DateTime.now();
    final hits = _hits.putIfAbsent(key, () => []);

    hits.removeWhere((t) => now.difference(t) > window);

    if (hits.length >= maxRequests) {
      return false;
    }

    hits.add(now);
    return true;
  }
}

/// Shelf middleware that rate-limits requests by the client's IP address.
///
/// Requests that exceed the limit receive HTTP 429.
Middleware rateLimitMiddleware(RateLimiter limiter) {
  return (Handler innerHandler) {
    return (Request request) async {
      final connectionInfo = request.context['shelf.io.connection_info'];
      final ip = connectionInfo is HttpConnectionInfo
          ? connectionInfo.remoteAddress.address
          : 'unknown';

      if (!limiter.allow(ip)) {
        return Response(
          429,
          body: jsonEncode({
            'error': 'Too many requests. Please try again later.',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      return innerHandler(request);
    };
  };
}
