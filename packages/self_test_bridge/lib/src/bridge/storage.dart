part of '../bridge_service.dart';

/// Preferences, saved state, dialogs and the clipboard.
extension _BridgeStorage on SelfTestBridge {
  /// The storage commands.
  ///
  /// Returns [_unhandled] for a command this group does not
  /// own, which is how the dispatcher walks on to the next.
  Future<Object?> _storageCommands(BridgeCommand command) async {
    final params = command.params;
    switch (command.command) {
      case 'handleDialog':
        final action = params['action'] as String;
        final text = params['text'] as String?;
        return await _handleDialog(action, text);

      case 'dismissOverlay':
        return await _dismissOverlay();

      // =====================================================================
      // STORAGE & STATE
      // =====================================================================

      case 'storageGet':
        final key = params['key'] as String;
        final storage = params['storage'] as String? ?? 'shared_prefs';
        return await _storageGet(key, storage);

      case 'storageSet':
        final key = params['key'] as String;
        final value = params['value'];
        final storage = params['storage'] as String? ?? 'shared_prefs';
        await _storageSet(key, value, storage);
        return {'success': true};

      case 'storageClear':
        final storage = params['storage'] as String? ?? 'all';
        await _storageClear(storage);
        return {'success': true};

      case 'saveState':
        final name = params['name'] as String;
        await _saveState(name);
        return {'success': true};

      case 'restoreState':
        final name = params['name'] as String;
        await _restoreState(name);
        return {'success': true};

      // =====================================================================
      // FILES
      // =====================================================================

      case 'filePicker':
        final files = (params['files'] as List?)?.cast<String>() ?? [];
        _filePickerMockFiles = files;
        return {'success': true};

      // =====================================================================
      // SCENARIOS
      // =====================================================================

      case 'clipboardRead':
        return await _clipboardRead();

      case 'clipboardWrite':
        final text = params['text'] as String;
        await _clipboardWrite(text);
        return {'success': true};

      // =====================================================================
      // HAR EXPORT
      // =====================================================================

      default:
        return _unhandled;
    }
  }

  // ===========================================================================
  // DIALOGS & OVERLAYS
  // ===========================================================================

  Future<Map<String, dynamic>> _handleDialog(
    String action,
    String? text,
  ) async {
    final manager = SelfTestManager();
    final nodes = manager.activeTestNodes;

    // Find dialog buttons
    for (final entry in nodes.entries) {
      final nodeText = entry.value.currentText?.toLowerCase() ?? '';

      if (action == 'accept') {
        if (nodeText.contains('ok') ||
            nodeText.contains('yes') ||
            nodeText.contains('confirm') ||
            nodeText.contains('accept')) {
          await manager.trigger(entry.key);
          await manager.waitForAnimations();
          return {'success': true, 'text': entry.value.currentText};
        }
      } else if (action == 'dismiss') {
        if (nodeText.contains('cancel') ||
            nodeText.contains('no') ||
            nodeText.contains('close') ||
            nodeText.contains('dismiss')) {
          await manager.trigger(entry.key);
          await manager.waitForAnimations();
          return {'success': true};
        }
      } else if (action == 'get_text') {
        // Return dialog message text
        for (final n in nodes.values) {
          if (n.currentText != null && n.currentText!.length > 20) {
            return {'text': n.currentText};
          }
        }
      }
    }

    // Try pressing back to dismiss
    if (action == 'dismiss') {
      final target = navigator;
      if (target != null && target.canGoBack) {
        await target.goBack();
      }
      return {'success': true};
    }

    return {'error': 'Dialog action not completed'};
  }

  Future<Map<String, dynamic>> _dismissOverlay() async {
    // Try to pop any modal routes
    final target = navigator;
    if (target != null && target.canGoBack) {
      await target.goBack();
      await SelfTestManager().waitForAnimations();
      return {'success': true};
    }

    // Try pressing escape
    await _pressKey('escape');
    await SelfTestManager().waitForAnimations();
    return {'success': true};
  }

  // ===========================================================================
  // STORAGE & STATE
  // ===========================================================================

  Future<Map<String, dynamic>> _storageGet(String key, String storage) async {
    if (storage == 'shared_prefs') {
      final prefs = await SharedPreferences.getInstance();
      return {'value': prefs.get(key)};
    }
    return {'error': 'Storage type not supported'};
  }

  Future<void> _storageSet(String key, dynamic value, String storage) async {
    if (storage == 'shared_prefs') {
      final prefs = await SharedPreferences.getInstance();
      if (value is String) {
        await prefs.setString(key, value);
      } else if (value is int) {
        await prefs.setInt(key, value);
      } else if (value is double) {
        await prefs.setDouble(key, value);
      } else if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is List<String>) {
        await prefs.setStringList(key, value);
      }
    }
  }

  Future<void> _storageClear(String storage) async {
    if (storage == 'shared_prefs' || storage == 'all') {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    }
  }

  Future<void> _saveState(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final state = <String, dynamic>{};

    for (final key in prefs.getKeys()) {
      state[key] = prefs.get(key);
    }

    state['_currentRoute'] = navigator?.currentLocation;

    _savedStates[name] = state;
  }

  Future<void> _restoreState(String name) async {
    final state = _savedStates[name];
    if (state == null) {
      throw Exception('State "$name" not found');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    for (final entry in state.entries) {
      if (entry.key.startsWith('_')) continue;
      await _storageSet(entry.key, entry.value, 'shared_prefs');
    }

    final route = state['_currentRoute'] as String?;
    if (route != null) {
      await navigator?.goTo(route, replace: true);
    }

    await SelfTestManager().waitForAnimations();
  }

  // ===========================================================================
  // CLIPBOARD
  // ===========================================================================

  Future<Map<String, dynamic>> _clipboardRead() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      return {
        'text': data?.text ?? '',
        'hasData': data != null && data.text != null,
      };
    } catch (e) {
      return {'text': '', 'hasData': false, 'error': e.toString()};
    }
  }

  Future<void> _clipboardWrite(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }
}
