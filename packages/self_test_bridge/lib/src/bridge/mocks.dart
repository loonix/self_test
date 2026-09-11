part of '../bridge_service.dart';

/// Permissions, sensors, biometrics, notifications and channels.
extension _BridgeMocks on SelfTestBridge {
  /// The mocks commands.
  ///
  /// Returns [_unhandled] for a command this group does not
  /// own, which is how the dispatcher walks on to the next.
  Future<Object?> _mocksCommands(BridgeCommand command) async {
    final params = command.params;
    switch (command.command) {
      case 'mockChannel':
        final channel = params['channel'] as String;
        final method = params['method'] as String;
        final response = params['response'];
        final errorCode = params['errorCode'] as String?;
        final errorMessage = params['errorMessage'] as String?;
        _mockChannel(channel, method, response, errorCode, errorMessage);
        return {'success': true};

      case 'clearChannelMocks':
        final channel = params['channel'] as String?;
        _clearChannelMocks(channel);
        return {'success': true};

      case 'channelLog':
        final channel = params['channel'] as String?;
        final limit = params['limit'] as int? ?? 50;
        final clear = params['clear'] as bool? ?? false;
        return _getChannelLog(channel, limit, clear);

      // =====================================================================
      // STATE MANAGEMENT INSPECTION
      // =====================================================================

      case 'setGeolocation':
        return _setGeolocation(params);

      case 'setPermission':
        return _setPermission(params);

      case 'setConnectivity':
        return _setConnectivity(params);

      // =====================================================================
      // TIME-TRAVEL STATE SNAPSHOTS
      // =====================================================================

      case 'setBiometricAvailability':
        return _setBiometricAvailability(params);

      case 'setBiometricResult':
        return _setBiometricResult(params);

      case 'biometricAuthHistory':
        return _getBiometricAuthHistory();

      case 'simulateBiometricPrompt':
        final reason = params['reason'] as String;
        final type = params['type'] as String?;
        return await _simulateBiometricPrompt(reason, type);

      case 'clearBiometricConfig':
        return _clearBiometricConfig();

      // =====================================================================
      // MEMORY PROFILING
      // =====================================================================

      case BridgeCommands.simulatePushNotification:
        final title = params['title'] as String;
        final body = params['body'] as String;
        final data = params['data'] as Map<String, dynamic>?;
        final action = params['action'] as String? ?? 'received';
        final delay = params['delay'] as int?;
        return await _simulatePushNotification(
          title: title,
          body: body,
          data: data,
          action: action,
          delayMs: delay,
        );

      case BridgeCommands.simulateNotificationTap:
        final notificationId = params['notificationId'] as String;
        final actionId = params['actionId'] as String?;
        return await _simulateNotificationTap(notificationId, actionId);

      case BridgeCommands.notificationHistory:
        return _getNotificationHistory();

      case BridgeCommands.setNotificationHandler:
        final onReceive = params['onReceive'] as bool?;
        final onTap = params['onTap'] as bool?;
        final onDismiss = params['onDismiss'] as bool?;
        return _setNotificationHandler(
          onReceive: onReceive,
          onTap: onTap,
          onDismiss: onDismiss,
        );

      case BridgeCommands.clearNotifications:
        return _clearNotifications();

      case BridgeCommands.getFcmToken:
        return _getFcmToken();

      // =====================================================================
      // NAVIGATION STACK INSPECTOR
      // =====================================================================

      default:
        return _unhandled;
    }
  }

  // ===========================================================================
  // PLATFORM CHANNEL MOCKING
  // ===========================================================================

  /// Initialize platform channel mocking by setting up mock method call handlers
  void _initializeChannelMocking() {
    if (_channelMockingInitialized) return;
    _channelMockingInitialized = true;
    _logConsole('info', 'Platform channel mocking initialized');
  }

  /// Mock a platform channel method with specified response
  void _mockChannel(
    String channel,
    String method,
    dynamic response,
    String? errorCode,
    String? errorMessage,
  ) {
    _initializeChannelMocking();

    // Get or create the channel's method mocks
    final channelMocks = _channelMocks.putIfAbsent(channel, () => {});

    // Store the mock configuration
    channelMocks[method] = _ChannelMockConfig(
      response: response,
      errorCode: errorCode,
      errorMessage: errorMessage,
    );

    // Set up the mock handler for this channel
    _setupChannelHandler(channel);

    _logConsole('info', 'Mocked $channel:$method');
  }

  /// Set up a mock handler for a specific channel
  void _setupChannelHandler(String channel) {
    const codec = StandardMethodCodec();

    // Set the message handler on the binary messenger
    ServicesBinding.instance.defaultBinaryMessenger.setMessageHandler(channel, (
      ByteData? message,
    ) async {
      if (message == null) return null;

      final methodCall = codec.decodeMethodCall(message);
      final timestamp = DateTime.now().toIso8601String();

      // Log the call
      _channelCallLog.add({
        'channel': channel,
        'method': methodCall.method,
        'arguments': methodCall.arguments,
        'timestamp': timestamp,
      });

      // Check if we have a mock for this method
      final channelMocks = _channelMocks[channel];
      if (channelMocks != null && channelMocks.containsKey(methodCall.method)) {
        final config = channelMocks[methodCall.method]!;

        // Update the log entry with the result
        _channelCallLog.last['mocked'] = true;

        // If error is configured, encode PlatformException
        if (config.errorCode != null) {
          _channelCallLog.last['error'] = config.errorCode;
          return codec.encodeErrorEnvelope(
            code: config.errorCode!,
            message: config.errorMessage,
          );
        }

        // Return the mocked response
        _channelCallLog.last['result'] = config.response;
        return codec.encodeSuccessEnvelope(config.response);
      }

      // No mock found, mark as passthrough and return null
      // This allows the original handler to be called
      _channelCallLog.last['mocked'] = false;
      return null;
    });
  }

  /// Clear all channel mocks or mocks for a specific channel
  void _clearChannelMocks(String? channel) {
    if (channel != null) {
      // Clear mocks for specific channel
      _channelMocks.remove(channel);
      ServicesBinding.instance.defaultBinaryMessenger.setMessageHandler(
        channel,
        null,
      );
      _logConsole('info', 'Cleared mocks for channel: $channel');
    } else {
      // Clear all mocks
      for (final ch in _channelMocks.keys.toList()) {
        ServicesBinding.instance.defaultBinaryMessenger.setMessageHandler(
          ch,
          null,
        );
      }
      _channelMocks.clear();
      _logConsole('info', 'Cleared all channel mocks');
    }
  }

  /// Get the channel call log
  Map<String, dynamic> _getChannelLog(String? channel, int limit, bool clear) {
    var calls = _channelCallLog.toList();

    // Filter by channel if specified
    if (channel != null) {
      calls = calls.where((c) => c['channel'] == channel).toList();
    }

    // Reverse to get most recent first and apply limit
    final result = calls.reversed.take(limit).toList();

    if (clear) {
      if (channel != null) {
        _channelCallLog.removeWhere((c) => c['channel'] == channel);
      } else {
        _channelCallLog.clear();
      }
    }

    return {'calls': result};
  }

  // ===========================================================================
  // SENSOR & DEVICE MOCKING IMPLEMENTATIONS
  // ===========================================================================

  /// Set mock geolocation
  Map<String, dynamic> _setGeolocation(Map<String, dynamic> params) {
    final location = MockLocation.fromJson(params);
    _mockLocation = location;

    // Invoke the callback if registered
    if (SelfTestBridge.onLocationChanged != null) {
      SelfTestBridge.onLocationChanged!(location);
    }

    _logConsole(
      'info',
      'Mock location set: (${location.latitude}, ${location.longitude})',
    );

    return {'success': true, 'location': location.toJson()};
  }

  /// Set mock permission state
  Map<String, dynamic> _setPermission(Map<String, dynamic> params) {
    final permissionStr = params['permission'] as String;
    final stateStr = params['state'] as String;

    final permission = MockPermissionType.fromString(permissionStr);
    final state = MockPermissionState.fromString(stateStr);

    _mockPermissions[permission] = state;

    _logConsole('info', 'Mock permission set: $permissionStr = $stateStr');

    return {'success': true, 'permission': permissionStr, 'state': stateStr};
  }

  /// Set mock connectivity state
  Map<String, dynamic> _setConnectivity(Map<String, dynamic> params) {
    final connectivity = MockConnectivity.fromJson(params);
    _mockConnectivity = connectivity;

    // Invoke the callback if registered
    if (SelfTestBridge.onConnectivityChanged != null) {
      SelfTestBridge.onConnectivityChanged!(connectivity);
    }

    _logConsole(
      'info',
      'Mock connectivity set: ${connectivity.state.name} (connected: ${connectivity.isConnected})',
    );

    return {'success': true, 'connectivity': connectivity.toJson()};
  }

  // ===========================================================================
  // BIOMETRIC AUTHENTICATION MOCKING IMPLEMENTATIONS
  // ===========================================================================

  /// Set which biometric types are available
  Map<String, dynamic> _setBiometricAvailability(Map<String, dynamic> params) {
    if (params['faceId'] != null) {
      _biometricFaceIdAvailable = params['faceId'] as bool;
    }
    if (params['touchId'] != null) {
      _biometricTouchIdAvailable = params['touchId'] as bool;
    }
    if (params['fingerprint'] != null) {
      _biometricFingerprintAvailable = params['fingerprint'] as bool;
    }
    if (params['iris'] != null) {
      _biometricIrisAvailable = params['iris'] as bool;
    }
    if (params['deviceCredential'] != null) {
      _biometricDeviceCredentialAvailable = params['deviceCredential'] as bool;
    }

    final available = getAvailableBiometrics();
    _logConsole('info', 'Biometric availability set: $available');

    return {'available': available};
  }

  /// Set what the next biometric auth will return
  Map<String, dynamic> _setBiometricResult(Map<String, dynamic> params) {
    final resultStr = params['result'] as String;
    _nextBiometricResult = MockBiometricResult.fromString(resultStr);
    _nextBiometricErrorMessage = params['errorMessage'] as String?;
    _nextBiometricDelay = (params['delay'] as int?) ?? 0;

    _logConsole(
      'info',
      'Biometric result configured: $_nextBiometricResult'
          '${_nextBiometricErrorMessage != null ? ' (error: $_nextBiometricErrorMessage)' : ''}'
          '${_nextBiometricDelay > 0 ? ' (delay: ${_nextBiometricDelay}ms)' : ''}',
    );

    return {'configured': true};
  }

  /// Get history of biometric authentication attempts
  Map<String, dynamic> _getBiometricAuthHistory() {
    return {'attempts': _biometricHistory.map((a) => a.toJson()).toList()};
  }

  /// Simulate a biometric prompt and get the configured result
  Future<Map<String, dynamic>> _simulateBiometricPrompt(
    String reason,
    String? type,
  ) async {
    // Apply configured delay
    if (_nextBiometricDelay > 0) {
      await Future.delayed(Duration(milliseconds: _nextBiometricDelay));
    }

    final biometricType = type ?? 'fingerprint';
    final resultStr = _nextBiometricResult.name;
    final success = _nextBiometricResult == MockBiometricResult.success;

    // Record the attempt
    final attempt = BiometricAttempt(
      timestamp: DateTime.now(),
      type: biometricType,
      result: resultStr,
      reason: reason,
    );
    _biometricHistory.add(attempt);

    _logConsole(
      'info',
      'Biometric auth attempt: $biometricType, result: $resultStr, reason: $reason',
    );

    // Trigger callback if set
    if (SelfTestBridge.onBiometricAuth != null) {
      try {
        await SelfTestBridge.onBiometricAuth!(reason);
      } catch (e) {
        _logConsole('error', 'Biometric auth callback error: $e');
      }
    }

    return {
      'success': success,
      if (success) 'authenticatedAs': 'user',
      if (!success) 'error': _nextBiometricErrorMessage ?? resultStr,
    };
  }

  /// Clear biometric configuration and reset to defaults
  Map<String, dynamic> _clearBiometricConfig() {
    _biometricFaceIdAvailable = false;
    _biometricTouchIdAvailable = false;
    _biometricFingerprintAvailable = false;
    _biometricIrisAvailable = false;
    _biometricDeviceCredentialAvailable = true;
    _nextBiometricResult = MockBiometricResult.success;
    _nextBiometricErrorMessage = null;
    _nextBiometricDelay = 0;
    _biometricHistory.clear();

    _logConsole('info', 'Biometric configuration cleared');

    return {'cleared': true};
  }

  // ===========================================================================
  // PUSH NOTIFICATION MOCKING IMPLEMENTATION
  // ===========================================================================

  /// Simulate receiving a push notification.
  ///
  /// Creates a mock notification with the given parameters and triggers
  /// the appropriate callbacks based on the action type.
  Future<Map<String, dynamic>> _simulatePushNotification({
    required String title,
    required String body,
    Map<String, dynamic>? data,
    String action = 'received',
    int? delayMs,
  }) async {
    // Apply delay if specified
    if (delayMs != null && delayMs > 0) {
      await Future.delayed(Duration(milliseconds: delayMs));
    }

    // Generate notification ID
    final notificationId = 'notif_${++_notificationIdCounter}';

    // Create the notification
    final notification = MockNotification(
      id: notificationId,
      title: title,
      body: body,
      data: data,
      action: action,
    );

    // Add to history
    _notificationHistory.add(notification);

    // Trigger appropriate callbacks based on action
    switch (action) {
      case 'received':
        if (_notificationOnReceiveEnabled) {
          SelfTestBridge.onNotificationReceived?.call(notification);
        }
        break;
      case 'tap':
        if (_notificationOnTapEnabled) {
          SelfTestBridge.onNotificationTap?.call(notification);
        }
        // Handle deep link navigation if present
        final deepLink = data?['deep_link'] as String?;
        if (deepLink != null) {
          await navigator?.goTo(deepLink);
        }
        break;
      case 'dismiss':
        if (_notificationOnDismissEnabled) {
          SelfTestBridge.onNotificationDismiss?.call(notification);
        }
        break;
    }

    _logConsole('info', 'Simulated notification: $title ($action)');

    return {'success': true, 'notificationId': notificationId};
  }

  /// Simulate user tapping a notification.
  ///
  /// Finds the notification by ID and triggers the tap callback.
  /// If the notification has a deep_link in its data, navigates to it.
  Future<Map<String, dynamic>> _simulateNotificationTap(
    String notificationId,
    String? actionId,
  ) async {
    // Find the notification
    final index = _notificationHistory.indexWhere(
      (n) => n.id == notificationId,
    );
    if (index == -1) {
      return {
        'success': false,
        'error': 'Notification not found: $notificationId',
      };
    }

    final notification = _notificationHistory[index];
    notification.action = 'tap';

    // Trigger tap callback
    if (_notificationOnTapEnabled) {
      SelfTestBridge.onNotificationTap?.call(notification);
    }

    // Handle deep link navigation
    String? navigatedTo;
    final deepLink = notification.data['deep_link'] as String?;
    if (deepLink != null && navigator != null) {
      navigatedTo = deepLink;
      await navigator!.goTo(deepLink);
      await SelfTestManager().waitForAnimations();
    }

    _logConsole('info', 'Notification tapped: ${notification.title}');

    return {'success': true, 'navigatedTo': navigatedTo};
  }

  /// Get history of simulated notifications.
  Map<String, dynamic> _getNotificationHistory() {
    return {
      'notifications': _notificationHistory
          .map(
            (n) => {
              'id': n.id,
              'title': n.title,
              'body': n.body,
              'data': n.data,
              'timestamp': n.timestamp.millisecondsSinceEpoch,
              'action': n.action,
            },
          )
          .toList(),
      'count': _notificationHistory.length,
    };
  }

  /// Set notification handler flags.
  Map<String, dynamic> _setNotificationHandler({
    bool? onReceive,
    bool? onTap,
    bool? onDismiss,
  }) {
    final handlersSet = <String>[];

    if (onReceive != null) {
      _notificationOnReceiveEnabled = onReceive;
      if (onReceive) handlersSet.add('onReceive');
    }
    if (onTap != null) {
      _notificationOnTapEnabled = onTap;
      if (onTap) handlersSet.add('onTap');
    }
    if (onDismiss != null) {
      _notificationOnDismissEnabled = onDismiss;
      if (onDismiss) handlersSet.add('onDismiss');
    }

    return {
      'handlersSet': handlersSet,
      'onReceive': _notificationOnReceiveEnabled,
      'onTap': _notificationOnTapEnabled,
      'onDismiss': _notificationOnDismissEnabled,
    };
  }

  /// Clear notification history.
  Map<String, dynamic> _clearNotifications() {
    final count = _notificationHistory.length;
    _notificationHistory.clear();
    _notificationIdCounter = 0;

    return {'cleared': count};
  }

  /// Get mock FCM token.
  ///
  /// Returns a consistent mock token for the session.
  /// The token is generated once and reused for subsequent calls.
  Map<String, dynamic> _getFcmToken() {
    _mockFcmToken ??= 'mock_fcm_token_${DateTime.now().millisecondsSinceEpoch}';
    return {'token': _mockFcmToken};
  }
}
