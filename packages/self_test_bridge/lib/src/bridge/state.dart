part of '../bridge_service.dart';

/// Inspecting the app state providers.
extension _BridgeState on SelfTestBridge {
  /// The state commands.
  ///
  /// Returns [_unhandled] for a command this group does not
  /// own, which is how the dispatcher walks on to the next.
  Future<Object?> _stateCommands(BridgeCommand command) async {
    final params = command.params;
    switch (command.command) {
      case 'getState':
        final providerId = params['providerId'] as String;
        final path = params['path'] as String?;
        final stateType = params['stateType'] as String? ?? 'auto';
        return await _getState(providerId, path, stateType);

      case 'dispatchAction':
        final providerId = params['providerId'] as String;
        final action = params['action'] as String;
        final payload = params['payload'];
        final stateType = params['stateType'] as String? ?? 'auto';
        return await _dispatchAction(providerId, action, payload, stateType);

      case 'watchState':
        final providerId = params['providerId'] as String;
        final stateType = params['stateType'] as String? ?? 'auto';
        final debounceMs = params['debounceMs'] as int? ?? 100;
        return await _watchState(providerId, stateType, debounceMs);

      case 'getStateChanges':
        final subscriptionId = params['subscriptionId'] as String;
        final clear = params['clear'] as bool? ?? true;
        return _getStateChanges(subscriptionId, clear);

      case 'unwatchState':
        final subscriptionId = params['subscriptionId'] as String;
        _unwatchState(subscriptionId);
        return {'success': true};

      case 'listStateProviders':
        final stateType = params['stateType'] as String? ?? 'all';
        return _listStateProviders(stateType);

      // =====================================================================
      // SENSOR & DEVICE MOCKING
      // =====================================================================

      case 'stateDependencyGraph':
        return _getStateDependencyGraph();

      case 'stateImpactAnalysis':
        final providerId = params['providerId'] as String;
        return _getStateImpactAnalysis(providerId);

      case 'stateTrace':
        final providerId = params['providerId'] as String;
        final widgetId = params['widgetId'] as String?;
        return _getStateTrace(providerId, widgetId);

      case 'orphanStateCheck':
        return _getOrphanStateCheck();

      // =====================================================================
      // WIDGET REBUILD PROFILING
      // =====================================================================

      default:
        return _unhandled;
    }
  }

  Future<Map<String, dynamic>> _getState(
    String providerId,
    String? path,
    String stateType,
  ) async {
    // Try registered providers first
    final provider = _stateProviders[providerId];
    if (provider != null) {
      try {
        var state = provider.getState();

        // Apply path extraction if specified
        if (path != null && path.isNotEmpty) {
          state = _extractPath(state, path);
        }

        return {
          'state': state,
          'stateType': provider.type,
          'metadata': {
            'providerId': providerId,
            'timestamp': DateTime.now().toIso8601String(),
          },
        };
      } catch (e) {
        throw Exception('Failed to get state for $providerId: $e');
      }
    }

    // Try Riverpod if available and stateType allows
    if ((stateType == 'auto' || stateType == 'riverpod') &&
        _riverpodContainer != null) {
      final riverpodState = await _getRiverpodState(providerId, path);
      if (riverpodState != null) {
        return riverpodState;
      }
    }

    throw Exception(
      'State provider "$providerId" not found. '
      'Register it using registerStateProvider() or registerRiverpodContainer().',
    );
  }

  Future<Map<String, dynamic>?> _getRiverpodState(
    String providerId,
    String? path,
  ) async {
    // This requires runtime reflection or code generation to work with Riverpod.
    // For now, we rely on registered providers. Apps can register their Riverpod
    // providers manually using registerStateProvider().
    //
    // A full implementation would require:
    // 1. Access to the ProviderContainer
    // 2. A way to look up providers by name (which Riverpod doesn't provide natively)
    // 3. Reading the current value
    //
    // Apps can integrate this by:
    // ```dart
    // bridge.registerStateProvider(
    //   'userProvider',
    //   type: 'riverpod',
    //   getState: () => ref.read(userProvider).toJson(),
    //   dispatchAction: (action, payload) {
    //     if (action == 'setUser') ref.read(userProvider.notifier).setUser(payload);
    //   },
    // );
    // ```
    return null;
  }

  Map<String, dynamic> _extractPath(Map<String, dynamic> state, String path) {
    // Parse path like 'user.name' or 'items[0].id'
    final segments = path.split('.');
    dynamic current = state;

    for (final segment in segments) {
      if (current == null) {
        throw Exception('Path "$path" not found: null encountered');
      }

      // Check for array access like 'items[0]'
      final arrayMatch = RegExp(r'^(\w+)\[(\d+)\]$').firstMatch(segment);
      if (arrayMatch != null) {
        final key = arrayMatch.group(1)!;
        final index = int.parse(arrayMatch.group(2)!);

        if (current is Map) {
          current = current[key];
        } else {
          throw Exception(
            'Expected map at "$key" but got ${current.runtimeType}',
          );
        }

        if (current is List && index < current.length) {
          current = current[index];
        } else {
          throw Exception('Invalid array access: $segment');
        }
      } else {
        if (current is Map) {
          current = current[segment];
        } else {
          throw Exception(
            'Expected map at "$segment" but got ${current.runtimeType}',
          );
        }
      }
    }

    // Wrap result in a map if it's not already
    if (current is Map<String, dynamic>) {
      return current;
    }
    return {'value': current};
  }

  Future<Map<String, dynamic>> _dispatchAction(
    String providerId,
    String action,
    dynamic payload,
    String stateType,
  ) async {
    final provider = _stateProviders[providerId];
    if (provider == null) {
      throw Exception(
        'State provider "$providerId" not found. '
        'Register it using registerStateProvider() to enable action dispatch.',
      );
    }

    if (provider.dispatchAction == null) {
      throw Exception(
        'State provider "$providerId" does not support action dispatch. '
        'Provide a dispatchAction callback when registering.',
      );
    }

    // Capture state before
    final previousState = provider.getState();

    // Dispatch the action
    provider.dispatchAction!(action, payload);

    // Wait a frame for state to update
    await Future.delayed(const Duration(milliseconds: 16));

    // Capture state after
    final newState = provider.getState();

    return {
      'success': true,
      'providerId': providerId,
      'action': action,
      'previousState': previousState,
      'newState': newState,
    };
  }

  Future<Map<String, dynamic>> _watchState(
    String providerId,
    String stateType,
    int debounceMs,
  ) async {
    final provider = _stateProviders[providerId];
    if (provider == null) {
      throw Exception('State provider "$providerId" not found.');
    }

    // Generate subscription ID
    final subscriptionId = 'watch_${++_subscriptionIdCounter}';

    // Get initial state
    final initialState = provider.getState();

    // Create subscription
    final subscription = _StateWatchSubscription(
      id: subscriptionId,
      providerId: providerId,
      changes: [],
      debounceMs: debounceMs,
    );

    // If provider has a state stream, subscribe to it
    if (provider.stateStream != null) {
      subscription.streamSubscription = provider.stateStream!.listen((state) {
        subscription.changes.add({
          'state': state,
          'timestamp': DateTime.now().toIso8601String(),
        });
      });
    } else {
      // Poll for changes (less efficient but works without streams)
      subscription.pollTimer = Timer.periodic(
        Duration(milliseconds: debounceMs),
        (_) {
          try {
            final currentState = provider.getState();
            final lastState = subscription.changes.isNotEmpty
                ? subscription.changes.last['state']
                : initialState;

            // Simple equality check - deep comparison would be better
            if (jsonEncode(currentState) != jsonEncode(lastState)) {
              subscription.changes.add({
                'state': currentState,
                'timestamp': DateTime.now().toIso8601String(),
              });
            }
          } catch (e) {
            _logConsole('error', 'Error polling state for $providerId: $e');
          }
        },
      );
    }

    _stateWatches[subscriptionId] = subscription;

    return {
      'subscriptionId': subscriptionId,
      'initialState': initialState,
      'providerId': providerId,
    };
  }

  Map<String, dynamic> _getStateChanges(String subscriptionId, bool clear) {
    final subscription = _stateWatches[subscriptionId];
    if (subscription == null) {
      throw Exception('Subscription "$subscriptionId" not found.');
    }

    final changes = List<Map<String, dynamic>>.from(subscription.changes);

    if (clear) {
      subscription.changes.clear();
    }

    return {
      'subscriptionId': subscriptionId,
      'providerId': subscription.providerId,
      'changes': changes,
    };
  }

  void _unwatchState(String subscriptionId) {
    final subscription = _stateWatches.remove(subscriptionId);
    if (subscription != null) {
      subscription.streamSubscription?.cancel();
      subscription.pollTimer?.cancel();
    }
  }

  Map<String, dynamic> _listStateProviders(String stateType) {
    final result = <String, List<Map<String, dynamic>>>{
      'riverpod': [],
      'bloc': [],
      'provider': [],
    };

    for (final provider in _stateProviders.values) {
      final category = _categorizeStateType(provider.type);
      if (stateType == 'all' || stateType == category) {
        try {
          final currentValue = provider.getState();
          (result[category] ?? result['provider']!).add({
            'name': provider.id,
            'type': provider.type,
            'currentValue': _truncateState(currentValue),
            'canDispatch': provider.dispatchAction != null,
            'hasStream': provider.stateStream != null,
          });
        } catch (e) {
          (result[category] ?? result['provider']!).add({
            'name': provider.id,
            'type': provider.type,
            'error': e.toString(),
          });
        }
      }
    }

    return result;
  }

  String _categorizeStateType(String type) {
    final lower = type.toLowerCase();
    if (lower.contains('riverpod') || lower.contains('notifier')) {
      return 'riverpod';
    }
    if (lower.contains('bloc') || lower.contains('cubit')) {
      return 'bloc';
    }
    return 'provider';
  }

  Map<String, dynamic> _truncateState(Map<String, dynamic> state) {
    // Truncate large state objects for listing
    final json = jsonEncode(state);
    if (json.length > 200) {
      return {'_truncated': true, '_preview': json.substring(0, 200)};
    }
    return state;
  }

  /// Get the dependency graph of all state providers.
  Map<String, dynamic> _getStateDependencyGraph() {
    final nodes = <Map<String, dynamic>>[];
    final edges = <Map<String, dynamic>>[];

    // Add all registered providers as nodes
    for (final provider in _stateProviders.values) {
      nodes.add({
        'id': provider.id,
        'type': _categorizeStateType(provider.type),
        'name': provider.id,
      });
    }

    // Add providers that appear in dependencies but aren't registered
    final allProviderIds = <String>{
      ..._stateProviders.keys,
      ..._providerDependencies.keys,
      ..._providerDependencies.values.expand((s) => s),
      ..._providerDependents.keys,
      ..._providerDependents.values.expand((s) => s),
    };

    for (final providerId in allProviderIds) {
      if (!_stateProviders.containsKey(providerId)) {
        nodes.add({'id': providerId, 'type': 'unknown', 'name': providerId});
      }
    }

    // Add dependency edges
    for (final entry in _providerDependencies.entries) {
      final consumer = entry.key;
      for (final dependency in entry.value) {
        edges.add({'from': consumer, 'to': dependency, 'type': 'depends'});
      }
    }

    // Add notification edges (reverse of depends)
    for (final entry in _providerDependents.entries) {
      final provider = entry.key;
      for (final dependent in entry.value) {
        // Check if this edge doesn't already exist as a 'depends' edge
        final existsAsDependsEdge = edges.any(
          (e) =>
              e['from'] == dependent &&
              e['to'] == provider &&
              e['type'] == 'depends',
        );
        if (!existsAsDependsEdge) {
          edges.add({'from': provider, 'to': dependent, 'type': 'notifies'});
        }
      }
    }

    return {'nodes': nodes, 'edges': edges};
  }

  /// Analyze what would be affected by changing a provider.
  Map<String, dynamic> _getStateImpactAnalysis(String providerId) {
    // Direct dependents
    final directDependents = _providerDependents[providerId]?.toList() ?? [];

    // Transitive dependents (BFS)
    final transitiveDependents = <String>{};
    final queue = <String>[...directDependents];
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      if (transitiveDependents.add(current)) {
        queue.addAll(_providerDependents[current] ?? {});
      }
    }
    // Remove direct dependents from transitive set
    transitiveDependents.removeAll(directDependents);

    // Affected widgets
    final affectedWidgets = <String>{..._widgetConsumers[providerId] ?? {}};
    // Also include widgets affected by dependents
    for (final dependent in [...directDependents, ...transitiveDependents]) {
      affectedWidgets.addAll(_widgetConsumers[dependent] ?? {});
    }

    // Calculate impact score (0-100)
    final totalProviders = _stateProviders.length;
    final totalDependents =
        directDependents.length + transitiveDependents.length;
    final totalWidgets = affectedWidgets.length;

    int impactScore = 0;
    if (totalProviders > 0) {
      impactScore += ((totalDependents / totalProviders) * 50).round();
    }
    if (totalWidgets > 0) {
      impactScore += (totalWidgets.clamp(0, 10) * 5);
    }
    impactScore = impactScore.clamp(0, 100);

    return {
      'directDependents': directDependents,
      'transitiveDependents': transitiveDependents.toList(),
      'affectedWidgets': affectedWidgets.toList(),
      'impactScore': impactScore,
    };
  }

  /// Trace state flow from a source provider to widgets or a specific widget.
  Map<String, dynamic> _getStateTrace(String providerId, String? widgetId) {
    final path = <Map<String, dynamic>>[];
    final transformations = <String>[];

    // Start with the source provider
    path.add({
      'node': providerId,
      'type': _stateProviders.containsKey(providerId)
          ? _categorizeStateType(_stateProviders[providerId]!.type)
          : 'unknown',
    });

    if (widgetId != null) {
      // Find path from provider to specific widget
      final visited = <String>{providerId};
      final queue = <List<String>>[
        [providerId],
      ];

      while (queue.isNotEmpty) {
        final currentPath = queue.removeAt(0);
        final current = currentPath.last;

        // Check if this provider is consumed by the target widget
        if (_widgetConsumers[current]?.contains(widgetId) ?? false) {
          // Build the full path
          for (int i = 1; i < currentPath.length; i++) {
            final node = currentPath[i];
            path.add({
              'node': node,
              'type': _stateProviders.containsKey(node)
                  ? _categorizeStateType(_stateProviders[node]!.type)
                  : 'unknown',
            });
            transformations.add('$node depends on ${currentPath[i - 1]}');
          }
          path.add({'node': widgetId, 'type': 'widget'});
          transformations.add('$widgetId consumes $current');
          break;
        }

        // Explore dependents
        for (final dependent in _providerDependents[current] ?? <String>{}) {
          if (!visited.contains(dependent)) {
            visited.add(dependent);
            queue.add([...currentPath, dependent]);
          }
        }
      }
    } else {
      // Trace to all consuming widgets
      final directWidgets = _widgetConsumers[providerId] ?? <String>{};
      for (final widget in directWidgets) {
        path.add({'node': widget, 'type': 'widget'});
        transformations.add('$widget consumes $providerId');
      }

      // Also add dependent providers
      for (final dependent in _providerDependents[providerId] ?? <String>{}) {
        path.add({
          'node': dependent,
          'type': _stateProviders.containsKey(dependent)
              ? _categorizeStateType(_stateProviders[dependent]!.type)
              : 'unknown',
        });
        transformations.add('$dependent depends on $providerId');
      }
    }

    return {'path': path, 'transformations': transformations};
  }

  /// Find providers that are defined but never used.
  Map<String, dynamic> _getOrphanStateCheck() {
    final orphanedProviders = <String>[];
    final unusedInWidgets = <String>[];

    for (final providerId in _stateProviders.keys) {
      // Check if this provider has any dependents
      final dependents = _providerDependents[providerId] ?? <String>{};
      if (dependents.isEmpty) {
        orphanedProviders.add(providerId);
      }

      // Check if this provider is consumed by any widgets
      final widgets = _widgetConsumers[providerId] ?? <String>{};
      if (widgets.isEmpty) {
        unusedInWidgets.add(providerId);
      }
    }

    return {
      'orphanedProviders': orphanedProviders,
      'unusedInWidgets': unusedInWidgets,
    };
  }
}
