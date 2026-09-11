part of '../bridge_service.dart';

/// HTTP mocking, the request log, console and tracing.
extension _BridgeNetwork on SelfTestBridge {
  /// The network commands.
  ///
  /// Returns [_unhandled] for a command this group does not
  /// own, which is how the dispatcher walks on to the next.
  Future<Object?> _networkCommands(BridgeCommand command) async {
    final params = command.params;
    switch (command.command) {
      case 'mockHttp':
        final urlPattern = params['urlPattern'] as String;
        final response = params['response'] as Map<String, dynamic>;
        _httpMocks[urlPattern] = response;
        return {'success': true};

      case 'blockHttp':
        final urlPattern = params['urlPattern'] as String;
        _blockedPatterns.add(urlPattern);
        return {'success': true};

      case 'clearMocks':
        _httpMocks.clear();
        _blockedPatterns.clear();
        return {'success': true};

      case 'networkLog':
        final limit = params['limit'] as int? ?? 50;
        return {'requests': _networkLog.take(limit).toList()};

      case 'waitNetwork':
        final urlPattern = params['urlPattern'] as String;
        final timeout = params['timeout'] as int? ?? 10000;
        return await _waitForNetwork(urlPattern, timeout);

      // =====================================================================
      // CONSOLE & ERRORS
      // =====================================================================

      case 'console':
        final level = params['level'] as String? ?? 'all';
        final limit = params['limit'] as int? ?? 100;
        final clear = params['clear'] as bool? ?? false;

        var messages = _consoleMessages;
        if (level != 'all') {
          messages = messages.where((m) => m['level'] == level).toList();
        }
        messages = messages.take(limit).toList();

        if (clear) {
          _consoleMessages.clear();
        }

        return {'messages': messages};

      case 'errors':
        final clear = params['clear'] as bool? ?? false;
        final errors = List<Map<String, dynamic>>.from(_errors);
        if (clear) {
          _errors.clear();
        }
        return {'errors': errors};

      // =====================================================================
      // TRACING
      // =====================================================================

      case 'traceStart':
        final name = params['name'] as String? ?? 'trace';
        final screenshots = params['screenshots'] as bool? ?? false;
        _isTracing = true;
        _traceName = name;
        _traceScreenshots = screenshots;
        _traceEvents.clear();
        _traceEvents.add({
          'type': 'trace_start',
          'timestamp': DateTime.now().toIso8601String(),
          'name': name,
        });
        return {'success': true};

      case 'traceStop':
        _isTracing = false;
        _traceEvents.add({
          'type': 'trace_end',
          'timestamp': DateTime.now().toIso8601String(),
        });

        // Save trace to file
        final filepath = await _saveTrace();
        return {'filepath': filepath, 'events': _traceEvents.length};

      // =====================================================================
      // DEVICE EMULATION
      // =====================================================================

      case 'harExport':
        return _harExport();

      // =====================================================================
      // ANIMATION CONTROL
      // =====================================================================

      default:
        return _unhandled;
    }
  }

  // ===========================================================================
  // NETWORK
  // ===========================================================================

  Future<Map<String, dynamic>> _waitForNetwork(
    String urlPattern,
    int timeout,
  ) async {
    final completer = Completer<Map<String, dynamic>>();
    _pendingNetworkWaits[urlPattern] = completer;

    // Check if already in log
    for (final req in _networkLog) {
      if (_matchesPattern(req['url'] as String, urlPattern)) {
        _pendingNetworkWaits.remove(urlPattern);
        return req;
      }
    }

    // Wait with timeout
    return completer.future.timeout(
      Duration(milliseconds: timeout),
      onTimeout: () {
        _pendingNetworkWaits.remove(urlPattern);
        throw Exception('Timeout waiting for request matching $urlPattern');
      },
    );
  }

  bool _matchesPattern(String url, String pattern) {
    if (pattern.contains('*')) {
      final regex = RegExp(pattern.replaceAll('*', '.*'));
      return regex.hasMatch(url);
    }
    return url.contains(pattern);
  }

  // ===========================================================================
  // HAR EXPORT
  // ===========================================================================

  Map<String, dynamic> _harExport() {
    // Generate HAR 1.2 format from network log
    final har = <String, dynamic>{
      'log': {
        'version': '1.2',
        'creator': {'name': 'SelfTestBridge', 'version': '2.0.0'},
        'entries': _networkLog.map((req) {
          final startTime =
              DateTime.tryParse(req['timestamp'] as String? ?? '') ??
              DateTime.now();
          final response = req['response'] as Map<String, dynamic>?;
          final responseTime =
              DateTime.tryParse(response?['timestamp'] as String? ?? '') ??
              startTime;
          final waitTime = responseTime.difference(startTime).inMilliseconds;

          return {
            'startedDateTime': startTime.toIso8601String(),
            'time': waitTime,
            'request': {
              'method': req['method'] ?? 'GET',
              'url': req['url'] ?? '',
              'httpVersion': 'HTTP/1.1',
              'cookies': <dynamic>[],
              'headers': _convertHeadersToHar(
                req['headers'] as Map<String, dynamic>?,
              ),
              'queryString': _parseQueryString(req['url'] as String?),
              'postData': req['body'] != null
                  ? {
                      'mimeType': req['contentType'] ?? 'application/json',
                      'text': req['body'] is String
                          ? req['body']
                          : jsonEncode(req['body']),
                    }
                  : null,
              'headersSize': -1,
              'bodySize': req['body'] != null
                  ? (req['body'] is String
                        ? (req['body'] as String).length
                        : jsonEncode(req['body']).length)
                  : 0,
            },
            'response': {
              'status': response?['status'] ?? 0,
              'statusText': response?['statusText'] ?? '',
              'httpVersion': 'HTTP/1.1',
              'cookies': <dynamic>[],
              'headers': _convertHeadersToHar(
                response?['headers'] as Map<String, dynamic>?,
              ),
              'content': {
                'size': response?['body'] != null
                    ? (response!['body'] is String
                          ? (response['body'] as String).length
                          : jsonEncode(response['body']).length)
                    : 0,
                'mimeType': response?['contentType'] ?? 'application/json',
                'text': response != null && response['body'] is String
                    ? response['body']
                    : jsonEncode(response?['body'] ?? {}),
              },
              'redirectURL': response?['redirectUrl'] ?? '',
              'headersSize': -1,
              'bodySize': response?['body'] != null
                  ? (response!['body'] is String
                        ? (response['body'] as String).length
                        : jsonEncode(response['body']).length)
                  : 0,
            },
            'cache': <String, dynamic>{},
            'timings': {
              'blocked': 0,
              'dns': -1,
              'connect': -1,
              'send': 0,
              'wait': waitTime,
              'receive': 0,
              'ssl': -1,
            },
          };
        }).toList(),
      },
    };

    return har;
  }

  List<Map<String, dynamic>> _convertHeadersToHar(
    Map<String, dynamic>? headers,
  ) {
    if (headers == null) return [];
    return headers.entries
        .map((e) => {'name': e.key, 'value': e.value?.toString() ?? ''})
        .toList();
  }

  List<Map<String, dynamic>> _parseQueryString(String? url) {
    if (url == null) return [];
    final uri = Uri.tryParse(url);
    if (uri == null) return [];
    return uri.queryParameters.entries
        .map((e) => {'name': e.key, 'value': e.value})
        .toList();
  }
}
