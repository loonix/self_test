part of '../bridge_service.dart';

/// Semantics coverage and label suggestions.
extension _BridgeAccessibility on SelfTestBridge {
  /// The accessibility commands.
  ///
  /// Returns [_unhandled] for a command this group does not
  /// own, which is how the dispatcher walks on to the next.
  Future<Object?> _accessibilityCommands(BridgeCommand command) async {
    final params = command.params;
    switch (command.command) {
      case 'suggestSemantics':
        final screen = params['screen'] as String?;
        final includeLabeled = params['includeLabeled'] as bool? ?? false;
        return _suggestSemantics(screen, includeLabeled);

      case 'semanticsCoverage':
        return _semanticsCoverage();

      case 'semanticsTree':
        final includeHidden = params['includeHidden'] as bool? ?? false;
        return _semanticsTree(includeHidden);

      case 'applySuggestedSemantics':
        final suggestions =
            (params['suggestions'] as List?)?.cast<String>() ?? [];
        return _applySuggestedSemantics(suggestions);

      // =====================================================================
      // APP LIFECYCLE TESTING
      // =====================================================================

      default:
        return _unhandled;
    }
  }

  /// Analyze widgets and suggest semantic labels for accessibility
  Map<String, dynamic> _suggestSemantics(String? screen, bool includeLabeled) {
    final suggestions = <Map<String, dynamic>>[];
    _cachedSuggestions.clear();

    void visitElement(Element element) {
      final widget = element.widget;
      final widgetType = widget.runtimeType.toString();

      if (screen != null) {
        final elementScreen = _inferScreen(element);
        if (!elementScreen.toLowerCase().contains(screen.toLowerCase())) {
          element.visitChildren(visitElement);
          return;
        }
      }

      if (_isSemanticsInteractiveWidget(widget)) {
        final currentLabel = _extractSemanticLabelFromElement(element);
        final hasLabel = currentLabel != null && currentLabel.isNotEmpty;

        if (!hasLabel || includeLabeled) {
          final suggestion = _generateSemanticSuggestion(
            element,
            widget,
            widgetType,
            currentLabel,
          );

          if (suggestion != null) {
            final id = 'suggestion_${suggestions.length}';
            _cachedSuggestions[id] = suggestion;

            suggestions.add({
              'id': id,
              'widgetType': widgetType,
              'currentLabel': currentLabel,
              'suggestedLabel': suggestion.suggestedLabel,
              'confidence': suggestion.confidence,
              'location': suggestion.location,
              'reason': suggestion.reason,
            });
          }
        }
      }

      element.visitChildren(visitElement);
    }

    final rootElement = WidgetsBinding.instance.rootElement;
    if (rootElement != null) {
      visitElement(rootElement);
    }

    return {
      'suggestions': suggestions,
      'totalAnalyzed': _countElementsInTree(rootElement),
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  /// Get semantics coverage report
  Map<String, dynamic> _semanticsCoverage() {
    int totalWidgets = 0;
    int labeledWidgets = 0;
    final byType = <String, Map<String, int>>{};
    final unlabeledInteractive = <String>[];

    void visitElement(Element element) {
      final widget = element.widget;
      final widgetType = widget.runtimeType.toString();

      if (_isSemanticsInteractiveWidget(widget)) {
        totalWidgets++;
        byType.putIfAbsent(widgetType, () => {'total': 0, 'labeled': 0});
        byType[widgetType]!['total'] = byType[widgetType]!['total']! + 1;

        final label = _extractSemanticLabelFromElement(element);
        if (label != null && label.isNotEmpty) {
          labeledWidgets++;
          byType[widgetType]!['labeled'] = byType[widgetType]!['labeled']! + 1;
        } else {
          final widgetId = _inferWidgetIdFromElement(element, widget);
          if (widgetId.isNotEmpty) {
            unlabeledInteractive.add(widgetId);
          }
        }
      }
      element.visitChildren(visitElement);
    }

    final rootElement = WidgetsBinding.instance.rootElement;
    if (rootElement != null) {
      visitElement(rootElement);
    }

    final coveragePercent = totalWidgets > 0
        ? (labeledWidgets / totalWidgets * 100)
        : 100.0;

    return {
      'totalWidgets': totalWidgets,
      'labeledWidgets': labeledWidgets,
      'coveragePercent': coveragePercent,
      'byType': byType,
      'unlabeledInteractive': unlabeledInteractive,
    };
  }

  /// Get the full semantics tree
  Map<String, dynamic> _semanticsTree(bool includeHidden) {
    final tree = <Map<String, dynamic>>[];
    final flatList = <Map<String, dynamic>>[];

    final owner = WidgetsBinding.instance.pipelineOwner.semanticsOwner;
    if (owner == null) {
      return {'tree': [], 'flatList': [], 'error': 'Semantics not enabled.'};
    }

    void visitSemantics(SemanticsNode node, List<Map<String, dynamic>> parent) {
      if (!includeHidden && node.isInvisible) return;

      final nodeData = _extractSemanticsNodeData(node);
      final children = <Map<String, dynamic>>[];

      node.visitChildren((child) {
        visitSemantics(child, children);
        return true;
      });

      if (children.isNotEmpty) nodeData['children'] = children;
      parent.add(nodeData);
      flatList.add({
        'id': node.id,
        'label': node.label,
        'role': _inferSemanticsRole(node),
        'actions': _extractSemanticsActions(node),
        'rect': {
          'left': node.rect.left,
          'top': node.rect.top,
          'width': node.rect.width,
          'height': node.rect.height,
        },
      });
    }

    final rootNode = owner.rootSemanticsNode;
    if (rootNode != null) visitSemantics(rootNode, tree);

    return {'tree': tree, 'flatList': flatList};
  }

  /// Generate code snippets to apply suggested semantic labels
  Map<String, dynamic> _applySuggestedSemantics(List<String> suggestionIds) {
    final codeSnippets = <Map<String, dynamic>>[];

    for (final id in suggestionIds) {
      final suggestion = _cachedSuggestions[id];
      if (suggestion == null) continue;
      final snippet = _generateSemanticCodeSnippet(suggestion);
      if (snippet != null) codeSnippets.add(snippet);
    }

    return {
      'codeSnippets': codeSnippets,
      'appliedCount': codeSnippets.length,
      'requestedCount': suggestionIds.length,
    };
  }

  bool _isSemanticsInteractiveWidget(Widget widget) {
    final t = widget.runtimeType.toString();
    return t.contains('Button') ||
        t.contains('TextField') ||
        t.contains('Checkbox') ||
        t.contains('Radio') ||
        t.contains('Switch') ||
        t.contains('Slider') ||
        t.contains('DropdownButton') ||
        t.contains('GestureDetector') ||
        t.contains('InkWell') ||
        t.contains('InkResponse') ||
        t.contains('ListTile') ||
        t.contains('Card');
  }

  String? _extractSemanticLabelFromElement(Element element) {
    String? label;
    element.visitAncestorElements((ancestor) {
      if (ancestor.widget is Semantics) {
        final s = ancestor.widget as Semantics;
        if (s.properties.label != null) {
          label = s.properties.label;
          return false;
        }
      }
      return true;
    });
    if (label != null) return label;

    final ro = element.renderObject;
    if (ro is RenderBox) {
      final sd = ro.debugSemantics;
      if (sd != null && sd.label.isNotEmpty) return sd.label;
    }
    return null;
  }

  _SemanticSuggestion? _generateSemanticSuggestion(
    Element element,
    Widget widget,
    String widgetType,
    String? currentLabel,
  ) {
    final suggestedLabel = _inferSemanticLabel(element, widget);
    if (suggestedLabel == null || suggestedLabel.isEmpty) return null;

    return _SemanticSuggestion(
      widgetType: widgetType,
      currentLabel: currentLabel,
      suggestedLabel: suggestedLabel,
      confidence: _calculateSemanticConfidence(widget, suggestedLabel),
      location: _getSemanticWidgetLocation(element),
      reason: _explainSemanticSuggestion(widget),
      element: element,
    );
  }

  String? _inferSemanticLabel(Element element, Widget widget) {
    final t = widget.runtimeType.toString();
    final text = _findTextInElementTree(element);

    if (t.contains('Button')) {
      if (text != null && text.isNotEmpty)
        return _textToSnakeCase(text) + '_button';
      final icon = _findIconInElementTree(element);
      if (icon != null) return _textToSnakeCase(icon) + '_button';
      return 'action_button';
    }
    if (t.contains('TextField') || t.contains('TextFormField')) {
      final hint = _findTextFieldHintText(element);
      if (hint != null && hint.isNotEmpty)
        return _textToSnakeCase(hint) + '_input';
      return 'text_input';
    }
    if (t.contains('Checkbox'))
      return text != null
          ? _textToSnakeCase(text) + '_checkbox'
          : 'option_checkbox';
    if (t.contains('Switch'))
      return text != null
          ? _textToSnakeCase(text) + '_switch'
          : 'toggle_switch';
    if (t.contains('Slider'))
      return text != null ? _textToSnakeCase(text) + '_slider' : 'value_slider';
    if (t.contains('IconButton')) {
      final icon = _findIconInElementTree(element);
      return icon != null ? _textToSnakeCase(icon) + '_button' : 'icon_button';
    }
    if (t.contains('ListTile'))
      return text != null ? _textToSnakeCase(text) + '_item' : 'list_item';
    if (t.contains('GestureDetector') || t.contains('InkWell')) {
      return text != null
          ? _textToSnakeCase(text) + '_tap'
          : 'interactive_area';
    }
    return text != null && text.isNotEmpty
        ? _textToSnakeCase(text)
        : _textToSnakeCase(t);
  }

  String? _findTextInElementTree(Element element) {
    String? foundText;
    void search(Element el) {
      if (foundText != null && foundText!.isNotEmpty) return;
      final w = el.widget;
      if (w is Text) {
        final txt = w.data ?? w.textSpan?.toPlainText();
        if (txt != null && txt.trim().isNotEmpty) {
          foundText = txt.trim();
          return;
        }
      }
      if (w is RichText) {
        final txt = w.text.toPlainText();
        if (txt.trim().isNotEmpty) {
          foundText = txt.trim();
          return;
        }
      }
      el.visitChildren(search);
    }

    search(element);
    if (foundText != null && foundText!.length > 50)
      foundText = foundText!.substring(0, 50);
    return foundText;
  }

  String? _findIconInElementTree(Element element) {
    String? iconName;
    void search(Element el) {
      if (iconName != null) return;
      if (el.widget is Icon) {
        final ic = (el.widget as Icon).icon;
        if (ic != null) iconName = _iconDataToName(ic);
      }
      el.visitChildren(search);
    }

    search(element);
    return iconName;
  }

  String _iconDataToName(IconData icon) {
    const icons = {
      0xe5cd: 'close',
      0xe5ca: 'check',
      0xe145: 'add',
      0xe15b: 'remove',
      0xe872: 'settings',
      0xe88a: 'home',
      0xe8b8: 'menu',
      0xe5d2: 'arrow_back',
      0xe8b6: 'search',
      0xe161: 'send',
      0xe3c9: 'edit',
      0xe92b: 'delete',
      0xe7fb: 'person',
      0xe0e1: 'email',
      0xe0cd: 'phone',
      0xe153: 'share',
      0xe866: 'favorite',
      0xe87d: 'star',
      0xe8e5: 'notifications',
      0xe8d3: 'refresh',
    };
    return icons[icon.codePoint] ?? 'icon_${icon.codePoint}';
  }

  String? _findTextFieldHintText(Element element) {
    String? hint;
    void search(Element el) {
      if (hint != null) return;
      if (el.widget is TextField) {
        hint =
            (el.widget as TextField).decoration?.hintText ??
            (el.widget as TextField).decoration?.labelText;
      }
      el.visitChildren(search);
    }

    search(element);
    return hint;
  }

  double _calculateSemanticConfidence(Widget widget, String label) {
    double c = 0.5;
    if (!label.contains('button') &&
        !label.contains('input') &&
        label.length > 5)
      c += 0.2;
    final t = widget.runtimeType.toString();
    if (t.contains('ElevatedButton') ||
        t.contains('TextButton') ||
        t.contains('TextField'))
      c += 0.2;
    if (t.contains('GestureDetector') || t.contains('InkWell')) c -= 0.1;
    return c.clamp(0.0, 1.0);
  }

  String _getSemanticWidgetLocation(Element element) {
    try {
      return element.widget.toStringShort();
    } catch (_) {}
    return element.widget.runtimeType.toString();
  }

  String _explainSemanticSuggestion(Widget widget) {
    final t = widget.runtimeType.toString();
    if (t.contains('Button'))
      return 'Interactive button should have a semantic label for accessibility';
    if (t.contains('TextField'))
      return 'Text input fields need labels for screen readers';
    if (t.contains('Checkbox') || t.contains('Switch'))
      return 'Toggle controls should describe their purpose';
    if (t.contains('GestureDetector') || t.contains('InkWell'))
      return 'Tappable area lacks semantic description';
    if (t.contains('IconButton'))
      return 'Icon-only buttons need text labels for accessibility';
    return 'Interactive widget should have a semantic label';
  }

  String _textToSnakeCase(String text) {
    var r = text
        .trim()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), '_')
        .toLowerCase();
    r = r.replaceAllMapped(
      RegExp(r'(?<!_)([A-Z])'),
      (m) => '_${m.group(1)!.toLowerCase()}',
    );
    r = r.replaceAll(RegExp(r'^_+|_+$'), '').replaceAll(RegExp(r'_+'), '_');
    return r.isEmpty ? 'widget' : r;
  }

  String _inferWidgetIdFromElement(Element element, Widget widget) {
    final m = SelfTestManager();
    for (final e in m.activeTestNodes.entries) {
      if (e.value.context == element) return e.key;
    }
    return widget.toStringShort();
  }

  int _countElementsInTree(Element? root) {
    if (root == null) return 0;
    int c = 1;
    root.visitChildren((child) {
      c += _countElementsInTree(child);
    });
    return c;
  }

  Map<String, dynamic> _extractSemanticsNodeData(SemanticsNode node) {
    final data = node.getSemanticsData();
    return {
      'id': node.id,
      'label': node.label,
      'value': node.value,
      'hint': node.hint,
      'isButton': data.hasFlag(SemanticsFlag.isButton),
      'isTextField': data.hasFlag(SemanticsFlag.isTextField),
      'isCheckbox': data.hasFlag(SemanticsFlag.hasCheckedState),
      'isChecked': data.hasFlag(SemanticsFlag.isChecked),
      'isEnabled': data.hasFlag(SemanticsFlag.isEnabled),
      'isFocused': data.hasFlag(SemanticsFlag.isFocused),
      'isSelected': data.hasFlag(SemanticsFlag.isSelected),
      'isHidden': data.hasFlag(SemanticsFlag.isHidden),
      'rect': {
        'left': node.rect.left,
        'top': node.rect.top,
        'width': node.rect.width,
        'height': node.rect.height,
      },
      'actions': _extractSemanticsActions(node),
    };
  }

  String _inferSemanticsRole(SemanticsNode node) {
    final data = node.getSemanticsData();
    if (data.hasFlag(SemanticsFlag.isButton)) return 'button';
    if (data.hasFlag(SemanticsFlag.isTextField)) return 'textbox';
    if (data.hasFlag(SemanticsFlag.hasCheckedState)) return 'checkbox';
    if (data.hasFlag(SemanticsFlag.isSlider)) return 'slider';
    if (data.hasFlag(SemanticsFlag.isLink)) return 'link';
    if (data.hasFlag(SemanticsFlag.isImage)) return 'image';
    if (data.hasFlag(SemanticsFlag.isHeader)) return 'heading';
    if (data.hasAction(SemanticsAction.tap)) return 'interactive';
    return 'generic';
  }

  List<String> _extractSemanticsActions(SemanticsNode node) {
    final data = node.getSemanticsData();
    final a = <String>[];
    if (data.hasAction(SemanticsAction.tap)) a.add('tap');
    if (data.hasAction(SemanticsAction.longPress)) a.add('longPress');
    if (data.hasAction(SemanticsAction.scrollLeft)) a.add('scrollLeft');
    if (data.hasAction(SemanticsAction.scrollRight)) a.add('scrollRight');
    if (data.hasAction(SemanticsAction.scrollUp)) a.add('scrollUp');
    if (data.hasAction(SemanticsAction.scrollDown)) a.add('scrollDown');
    if (data.hasAction(SemanticsAction.increase)) a.add('increase');
    if (data.hasAction(SemanticsAction.decrease)) a.add('decrease');
    if (data.hasAction(SemanticsAction.copy)) a.add('copy');
    if (data.hasAction(SemanticsAction.paste)) a.add('paste');
    if (data.hasAction(SemanticsAction.focus)) a.add('focus');
    return a;
  }

  Map<String, dynamic>? _generateSemanticCodeSnippet(_SemanticSuggestion s) {
    final wt = s.widgetType;
    final sl = s.suggestedLabel;
    String before, after;

    if (wt.contains('IconButton')) {
      before = 'IconButton(icon: Icon(Icons.xxx), onPressed: () {})';
      after =
          'IconButton(icon: Icon(Icons.xxx), onPressed: () {}, tooltip: \'${_snakeCaseToTitleCase(sl)}\')';
    } else if (wt.contains('Button')) {
      before = '$wt(onPressed: () {}, child: Text(\'Label\'))';
      after =
          'Semantics(label: \'$sl\', child: $wt(onPressed: () {}, child: Text(\'Label\')))';
    } else if (wt.contains('TextField')) {
      before =
          'TextField(decoration: InputDecoration(hintText: \'Enter value\'))';
      after =
          'TextField(decoration: InputDecoration(hintText: \'Enter value\', labelText: \'${_snakeCaseToTitleCase(sl)}\'))';
    } else if (wt.contains('GestureDetector') || wt.contains('InkWell')) {
      before = '$wt(onTap: () {}, child: widget)';
      after =
          'Semantics(label: \'$sl\', button: true, child: $wt(onTap: () {}, child: widget))';
    } else {
      before = '$wt(...)';
      after = 'Semantics(label: \'$sl\', child: $wt(...))';
    }

    return {
      'suggestionId': sl,
      'widgetType': wt,
      'file': s.location,
      'line': 0,
      'before': before,
      'after': after,
      'suggestedLabel': sl,
    };
  }

  String _snakeCaseToTitleCase(String s) => s
      .split('_')
      .map((w) => w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1))
      .join(' ')
      .trim();
}
