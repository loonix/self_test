part of '../bridge_service.dart';

/// The socket, the handshake and the command loop.
extension _BridgeServer on SelfTestBridge {
  /// Runs [command] against each group of commands in turn.
  ///
  /// This was one switch with 208 cases in a 7000-line file, which meant every
  /// concern's implementation sat a thousand lines from the case that called
  /// it. Each group now owns its own commands and lives next to them, and
  /// answers [_unhandled] for anything it does not recognise.
  ///
  /// The order is the order an agent works in, so the commands used on every
  /// step are matched first.
  Future<dynamic> _executeCommand(BridgeCommand command) async {
    for (final group in <Future<Object?> Function(BridgeCommand)>[
      _discoveryCommands,
      _actionsCommands,
      _navigationCommands,
      _assertionsCommands,
      _goldensCommands,
      _networkCommands,
      _storageCommands,
      _deviceCommands,
      _mocksCommands,
      _profilingCommands,
      _memoryCommands,
      _stateCommands,
      _timeTravelCommands,
      _accessibilityCommands,
      _testRecordingCommands,
    ]) {
      final result = await group(command);
      if (!identical(result, _unhandled)) return result;
    }
    throw Exception('Unknown command: ${command.command}');
  }

  /// Check the token, then upgrade.
  ///
  /// The check happens before the upgrade so a client with the wrong token
  /// gets an HTTP 403 it can read, rather than a WebSocket that closes for no
  /// stated reason.
  Future<void> _handleRequest(HttpRequest request) async {
    if (!_isAuthorised(request)) {
      debugPrint(
        '[SelfTestBridge] Rejected a connection with a bad or missing token',
      );
      request.response
        ..statusCode = HttpStatus.forbidden
        ..write('self_test bridge: bad or missing token');
      await request.response.close();
      return;
    }

    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('self_test bridge: expected a WebSocket upgrade');
      await request.response.close();
      return;
    }

    _handleConnection(await WebSocketTransformer.upgrade(request));
  }

  bool _isAuthorised(HttpRequest request) {
    final presented =
        request.uri.queryParameters['token'] ??
        request.headers.value('x-self-test-token');
    if (presented == null) return false;
    return _secretsMatch(presented, token);
  }

  /// Handle a new WebSocket connection
  void _handleConnection(WebSocket socket) {
    debugPrint('[SelfTestBridge] Client connected');
    _clients.add(socket);

    socket.listen(
      (data) async {
        try {
          final command = BridgeCommand.fromJson(jsonDecode(data as String));
          final response = await _handleCommand(command);
          socket.add(jsonEncode(response.toJson()));
        } catch (e, stackTrace) {
          debugPrint('[SelfTestBridge] Error handling command: $e');
          debugPrint(stackTrace.toString());
          socket.add(jsonEncode({'id': 0, 'error': e.toString()}));
        }
      },
      onDone: () {
        debugPrint('[SelfTestBridge] Client disconnected');
        _clients.remove(socket);
      },
      onError: (error) {
        debugPrint('[SelfTestBridge] Client error: $error');
        _clients.remove(socket);
      },
    );
  }

  Future<BridgeResponse> _handleCommand(BridgeCommand command) async {
    debugPrint('[SelfTestBridge] Handling command: ${command.command}');

    // Record trace event if tracing
    if (_isTracing) {
      _traceEvents.add({
        'timestamp': DateTime.now().toIso8601String(),
        'command': command.command,
        'params': command.params,
      });
    }

    try {
      final result = await _executeCommand(command);
      if (_interactionCommands.contains(command.command)) {
        await _afterInteraction(command.command, command.params);
      }
      return BridgeResponse(id: command.id, result: result);
    } catch (e) {
      return BridgeResponse(id: command.id, error: e.toString());
    }
  }

  /// Runs after a command that changed the app, once it has succeeded.
  Future<void> _afterInteraction(
    String action,
    Map<String, dynamic> params,
  ) async {
    await _onUserInteraction();
    _recordInteractionStep(action, params);
  }

  // HELPERS
  // ===========================================================================

  void _captureError(FlutterErrorDetails details) {
    _errors.add({
      'type': details.exception.runtimeType.toString(),
      'message': details.exceptionAsString(),
      'stackTrace': details.stack?.toString(),
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  void _logConsole(String level, String message) {
    _consoleMessages.add({
      'level': level,
      'message': message,
      'timestamp': DateTime.now().toIso8601String(),
    });
    debugPrint('[$level] $message');
  }
}
