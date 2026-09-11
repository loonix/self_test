part of '../bridge_service.dart';

/// Reading what is on screen, and resolving locators.
extension _BridgeDiscovery on SelfTestBridge {
  /// The discovery commands.
  ///
  /// Returns [_unhandled] for a command this group does not
  /// own, which is how the dispatcher walks on to the next.
  Future<Object?> _discoveryCommands(BridgeCommand command) async {
    final manager = SelfTestManager();
    final params = command.params;
    switch (command.command) {
      case 'describeScreen':
        return {
          'widgets': manager.describeScreen().map((w) => w.toJson()).toList(),
        };

      case 'find':
        final found = manager.findAll(_requireLocator(params));
        return {'widget': found.isEmpty ? null : found.first.toJson()};

      case 'exists':
        return {'result': manager.exists(_requireLocator(params))};

      case 'isVisible':
        return {'result': manager.isVisible(_requireLocator(params))};

      case 'readText':
        return {'text': manager.readText(_requireLocator(params))};

      case 'getSnapshot':
        return _getSnapshot();

      case 'getWidgetCatalog':
        return WidgetCatalog.exportCatalog();

      case 'getFlowGraph':
        final flowNavigator = navigator;
        if (flowNavigator == null) return _navigatorMissing;
        return {'routes': flowNavigator.describeRoutes()};

      case 'getScreens':
        return _getScreens();

      case 'getCurrentState':
        return _getCurrentState();

      case 'getByRole':
        return _getByRole(params['role'] as String, params['name'] as String?);

      case 'getByText':
        return _getByText(
          params['text'] as String,
          params['exact'] as bool? ?? false,
        );

      // =====================================================================
      // ACTIONS
      // =====================================================================

      default:
        return _unhandled;
    }
  }

  // ===========================================================================
  // LOCATORS
  //
  // Every command that named a widget by its registered id also takes a
  // `locator` object, which is the wire form of SelfTestLocator:
  //
  //   {"by": "text|key|id|semanticsLabel|type|tooltip",
  //    "value": "Sign in", "exact": true, "index": 0}
  //
  // A locator wins over widgetId when both are sent, because a caller that
  // sends one has the more precise intent. Locators need no registration: they
  // resolve against the element tree, so they reach widgets a
  // SelfTestableWidget id never could.
  // ===========================================================================

  /// The locator a command sent, or null when it sent none.
  ///
  /// Throws with the reason when a locator is present but malformed, so the
  /// caller is told what is wrong with it rather than being handed a cast
  /// error from three layers down.
  SelfTestLocator? _locatorFrom(Map<String, dynamic> params) {
    final raw = params['locator'];
    if (raw == null) return null;
    if (raw is! Map) {
      throw Exception(
        'The "locator" parameter must be an object such as '
        '{"by": "text", "value": "Sign in"}, not a ${raw.runtimeType}.',
      );
    }

    final json = Map<String, dynamic>.from(raw);
    final index = json['index'];
    if (index != null && (index is! int || index < 0)) {
      throw Exception(
        'Locator "index" must be an integer of 0 or more, not '
        '${_describeJsonValue(index)}.',
      );
    }
    final exact = json['exact'];
    if (exact != null && exact is! bool) {
      throw Exception(
        'Locator "exact" must be true or false, not '
        '${_describeJsonValue(exact)}.',
      );
    }

    try {
      return SelfTestLocator.fromJson(json);
    } on ArgumentError catch (e) {
      throw Exception('Bad locator: ${e.message}');
    }
  }

  /// The locator a command requires, for the commands that take nothing else.
  SelfTestLocator _requireLocator(Map<String, dynamic> params) {
    final locator = _locatorFrom(params);
    if (locator == null) {
      throw Exception(
        'This command needs a "locator" parameter, such as '
        '{"by": "text", "value": "Sign in"}.',
      );
    }
    return locator;
  }

  /// The registered widget id a command is aimed at.
  ///
  /// Commands that still work through the registered-node map need an id, so a
  /// locator is resolved against the tree and the id of what it matched is
  /// used. A locator can match a widget the app never registered, and that
  /// combination is refused rather than silently acting on something else.
  String _targetId(Map<String, dynamic> params, {String key = 'widgetId'}) {
    final locator = _locatorFrom(params);
    if (locator != null) {
      final matches = SelfTestManager().findAll(locator);
      if (matches.isEmpty) {
        throw Exception('No widget matches $locator.');
      }
      if (locator.index >= matches.length) {
        throw Exception(
          'Locator $locator asked for index ${locator.index} but only '
          '${matches.length} widget(s) match.',
        );
      }
      final id = matches[locator.index].id;
      if (id == null) {
        throw Exception(
          'The widget matching $locator has no self-test id, and this command '
          'works through the registered-widget map. Either wrap it in a '
          'SelfTestableWidget or use a command that takes a locator directly.',
        );
      }
      return id;
    }

    final widgetId = params[key];
    if (widgetId is! String) {
      throw Exception('This command needs either a "locator" or a "$key".');
    }
    return widgetId;
  }

  // ===========================================================================
  // LOCATOR IMPLEMENTATIONS
  // ===========================================================================

  Map<String, dynamic> _getSnapshot() {
    final manager = SelfTestManager();
    final nodes = manager.activeTestNodes;

    String currentScreen = 'unknown';
    if (nodes.isNotEmpty) {
      final firstNode = nodes.values.first;
      if (firstNode.context != null) {
        currentScreen = _inferScreen(firstNode.context!);
      }
    }

    final widgets = <Map<String, dynamic>>[];
    for (final entry in nodes.entries) {
      final node = entry.value;
      widgets.add({
        'id': entry.key,
        'type': _inferWidgetType(node),
        'screen': node.context != null
            ? _inferScreen(node.context!)
            : 'unknown',
        'isStable': !entry.key.endsWith('_UNSTABLE'),
        'isEnabled': node.onTap != null || node.onTextChange != null,
        'isChecked': null, // TestNode doesn't track checked state
        'currentText': node.currentText,
        'capabilities': {
          'canTap': node.onTap != null,
          'canEnterText': node.onTextChange != null,
          'canToggle': node.onTap != null, // Toggle uses onTap
        },
      });
    }

    return {
      'currentScreen': currentScreen,
      'widgets': widgets,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  List<Map<String, dynamic>> _getByRole(String role, String? name) {
    final manager = SelfTestManager();
    final nodes = manager.activeTestNodes;
    final matches = <Map<String, dynamic>>[];

    for (final entry in nodes.entries) {
      final node = entry.value;
      final inferredType = _inferWidgetType(node);

      bool roleMatches = false;
      switch (role) {
        case 'button':
          roleMatches = inferredType == 'button';
          break;
        case 'textbox':
          roleMatches = inferredType == 'text_input';
          break;
        case 'checkbox':
        case 'switch':
          roleMatches = inferredType == 'checkbox' || inferredType == 'switch';
          break;
        case 'slider':
          roleMatches = inferredType == 'slider';
          break;
        case 'link':
          roleMatches = inferredType == 'link';
          break;
        default:
          roleMatches = inferredType == role;
      }

      if (roleMatches) {
        if (name == null || (node.currentText?.contains(name) ?? false)) {
          matches.add({
            'id': entry.key,
            'type': inferredType,
            'text': node.currentText,
          });
        }
      }
    }

    return matches;
  }

  List<Map<String, dynamic>> _getByText(String text, bool exact) {
    final manager = SelfTestManager();
    final nodes = manager.activeTestNodes;
    final matches = <Map<String, dynamic>>[];

    for (final entry in nodes.entries) {
      final node = entry.value;
      final nodeText = node.currentText ?? '';

      bool textMatches;
      if (exact) {
        textMatches = nodeText == text;
      } else {
        textMatches = nodeText.toLowerCase().contains(text.toLowerCase());
      }

      if (textMatches) {
        matches.add({
          'id': entry.key,
          'type': _inferWidgetType(node),
          'text': nodeText,
        });
      }
    }

    return matches;
  }

  List<Map<String, dynamic>> _getScreens() {
    final catalog = WidgetCatalog.exportByScreen();
    final screens = <Map<String, dynamic>>[];

    for (final entry in catalog.entries) {
      final screenData = entry.value as Map<String, dynamic>;
      final widgets = screenData['widgets'] as List? ?? [];

      screens.add({
        'name': entry.key,
        'path': '/${entry.key}',
        'requiresAuth': _inferAuthRequirement(entry.key),
        'widgetCount': widgets.length,
      });
    }

    return screens;
  }

  Map<String, dynamic> _getCurrentState() {
    final manager = SelfTestManager();
    final nodes = manager.activeTestNodes;

    String currentScreen = 'unknown';
    if (nodes.isNotEmpty) {
      final firstNode = nodes.values.first;
      if (firstNode.context != null) {
        currentScreen = _inferScreen(firstNode.context!);
      }
    }

    return {
      'currentScreen': currentScreen,
      'widgetCount': nodes.length,
      'testModeActive': manager.isSelfTestModeActive || manager.isTestMode,
      'autoDetectionEnabled': true,
      'isTracing': _isTracing,
      'isRecording': _isRecording,
    };
  }

  String _inferWidgetType(TestNode node) {
    // TestNode only has onTap and onTextChange callbacks
    // We infer widget type based on these and the node id
    if (node.onTap != null && node.onTextChange != null) {
      return 'interactive';
    }
    if (node.onTap != null) {
      // Check if the id suggests a toggle/checkbox/switch
      final lowerId = node.id.toLowerCase();
      if (lowerId.contains('checkbox') ||
          lowerId.contains('switch') ||
          lowerId.contains('toggle')) {
        return 'checkbox';
      }
      return 'button';
    }
    if (node.onTextChange != null) {
      // Check if the id suggests a slider
      final lowerId = node.id.toLowerCase();
      if (lowerId.contains('slider')) {
        return 'slider';
      }
      return 'text_input';
    }
    return 'unknown';
  }

  String _inferScreen(BuildContext context) {
    try {
      final route = ModalRoute.of(context);
      if (route?.settings.name != null) {
        return route!.settings.name!
            .replaceAll('/', '_')
            .replaceAll('-', '_')
            .toLowerCase()
            .replaceFirst('_', '');
      }
    } catch (_) {}

    try {
      BuildContext? current = context;
      while (current != null) {
        final widget = current.widget;
        final typeName = widget.runtimeType.toString();
        if (typeName.endsWith('Screen') || typeName.endsWith('Page')) {
          return typeName
              .replaceAll('Screen', '')
              .replaceAll('Page', '')
              .replaceAllMapped(RegExp(r'(?<!^)(?=[A-Z])'), (m) => '_')
              .toLowerCase();
        }

        BuildContext? parent;
        current.visitAncestorElements((element) {
          parent = element;
          return false;
        });
        current = parent;
      }
    } catch (_) {}

    return 'unknown';
  }

  bool _inferAuthRequirement(String screenName) {
    final lower = screenName.toLowerCase();
    if (lower.contains('login') ||
        lower.contains('sign') ||
        lower.contains('intro') ||
        lower.contains('welcome') ||
        lower.contains('forgot')) {
      return false;
    }
    return true;
  }
}
