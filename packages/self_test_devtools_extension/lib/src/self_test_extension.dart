import 'dart:convert';

import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/material.dart';

/// How one widget on the running app's screen is addressed from here.
///
/// The panel used to list only widgets the app had wrapped in
/// `SelfTestableWidget`, which on an app that has not been changed for testing
/// is none of them. It now lists whatever is on screen and works out how to
/// point at each one.
class ScreenWidget {
  ScreenWidget(this.json, this.index);

  final Map<String, dynamic> json;

  /// Which match this is among the widgets sharing its locator, so two rows
  /// reading "Delete" do not both act on the first one.
  final int index;

  String get type => json['type'] as String? ?? 'Widget';
  String? get id => json['id'] as String?;
  String? get key => json['key'] as String?;
  String? get text => json['text'] as String?;
  String? get tooltip => json['tooltip'] as String?;
  bool get enabled => json['enabled'] as bool? ?? true;
  bool get interactive => json['interactive'] as bool? ?? false;

  /// The most specific way to point at this widget that will still be true
  /// after the app rebuilds.
  (String, String) get locator {
    if (id != null) return ('id', id!);
    if (key != null) return ('key', key!);
    if (tooltip != null) return ('tooltip', tooltip!);
    if (text != null && text!.isNotEmpty) return ('text', text!);
    return ('type', type);
  }

  String get label {
    final parts = <String>[type];
    if (text != null && text!.isNotEmpty) parts.add('"${text!}"');
    if (id != null) parts.add('#${id!}');
    if (tooltip != null) parts.add('tooltip: ${tooltip!}');
    if (!enabled) parts.add('disabled');
    return parts.join('  ');
  }
}

class SelfTestExtension extends StatefulWidget {
  const SelfTestExtension({super.key});

  @override
  State<SelfTestExtension> createState() => _SelfTestExtensionState();
}

class _SelfTestExtensionState extends State<SelfTestExtension> {
  List<ScreenWidget> _widgets = const [];
  final List<String> _logs = [];
  final TextEditingController _textController = TextEditingController();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final response = await serviceManager.callServiceExtensionOnMainIsolate(
        'ext.selfTest.getNodes',
      );
      final data =
          jsonDecode(response.json!['value'] as String) as Map<String, dynamic>;
      final raw = (data['nodes'] as List<dynamic>).cast<Map<String, dynamic>>();

      // Count as we go, so the index sent with each locator matches the
      // position the app will resolve it to.
      final seen = <String, int>{};
      final widgets = <ScreenWidget>[];
      for (final node in raw) {
        final candidate = ScreenWidget(node, 0);
        final key = '${candidate.locator.$1}:${candidate.locator.$2}';
        final index = seen[key] ?? 0;
        seen[key] = index + 1;
        widgets.add(ScreenWidget(node, index));
      }

      setState(() => _widgets = widgets);
      _log('Listed ${widgets.length} widgets');
    } catch (error) {
      _log('Could not list widgets: $error');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _run(String command, ScreenWidget widget, [String? text]) async {
    final (by, value) = widget.locator;
    try {
      await serviceManager.callServiceExtensionOnMainIsolate(
        'ext.selfTest.runCommand',
        args: {
          'command': command,
          'by': by,
          'value': value,
          'index': '${widget.index}',
          if (text != null) 'text': text,
        },
      );
      _log('$command on $by "$value" (index ${widget.index})');
      await _refresh();
    } catch (error) {
      _log('$command failed on $by "$value": $error');
    }
  }

  void _log(String message) {
    setState(() {
      _logs.insert(0, '${DateTime.now().toIso8601String()}  $message');
      if (_logs.length > 200) _logs.removeLast();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('self_test'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              controller: _textController,
              decoration: const InputDecoration(
                labelText: 'Text to type',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: _widgets.isEmpty
                ? const Center(
                    child: Text(
                      'Nothing listed yet. Refresh with the app in the '
                      'foreground.',
                    ),
                  )
                : ListView.builder(
                    itemCount: _widgets.length,
                    itemBuilder: (context, i) {
                      final widget = _widgets[i];
                      return ListTile(
                        dense: true,
                        title: Text(widget.label),
                        subtitle: Text(
                          '${widget.locator.$1}: ${widget.locator.$2}'
                          '${widget.index == 0 ? '' : ' (index ${widget.index})'}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: widget.enabled
                                  ? () => _run('tap', widget)
                                  : null,
                              child: const Text('Tap'),
                            ),
                            TextButton(
                              onPressed: () =>
                                  _run('type', widget, _textController.text),
                              child: const Text('Type'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: _logs.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 2,
                ),
                child: Text(
                  _logs[i],
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
