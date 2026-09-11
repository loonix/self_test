part of '../bridge_service.dart';

/// Frame timing and the frame budget.
extension _BridgeProfiling on SelfTestBridge {
  /// The profiling commands.
  ///
  /// Returns [_unhandled] for a command this group does not
  /// own, which is how the dispatcher walks on to the next.
  Future<Object?> _profilingCommands(BridgeCommand command) async {
    final params = command.params;
    switch (command.command) {
      case 'frameProfilingStart':
        final budgetMs = (params['budgetMs'] as num?)?.toDouble() ?? 16.67;
        _startFrameProfiling(budgetMs: budgetMs);
        return {'success': true, 'budgetMs': budgetMs};

      case 'frameProfilingStop':
        return _stopFrameProfiling();

      case 'frameBudgetCheck':
        final action = params['action'] as String;
        final widgetId = params.containsKey('locator')
            ? _targetId(params)
            : params['widgetId'] as String?;
        final actionParams = params['params'] as Map<String, dynamic>? ?? {};
        final budgetMs = (params['budgetMs'] as num?)?.toDouble() ?? 16.67;
        return await _frameBudgetCheck(
          action,
          widgetId,
          actionParams,
          budgetMs,
        );

      case 'jankDetector':
        final enabled = params['enabled'] as bool;
        final threshold = (params['threshold'] as num?)?.toDouble() ?? 16.67;
        final callback = params['callback'] as bool? ?? enabled;
        return _setJankDetector(enabled, threshold, callback);

      // =====================================================================
      // PLATFORM CHANNEL MOCKING
      // =====================================================================

      default:
        return _unhandled;
    }
  }

  // ===========================================================================
  // ===========================================================================
  // FRAME BUDGET ANALYSIS IMPLEMENTATIONS
  // ===========================================================================

  /// Callback for frame timings during profiling
  void _onFrameTimings(List<FrameTiming> timings) {
    if (_isProfilingFrames) {
      _frameTimings.addAll(timings);
    }

    // Handle jank detection if enabled
    if (_jankDetectorEnabled) {
      for (final timing in timings) {
        _jankDetectorTotalFrames++;
        final durationMs = timing.totalSpan.inMicroseconds / 1000.0;
        if (durationMs > _jankThresholdMs) {
          _jankDetectorJankyFrames++;
          if (durationMs > _jankDetectorWorstFrameMs) {
            _jankDetectorWorstFrameMs = durationMs;
          }
          _logConsole(
            'warning',
            'Jank detected: frame took ${durationMs.toStringAsFixed(2)}ms (threshold: ${_jankThresholdMs}ms)',
          );
        }
      }
    }
  }

  /// Start frame timing profiling
  void _startFrameProfiling({double? budgetMs}) {
    _frameTimings.clear();
    _frameBudgetMs = budgetMs ?? 16.67;
    _isProfilingFrames = true;

    // Register the frame timings callback
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);

    _logConsole(
      'info',
      'Frame profiling started (budget: ${_frameBudgetMs}ms)',
    );
  }

  /// Stop frame profiling and return results
  Map<String, dynamic> _stopFrameProfiling() {
    _isProfilingFrames = false;
    SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);

    if (_frameTimings.isEmpty) {
      return {
        'totalFrames': 0,
        'jankyFrames': 0,
        'averageMs': 0.0,
        'p50Ms': 0.0,
        'p95Ms': 0.0,
        'p99Ms': 0.0,
        'worstFrame': null,
        'histogram': {'0-8ms': 0, '8-16ms': 0, '16-32ms': 0, '32ms+': 0},
      };
    }

    // Convert frame timings to durations in milliseconds
    final durations = _frameTimings
        .map((t) => t.totalSpan.inMicroseconds / 1000.0)
        .toList();

    // Sort for percentile calculations
    durations.sort();

    // Calculate statistics
    final totalFrames = durations.length;
    final jankyFrames = durations.where((d) => d > _frameBudgetMs).length;
    final average = durations.reduce((a, b) => a + b) / totalFrames;

    // Find worst frame
    double worstDuration = 0;
    int worstIndex = 0;
    for (int i = 0; i < _frameTimings.length; i++) {
      final duration = _frameTimings[i].totalSpan.inMicroseconds / 1000.0;
      if (duration > worstDuration) {
        worstDuration = duration;
        worstIndex = i;
      }
    }

    // Calculate histogram
    final histogram = {
      '0-8ms': durations.where((d) => d < 8).length,
      '8-16ms': durations.where((d) => d >= 8 && d < 16).length,
      '16-32ms': durations.where((d) => d >= 16 && d < 32).length,
      '32ms+': durations.where((d) => d >= 32).length,
    };

    _logConsole(
      'info',
      'Frame profiling stopped: $totalFrames frames, $jankyFrames janky',
    );

    return {
      'totalFrames': totalFrames,
      'jankyFrames': jankyFrames,
      'averageMs': average,
      'p50Ms': _percentile(durations, 50),
      'p95Ms': _percentile(durations, 95),
      'p99Ms': _percentile(durations, 99),
      'worstFrame': {'index': worstIndex, 'durationMs': worstDuration},
      'histogram': histogram,
    };
  }

  /// Calculate percentile from sorted list
  double _percentile(List<double> sortedList, int percentile) {
    if (sortedList.isEmpty) return 0.0;
    final index = ((percentile / 100) * (sortedList.length - 1)).round();
    return sortedList[index.clamp(0, sortedList.length - 1)];
  }

  /// Profile a specific action and return frame analysis
  Future<Map<String, dynamic>> _frameBudgetCheck(
    String action,
    String? widgetId,
    Map<String, dynamic> actionParams,
    double budgetMs,
  ) async {
    // Start profiling
    _startFrameProfiling(budgetMs: budgetMs);

    final stopwatch = Stopwatch()..start();

    try {
      // Execute the action
      switch (action) {
        case 'scroll':
          final direction = actionParams['direction'] as String? ?? 'down';
          final delta = (actionParams['delta'] as num?)?.toDouble() ?? 300.0;
          await _scroll(widgetId, direction, delta);
          break;

        case 'tap':
          if (widgetId == null) {
            throw Exception('widgetId required for tap action');
          }
          final manager = SelfTestManager();
          await _waitForWidget(widgetId, 5000);
          await manager.trigger(widgetId);
          await manager.waitForAnimations();
          break;

        case 'navigate':
          final route = actionParams['route'] as String?;
          final target = navigator;
          if (route != null && target != null) {
            await target.goTo(route);
            await SelfTestManager().waitForAnimations();
          }
          break;

        case 'type':
          if (widgetId == null) {
            throw Exception('widgetId required for type action');
          }
          final text = actionParams['text'] as String? ?? '';
          final manager = SelfTestManager();
          await manager.enterText(widgetId, text);
          await manager.waitForAnimations();
          break;

        case 'drag':
          final sourceId = actionParams['sourceId'] as String?;
          final targetId = actionParams['targetId'] as String?;
          if (sourceId != null && targetId != null) {
            await _drag(sourceId, targetId);
          }
          break;

        default:
          throw Exception('Unknown action: $action');
      }

      // Wait a bit for frames to settle
      await Future.delayed(const Duration(milliseconds: 100));
    } finally {
      stopwatch.stop();
    }

    // Get profiling results
    final results = _stopFrameProfiling();

    // Add action duration
    results['actionDuration'] = stopwatch.elapsedMicroseconds / 1000.0;
    results['action'] = action;
    results['widgetId'] = widgetId;

    return results;
  }

  /// Enable or disable continuous jank monitoring
  Map<String, dynamic> _setJankDetector(
    bool enabled,
    double threshold,
    bool callback,
  ) {
    final previousState = _jankDetectorEnabled;

    if (enabled && !previousState) {
      // Enable jank detection
      _jankDetectorEnabled = true;
      _jankThresholdMs = threshold;
      _jankDetectorTotalFrames = 0;
      _jankDetectorJankyFrames = 0;
      _jankDetectorWorstFrameMs = 0;

      // Register callback if not already profiling
      if (!_isProfilingFrames) {
        SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
      }

      _logConsole('info', 'Jank detector enabled (threshold: ${threshold}ms)');

      return {
        'enabled': true,
        'threshold': threshold,
        'statistics': {'totalFrames': 0, 'jankyFrames': 0, 'jankRate': 0.0},
      };
    } else if (!enabled && previousState) {
      // Disable jank detection
      _jankDetectorEnabled = false;

      // Remove callback if not profiling
      if (!_isProfilingFrames) {
        SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
      }

      final jankRate = _jankDetectorTotalFrames > 0
          ? (_jankDetectorJankyFrames / _jankDetectorTotalFrames) * 100
          : 0.0;

      _logConsole('info', 'Jank detector disabled');

      return {
        'enabled': false,
        'statistics': {
          'totalFrames': _jankDetectorTotalFrames,
          'jankyFrames': _jankDetectorJankyFrames,
          'jankRate': jankRate,
          'worstFrameMs': _jankDetectorWorstFrameMs,
        },
      };
    }

    // Return current state if no change
    final jankRate = _jankDetectorTotalFrames > 0
        ? (_jankDetectorJankyFrames / _jankDetectorTotalFrames) * 100
        : 0.0;

    return {
      'enabled': _jankDetectorEnabled,
      'threshold': _jankThresholdMs,
      'statistics': {
        'totalFrames': _jankDetectorTotalFrames,
        'jankyFrames': _jankDetectorJankyFrames,
        'jankRate': jankRate,
        'worstFrameMs': _jankDetectorWorstFrameMs,
      },
    };
  }
}
