part of '../bridge_service.dart';

/// Driving the app: taps, typing, drags and scrolls.
extension _BridgeActions on SelfTestBridge {
  /// The actions commands.
  ///
  /// Returns [_unhandled] for a command this group does not
  /// own, which is how the dispatcher walks on to the next.
  Future<Object?> _actionsCommands(BridgeCommand command) async {
    final manager = SelfTestManager();
    final params = command.params;
    switch (command.command) {
      case 'tap':
        return await _tapCommand(params);

      case 'type':
      case 'enterText':
        return await _typeCommand(params);

      case 'submit':
        return await _submitCommand(params);

      case 'clear':
        final locator = _locatorFrom(params);
        if (locator != null) {
          await manager.typeInto(locator, '');
        } else {
          await manager.enterText(_targetId(params), '');
        }
        return {'success': true};

      case 'pressKey':
        final key = params['key'] as String;
        await _pressKey(key);
        return {'success': true};

      case 'scroll':
        return await _scrollCommand(params);

      case 'scrollTo':
        final scrollableId = params['scrollableId'] as String?;
        final timeout = params['timeout'] as int? ?? 10000;
        await _scrollToWidget(_targetId(params), scrollableId, timeout);
        return {'success': true};

      case 'drag':
        return await _dragCommand(params);

      case 'longPress':
        return await _longPressCommand(params);

      case 'doubleTap':
        return await _doubleTapCommand(params);

      case 'hover':
        await _hover(_targetId(params));
        return {'success': true};

      case 'focus':
        await _focus(_targetId(params));
        return {'success': true};

      case 'select':
        final value = params['value'] as String;
        await _selectOption(_targetId(params), value);
        return {'success': true};

      case 'toggle':
        final checked = params['checked'] as bool?;
        await _toggle(_targetId(params), checked);
        return {'success': true};

      case 'setSlider':
        final value = (params['value'] as num).toDouble();
        await _setSlider(_targetId(params), value);
        return {'success': true};

      // =====================================================================
      // NAVIGATION
      // =====================================================================

      default:
        return _unhandled;
    }
  }

  // ===========================================================================
  // ACTION COMMANDS
  //
  // Each takes the locator path when one was sent and the registered-id path
  // otherwise, so a caller written against 0.1.0 keeps working.
  // ===========================================================================

  Future<Map<String, dynamic>> _tapCommand(Map<String, dynamic> params) async {
    final manager = SelfTestManager();
    final locator = _locatorFrom(params);
    if (locator != null) {
      await manager.tap(locator);
    } else {
      final widgetId = _targetId(params);
      await _waitForWidget(widgetId, params['timeout'] as int? ?? 5000);
      await manager.trigger(widgetId);
    }
    await manager.waitForAnimations();
    if (_traceScreenshots) {
      await _captureTraceScreenshot('tap_${locator ?? params['widgetId']}');
    }
    return {'success': true};
  }

  Future<Map<String, dynamic>> _doubleTapCommand(
    Map<String, dynamic> params,
  ) async {
    final locator = _locatorFrom(params);
    if (locator != null) {
      await SelfTestManager().doubleTap(locator);
    } else {
      await _doubleTap(_targetId(params));
    }
    return {'success': true};
  }

  Future<Map<String, dynamic>> _longPressCommand(
    Map<String, dynamic> params,
  ) async {
    final durationMs = params['duration'] as int? ?? 500;
    final locator = _locatorFrom(params);
    if (locator != null) {
      await SelfTestManager().longPress(
        locator,
        hold: Duration(milliseconds: durationMs),
      );
    } else {
      await _longPress(_targetId(params), durationMs);
    }
    return {'success': true};
  }

  Future<Map<String, dynamic>> _typeCommand(Map<String, dynamic> params) async {
    final manager = SelfTestManager();
    final text = params['text'] as String;
    final append = params['append'] as bool? ?? false;
    final submit = params['submit'] as bool? ?? false;

    final locator = _locatorFrom(params);
    if (locator != null) {
      // typeInto replaces the field's contents, so appending means sending
      // what is there now plus the new text.
      final value = append ? '${manager.readText(locator) ?? ''}$text' : text;
      await manager.typeInto(locator, value);
      if (submit) await manager.submit(locator);
    } else {
      final widgetId = _targetId(params);
      if (!append) {
        // Clear by entering empty string first
        await manager.enterText(widgetId, '');
      }
      await manager.enterText(widgetId, text);
      if (submit) await _sendDoneAction();
    }

    await manager.waitForAnimations();
    return {'success': true};
  }

  Future<Map<String, dynamic>> _submitCommand(
    Map<String, dynamic> params,
  ) async {
    final manager = SelfTestManager();
    final locator = _locatorFrom(params);
    if (locator != null) {
      await manager.submit(locator);
    } else {
      await _sendDoneAction();
    }
    await manager.waitForAnimations();
    return {'success': true};
  }

  /// Fires the keyboard's "done" action at whatever holds focus.
  ///
  /// The registered-id path has no field to aim at, so it goes through the
  /// platform channel the soft keyboard uses.
  Future<void> _sendDoneAction() async {
    await ServicesBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/textinput',
      const JSONMessageCodec().encodeMessage(<String, dynamic>{
        'method': 'TextInputClient.performAction',
        'args': <dynamic>[0, 'TextInputAction.done'],
      }),
      (ByteData? data) {},
    );
  }

  Future<Map<String, dynamic>> _dragCommand(Map<String, dynamic> params) async {
    final locator = _locatorFrom(params);
    if (locator != null) {
      final dx = (params['dx'] as num?)?.toDouble();
      final dy = (params['dy'] as num?)?.toDouble();
      if (dx == null && dy == null) {
        throw Exception(
          'A drag by locator needs "dx" and/or "dy": how far to drag from the '
          'widget the locator matches.',
        );
      }
      await SelfTestManager().dragFrom(locator, Offset(dx ?? 0, dy ?? 0));
    } else {
      await _drag(
        _requireString(params, 'sourceId'),
        _requireString(params, 'targetId'),
      );
    }
    return {'success': true};
  }

  Future<Map<String, dynamic>> _scrollCommand(
    Map<String, dynamic> params,
  ) async {
    final direction = params['direction'] as String? ?? 'down';
    final delta = (params['delta'] as num?)?.toDouble() ?? 300.0;

    final locator = _locatorFrom(params);
    if (locator != null) {
      await SelfTestManager().scrollBy(
        locator,
        _scrollOffset(direction, delta),
      );
    } else {
      await _scroll(params['widgetId'] as String?, direction, delta);
    }
    return {'success': true};
  }

  // ===========================================================================
  // ACTION IMPLEMENTATIONS
  // ===========================================================================

  Future<void> _waitForWidget(String widgetId, int timeoutMs) async {
    final manager = SelfTestManager();
    final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));

    while (DateTime.now().isBefore(deadline)) {
      if (manager.activeTestNodes.containsKey(widgetId)) {
        return;
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }

    throw Exception('Widget "$widgetId" not found within ${timeoutMs}ms');
  }

  Future<void> _pressKey(String key) async {
    LogicalKeyboardKey logicalKey;
    switch (key.toLowerCase()) {
      case 'enter':
        logicalKey = LogicalKeyboardKey.enter;
        break;
      case 'tab':
        logicalKey = LogicalKeyboardKey.tab;
        break;
      case 'escape':
        logicalKey = LogicalKeyboardKey.escape;
        break;
      case 'backspace':
        logicalKey = LogicalKeyboardKey.backspace;
        break;
      case 'delete':
        logicalKey = LogicalKeyboardKey.delete;
        break;
      case 'up':
        logicalKey = LogicalKeyboardKey.arrowUp;
        break;
      case 'down':
        logicalKey = LogicalKeyboardKey.arrowDown;
        break;
      case 'left':
        logicalKey = LogicalKeyboardKey.arrowLeft;
        break;
      case 'right':
        logicalKey = LogicalKeyboardKey.arrowRight;
        break;
      case 'home':
        logicalKey = LogicalKeyboardKey.home;
        break;
      case 'end':
        logicalKey = LogicalKeyboardKey.end;
        break;
      default:
        throw Exception('Unknown key: $key');
    }

    // Simulate key press through raw key event
    await ServicesBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/keyevent',
      const JSONMessageCodec().encodeMessage(<String, dynamic>{
        'type': 'keydown',
        'keyCode': logicalKey.keyId,
      }),
      (ByteData? data) {},
    );

    await Future.delayed(const Duration(milliseconds: 50));

    await ServicesBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/keyevent',
      const JSONMessageCodec().encodeMessage(<String, dynamic>{
        'type': 'keyup',
        'keyCode': logicalKey.keyId,
      }),
      (ByteData? data) {},
    );
  }

  Future<void> _scroll(String? widgetId, String direction, double delta) async {
    final manager = SelfTestManager();

    // Find scrollable
    ScrollController? controller;
    if (widgetId != null) {
      final node = manager.activeTestNodes[widgetId];
      if (node?.context != null) {
        final scrollable = Scrollable.maybeOf(node!.context!);
        controller = scrollable?.widget.controller;
      }
    } else {
      // Find any scrollable in current context
      // This would need access to the current build context
    }

    if (controller != null) {
      double offset;
      switch (direction) {
        case 'up':
          offset = -delta;
          break;
        case 'down':
          offset = delta;
          break;
        case 'left':
          offset = -delta;
          break;
        case 'right':
          offset = delta;
          break;
        default:
          throw Exception('Unknown scroll direction: $direction');
      }

      await controller.animateTo(
        controller.offset + offset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }

    await manager.waitForAnimations();
  }

  Future<void> _scrollToWidget(
    String widgetId,
    String? scrollableId,
    int timeout,
  ) async {
    final manager = SelfTestManager();
    final deadline = DateTime.now().add(Duration(milliseconds: timeout));

    while (DateTime.now().isBefore(deadline)) {
      final node = manager.activeTestNodes[widgetId];
      if (node?.context != null) {
        // Widget found, ensure visible
        await Scrollable.ensureVisible(
          node!.context!,
          duration: const Duration(milliseconds: 300),
          alignment: 0.5,
        );
        return;
      }

      // Scroll down and try again
      await _scroll(scrollableId, 'down', 200);
      await Future.delayed(const Duration(milliseconds: 100));
    }

    throw Exception('Widget "$widgetId" not found after scrolling');
  }

  Future<void> _drag(String sourceId, String targetId) async {
    final manager = SelfTestManager();
    final sourceNode = manager.activeTestNodes[sourceId];
    final targetNode = manager.activeTestNodes[targetId];

    if (sourceNode == null)
      throw Exception('Source widget "$sourceId" not found');
    if (targetNode == null)
      throw Exception('Target widget "$targetId" not found');

    if (sourceNode.context == null || targetNode.context == null) {
      throw Exception('Widget contexts not available');
    }

    final sourceBox = sourceNode.context!.findRenderObject() as RenderBox?;
    final targetBox = targetNode.context!.findRenderObject() as RenderBox?;

    if (sourceBox == null || targetBox == null) {
      throw Exception('Widget render objects not found');
    }

    // Get global positions
    final sourcePos = sourceBox.localToGlobal(
      sourceBox.size.center(Offset.zero),
    );
    final targetPos = targetBox.localToGlobal(
      targetBox.size.center(Offset.zero),
    );

    // Simulate drag using gesture binding
    final binding = WidgetsBinding.instance;
    final pointer = TestPointer();

    binding.handlePointerEvent(pointer.down(sourcePos));
    await Future.delayed(const Duration(milliseconds: 100));

    // Move in steps
    const steps = 10;
    for (int i = 1; i <= steps; i++) {
      final t = i / steps;
      final current = Offset.lerp(sourcePos, targetPos, t)!;
      binding.handlePointerEvent(pointer.move(current));
      await Future.delayed(const Duration(milliseconds: 20));
    }

    binding.handlePointerEvent(pointer.up());
    await manager.waitForAnimations();
  }

  Future<void> _longPress(String widgetId, int durationMs) async {
    final manager = SelfTestManager();
    final node = manager.activeTestNodes[widgetId];

    if (node == null) throw Exception('Widget "$widgetId" not found');
    if (node.context == null) throw Exception('Widget context not available');

    final box = node.context!.findRenderObject() as RenderBox?;
    if (box == null) throw Exception('Widget render object not found');

    final position = box.localToGlobal(box.size.center(Offset.zero));

    final binding = WidgetsBinding.instance;
    final pointer = TestPointer();

    binding.handlePointerEvent(pointer.down(position));
    await Future.delayed(Duration(milliseconds: durationMs));
    binding.handlePointerEvent(pointer.up());
    await manager.waitForAnimations();
  }

  Future<void> _doubleTap(String widgetId) async {
    final manager = SelfTestManager();
    await manager.trigger(widgetId);
    await Future.delayed(const Duration(milliseconds: 100));
    await manager.trigger(widgetId);
    await manager.waitForAnimations();
  }

  Future<void> _hover(String widgetId) async {
    final manager = SelfTestManager();
    final node = manager.activeTestNodes[widgetId];

    if (node == null) throw Exception('Widget "$widgetId" not found');
    if (node.context == null) throw Exception('Widget context not available');

    final box = node.context!.findRenderObject() as RenderBox?;
    if (box == null) throw Exception('Widget render object not found');

    final position = box.localToGlobal(box.size.center(Offset.zero));

    final binding = WidgetsBinding.instance;
    final pointer = TestPointer(kind: PointerDeviceKind.mouse);

    binding.handlePointerEvent(pointer.hover(position));
  }

  Future<void> _focus(String widgetId) async {
    final manager = SelfTestManager();
    final node = manager.activeTestNodes[widgetId];

    if (node == null) throw Exception('Widget "$widgetId" not found');
    if (node.context == null) throw Exception('Widget context not available');

    // Find focus node in widget tree
    final focusNode = Focus.maybeOf(node.context!);
    focusNode?.requestFocus();
  }

  Future<void> _selectOption(String widgetId, String value) async {
    final manager = SelfTestManager();

    // First tap to open dropdown
    await manager.trigger(widgetId);
    await manager.waitForAnimations();
    await Future.delayed(const Duration(milliseconds: 200));

    // Find and tap the option
    final nodes = manager.activeTestNodes;
    for (final entry in nodes.entries) {
      if (entry.value.currentText == value) {
        await manager.trigger(entry.key);
        break;
      }
    }

    await manager.waitForAnimations();
  }

  Future<void> _toggle(String widgetId, bool? checked) async {
    final manager = SelfTestManager();
    final node = manager.activeTestNodes[widgetId];

    if (node == null) throw Exception('Widget "$widgetId" not found');

    // TestNode doesn't track checked state, so we always trigger the tap
    // The widget itself manages its internal state
    if (node.onTap != null) {
      await manager.trigger(widgetId);
    } else {
      throw Exception(
        'Widget "$widgetId" is not toggleable (no onTap callback)',
      );
    }

    await manager.waitForAnimations();
  }

  Future<void> _setSlider(String widgetId, double value) async {
    final manager = SelfTestManager();
    final node = manager.activeTestNodes[widgetId];

    if (node == null) throw Exception('Widget "$widgetId" not found');

    // TestNode uses onTextChange for value changes (pass value as string)
    if (node.onTextChange != null) {
      node.onTextChange!(value.toString());
    } else {
      throw Exception('Widget "$widgetId" does not support value changes');
    }

    await manager.waitForAnimations();
  }
}
