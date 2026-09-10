import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// HTTP mock response configuration.
class MockResponse {
  /// HTTP status code to return.
  final int status;

  /// Response body (can be Map, List, String, etc.).
  final dynamic body;

  /// Optional response headers.
  final Map<String, String>? headers;

  /// Optional delay before returning the response.
  final Duration? delay;

  const MockResponse({
    this.status = 200,
    this.body,
    this.headers,
    this.delay,
  });

  factory MockResponse.fromJson(Map<String, dynamic> json) {
    return MockResponse(
      status: json['status'] as int? ?? 200,
      body: json['body'],
      headers: (json['headers'] as Map<String, dynamic>?)?.map(
        (k, v) => MapEntry(k, v.toString()),
      ),
      delay: json['delay'] != null
          ? Duration(milliseconds: json['delay'] as int)
          : null,
    );
  }
}

/// Network request log entry.
class NetworkLogEntry {
  final String method;
  final String url;
  final Map<String, dynamic>? requestHeaders;
  final dynamic requestBody;
  final int? statusCode;
  final Map<String, dynamic>? responseHeaders;
  final dynamic responseBody;
  final String? error;
  final DateTime timestamp;
  final Duration? duration;
  final bool wasMocked;
  final bool wasBlocked;

  NetworkLogEntry({
    required this.method,
    required this.url,
    this.requestHeaders,
    this.requestBody,
    this.statusCode,
    this.responseHeaders,
    this.responseBody,
    this.error,
    required this.timestamp,
    this.duration,
    this.wasMocked = false,
    this.wasBlocked = false,
  });

  Map<String, dynamic> toJson() => {
        'method': method,
        'url': url,
        'requestHeaders': requestHeaders,
        'requestBody': requestBody,
        'statusCode': statusCode,
        'responseHeaders': responseHeaders,
        'responseBody': responseBody,
        'error': error,
        'timestamp': timestamp.toIso8601String(),
        'durationMs': duration?.inMilliseconds,
        'wasMocked': wasMocked,
        'wasBlocked': wasBlocked,
      };
}

/// Dio interceptor that applies HTTP mocks stored in the SelfTestBridge.
///
/// This interceptor:
/// 1. Checks if request URL matches any pattern in the mocks map
/// 2. Checks if request URL matches any blocked pattern
/// 3. If blocked, rejects with an error
/// 4. If mocked, returns the mock response (status, body, headers, optional delay)
/// 5. Logs all requests to the network log
/// 6. Notifies pending network wait completers when matching requests complete
/// 7. Supports glob patterns (*, **) and regex patterns
class SelfTestHttpInterceptor extends Interceptor {
  /// HTTP mocks map: pattern -> mock response config.
  final Map<String, Map<String, dynamic>> _httpMocks;

  /// Blocked URL patterns.
  final Set<String> _blockedPatterns;

  /// Network request log.
  final List<Map<String, dynamic>> _networkLog;

  /// Pending network wait completers: pattern -> completer.
  final Map<String, Completer<Map<String, dynamic>>> _pendingNetworkWaits;

  /// Request start times for duration calculation.
  final Map<RequestOptions, DateTime> _requestStartTimes = {};

  /// Create a new interceptor instance.
  ///
  /// The parameters are references to the bridge's internal state,
  /// allowing the interceptor to read mocks and write logs.
  SelfTestHttpInterceptor({
    required Map<String, Map<String, dynamic>> httpMocks,
    required Set<String> blockedPatterns,
    required List<Map<String, dynamic>> networkLog,
    required Map<String, Completer<Map<String, dynamic>>> pendingNetworkWaits,
  })  : _httpMocks = httpMocks,
        _blockedPatterns = blockedPatterns,
        _networkLog = networkLog,
        _pendingNetworkWaits = pendingNetworkWaits;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    final url = options.uri.toString();
    _requestStartTimes[options] = DateTime.now();

    debugPrint('[SelfTestHttpInterceptor] Request: ${options.method} $url');

    // Check if URL is blocked
    final blockedPattern = _findMatchingPattern(url, _blockedPatterns);
    if (blockedPattern != null) {
      debugPrint(
          '[SelfTestHttpInterceptor] Blocked by pattern: $blockedPattern');

      final logEntry = NetworkLogEntry(
        method: options.method,
        url: url,
        requestHeaders: options.headers.map((k, v) => MapEntry(k, v)),
        requestBody: options.data,
        error: 'Request blocked by pattern: $blockedPattern',
        timestamp: DateTime.now(),
        wasBlocked: true,
      );
      _addToNetworkLog(logEntry);

      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.cancel,
          error: 'Request blocked by test: $blockedPattern',
          message: 'Request to $url was blocked by pattern: $blockedPattern',
        ),
      );
      return;
    }

    // Check if URL matches a mock
    final mockPattern = _findMatchingPattern(url, _httpMocks.keys.toSet());
    if (mockPattern != null) {
      final mockConfig = _httpMocks[mockPattern]!;
      final mockResponse = MockResponse.fromJson(mockConfig);

      debugPrint('[SelfTestHttpInterceptor] Mocked by pattern: $mockPattern');

      _handleMockResponse(options, mockResponse, mockPattern, handler);
      return;
    }

    // No mock or block, proceed with actual request
    handler.next(options);
  }

  @override
  void onResponse(
    Response response,
    ResponseInterceptorHandler handler,
  ) {
    final startTime = _requestStartTimes.remove(response.requestOptions);
    final duration =
        startTime != null ? DateTime.now().difference(startTime) : null;

    final logEntry = NetworkLogEntry(
      method: response.requestOptions.method,
      url: response.requestOptions.uri.toString(),
      requestHeaders:
          response.requestOptions.headers.map((k, v) => MapEntry(k, v)),
      requestBody: response.requestOptions.data,
      statusCode: response.statusCode,
      responseHeaders:
          response.headers.map.map((k, v) => MapEntry(k, v.join(', '))),
      responseBody: response.data,
      timestamp: DateTime.now(),
      duration: duration,
    );
    _addToNetworkLog(logEntry);

    handler.next(response);
  }

  @override
  void onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) {
    final startTime = _requestStartTimes.remove(err.requestOptions);
    final duration =
        startTime != null ? DateTime.now().difference(startTime) : null;

    final logEntry = NetworkLogEntry(
      method: err.requestOptions.method,
      url: err.requestOptions.uri.toString(),
      requestHeaders: err.requestOptions.headers.map((k, v) => MapEntry(k, v)),
      requestBody: err.requestOptions.data,
      statusCode: err.response?.statusCode,
      responseHeaders:
          err.response?.headers.map.map((k, v) => MapEntry(k, v.join(', '))),
      responseBody: err.response?.data,
      error: err.message ?? err.error?.toString(),
      timestamp: DateTime.now(),
      duration: duration,
    );
    _addToNetworkLog(logEntry);

    handler.next(err);
  }

  /// Handle a mocked response.
  Future<void> _handleMockResponse(
    RequestOptions options,
    MockResponse mockResponse,
    String matchedPattern,
    RequestInterceptorHandler handler,
  ) async {
    // Apply optional delay
    if (mockResponse.delay != null) {
      await Future.delayed(mockResponse.delay!);
    }

    final startTime = _requestStartTimes.remove(options);
    final duration =
        startTime != null ? DateTime.now().difference(startTime) : null;

    // Build response headers
    final headers = Headers();
    if (mockResponse.headers != null) {
      mockResponse.headers!.forEach((key, value) {
        headers.add(key, value);
      });
    }
    // Add default content-type if not specified
    if (!headers.map.containsKey('content-type')) {
      if (mockResponse.body is Map || mockResponse.body is List) {
        headers.add('content-type', 'application/json');
      } else {
        headers.add('content-type', 'text/plain');
      }
    }

    final response = Response(
      requestOptions: options,
      statusCode: mockResponse.status,
      data: mockResponse.body,
      headers: headers,
    );

    final logEntry = NetworkLogEntry(
      method: options.method,
      url: options.uri.toString(),
      requestHeaders: options.headers.map((k, v) => MapEntry(k, v)),
      requestBody: options.data,
      statusCode: mockResponse.status,
      responseHeaders: headers.map.map((k, v) => MapEntry(k, v.join(', '))),
      responseBody: mockResponse.body,
      timestamp: DateTime.now(),
      duration: duration,
      wasMocked: true,
    );
    _addToNetworkLog(logEntry);

    // Check if this is an error status code
    if (mockResponse.status >= 400) {
      handler.reject(
        DioException(
          requestOptions: options,
          response: response,
          type: DioExceptionType.badResponse,
          error: 'Mocked error response',
        ),
      );
    } else {
      handler.resolve(response);
    }
  }

  /// Add entry to network log and notify pending waiters.
  void _addToNetworkLog(NetworkLogEntry entry) {
    final entryJson = entry.toJson();
    _networkLog.add(entryJson);

    // Notify any pending network wait completers
    final waitersToComplete = <String>[];
    for (final pattern in _pendingNetworkWaits.keys) {
      if (_matchesPattern(entry.url, pattern)) {
        waitersToComplete.add(pattern);
      }
    }

    for (final pattern in waitersToComplete) {
      final completer = _pendingNetworkWaits.remove(pattern);
      if (completer != null && !completer.isCompleted) {
        completer.complete(entryJson);
      }
    }
  }

  /// Find the first pattern that matches the URL.
  String? _findMatchingPattern(String url, Set<String> patterns) {
    for (final pattern in patterns) {
      if (_matchesPattern(url, pattern)) {
        return pattern;
      }
    }
    return null;
  }

  /// Check if a URL matches a pattern.
  ///
  /// Supports:
  /// - Simple string contains matching
  /// - Glob patterns (* for single segment, ** for multiple segments)
  /// - Regex patterns (prefixed with "regex:")
  bool _matchesPattern(String url, String pattern) {
    // Handle regex patterns
    if (pattern.startsWith('regex:')) {
      try {
        final regex = RegExp(pattern.substring(6));
        return regex.hasMatch(url);
      } catch (e) {
        debugPrint('[SelfTestHttpInterceptor] Invalid regex pattern: $pattern');
        return false;
      }
    }

    // Handle glob patterns
    if (pattern.contains('*')) {
      final regexPattern = _globToRegex(pattern);
      try {
        final regex = RegExp(regexPattern);
        return regex.hasMatch(url);
      } catch (e) {
        debugPrint('[SelfTestHttpInterceptor] Invalid glob pattern: $pattern');
        return false;
      }
    }

    // Simple contains matching
    return url.contains(pattern);
  }

  /// Convert a glob pattern to a regex pattern.
  ///
  /// - ** matches any characters (including /)
  /// - * matches any characters except /
  /// - Other special regex characters are escaped
  String _globToRegex(String glob) {
    final buffer = StringBuffer();

    // Escape regex special characters except * and **
    for (int i = 0; i < glob.length; i++) {
      final char = glob[i];

      if (char == '*') {
        // Check for **
        if (i + 1 < glob.length && glob[i + 1] == '*') {
          buffer.write('.*'); // ** matches everything
          i++; // Skip the next *
        } else {
          buffer.write('[^/]*'); // * matches everything except /
        }
      } else if (_isRegexSpecialChar(char)) {
        buffer.write('\\$char');
      } else {
        buffer.write(char);
      }
    }

    return buffer.toString();
  }

  /// Check if a character is a regex special character (except *).
  bool _isRegexSpecialChar(String char) {
    return '.+?^|\${}[]()\\'.contains(char);
  }
}
