import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:self_test/self_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// WebSocket bridge client for Flutter Web.
///
/// This client connects TO the MCP server's WebSocket server,
/// enabling testing of Flutter Web apps.
class SelfTestBridgeClient {
  /// WebSocket channel
  WebSocketChannel? _channel;

  /// MCP server URL
  final String serverUrl;

  /// Whether the bridge is connected
  bool get isConnected => _channel != null;

  /// Reconnection settings
  final Duration reconnectDelay;
  final int maxReconnectAttempts;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  bool _shouldReconnect = true;

  /// Subscription to messages
  StreamSubscription? _subscription;

  SelfTestBridgeClient({
    String? host,
    int? port,
    this.reconnectDelay = const Duration(seconds: 2),
    this.maxReconnectAttempts = 10,
  }) : serverUrl = 'ws://${host ?? 'localhost'}:${port ?? 9999}';

  /// Start the bridge client - connects to the MCP server
  Future<void> start() async {
    await _connect();
  }

  /// Connect to the MCP server
  Future<void> _connect() async {
    try {
      debugPrint('[SelfTestBridge] Connecting to $serverUrl...');

      _channel = WebSocketChannel.connect(Uri.parse(serverUrl));

      // Wait for connection to be established
      await _channel!.ready;

      debugPrint('[SelfTestBridge] Connected to MCP server');
      _reconnectAttempts = 0;

      // Listen for messages
      _subscription = _channel!.stream.listen(
        _handleMessage,
        onError: (error) {
          debugPrint('[SelfTestBridge] WebSocket error: $error');
          _handleDisconnect();
        },
        onDone: () {
          debugPrint('[SelfTestBridge] WebSocket closed');
          _handleDisconnect();
        },
      );
    } catch (e) {
      debugPrint('[SelfTestBridge] Connection failed: $e');
      _handleDisconnect();
    }
  }

  /// Handle incoming message from MCP server
  void _handleMessage(dynamic data) {
    try {
      final message = jsonDecode(data.toString());
      final id = message['id'];
      final command = message['command'] as String?;
      final params = message['params'] as Map<String, dynamic>? ?? {};

      if (command == null) {
        _sendError(id, 'Missing command');
        return;
      }

      debugPrint('[SelfTestBridge] Received command: $command');

      // Execute command and send response
      _executeCommand(id, command, params);
    } catch (e) {
      debugPrint('[SelfTestBridge] Failed to parse message: $e');
    }
  }

  /// Execute a command from the MCP server
  Future<void> _executeCommand(
    int id,
    String command,
    Map<String, dynamic> params,
  ) async {
    try {
      final result = await _handleCommand(command, params);
      _sendResult(id, result);
    } catch (e) {
      _sendError(id, e.toString());
    }
  }

  /// Handle a command and return the result
  Future<Map<String, dynamic>> _handleCommand(
    String command,
    Map<String, dynamic> params,
  ) async {
    final manager = SelfTestManager();

    switch (command) {
      case 'snapshot':
      case 'getSnapshot':
        return _getSnapshot();

      case 'tap':
        final ref = params['ref'] as String? ?? params['widgetId'] as String?;
        if (ref == null) {
          throw Exception('Missing ref parameter');
        }
        manager.trigger(ref);
        await Future.delayed(const Duration(milliseconds: 100));
        return {'success': true};

      case 'type':
        final ref = params['ref'] as String? ?? params['widgetId'] as String?;
        final text = params['text'] as String?;
        if (ref == null || text == null) {
          throw Exception('Missing ref/widgetId or text parameter');
        }
        manager.enterText(ref, text);
        await Future.delayed(const Duration(milliseconds: 100));
        return {'success': true};

      case 'screenshot':
        return await _takeScreenshot(params);

      case 'wait':
        final ms = params['ms'] as int? ?? 1000;
        await Future.delayed(Duration(milliseconds: ms));
        return {'success': true, 'waited': ms};

      case 'getWidgetInfo':
        final ref = params['ref'] as String?;
        if (ref == null) {
          throw Exception('Missing ref parameter');
        }
        final info = manager.getWidgetInfo(ref);
        return info ?? {'error': 'Widget not found'};

      case 'clear':
        final ref = params['ref'] as String? ?? params['widgetId'] as String?;
        if (ref == null) {
          throw Exception('Missing ref/widgetId parameter');
        }
        manager.enterText(ref, '');
        return {'success': true};

      case 'scroll':
        // Scroll is handled by tap on scrollable area
        return {'success': true, 'note': 'Use tap on scroll target'};

      case 'navigate':
        final route = params['route'] as String?;
        if (route == null) {
          throw Exception('Missing route parameter');
        }
        // Navigation would need router access - return guidance
        return {
          'success': false,
          'note':
              'Direct navigation not supported in client mode. Use tap on navigation elements.'
        };

      default:
        throw Exception('Unknown command: $command');
    }
  }

  /// Get widget tree snapshot
  Map<String, dynamic> _getSnapshot() {
    final manager = SelfTestManager();
    final widgets = manager.getRegisteredWidgets();

    final widgetList = widgets.entries.map((entry) {
      final info = manager.getWidgetInfo(entry.key);
      return {
        'id': entry.key,
        'type': info?['type'] ?? 'unknown',
        'hasCallback':
            entry.value['onTap'] != null || entry.value['onTextChange'] != null,
        ...?info,
      };
    }).toList();

    return {
      'currentScreen': 'unknown', // Would need router access
      'widgets': widgetList,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  /// Take a screenshot
  Future<Map<String, dynamic>> _takeScreenshot(
      Map<String, dynamic> params) async {
    try {
      // For web, we use html2canvas or similar approach
      // For now, return a placeholder
      if (kIsWeb) {
        return {
          'success': false,
          'note':
              'Screenshots on web require additional setup. Use browser DevTools or Playwright for screenshots.',
        };
      }

      // Native screenshot using RepaintBoundary
      final boundary = _findRepaintBoundary();
      if (boundary == null) {
        return {'success': false, 'error': 'No RepaintBoundary found'};
      }

      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) {
        return {'success': false, 'error': 'Failed to capture image'};
      }

      final base64 = base64Encode(byteData.buffer.asUint8List());
      return {
        'success': true,
        'base64': base64,
        'width': image.width,
        'height': image.height,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Find a RepaintBoundary for screenshots
  RenderRepaintBoundary? _findRepaintBoundary() {
    final renderObject = WidgetsBinding.instance.rootElement?.renderObject;
    if (renderObject == null) return null;

    RenderRepaintBoundary? boundary;
    void visit(RenderObject object) {
      if (object is RenderRepaintBoundary) {
        boundary = object;
        return;
      }
      object.visitChildren(visit);
    }

    visit(renderObject);
    return boundary;
  }

  /// Send result back to MCP server
  void _sendResult(int id, Map<String, dynamic> result) {
    _send({'id': id, 'result': result});
  }

  /// Send error back to MCP server
  void _sendError(int id, String error) {
    _send({'id': id, 'error': error});
  }

  /// Send a message to the MCP server
  void _send(Map<String, dynamic> message) {
    if (_channel == null) {
      debugPrint('[SelfTestBridge] Cannot send - not connected');
      return;
    }
    _channel!.sink.add(jsonEncode(message));
  }

  /// Handle disconnection
  void _handleDisconnect() {
    _channel = null;
    _subscription?.cancel();
    _subscription = null;

    if (_shouldReconnect && _reconnectAttempts < maxReconnectAttempts) {
      _reconnectAttempts++;
      debugPrint(
          '[SelfTestBridge] Reconnecting in ${reconnectDelay.inSeconds}s (attempt $_reconnectAttempts/$maxReconnectAttempts)...');

      _reconnectTimer = Timer(reconnectDelay, () {
        _connect();
      });
    } else if (_reconnectAttempts >= maxReconnectAttempts) {
      debugPrint('[SelfTestBridge] Max reconnect attempts reached. Giving up.');
    }
  }

  /// Stop the bridge client
  Future<void> stop() async {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    await _channel?.sink.close();
    _channel = null;
    debugPrint('[SelfTestBridge] Stopped');
  }
}
