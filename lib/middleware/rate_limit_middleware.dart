import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';

import '../config/app_config.dart';

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
/// When `RATE_LIMIT_TRUST_PROXY=true` is configured, the client address is
/// taken from the left-most `X-Forwarded-For` entry so that deployments behind
/// a reverse proxy (ngrok, nginx, cloud LB) don't funnel every client into a
/// single bucket. Otherwise the socket's remote address is used.
Middleware rateLimitMiddleware(RateLimiter limiter) {
  return (Handler innerHandler) {
    return (Request request) async {
      final ip = _clientAddress(request);

      if (!limiter.allow(ip)) {
        return Response(
          429,
          body: jsonEncode({
            'error': 'Too many requests. Please try again later.',
          }),
          headers: {
            'Content-Type': 'application/json',
            'Retry-After': '${limiter.window.inSeconds}',
          },
        );
      }

      return innerHandler(request);
    };
  };
}

String _clientAddress(Request request) {
  if (AppConfig.rateLimitTrustProxy) {
    final forwarded = request.headers['x-forwarded-for'];
    if (forwarded != null && forwarded.isNotEmpty) {
      final first = forwarded.split(',').first.trim();
      if (first.isNotEmpty) return first;
    }
  }

  final connectionInfo = request.context['shelf.io.connection_info'];
  return connectionInfo is HttpConnectionInfo
      ? connectionInfo.remoteAddress.address
      : 'unknown';
}
