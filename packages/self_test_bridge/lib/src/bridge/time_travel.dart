part of '../bridge_service.dart';

/// Capturing and restoring app snapshots.
extension _BridgeTimeTravel on SelfTestBridge {
  /// The time travel commands.
  ///
  /// Returns [_unhandled] for a command this group does not
  /// own, which is how the dispatcher walks on to the next.
  Future<Object?> _timeTravelCommands(BridgeCommand command) async {
    final params = command.params;
    switch (command.command) {
      case 'timeTravelStart':
        final captureOnInteraction =
            params['captureOnInteraction'] as bool? ?? false;
        final intervalMs = params['intervalMs'] as int?;
        return _timeTravelStart(captureOnInteraction, intervalMs);

      case 'timeTravelSnapshot':
        final label = params['label'] as String?;
        return await _timeTravelSnapshot(label);

      case 'timeTravelList':
        return _timeTravelList();

      case 'timeTravelGoto':
        final snapshotId = params['snapshotId'] as String?;
        final index = params['index'] as int?;
        return await _timeTravelGoto(snapshotId, index);

      case 'timeTravelStop':
        final clear = params['clear'] as bool? ?? false;
        return _timeTravelStop(clear);

      case 'timeTravelDiff':
        final from = params['from'] as String;
        final to = params['to'] as String;
        return _timeTravelDiff(from, to);

      // =====================================================================
      // STATE DEPENDENCY GRAPH
      // =====================================================================

      default:
        return _unhandled;
    }
  }

  // ===========================================================================
  // TIME-TRAVEL STATE SNAPSHOTS IMPLEMENTATION
  // ===========================================================================

  /// Start recording time-travel snapshots
  Map<String, dynamic> _timeTravelStart(
    bool captureOnInteraction,
    int? intervalMs,
  ) {
    if (_isRecordingTimeline) {
      return {
        'success': false,
        'error': 'Time-travel recording is already active',
      };
    }

    _isRecordingTimeline = true;
    _captureOnInteraction = captureOnInteraction;
    _timelineSnapshots.clear();

    // Capture initial snapshot
    _captureSnapshotInternal(label: 'initial');

    // Set up interval-based capturing if specified
    if (intervalMs != null && intervalMs > 0) {
      _snapshotTimer?.cancel();
      _snapshotTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
        if (_isRecordingTimeline) {
          _captureSnapshotInternal(label: 'auto');
        }
      });
    }

    return {
      'success': true,
      'captureOnInteraction': captureOnInteraction,
      'intervalMs': intervalMs,
    };
  }

  /// Manually capture a snapshot
  Future<Map<String, dynamic>> _timeTravelSnapshot(String? label) async {
    if (!_isRecordingTimeline) {
      return {
        'error':
            'Time-travel recording is not active. Call timeTravelStart first.',
      };
    }

    final snapshot = await _captureSnapshotInternal(label: label);
    return {
      'snapshotId': snapshot.id,
      'timestamp': snapshot.timestamp.millisecondsSinceEpoch,
      'label': snapshot.label,
      'route': snapshot.currentRoute,
    };
  }

  /// List all captured snapshots
  Map<String, dynamic> _timeTravelList() {
    return {
      'snapshots': _timelineSnapshots
          .map(
            (s) => {
              'id': s.id,
              'label': s.label,
              'timestamp': s.timestamp.millisecondsSinceEpoch,
              'route': s.currentRoute,
            },
          )
          .toList(),
      'isRecording': _isRecordingTimeline,
      'totalCount': _timelineSnapshots.length,
    };
  }

  /// Restore app to a previous snapshot state
  Future<Map<String, dynamic>> _timeTravelGoto(
    String? snapshotId,
    int? index,
  ) async {
    _AppSnapshot? snapshot;

    if (snapshotId != null) {
      snapshot = _timelineSnapshots.firstWhere(
        (s) => s.id == snapshotId,
        orElse: () => throw Exception('Snapshot not found: $snapshotId'),
      );
    } else if (index != null) {
      if (index < 0 || index >= _timelineSnapshots.length) {
        return {
          'success': false,
          'error':
              'Invalid snapshot index: $index. Valid range: 0-${_timelineSnapshots.length - 1}',
        };
      }
      snapshot = _timelineSnapshots[index];
    } else {
      return {
        'success': false,
        'error': 'Either snapshotId or index must be provided',
      };
    }

    try {
      await _restoreSnapshotInternal(snapshot);
      return {
        'success': true,
        'restoredFrom': snapshot.id,
        'timestamp': snapshot.timestamp.millisecondsSinceEpoch,
        'route': snapshot.currentRoute,
      };
    } catch (e) {
      return {'success': false, 'error': 'Failed to restore snapshot: $e'};
    }
  }

  /// Stop recording snapshots and optionally clear them
  Map<String, dynamic> _timeTravelStop(bool clear) {
    final totalSnapshots = _timelineSnapshots.length;

    _snapshotTimer?.cancel();
    _snapshotTimer = null;
    _isRecordingTimeline = false;
    _captureOnInteraction = false;

    if (clear) {
      _timelineSnapshots.clear();
    }

    return {
      'success': true,
      'totalSnapshots': totalSnapshots,
      'cleared': clear,
    };
  }

  /// Compare two snapshots and return differences
  Map<String, dynamic> _timeTravelDiff(String fromId, String toId) {
    final fromSnapshot = _timelineSnapshots.firstWhere(
      (s) => s.id == fromId,
      orElse: () => throw Exception('From snapshot not found: $fromId'),
    );

    final toSnapshot = _timelineSnapshots.firstWhere(
      (s) => s.id == toId,
      orElse: () => throw Exception('To snapshot not found: $toId'),
    );

    // Compare provider states
    final stateChanges = <Map<String, dynamic>>[];
    final allProviderIds = <String>{
      ...fromSnapshot.providerStates.keys,
      ...toSnapshot.providerStates.keys,
    };

    for (final providerId in allProviderIds) {
      final fromState = fromSnapshot.providerStates[providerId];
      final toState = toSnapshot.providerStates[providerId];

      if (fromState == null && toState != null) {
        stateChanges.add({
          'providerId': providerId,
          'type': 'added',
          'newValue': toState,
        });
      } else if (fromState != null && toState == null) {
        stateChanges.add({
          'providerId': providerId,
          'type': 'removed',
          'oldValue': fromState,
        });
      } else if (jsonEncode(fromState) != jsonEncode(toState)) {
        stateChanges.add({
          'providerId': providerId,
          'type': 'changed',
          'oldValue': fromState,
          'newValue': toState,
        });
      }
    }

    // Compare storage snapshots
    final storageChanges = <Map<String, dynamic>>[];
    final allStorageKeys = <String>{
      ...fromSnapshot.storageSnapshot.keys,
      ...toSnapshot.storageSnapshot.keys,
    };

    for (final key in allStorageKeys) {
      final fromValue = fromSnapshot.storageSnapshot[key];
      final toValue = toSnapshot.storageSnapshot[key];

      if (fromValue == null && toValue != null) {
        storageChanges.add({'key': key, 'type': 'added', 'newValue': toValue});
      } else if (fromValue != null && toValue == null) {
        storageChanges.add({
          'key': key,
          'type': 'removed',
          'oldValue': fromValue,
        });
      } else if (jsonEncode(fromValue) != jsonEncode(toValue)) {
        storageChanges.add({
          'key': key,
          'type': 'changed',
          'oldValue': fromValue,
          'newValue': toValue,
        });
      }
    }

    // Compare widget tree digests
    final widgetChanges = <Map<String, dynamic>>[];
    if (fromSnapshot.widgetTreeDigest != toSnapshot.widgetTreeDigest) {
      widgetChanges.add({
        'type': 'widget_tree_changed',
        'from': fromSnapshot.widgetTreeDigest,
        'to': toSnapshot.widgetTreeDigest,
      });
    }

    return {
      'from': {
        'id': fromSnapshot.id,
        'timestamp': fromSnapshot.timestamp.millisecondsSinceEpoch,
        'label': fromSnapshot.label,
      },
      'to': {
        'id': toSnapshot.id,
        'timestamp': toSnapshot.timestamp.millisecondsSinceEpoch,
        'label': toSnapshot.label,
      },
      'routeChanged': fromSnapshot.currentRoute != toSnapshot.currentRoute,
      'fromRoute': fromSnapshot.currentRoute,
      'toRoute': toSnapshot.currentRoute,
      'stateChanges': stateChanges,
      'storageChanges': storageChanges,
      'widgetChanges': widgetChanges,
      'timeDeltaMs':
          toSnapshot.timestamp.millisecondsSinceEpoch -
          fromSnapshot.timestamp.millisecondsSinceEpoch,
    };
  }

  /// Internal method to capture a snapshot
  Future<_AppSnapshot> _captureSnapshotInternal({String? label}) async {
    final id = 'snap_${DateTime.now().millisecondsSinceEpoch}';
    final timestamp = DateTime.now();

    // Capture current route
    final currentRoute = navigator?.currentLocation ?? '/';

    // Capture provider states from registered providers
    final providerStates = <String, Map<String, dynamic>>{};
    for (final entry in _stateProviders.entries) {
      try {
        providerStates[entry.key] = entry.value.getState();
      } catch (e) {
        providerStates[entry.key] = {'_error': e.toString()};
      }
    }

    // Capture storage snapshot
    final storageSnapshot = <String, dynamic>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys()) {
        storageSnapshot[key] = prefs.get(key);
      }
    } catch (e) {
      storageSnapshot['_error'] = e.toString();
    }

    // Capture widget tree digest
    String? widgetTreeDigest;
    try {
      final manager = SelfTestManager();
      final nodes = manager.activeTestNodes;
      // Create a simple digest of the widget tree
      final widgetIds = nodes.keys.toList()..sort();
      widgetTreeDigest = widgetIds.join('|');
    } catch (e) {
      widgetTreeDigest = null;
    }

    final snapshot = _AppSnapshot(
      id: id,
      label: label,
      timestamp: timestamp,
      currentRoute: currentRoute,
      providerStates: providerStates,
      storageSnapshot: storageSnapshot,
      widgetTreeDigest: widgetTreeDigest,
    );

    _timelineSnapshots.add(snapshot);
    return snapshot;
  }

  /// Internal method to restore a snapshot
  Future<void> _restoreSnapshotInternal(_AppSnapshot snapshot) async {
    // 1. Restore storage
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      for (final entry in snapshot.storageSnapshot.entries) {
        if (entry.key.startsWith('_')) continue;
        await _storageSet(entry.key, entry.value, 'shared_prefs');
      }
    } catch (e) {
      debugPrint('[SelfTestBridge] Failed to restore storage: $e');
    }

    // 2. Restore provider states (for registered providers that support injection)
    for (final entry in snapshot.providerStates.entries) {
      final config = _stateProviders[entry.key];
      if (config?.dispatchAction != null) {
        try {
          config!.dispatchAction!('_restore', entry.value);
        } catch (e) {
          debugPrint(
            '[SelfTestBridge] Failed to restore provider ${entry.key}: $e',
          );
        }
      }
    }

    // 3. Navigate to the route
    if (snapshot.currentRoute.isNotEmpty) {
      await navigator?.goTo(snapshot.currentRoute, replace: true);
    }

    // 4. Wait for animations to complete
    await SelfTestManager().waitForAnimations();
  }

  /// Called when a user interaction occurs (for captureOnInteraction mode)
  Future<void> _onUserInteraction() async {
    if (_isRecordingTimeline && _captureOnInteraction) {
      // _captureSnapshotInternal appends to _timelineSnapshots itself.
      await _captureSnapshotInternal(label: 'interaction');
    }
  }
}
