part of '../bridge_service.dart';

/// Moving between screens, and deep links.
extension _BridgeNavigation on SelfTestBridge {
  /// The navigation commands.
  ///
  /// Returns [_unhandled] for a command this group does not
  /// own, which is how the dispatcher walks on to the next.
  Future<Object?> _navigationCommands(BridgeCommand command) async {
    final manager = SelfTestManager();
    final params = command.params;
    switch (command.command) {
      case 'navigate':
        final route = params['route'] as String;
        final replace = params['replace'] as bool? ?? false;
        final navigateTarget = navigator;
        if (navigateTarget == null) return _navigatorMissing;
        await navigateTarget.goTo(route, replace: replace);
        await manager.waitForAnimations();
        return {'success': true};

      case 'goBack':
        final backTarget = navigator;
        if (backTarget == null) return _navigatorMissing;
        if (backTarget.canGoBack) {
          await backTarget.goBack();
        } else {
          // Nothing left in the app to pop, so ask the platform to leave it.
          await SystemNavigator.pop();
        }
        await manager.waitForAnimations();
        return {'success': true};

      case 'reload':
        // A real hot reload needs the VM service. This re-enters the current
        // route, which is as close as the bridge can get on its own.
        final reloadTarget = navigator;
        if (reloadTarget == null) return _navigatorMissing;
        final currentLocation = reloadTarget.currentLocation;
        if (currentLocation == null) {
          return {
            'error':
                'The configured BridgeNavigator cannot report where the app '
                'is, so there is nothing to reload.',
          };
        }
        await reloadTarget.goTo(currentLocation, replace: true);
        await manager.waitForAnimations();
        return {'success': true};

      case 'restart':
        // A real hot restart needs the VM service. Going back to the root is
        // the closest the bridge can get.
        final restartTarget = navigator;
        if (restartTarget == null) return _navigatorMissing;
        await restartTarget.goTo('/', replace: true);
        await manager.waitForAnimations();
        return {'success': true};

      // =====================================================================
      // WAITING
      // =====================================================================

      case BridgeCommands.navigationStack:
        return _getNavigationStack();

      case BridgeCommands.navigationHistory:
        final limit = params['limit'] as int? ?? 20;
        return _getNavigationHistory(limit);

      case BridgeCommands.popUntil:
        final route = params['route'] as String?;
        final predicate = params['predicate'] as String?;
        return await _popUntil(route, predicate);

      case BridgeCommands.canPop:
        return _canPop();

      case BridgeCommands.navigationListeners:
        return _getNavigationListeners();

      case BridgeCommands.simulateBackGesture:
        final type = params['type'] as String? ?? 'button';
        return await _simulateBackGesture(type);

      case BridgeCommands.routeSettings:
        final route = params['route'] as String?;
        return _getRouteSettings(route);

      // =====================================================================
      // DEEP LINK TESTING
      // =====================================================================

      case BridgeCommands.simulateDeepLink:
        final url = params['url'] as String;
        final source = params['source'] as String? ?? 'external';
        return await _simulateDeepLink(url, source);

      case BridgeCommands.deepLinkHistory:
        return _getDeepLinkHistory();

      case BridgeCommands.registerDeepLinkSchemes:
        final schemes = (params['schemes'] as List).cast<String>();
        return _registerDeepLinkSchemes(schemes);

      case BridgeCommands.testDeepLinkRouting:
        final url = params['url'] as String;
        final expectedRoute = params['expectedRoute'] as String;
        final expectedParams =
            params['expectedParams'] as Map<String, dynamic>?;
        return _testDeepLinkRouting(url, expectedRoute, expectedParams);

      case BridgeCommands.clearDeepLinkHistory:
        return _clearDeepLinkHistory();

      default:
        return _unhandled;
    }
  }

  // ===========================================================================
  // DEEP LINK TESTING IMPLEMENTATIONS
  // ===========================================================================

  /// Simulate receiving a deep link / universal link.
  ///
  /// Parses the URL and attempts to navigate using the configured router.
  /// Records the event in history for later inspection.
  Future<Map<String, dynamic>> _simulateDeepLink(
    String url,
    String source,
  ) async {
    final uri = Uri.parse(url);
    final manager = SelfTestManager();

    // Record the event
    final event = DeepLinkEvent(
      url: url,
      timestamp: DateTime.now(),
      source: source,
    );

    // Handed to whatever BridgeNavigator the app configured.
    String? handledBy;
    String? navigatedTo;

    final target = navigator;
    if (target != null) {
      try {
        // Check if this URL scheme is registered (if schemes are registered)
        bool schemeAllowed = _registeredSchemes.isEmpty;
        if (!schemeAllowed) {
          // Check if scheme matches
          if (uri.scheme.isNotEmpty &&
              _registeredSchemes.contains(uri.scheme)) {
            schemeAllowed = true;
          }
          // Check if host matches (for https/http links)
          if (uri.host.isNotEmpty) {
            for (final scheme in _registeredSchemes) {
              if (scheme.contains(uri.host)) {
                schemeAllowed = true;
                break;
              }
            }
          }
        }

        if (schemeAllowed) {
          // Determine the path to navigate to
          String path = uri.path;
          if (path.isEmpty) {
            path = '/';
          }

          // The query string rides along in the location rather than in a
          // router-specific "extra" bag, which is the only form every router
          // understands.
          if (uri.hasQuery) {
            path = '$path?${uri.query}';
          }
          await target.goTo(path);

          handledBy = target.runtimeType.toString();
          navigatedTo = path;
          event.handled = true;
          event.route = path;
          event.handledBy = handledBy;
        }

        await manager.waitForAnimations();
      } catch (e) {
        event.handled = false;
        debugPrint('[SelfTestBridge] Deep link navigation error: $e');
      }
    }

    _deepLinkHistory.add(event);

    return {
      'success': event.handled,
      'handledBy': handledBy,
      'navigatedTo': navigatedTo,
    };
  }

  /// Get history of deep links received during the session.
  Map<String, dynamic> _getDeepLinkHistory() {
    return {'links': _deepLinkHistory.map((e) => e.toJson()).toList()};
  }

  /// Register URL schemes that the app handles.
  Map<String, dynamic> _registerDeepLinkSchemes(List<String> schemes) {
    final previousSchemes = _registeredSchemes.toList();
    _registeredSchemes.addAll(schemes);

    return {'registered': schemes, 'previousSchemes': previousSchemes};
  }

  /// Test that a deep link routes correctly without actually navigating.
  ///
  /// Validates URL parsing and route matching.
  Map<String, dynamic> _testDeepLinkRouting(
    String url,
    String expectedRoute,
    Map<String, dynamic>? expectedParams,
  ) {
    final uri = Uri.parse(url);

    // Determine actual route from URL
    String actualRoute = uri.path;
    if (actualRoute.isEmpty) {
      actualRoute = '/';
    }

    // Get actual params
    final actualParams = <String, dynamic>{};

    // Add query parameters
    actualParams.addAll(uri.queryParameters);

    // Try to extract path parameters if the router supports it
    // This would require knowledge of the route configuration
    // For now, we compare query params

    // Check if route matches
    final routeMatches = actualRoute == expectedRoute;

    // Check if params match
    final paramMismatches = <Map<String, dynamic>>[];
    if (expectedParams != null) {
      for (final entry in expectedParams.entries) {
        final actualValue = actualParams[entry.key];
        if (actualValue != entry.value) {
          paramMismatches.add({
            'key': entry.key,
            'expected': entry.value,
            'actual': actualValue,
          });
        }
      }
    }

    final match = routeMatches && paramMismatches.isEmpty;

    return {
      'success': match,
      'actualRoute': actualRoute,
      'actualParams': actualParams,
      'match': match,
      'paramMismatches': paramMismatches,
    };
  }

  /// Clear deep link history.
  Map<String, dynamic> _clearDeepLinkHistory() {
    final count = _deepLinkHistory.length;
    _deepLinkHistory.clear();

    return {'cleared': count};
  }

  // ===========================================================================
  // NAVIGATION STACK INSPECTOR IMPLEMENTATIONS
  // ===========================================================================

  /// Initialize navigation observer if not already done
  void _ensureNavigationObserver() {
    if (!_navigationObserverAttached) {
      _navigationObserver = NavigationInspectorObserver(
        onPush: (route, previousRoute) {
          _routeStack.add(route);
          _navigationHistory.add(
            NavigationEvent(
              action: 'push',
              from: previousRoute?.settings.name,
              to: route.settings.name ?? 'unknown',
              timestamp: DateTime.now(),
              arguments: route.settings.arguments,
            ),
          );
        },
        onPop: (route, previousRoute) {
          _routeStack.remove(route);
          _navigationHistory.add(
            NavigationEvent(
              action: 'pop',
              from: route.settings.name ?? 'unknown',
              to: previousRoute?.settings.name ?? 'unknown',
              timestamp: DateTime.now(),
            ),
          );
        },
        onReplace: (newRoute, oldRoute) {
          if (oldRoute != null) _routeStack.remove(oldRoute);
          if (newRoute != null) _routeStack.add(newRoute);
          _navigationHistory.add(
            NavigationEvent(
              action: 'replace',
              from: oldRoute?.settings.name,
              to: newRoute?.settings.name ?? 'unknown',
              timestamp: DateTime.now(),
            ),
          );
        },
        onRemove: (route, previousRoute) {
          _routeStack.remove(route);
          _navigationHistory.add(
            NavigationEvent(
              action: 'remove',
              from: route.settings.name ?? 'unknown',
              to: previousRoute?.settings.name ?? 'unknown',
              timestamp: DateTime.now(),
            ),
          );
        },
      );
      _navigationObserverAttached = true;
    }
  }

  /// Where the app is, preferring the configured navigator and falling back to
  /// what the observer saw.
  String get _currentRouteName =>
      navigator?.currentLocation ??
      (_routeStack.isNotEmpty ? _routeStack.last.settings.name : null) ??
      'unknown';

  /// Get the full navigation stack
  Map<String, dynamic> _getNavigationStack() {
    _ensureNavigationObserver();

    final currentRoute = _currentRouteName;

    final stack = _routeStack.asMap().entries.map((e) {
      final route = e.value;
      dynamic arguments;
      try {
        // Try to serialize arguments as JSON-compatible
        arguments = _serializeNavigationArguments(route.settings.arguments);
      } catch (_) {
        arguments = route.settings.arguments?.toString();
      }
      return {
        'route': route.settings.name ?? 'Route#${e.key}',
        'name': route.settings.name,
        'arguments': arguments,
        'isFirst': e.key == 0,
        'isCurrent': e.key == _routeStack.length - 1,
      };
    }).toList();

    return {
      'stack': stack,
      'currentRoute': currentRoute,
      'depth': _routeStack.length,
    };
  }

  /// Get navigation history
  Map<String, dynamic> _getNavigationHistory(int limit) {
    _ensureNavigationObserver();

    final history = _navigationHistory.reversed
        .take(limit)
        .map((e) => e.toJson())
        .toList()
        .reversed
        .toList();

    return {'history': history};
  }

  /// Pop routes until a condition is met
  Future<Map<String, dynamic>> _popUntil(
    String? route,
    String? predicate,
  ) async {
    final manager = SelfTestManager();
    int poppedCount = 0;

    final target = navigator;
    if (target == null) return _navigatorMissing;

    if (route != null) {
      // A router that addresses screens by location cannot report how many
      // entries that dropped, so this counts the one move it made.
      await target.goTo(route, replace: true);
      poppedCount = 1;
    } else if (predicate == 'isFirst') {
      while (target.canGoBack) {
        await target.goBack();
        poppedCount++;
      }
    }

    await manager.waitForAnimations();

    final currentRoute = _currentRouteName;

    return {'poppedCount': poppedCount, 'currentRoute': currentRoute};
  }

  /// Check if current route can be popped
  Map<String, dynamic> _canPop() {
    _ensureNavigationObserver();

    final canPop = navigator?.canGoBack ?? _routeStack.length > 1;

    return {'canPop': canPop, 'stackDepth': _routeStack.length};
  }

  /// Get registered navigation observers
  Map<String, dynamic> _getNavigationListeners() {
    _ensureNavigationObserver();

    final observers = <Map<String, dynamic>>[];

    // Add our own observer
    if (_navigationObserverAttached) {
      observers.add({
        'type': 'NavigationInspectorObserver',
        'name': 'SelfTestBridge Inspector',
      });
    }

    final target = navigator;
    if (target != null) {
      observers.add({
        'type': target.runtimeType.toString(),
        'name': 'App BridgeNavigator',
      });
    }

    return {'observers': observers};
  }

  /// Simulate back gesture
  Future<Map<String, dynamic>> _simulateBackGesture(String type) async {
    final manager = SelfTestManager();
    bool popped = false;

    final target = navigator;
    if (target == null) return _navigatorMissing;

    if (target.canGoBack) {
      // An edge swipe and a back button both end in the same pop; the bridge
      // does not simulate the gesture itself.
      await target.goBack();
      popped = true;
    } else {
      // Nothing left in the app to pop, so ask the platform to leave it. That
      // may close the app, which is not a pop.
      await SystemNavigator.pop();
    }

    await manager.waitForAnimations();

    final currentRoute = _currentRouteName;

    return {'popped': popped, 'currentRoute': currentRoute};
  }

  /// Get route settings
  Map<String, dynamic> _getRouteSettings(String? route) {
    _ensureNavigationObserver();

    Route<dynamic>? targetRoute;

    if (route != null) {
      // Find specific route
      for (final r in _routeStack) {
        if (r.settings.name == route) {
          targetRoute = r;
          break;
        }
      }
    } else if (_routeStack.isNotEmpty) {
      // Use current route
      targetRoute = _routeStack.last;
    }

    if (targetRoute == null) {
      return {'error': 'Route not found'};
    }

    dynamic arguments;
    try {
      arguments = _serializeNavigationArguments(targetRoute.settings.arguments);
    } catch (_) {
      arguments = targetRoute.settings.arguments?.toString();
    }

    // Check if route maintains state (not all routes support this)
    bool maintainState = true;
    if (targetRoute is ModalRoute) {
      maintainState = targetRoute.maintainState;
    }

    return {
      'name': targetRoute.settings.name,
      'arguments': arguments,
      'maintainState': maintainState,
    };
  }

  /// Helper to serialize route arguments to JSON-compatible format
  dynamic _serializeNavigationArguments(dynamic arguments) {
    if (arguments == null) return null;
    if (arguments is String || arguments is num || arguments is bool) {
      return arguments;
    }
    if (arguments is Map) {
      return arguments.map(
        (k, v) => MapEntry(k.toString(), _serializeNavigationArguments(v)),
      );
    }
    if (arguments is List) {
      return arguments.map(_serializeNavigationArguments).toList();
    }
    // For other objects, try to convert to string
    return arguments.toString();
  }
}
