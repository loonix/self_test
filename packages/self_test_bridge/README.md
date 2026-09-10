# self_test_bridge

WebSocket bridge that enables MCP server communication with Flutter apps using the self_test framework.

## Overview

This package provides the Flutter-side infrastructure for AI-powered testing:

```
┌─────────────────┐        ┌─────────────────┐        ┌─────────────────┐
│   AI Agent      │  MCP   │  MCP Server     │   WS   │  Flutter App    │
│   (Claude)      │◄──────►│  (TypeScript)   │◄──────►│  (self_test)    │
└─────────────────┘        └─────────────────┘        └─────────────────┘
```

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  self_test:
    path: ../internal_packages/self_test
  self_test_bridge:
    path: ../internal_packages/self_test_bridge
```

## Quick Start

### 1. Start the Bridge

In your `main.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:self_test/self_test.dart';
import 'package:self_test_bridge/self_test_bridge.dart';

final navigatorKey = GlobalKey<NavigatorState>();
final bridgeNavigator = NavigatorStateBridgeNavigator(navigatorKey);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Start bridge in debug mode only
  if (kDebugMode) {
    final bridge = SelfTestBridge(
      navigator: bridgeNavigator,  // How the bridge navigates
      port: 9999,                  // WebSocket port
    );
    await bridge.start();
  }

  // Enable self-test mode
  SelfTestManager().setSelfTestModeActive(kDebugMode);

  runApp(const MyApp());
}
```

### 2. Wrap Your App

```dart
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SelfTestRoot(
      enableAutoDetection: true,  // Auto-detect interactive widgets
      child: ScreenshotBoundary(
        child: MaterialApp(
          navigatorKey: navigatorKey,
          // Optional: lets the bridge see the whole route stack.
          navigatorObservers: [bridgeNavigator.observer],
          routes: {'/': (_) => const HomeScreen()},
        ),
      ),
    );
  }
}
```

### Using a routing package

`BridgeNavigator` is a four-member interface, so any router can drive the
bridge. For go_router:

```dart
class GoRouterBridgeNavigator implements BridgeNavigator {
  GoRouterBridgeNavigator(this.router);
  final GoRouter router;

  @override
  Future<void> goTo(String location, {bool replace = false}) async =>
      replace ? router.go(location) : router.push(location);

  @override
  Future<void> goBack() async => router.pop();

  @override
  bool get canGoBack => router.canPop();

  @override
  String? get currentLocation =>
      router.routerDelegate.currentConfiguration.uri.toString();

  @override
  List<Map<String, dynamic>> describeRoutes() => const [];
}
```

With no navigator configured, the navigation commands return an error rather
than reporting a success for a move that never happened.

### 3. Add Semantic Labels

For stable test IDs, add `Semantics` labels to your widgets:

```dart
// Button with stable ID
Semantics(
  label: 'login_button',
  child: ElevatedButton(
    onPressed: handleLogin,
    child: Text('Login'),
  ),
)

// Text input with stable ID
Semantics(
  label: 'email_input',
  child: TextField(
    controller: emailController,
    decoration: InputDecoration(labelText: 'Email'),
  ),
)
```

### 4. Configure MCP Server

Add to your Claude Code settings:

```json
{
  "mcpServers": {
    "flutter-self-test": {
      "command": "node",
      "args": ["/path/to/self_test_mcp/dist/index.js"],
      "env": {
        "FLUTTER_APP_HOST": "localhost",
        "FLUTTER_APP_PORT": "9999"
      }
    }
  }
}
```

## How It Works

### Bridge Protocol

The bridge uses a simple JSON-RPC over WebSocket:

**Request (MCP → Flutter):**
```json
{
  "id": 1,
  "command": "tap",
  "params": { "widgetId": "login_button" }
}
```

**Response (Flutter → MCP):**
```json
{
  "id": 1,
  "result": { "success": true }
}
```

### Supported Commands

| Command | Description | Parameters |
|---------|-------------|------------|
| `getSnapshot` | Get current widget tree | - |
| `getWidgetCatalog` | Get all detected widgets | - |
| `getFlowGraph` | Get navigation structure | - |
| `getScreens` | List discovered screens | - |
| `getCurrentState` | Get app state | - |
| `tap` | Tap a widget | `widgetId` |
| `enterText` | Type into input | `widgetId`, `text`, `submit?` |
| `navigate` | Go to route | `route` |
| `scroll` | Scroll in container | `widgetId?`, `direction`, `amount?` |
| `screenshot` | Capture screen | `name?` |
| `assertWidget` | Check widget state | `widgetId`, `assertion`, `expectedText?` |
| `runScenario` | Run test scenario | `name`, `steps[]` |
| `waitFor` | Wait for condition | `condition`, `widgetId?`, `timeoutMs?` |

### Widget Auto-Detection

When `enableAutoDetection: true`, the bridge automatically detects:

- `ElevatedButton`, `TextButton`, `OutlinedButton`
- `IconButton`, `FloatingActionButton`
- `GestureDetector` (with `onTap`)
- `InkWell`
- `TextField`, `TextFormField`

## AI Testing Workflow

### 1. AI Gets Widget Snapshot

```
AI → flutter_snapshot
Flutter → { currentScreen: "login", widgets: [...] }
```

### 2. AI Interacts

```
AI → flutter_type { widgetId: "email_input", text: "test@example.com" }
AI → flutter_type { widgetId: "password_input", text: "password123" }
AI → flutter_tap { widgetId: "submit_button" }
```

### 3. AI Verifies

```
AI → flutter_assert { widgetId: "welcome_message", assertion: "exists" }
AI → flutter_screenshot { name: "login_success" }
```

## Best Practices

### 1. Use Semantic Labels

Always prefer `Semantics` labels over widget keys:

```dart
// ✅ Good - stable, accessible
Semantics(
  label: 'submit_button',
  child: ElevatedButton(...),
)

// ⚠️ Okay - stable but not accessible
ElevatedButton(
  key: const ValueKey('submit_button'),
  ...
)

// ❌ Bad - unstable ID generated
ElevatedButton(...)  // → elevatedbutton_12345_UNSTABLE
```

### 2. Group by Screen

Widget IDs are automatically grouped by screen. Use consistent naming:

```
login_email_input
login_password_input
login_submit_button

settings_notifications_toggle
settings_dark_mode_toggle
```

### 3. Handle Loading States

For async operations, use `waitFor`:

```dart
// In test scenario
TestStep.tap('submit_button'),
TestStep.custom('waitFor', {
  condition: 'widget_exists',
  widgetId: 'success_message'
}),
```

## Security

The bridge only runs in debug mode by default. Never include it in release builds:

```dart
if (kDebugMode) {
  await bridge.start();
}
```

## Troubleshooting

### "Connection refused"

1. Make sure the Flutter app is running
2. Check the port isn't blocked by firewall
3. Verify `bridge.start()` was called

### "Widget not found"

1. Run `flutter_snapshot` to see available widgets
2. Check if widget has a semantic label
3. Wait for animations with `flutter_wait`

### "Unstable ID warning"

Add a `Semantics` label to the widget:

```dart
Semantics(
  label: 'my_widget_id',
  child: MyWidget(...),
)
```
