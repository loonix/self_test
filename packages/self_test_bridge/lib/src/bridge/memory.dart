part of '../bridge_service.dart';

/// Heap, image cache and widget rebuild profiling.
extension _BridgeMemory on SelfTestBridge {
  /// The memory commands.
  ///
  /// Returns [_unhandled] for a command this group does not
  /// own, which is how the dispatcher walks on to the next.
  Future<Object?> _memoryCommands(BridgeCommand command) async {
    final params = command.params;
    switch (command.command) {
      case 'profileRebuildsStart':
        return _startRebuildProfiling();

      case 'profileRebuildsStop':
        return _stopRebuildProfiling();

      case 'profileRebuildsReport':
        final threshold = params['threshold'] as int? ?? 1;
        return _getRebuildReport(threshold);

      // =====================================================================
      // SEMANTIC LABEL AUTO-GENERATION
      // =====================================================================

      case 'memorySnapshot':
        return _getMemorySnapshot();

      case 'memoryProfileStart':
        final intervalMs = params['intervalMs'] as int? ?? 1000;
        _startMemoryProfiling(intervalMs: intervalMs);
        return {'profiling': true};

      case 'memoryProfileStop':
        return _stopMemoryProfiling();

      case 'forceGc':
        return await _forceGc();

      case 'imageCacheStats':
        return _getImageCacheStats();

      case 'clearImageCache':
        return _clearImageCache();

      case 'memoryLeakCheck':
        final action = params['action'] as String;
        final iterations = params['iterations'] as int? ?? 5;
        return await _memoryLeakCheck(action, iterations);

      // =====================================================================
      // WIDGET TEST GENERATION
      // =====================================================================

      default:
        return _unhandled;
    }
  }

  // ===========================================================================
  // MEMORY PROFILING IMPLEMENTATIONS
  // ===========================================================================

  /// Get current memory usage snapshot
  Map<String, dynamic> _getMemorySnapshot() {
    final imageCache = PaintingBinding.instance.imageCache;

    return {
      'heapUsed': _getHeapUsage(),
      'heapCapacity': _getHeapCapacity(),
      'externalUsage': _getExternalUsage(),
      'imageCache': {
        'count': imageCache.currentSize,
        'sizeBytes': imageCache.currentSizeBytes,
      },
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
  }

  /// Start memory profiling at specified intervals
  void _startMemoryProfiling({int intervalMs = 1000}) {
    // Starting twice used to drop the first timer on the floor and keep it
    // ticking forever, so the samples came from two interleaved runs.
    if (_isProfilingMemory) return;
    _memorySamples.clear();
    _isProfilingMemory = true;

    _memoryProfilingTimer = Timer.periodic(Duration(milliseconds: intervalMs), (
      _,
    ) {
      _memorySamples.add(
        _MemorySample(timestamp: DateTime.now(), heapUsed: _getHeapUsage()),
      );
    });

    _logConsole('info', 'Memory profiling started (interval: ${intervalMs}ms)');
  }

  /// Stop memory profiling and return results
  Map<String, dynamic> _stopMemoryProfiling() {
    _isProfilingMemory = false;
    _memoryProfilingTimer?.cancel();
    _memoryProfilingTimer = null;

    if (_memorySamples.isEmpty) {
      return {
        'samples': <Map<String, dynamic>>[],
        'peak': 0,
        'average': 0,
        'leakSuspects': <String>[],
      };
    }

    final heapValues = _memorySamples.map((s) => s.heapUsed).toList();
    final peak = heapValues.reduce((a, b) => a > b ? a : b);
    final average = heapValues.reduce((a, b) => a + b) ~/ heapValues.length;

    // Simple leak detection: check if memory is monotonically increasing
    final leakSuspects = <String>[];
    if (_isMonotonicallyIncreasing(heapValues)) {
      leakSuspects.add(
        'Possible memory leak: heap usage continuously increasing',
      );
    }

    // Check for significant growth (more than 20% increase from start to end)
    if (heapValues.length > 1 && heapValues.first > 0) {
      final growthRate =
          (heapValues.last - heapValues.first) / heapValues.first;
      if (growthRate > 0.2) {
        leakSuspects.add(
          'Significant memory growth: ${(growthRate * 100).toStringAsFixed(1)}% increase',
        );
      }
    }

    _logConsole(
      'info',
      'Memory profiling stopped: ${_memorySamples.length} samples',
    );

    return {
      'samples': _memorySamples.map((s) => s.toJson()).toList(),
      'peak': peak,
      'average': average,
      'leakSuspects': leakSuspects,
    };
  }

  /// Force garbage collection
  Future<Map<String, dynamic>> _forceGc() async {
    final before = _getHeapUsage();

    // Clear image cache to free memory
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();

    // Give GC time to run
    await Future.delayed(const Duration(milliseconds: 100));

    final after = _getHeapUsage();

    _logConsole('info', 'GC requested: $before -> $after bytes');

    return {
      'memoryBefore': before,
      'memoryAfter': after,
      'freed': before - after,
    };
  }

  /// Get image cache statistics
  Map<String, dynamic> _getImageCacheStats() {
    final cache = PaintingBinding.instance.imageCache;
    return {
      'currentSize': cache.currentSize,
      'maximumSize': cache.maximumSize,
      'liveImages': cache.liveImageCount,
      'pendingImages': cache.pendingImageCount,
      'currentSizeBytes': cache.currentSizeBytes,
      'maximumSizeBytes': cache.maximumSizeBytes,
    };
  }

  /// Clear the image cache
  Map<String, dynamic> _clearImageCache() {
    final cache = PaintingBinding.instance.imageCache;
    final sizeBefore = cache.currentSizeBytes;
    final countBefore = cache.currentSize;

    cache.clear();
    cache.clearLiveImages();

    _logConsole(
      'info',
      'Image cache cleared: $countBefore images, $sizeBefore bytes',
    );

    return {'cleared': countBefore, 'freedBytes': sizeBefore};
  }

  /// Run heuristic leak detection by repeating an action
  Future<Map<String, dynamic>> _memoryLeakCheck(
    String action,
    int iterations,
  ) async {
    final manager = SelfTestManager();
    final memoryBefore = _getHeapUsage();
    final samples = <int>[];

    for (int i = 0; i < iterations; i++) {
      // Execute the action
      try {
        final command = BridgeCommand(id: 0, command: action, params: {});
        await _executeCommand(command);
      } catch (e) {
        // Continue even if action fails
        _logConsole('warning', 'Leak check action failed: $e');
      }

      // Wait for animations and GC
      await manager.waitForAnimations();
      await Future.delayed(const Duration(milliseconds: 100));

      // Record memory
      samples.add(_getHeapUsage());
    }

    final memoryAfter = _getHeapUsage();
    final memoryGrowth = memoryAfter - memoryBefore;

    // Analyze for potential leaks
    final potentialLeaks = _isMonotonicallyIncreasing(samples);
    final suspectedWidgets = <String>[];

    // Check growth rate
    if (samples.isNotEmpty && memoryBefore > 0) {
      final growthRate = memoryGrowth / memoryBefore;
      if (growthRate > 0.1) {
        suspectedWidgets.add(
          'High memory growth rate: ${(growthRate * 100).toStringAsFixed(1)}%',
        );
      }
    }

    // Check if memory consistently increases with each iteration
    if (potentialLeaks) {
      suspectedWidgets.add('Memory increases with each iteration of "$action"');
    }

    return {
      'potentialLeaks':
          potentialLeaks ||
          (memoryBefore > 0 && memoryGrowth > memoryBefore * 0.1),
      'memoryGrowth': memoryGrowth,
      'memoryBefore': memoryBefore,
      'memoryAfter': memoryAfter,
      'iterations': iterations,
      'samples': samples,
      'suspectedWidgets': suspectedWidgets,
    };
  }

  /// Get approximate heap usage
  int _getHeapUsage() {
    // In debug/profile mode, we can get some memory info
    // This is approximate - actual heap access requires VM service
    try {
      // Try to get process info if available (dart:io)
      return ProcessInfo.currentRss;
    } catch (_) {
      // Fallback: return 0 if not available
      return 0;
    }
  }

  /// Get approximate heap capacity
  int _getHeapCapacity() {
    try {
      return ProcessInfo.maxRss;
    } catch (_) {
      return 0;
    }
  }

  /// Get external memory usage (estimate from image cache)
  int _getExternalUsage() {
    // External usage is primarily from images and native buffers
    final imageCache = PaintingBinding.instance.imageCache;
    return imageCache.currentSizeBytes;
  }

  /// Check if values are monotonically increasing
  bool _isMonotonicallyIncreasing(List<int> values) {
    if (values.length < 2) return false;
    for (int i = 1; i < values.length; i++) {
      if (values[i] < values[i - 1]) return false;
    }
    return true;
  }

  // ===========================================================================
  // WIDGET REBUILD PROFILING IMPLEMENTATIONS
  // ===========================================================================

  /// Start profiling widget rebuilds.
  ///
  /// Note: The `debugOnRebuildDirtyWidget` callback was removed in recent Flutter versions.
  /// This implementation uses frame callbacks and element tree sampling instead.
  Map<String, dynamic> _startRebuildProfiling() {
    if (_isProfilingRebuilds) {
      return {'success': false, 'error': 'Rebuild profiling is already active'};
    }

    // Clear previous profiling data
    _rebuildProfile.clear();
    _rebuildProfilingStartTime = DateTime.now();
    _isProfilingRebuilds = true;

    // Note: debugOnRebuildDirtyWidget is not available in current Flutter versions.
    // We track widgets using frame callbacks and element tree inspection instead.

    // Set up a frame callback to sample the widget tree periodically
    _rebuildProfilingFrameCallback = (Duration timestamp) {
      if (!_isProfilingRebuilds) return;

      // Schedule next frame callback
      SchedulerBinding.instance.addPostFrameCallback(
        _rebuildProfilingFrameCallback!,
      );

      // Sample elements by walking the tree
      _sampleWidgetTree();
    };

    SchedulerBinding.instance.addPostFrameCallback(
      _rebuildProfilingFrameCallback!,
    );

    _logConsole(
      'info',
      'Widget rebuild profiling started (using frame sampling)',
    );

    return {
      'success': true,
      'startTime': _rebuildProfilingStartTime?.toIso8601String(),
      'note':
          'Using frame-based sampling as debugOnRebuildDirtyWidget is not available',
    };
  }

  /// Sample the widget tree to track widgets.
  void _sampleWidgetTree() {
    try {
      final binding = WidgetsBinding.instance;
      final rootElement = binding.rootElement;
      if (rootElement == null) return;

      // Walk the element tree and track visible widgets
      void visitElement(Element element) {
        final widget = element.widget;
        final widgetType = widget.runtimeType.toString();
        final key = widget.key?.toString() ?? '';
        final widgetId = key.isNotEmpty ? '$widgetType($key)' : widgetType;

        // Track this widget - increment count each time we see it in a frame
        final info = _rebuildProfile.putIfAbsent(
          widgetId,
          () => _RebuildInfo(),
        );
        info.count++;
        info.reasons.add(_inferRebuildReason(element));

        // Try to get the widget location from debug info
        if (info.location == null) {
          info.location = _getWidgetLocation(element);
        }

        element.visitChildren(visitElement);
      }

      visitElement(rootElement);
    } catch (e) {
      // Silently ignore errors during sampling
    }
  }

  /// Stop profiling widget rebuilds and return results.
  Map<String, dynamic> _stopRebuildProfiling() {
    if (!_isProfilingRebuilds) {
      return {'error': 'Rebuild profiling is not active'};
    }

    _isProfilingRebuilds = false;
    final endTime = DateTime.now();
    final durationMs = _rebuildProfilingStartTime != null
        ? endTime.difference(_rebuildProfilingStartTime!).inMilliseconds
        : 0;

    // Clear the frame callback
    _rebuildProfilingFrameCallback = null;

    // Calculate totals
    int totalRebuilds = 0;
    for (final info in _rebuildProfile.values) {
      totalRebuilds += info.count;
    }

    // Convert to JSON-serializable format
    final widgets = <String, Map<String, dynamic>>{};
    for (final entry in _rebuildProfile.entries) {
      widgets[entry.key] = entry.value.toJson();
    }

    _logConsole(
      'info',
      'Widget rebuild profiling stopped. Total rebuilds: $totalRebuilds, Unique widgets: ${_rebuildProfile.length}',
    );

    return {
      'durationMs': durationMs,
      'totalRebuilds': totalRebuilds,
      'uniqueWidgets': _rebuildProfile.length,
      'widgets': widgets,
    };
  }

  /// Get detailed rebuild report with optional threshold filtering.
  Map<String, dynamic> _getRebuildReport(int threshold) {
    // Calculate totals
    int totalRebuilds = 0;
    for (final info in _rebuildProfile.values) {
      totalRebuilds += info.count;
    }

    // Filter and sort widgets by rebuild count
    final filtered = _rebuildProfile.entries
        .where((e) => e.value.count >= threshold)
        .toList();
    filtered.sort((a, b) => b.value.count.compareTo(a.value.count));

    // Convert to list format with widget ID included
    final widgets = filtered.map((entry) {
      final json = entry.value.toJson();
      json['widgetId'] = entry.key;
      return json;
    }).toList();

    return {
      'isActive': _isProfilingRebuilds,
      'totalRebuilds': totalRebuilds,
      'matchingWidgets': widgets.length,
      'widgets': widgets,
    };
  }

  /// Infer the reason for a widget rebuild based on element state.
  String _inferRebuildReason(Element element) {
    // Check if this is a StatefulElement
    if (element is StatefulElement) {
      // This could be due to setState being called
      return 'setState';
    }

    // Check for InheritedWidget dependencies
    try {
      // If the element depends on inherited widgets, it might have rebuilt
      // due to dependency changes
      final dependencies = element.debugGetDiagnosticChain();
      for (final diagnostic in dependencies) {
        final name = diagnostic.toStringShort();
        if (name.contains('InheritedWidget') || name.contains('Provider')) {
          return 'InheritedWidget/Provider changed';
        }
      }
    } catch (_) {
      // Ignore errors when accessing debug info
    }

    // Check for parent rebuilds
    Element? parent;
    element.visitAncestorElements((ancestor) {
      parent = ancestor;
      return false; // Stop at first ancestor
    });

    if (parent != null) {
      return 'Parent rebuilt';
    }

    return 'Unknown';
  }

  /// Get the source location of a widget if available from debug info.
  String? _getWidgetLocation(Element element) {
    try {
      // Try to get location from widget's toStringShort which sometimes includes it
      final diagnostics = element.toDiagnosticsNode();
      final properties = diagnostics.getProperties();

      for (final prop in properties) {
        if (prop.name == 'creationLocation' || prop.name == 'location') {
          return prop.value?.toString();
        }
      }

      // Try to extract from the diagnostic chain
      final chain = element.debugGetDiagnosticChain();
      for (final node in chain) {
        final nodeStr = node.toStringDeep();
        // Look for file:line patterns
        final match = RegExp(
          r'package:[^\s]+\.dart:\d+:\d+',
        ).firstMatch(nodeStr);
        if (match != null) {
          return match.group(0);
        }
      }
    } catch (_) {
      // Ignore errors when accessing debug info
    }
    return null;
  }
}
