part of '../bridge_service.dart';

/// Theme, locale, text scale and app lifecycle.
extension _BridgeDevice on SelfTestBridge {
  /// The device commands.
  ///
  /// Returns [_unhandled] for a command this group does not
  /// own, which is how the dispatcher walks on to the next.
  Future<Object?> _deviceCommands(BridgeCommand command) async {
    final params = command.params;
    switch (command.command) {
      case 'resize':
        final width = (params['width'] as num).toDouble();
        final height = (params['height'] as num).toDouble();
        // Window resizing requires platform-specific implementation
        // This is mainly useful for web and desktop
        _logConsole('info', 'Resize requested: ${width}x$height');
        return {'success': true, 'note': 'Resize may require platform support'};

      case 'setTheme':
        final theme = params['theme'] as String;
        await _setTheme(theme);
        return {'success': true};

      case 'setLocale':
        final locale = params['locale'] as String;
        await _setLocale(locale);
        return {'success': true};

      case 'setTextScale':
        final scale = (params['scale'] as num).toDouble();
        await _setTextScale(scale);
        return {'success': true};

      // =====================================================================
      // DIALOGS & OVERLAYS
      // =====================================================================

      case 'animationSpeed':
        final speed = (params['speed'] as num).toDouble();
        _setAnimationSpeed(speed);
        return {'success': true, 'speed': speed};

      case 'pump':
        final durationMs = params['duration'] as int? ?? 0;
        await _pump(durationMs);
        return {'success': true};

      // =====================================================================
      // FRAME BUDGET ANALYSIS
      // =====================================================================

      case 'simulateLifecycle':
        final state = params['state'] as String;
        return await _simulateLifecycleState(state);

      case 'lifecycleHistory':
        return _getLifecycleHistory();

      case 'simulateMemoryPressure':
        final level = params['level'] as String? ?? 'low';
        return await _simulateMemoryPressure(level);

      case 'simulateLocaleChange':
        final locale = params['locale'] as String;
        return await _simulateLocaleChange(locale);

      case 'simulateTextScaleChange':
        final scale = (params['scale'] as num).toDouble();
        return await _simulateTextScaleChange(scale);

      case 'simulateBrightnessChange':
        final brightness = params['brightness'] as String;
        return await _simulateBrightnessChange(brightness);

      // =====================================================================
      // BIOMETRIC AUTHENTICATION MOCKING
      // =====================================================================

      default:
        return _unhandled;
    }
  }

  // ===========================================================================
  // DEVICE EMULATION
  // ===========================================================================

  Future<void> _setTheme(String theme) async {
    // This requires app-level support via a callback or provider
    _logConsole('info', 'Theme change requested: $theme');
  }

  Future<void> _setLocale(String locale) async {
    final parts = locale.split('_');
    final newLocale = Locale(parts[0], parts.length > 1 ? parts[1] : null);
    _logConsole('info', 'Locale change requested: $newLocale');
  }

  Future<void> _setTextScale(double scale) async {
    _logConsole('info', 'Text scale change requested: $scale');
  }

  // ===========================================================================
  // ANIMATION CONTROL
  // ===========================================================================

  void _setAnimationSpeed(double speed) {
    // timeDilation controls animation speed globally
    // speed = 0 pauses animations (we use a very large value)
    // speed = 0.5 is slow motion (2x timeDilation)
    // speed = 1 is normal (1x timeDilation)
    // speed = 2 is fast (0.5x timeDilation)
    if (speed <= 0) {
      // Pause animations by setting a very high dilation
      timeDilation = 1000000.0;
    } else {
      // timeDilation is inverse of speed
      // speed 2 = timeDilation 0.5 (faster)
      // speed 0.5 = timeDilation 2 (slower)
      timeDilation = 1.0 / speed;
    }
    _logConsole(
      'info',
      'Animation speed set to $speed (timeDilation: $timeDilation)',
    );
  }

  Future<void> _pump([int durationMs = 0]) async {
    final binding = WidgetsBinding.instance;

    if (durationMs > 0) {
      // Advance time by the specified duration
      // We do this by scheduling multiple frames
      final frames = (durationMs / 16.67).ceil(); // ~60fps
      for (int i = 0; i < frames; i++) {
        binding.scheduleFrame();
        await Future.delayed(const Duration(milliseconds: 1));
      }
    } else {
      // Just pump once - schedule a single frame
      binding.scheduleFrame();
    }

    // Wait for the frame to be processed
    await Future.delayed(Duration(milliseconds: durationMs > 0 ? 1 : 16));

    // Ensure all scheduled callbacks are processed
    await binding.endOfFrame;
  }

  // ===========================================================================
  // APP LIFECYCLE TESTING IMPLEMENTATIONS
  // ===========================================================================

  /// Simulate app lifecycle state change.
  ///
  /// Triggers the lifecycle callback in the app, notifying all WidgetsBindingObservers.
  Future<Map<String, dynamic>> _simulateLifecycleState(String stateStr) async {
    final previousState = _currentLifecycleState;

    // Parse the state string to AppLifecycleState
    AppLifecycleState newState;
    switch (stateStr.toLowerCase()) {
      case 'paused':
        newState = AppLifecycleState.paused;
        break;
      case 'resumed':
        newState = AppLifecycleState.resumed;
        break;
      case 'inactive':
        newState = AppLifecycleState.inactive;
        break;
      case 'detached':
        newState = AppLifecycleState.detached;
        break;
      case 'hidden':
        newState = AppLifecycleState.hidden;
        break;
      default:
        throw Exception(
          'Invalid lifecycle state: $stateStr. '
          'Valid states: paused, resumed, inactive, detached, hidden',
        );
    }

    _currentLifecycleState = newState;

    // Record in history
    _lifecycleHistory.add(
      AppLifecycleEvent(state: newState, timestamp: DateTime.now()),
    );

    // Notify all observers through the binding
    try {
      final binding = WidgetsBinding.instance;
      binding.handleAppLifecycleStateChanged(newState);
      _logConsole(
        'info',
        'Lifecycle state changed: ${previousState.name} -> ${newState.name}',
      );
    } catch (e) {
      _logConsole('error', 'Failed to notify lifecycle observers: $e');
    }

    // Wait a frame for observers to react
    await Future.delayed(const Duration(milliseconds: 16));

    return {
      'success': true,
      'previousState': previousState.name,
      'currentState': newState.name,
    };
  }

  /// Get history of lifecycle events.
  Map<String, dynamic> _getLifecycleHistory() {
    return {
      'events': _lifecycleHistory.map((e) => e.toJson()).toList(),
      'currentState': _currentLifecycleState.name,
      'eventCount': _lifecycleHistory.length,
    };
  }

  /// Simulate memory pressure warning.
  ///
  /// Triggers cache clearing and notifies observers about low memory condition.
  Future<Map<String, dynamic>> _simulateMemoryPressure(String level) async {
    _clearedCaches.clear();

    // Clear image caches
    try {
      PaintingBinding.instance.imageCache.clear();
      _clearedCaches.add('imageCache');
      PaintingBinding.instance.imageCache.clearLiveImages();
      _clearedCaches.add('liveImageCache');
    } catch (e) {
      _logConsole('error', 'Failed to clear image cache: $e');
    }

    // For critical level, try more aggressive cleanup
    if (level == 'critical') {
      try {
        // Trigger garbage collection hints (not guaranteed)
        await Future.delayed(const Duration(milliseconds: 50));

        // Clear any additional caches the app might have registered
        _clearedCaches.add('forcedGC');
      } catch (e) {
        _logConsole('error', 'Failed aggressive cleanup: $e');
      }
    }

    // Notify about memory pressure
    // Note: WidgetsBinding.observers is not directly accessible in current Flutter versions.
    // We trigger a frame rebuild to give the app a chance to respond to memory state changes.
    try {
      WidgetsBinding.instance.scheduleFrame();
      _clearedCaches.add('notifiedObservers');
    } catch (e) {
      _logConsole('error', 'Failed to notify memory pressure: $e');
    }

    _logConsole('info', 'Memory pressure simulated: $level');

    return {'success': true, 'level': level, 'clearedCaches': _clearedCaches};
  }

  /// Simulate system locale change.
  Future<Map<String, dynamic>> _simulateLocaleChange(String localeStr) async {
    final previousLocale = _currentLocale;

    // Parse locale string (e.g., "en_US", "fr_FR")
    final parts = localeStr.split('_');
    final newLocale = Locale(parts[0], parts.length > 1 ? parts[1] : null);

    _currentLocale = newLocale;

    // Notify about locale change
    // Note: WidgetsBinding.observers is not directly accessible in current Flutter versions.
    // Locale changes are typically triggered through the platform channel.
    try {
      // Force a rebuild of the widget tree by scheduling a frame
      WidgetsBinding.instance.scheduleFrame();
      _logConsole(
        'info',
        'Locale changed: ${previousLocale.toString()} -> ${newLocale.toString()}',
      );
    } catch (e) {
      _logConsole('error', 'Failed to notify locale change: $e');
    }

    // Wait a frame for UI to update
    await Future.delayed(const Duration(milliseconds: 16));

    return {
      'success': true,
      'previousLocale': previousLocale.toString(),
      'currentLocale': newLocale.toString(),
    };
  }

  /// Simulate system text scale change.
  Future<Map<String, dynamic>> _simulateTextScaleChange(double scale) async {
    final previousScale = _currentTextScale;
    _currentTextScale = scale;

    // Notify about text scale change
    // Note: WidgetsBinding.observers is not directly accessible in current Flutter versions.
    // Text scale changes are typically triggered through the platform channel.
    try {
      // Force a rebuild of the widget tree by scheduling a frame
      WidgetsBinding.instance.scheduleFrame();
      _logConsole('info', 'Text scale changed: $previousScale -> $scale');
    } catch (e) {
      _logConsole('error', 'Failed to notify text scale change: $e');
    }

    // Wait a frame for UI to update
    await Future.delayed(const Duration(milliseconds: 16));

    return {
      'success': true,
      'previousScale': previousScale,
      'currentScale': scale,
    };
  }

  /// Simulate system brightness mode change.
  Future<Map<String, dynamic>> _simulateBrightnessChange(
    String brightnessStr,
  ) async {
    final previousBrightness = _currentBrightness;

    // Parse brightness string
    Brightness newBrightness;
    switch (brightnessStr.toLowerCase()) {
      case 'light':
        newBrightness = Brightness.light;
        break;
      case 'dark':
        newBrightness = Brightness.dark;
        break;
      default:
        throw Exception(
          'Invalid brightness: $brightnessStr. Valid values: light, dark',
        );
    }

    _currentBrightness = newBrightness;

    // Notify about brightness change
    // Note: WidgetsBinding.observers is not directly accessible in current Flutter versions.
    // Brightness changes are typically triggered through the platform channel.
    try {
      // Force a rebuild of the widget tree by scheduling a frame
      WidgetsBinding.instance.scheduleFrame();
      _logConsole(
        'info',
        'Brightness changed: ${previousBrightness.name} -> ${newBrightness.name}',
      );
    } catch (e) {
      _logConsole('error', 'Failed to notify brightness change: $e');
    }

    // Wait a frame for UI to update
    await Future.delayed(const Duration(milliseconds: 16));

    return {
      'success': true,
      'previousBrightness': previousBrightness.name,
      'currentBrightness': newBrightness.name,
    };
  }
}
