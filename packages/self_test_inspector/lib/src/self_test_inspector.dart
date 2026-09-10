import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class SelfTestInspector extends StatefulWidget {
  const SelfTestInspector({super.key});

  @override
  State<SelfTestInspector> createState() => _SelfTestInspectorState();
}

class _SelfTestInspectorState extends State<SelfTestInspector> {
  bool _isConnected = false;
  bool _isModeActive = false;
  List<Map<String, dynamic>> _nodes = [];
  List<String> _logs = [];
  final TextEditingController _vmServiceUrlController = TextEditingController();
  final TextEditingController _textController = TextEditingController();
  String? _isolateId;

  @override
  void initState() {
    super.initState();
    // Try to auto-connect if URL is provided in the query parameters
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryAutoConnect();
    });
  }

  void _tryAutoConnect() {
    // Check for VM service URL in the current URL parameters
    final uri = Uri.base;
    final vmServiceUri = uri.queryParameters['uri'];
    if (vmServiceUri != null) {
      _vmServiceUrlController.text = vmServiceUri;
      _connect();
    }
  }

  Future<void> _connect() async {
    final url = _vmServiceUrlController.text.trim();
    if (url.isEmpty) {
      _addLog('Please enter a VM service URL');
      return;
    }

    try {
      _addLog('Connecting to VM service at: $url');

      // Get VM info via HTTP to find isolate
      final vmResponse = await http
          .get(Uri.parse('$url/getVM'))
          .timeout(const Duration(seconds: 10));
      if (vmResponse.statusCode != 200) {
        throw Exception('Failed to get VM info: ${vmResponse.statusCode}');
      }

      final vmData = jsonDecode(vmResponse.body);
      _addLog('VM info retrieved via HTTP');

      final isolates = vmData['isolates'];
      if (isolates == null || isolates.isEmpty) {
        throw Exception('No isolates found');
      }

      _isolateId = isolates[0]['id'];
      _addLog('Found isolate: $_isolateId');

      setState(() {
        _isConnected = true;
      });

      _addLog('Connected successfully!');
      await _loadNodes();
    } catch (e, stackTrace) {
      _addLog('Failed to connect: $e');
      if (stackTrace.toString().isNotEmpty) {
        _addLog('Stack trace: $stackTrace');
      }
      setState(() {
        _isConnected = false;
      });
    }
  }

  Future<void> _disconnect() async {
    setState(() {
      _isConnected = false;
      _isModeActive = false;
      _nodes = [];
      _isolateId = null;
    });
    _addLog('Disconnected from VM service');
  }

  Future<void> _loadNodes() async {
    if (!_isConnected || _isolateId == null) return;

    try {
      final url = _vmServiceUrlController.text.trim();
      final response = await http
          .post(
            Uri.parse('$url/$_isolateId/ext.selfTest.getNodes'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({}),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }

      final result = jsonDecode(response.body);
      if (result['result'] != null && result['result']['value'] != null) {
        final nodesData = jsonDecode(result['result']['value'] as String);
        setState(() {
          _nodes = List<Map<String, dynamic>>.from(nodesData['nodes']);
        });
        _addLog('Loaded ${_nodes.length} test nodes');
      } else {
        _addLog('No nodes data in response: ${response.body}');
      }
    } catch (e) {
      _addLog('Error loading nodes: $e');
    }
  }

  Future<void> _setMode(bool active) async {
    if (!_isConnected || _isolateId == null) return;

    try {
      final url = _vmServiceUrlController.text.trim();
      final response = await http
          .post(
            Uri.parse('$url/$_isolateId/ext.selfTest.setMode'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'active': active}),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }

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
    if (!_isConnected || _isolateId == null) return;

    try {
      final url = _vmServiceUrlController.text.trim();
      final args = {'command': command, 'id': id};
      if (text != null) {
        args['text'] = text;
      }

      final response = await http
          .post(
            Uri.parse('$url/$_isolateId/ext.selfTest.runCommand'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(args),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }

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
        title: const Text('Self-Test Inspector'),
        backgroundColor: _isConnected ? Colors.green : Colors.red,
      ),
      body: Column(
        children: [
          // Connection Panel
          Card(
            margin: const EdgeInsets.all(8),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Connection',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _vmServiceUrlController,
                          decoration: const InputDecoration(
                            labelText: 'VM Service URL',
                            hintText: 'http://127.0.0.1:XXXX/XXXX=',
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton(
                        onPressed: _isConnected ? _disconnect : _connect,
                        child: Text(_isConnected ? 'Disconnect' : 'Connect'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Status: ${_isConnected ? 'Connected' : 'Disconnected'}',
                    style: TextStyle(
                      color: _isConnected ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Control Panel
          if (_isConnected)
            Card(
              margin: const EdgeInsets.all(8),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Control Panel',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          'Self-Test Mode: ${_isModeActive ? 'Active' : 'Inactive'}',
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton(
                          onPressed: () => _setMode(!_isModeActive),
                          child: Text(
                            _isModeActive ? 'Deactivate' : 'Activate',
                          ),
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
          if (_isConnected && _isModeActive)
            Card(
              margin: const EdgeInsets.all(8),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Quick Actions',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButton<String>(
                            value: _nodes.isNotEmpty
                                ? _nodes.first['id']
                                : null,
                            hint: const Text('Select Node'),
                            items: _nodes.map((node) {
                              return DropdownMenuItem<String>(
                                value: node['id'],
                                child: Text(
                                  '${node['id']} (${node['hasTap'] ? 'Tap' : ''}${node['hasTextChange'] ? 'Text' : ''})',
                                ),
                              );
                            }).toList(),
                            onChanged: (value) {},
                          ),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton(
                          onPressed: () {
                            final selectedId = _nodes.isNotEmpty
                                ? _nodes.first['id']
                                : null;
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
                            decoration: const InputDecoration(
                              labelText: 'Text to Enter',
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton(
                          onPressed: () {
                            final selectedId = _nodes.isNotEmpty
                                ? _nodes.first['id']
                                : null;
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
                    const Text(
                      'Logs',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
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

  @override
  void dispose() {
    _vmServiceUrlController.dispose();
    _textController.dispose();
    super.dispose();
  }
}
