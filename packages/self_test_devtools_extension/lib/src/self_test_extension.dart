import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:devtools_extensions/devtools_extensions.dart';

class SelfTestExtension extends StatefulWidget {
  const SelfTestExtension({super.key});

  @override
  State<SelfTestExtension> createState() => _SelfTestExtensionState();
}

class _SelfTestExtensionState extends State<SelfTestExtension> {
  bool _isModeActive = false;
  List<Map<String, dynamic>> _nodes = [];
  List<String> _logs = [];
  final TextEditingController _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadNodes();
  }

  Future<void> _loadNodes() async {
    try {
      final response = await serviceManager.callServiceExtensionOnMainIsolate(
        'ext.selfTest.getNodes',
      );
      final data = jsonDecode(response.json!['value'] as String);
      setState(() {
        _nodes = List<Map<String, dynamic>>.from(data['nodes']);
      });
    } catch (e) {
      _addLog('Error loading nodes: $e');
    }
  }

  Future<void> _setMode(bool active) async {
    try {
      await serviceManager.callServiceExtensionOnMainIsolate(
        'ext.selfTest.setMode',
        args: {'active': active.toString()},
      );
      setState(() {
        _isModeActive = active;
      });
      _addLog('Self-test mode ${active ? 'activated' : 'deactivated'}');
      if (active) {
        await _loadNodes();
      } else {
        setState(() {
          _nodes = [];
        });
      }
    } catch (e) {
      _addLog('Error setting mode: $e');
    }
  }

  Future<void> _runCommand(String command, String id, [String? text]) async {
    try {
      final args = {'command': command, 'id': id};
      if (text != null) {
        args['text'] = text;
      }
      await serviceManager.callServiceExtensionOnMainIsolate(
        'ext.selfTest.runCommand',
        args: args,
      );
      _addLog('Executed $command on $id${text != null ? ' with "$text"' : ''}');
      await _loadNodes(); // Refresh nodes after command
    } catch (e) {
      _addLog('Error running command: $e');
    }
  }

  void _addLog(String message) {
    setState(() {
      _logs.add('${DateTime.now().toIso8601String()}: $message');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Self-Test DevTools'),
      ),
      body: Column(
        children: [
          // Control Panel
          Card(
            margin: const EdgeInsets.all(8),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Control Panel',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                          'Self-Test Mode: ${_isModeActive ? 'Active' : 'Inactive'}'),
                      const SizedBox(width: 16),
                      ElevatedButton(
                        onPressed: () => _setMode(!_isModeActive),
                        child: Text(_isModeActive ? 'Deactivate' : 'Activate'),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton(
                        onPressed: () => _runCommand('restartWidgetTree', ''),
                        child: const Text('Restart App'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Quick Actions
          Card(
            margin: const EdgeInsets.all(8),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Quick Actions',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButton<String>(
                          value: _nodes.isNotEmpty ? _nodes.first['id'] : null,
                          hint: const Text('Select Node'),
                          items: _nodes.map((node) {
                            return DropdownMenuItem<String>(
                              value: node['id'],
                              child: Text(
                                  '${node['id']} (${node['hasTap'] ? 'Tap' : ''}${node['hasTextChange'] ? 'Text' : ''})'),
                            );
                          }).toList(),
                          onChanged: (value) {},
                        ),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton(
                        onPressed: () {
                          final selectedId =
                              _nodes.isNotEmpty ? _nodes.first['id'] : null;
                          if (selectedId != null) {
                            _runCommand('trigger', selectedId);
                          }
                        },
                        child: const Text('Trigger'),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 200,
                        child: TextField(
                          controller: _textController,
                          decoration:
                              const InputDecoration(labelText: 'Text to Enter'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton(
                        onPressed: () {
                          final selectedId =
                              _nodes.isNotEmpty ? _nodes.first['id'] : null;
                          final text = _textController.text;
                          if (selectedId != null && text.isNotEmpty) {
                            _runCommand('enterText', selectedId, text);
                          }
                        },
                        child: const Text('Enter Text'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Logs
          Expanded(
            child: Card(
              margin: const EdgeInsets.all(8),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Logs',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _logs.length,
                        itemBuilder: (context, index) {
                          return Text(_logs[index]);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
