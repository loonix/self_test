# self_test MCP Server

An MCP (Model Context Protocol) server that enables AI agents to interact with Flutter apps using the self_test framework. Provides **Playwright feature parity** for Flutter testing.

## Quick Start

```bash
# Build the MCP server
npm install && npm run build

# Add to Claude Code (interactive)
./scripts/setup-claude.sh

# Or add manually to ~/.claude/settings.json
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         AI Agent (Claude)                        │
└─────────────────────────────┬───────────────────────────────────┘
                              │ MCP Protocol (JSON-RPC over stdio)
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     self_test MCP Server                         │
│                        (TypeScript/Node)                         │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │  60+ Tools (Playwright Parity)                              ││
│  │  - Locators: snapshot, getByRole, getByText                 ││
│  │  - Actions: tap, type, scroll, drag, hover, focus           ││
│  │  - Assertions: expect, expectScreenshot, goldens            ││
│  │  - Network: mockHttp, blockHttp, networkLog, harExport      ││
│  │  - State: getState, dispatchAction, watchState              ││
│  │  - Platform: mockChannel, setGeolocation, setPermission     ││
│  │  - Tracing: traceStart, traceStop, console, errors          ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────┬───────────────────────────────────┘
                              │ WebSocket (ws://localhost:9999)
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Flutter App                                 │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                 SelfTestBridge Service                       ││
│  │  - WebSocket server on port 9999                            ││
│  │  - Receives commands from MCP server                        ││
│  │  - Executes actions via SelfTestManager                     ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

## Installation

### 1. Build MCP Server

```bash
cd self_test_mcp
npm install
npm run build
```

### 2. Add to Claude Code

**Option A: Automatic Setup**
```bash
./scripts/setup-claude.sh
```

**Option B: Manual Setup**

Add to `~/.claude/settings.json`:
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

### 3. Flutter App Integration

Add to `pubspec.yaml`:
```yaml
dependencies:
  self_test:
    path: ../internal_packages/self_test
  self_test_bridge:
    path: ../internal_packages/self_test_bridge
```

Add to `main.dart`:
```dart
import 'package:flutter/foundation.dart';
import 'package:self_test_bridge/self_test_bridge.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kDebugMode) {
    final bridge = SelfTestBridge(router: goRouter, port: 9999);
    await bridge.start();
  }

  runApp(MyApp());
}
```

**Optional: HTTP Interceptor for Dio**

To enable HTTP mocking and network logging with Dio:
```dart
import 'package:dio/dio.dart';
import 'package:self_test_bridge/self_test_bridge.dart';

final dio = Dio();

if (kDebugMode) {
  dio.interceptors.add(SelfTestHttpInterceptor());
}
```

## Available Tools

### Locators

| Tool | Description | Playwright Equivalent |
|------|-------------|----------------------|
| `flutter_snapshot` | Get accessibility snapshot of current screen | `page.accessibility.snapshot()` |
| `flutter_get_by_role` | Find widgets by semantic role | `page.getByRole()` |
| `flutter_get_by_text` | Find widgets by text content | `page.getByText()` |

### Actions

| Tool | Description | Playwright Equivalent |
|------|-------------|----------------------|
| `flutter_tap` | Tap/click a widget | `locator.click()` |
| `flutter_type` | Type text into input | `locator.fill()` |
| `flutter_clear` | Clear input field | `locator.clear()` |
| `flutter_press_key` | Press keyboard key | `keyboard.press()` |
| `flutter_scroll` | Scroll in direction | `mouse.wheel()` |
| `flutter_scroll_to` | Scroll until widget visible | `locator.scrollIntoViewIfNeeded()` |
| `flutter_drag` | Drag and drop | `page.dragAndDrop()` |
| `flutter_long_press` | Long press widget | N/A (Flutter-specific) |
| `flutter_double_tap` | Double tap widget | `locator.dblclick()` |
| `flutter_hover` | Hover over widget | `locator.hover()` |
| `flutter_focus` | Focus on widget | `locator.focus()` |
| `flutter_select` | Select dropdown option | `locator.selectOption()` |
| `flutter_toggle` | Toggle checkbox/switch | `locator.check()` / `uncheck()` |
| `flutter_slider` | Set slider value | N/A (Flutter-specific) |

### Navigation

| Tool | Description | Playwright Equivalent |
|------|-------------|----------------------|
| `flutter_navigate` | Navigate to route | `page.goto()` |
| `flutter_back` | Go back | `page.goBack()` |
| `flutter_reload` | Hot reload app | `page.reload()` |
| `flutter_restart` | Hot restart app | N/A |

### Waiting

| Tool | Description | Playwright Equivalent |
|------|-------------|----------------------|
| `flutter_wait` | Wait for conditions | `locator.waitFor()` |

Conditions: `visible`, `hidden`, `enabled`, `disabled`, `text`, `idle`, `network_idle`, `duration`

### Assertions

| Tool | Description | Playwright Equivalent |
|------|-------------|----------------------|
| `flutter_expect` | Assert widget state | `expect(locator).toBeVisible()` etc. |
| `flutter_expect_screenshot` | Visual regression test | `expect(page).toHaveScreenshot()` |

Assertions: `toBeVisible`, `toBeHidden`, `toBeEnabled`, `toBeDisabled`, `toBeChecked`, `toBeUnchecked`, `toHaveText`, `toContainText`, `toHaveValue`, `toHaveCount`, `toBeFocused`

### Screenshots & Video

| Tool | Description | Playwright Equivalent |
|------|-------------|----------------------|
| `flutter_screenshot` | Take screenshot | `page.screenshot()` |
| `flutter_record_start` | Start recording | `context.tracing.start()` |
| `flutter_record_stop` | Stop recording | `context.tracing.stop()` |

### Network

| Tool | Description | Playwright Equivalent |
|------|-------------|----------------------|
| `flutter_mock_http` | Mock HTTP responses | `page.route()` |
| `flutter_block_http` | Block requests | `page.route()` + abort |
| `flutter_clear_mocks` | Clear all mocks | N/A |
| `flutter_network_log` | Get request log | HAR recording |
| `flutter_wait_network` | Wait for request | `page.waitForResponse()` |

### Console & Errors

| Tool | Description | Playwright Equivalent |
|------|-------------|----------------------|
| `flutter_console` | Get console messages | `page.on('console')` |
| `flutter_errors` | Get Flutter errors | `page.on('pageerror')` |

### Tracing

| Tool | Description | Playwright Equivalent |
|------|-------------|----------------------|
| `flutter_trace_start` | Start tracing | `tracing.start()` |
| `flutter_trace_stop` | Stop and save trace | `tracing.stop()` |

### Device Emulation

| Tool | Description | Playwright Equivalent |
|------|-------------|----------------------|
| `flutter_resize` | Resize viewport | `page.setViewportSize()` |
| `flutter_set_theme` | Switch light/dark | `emulateMedia()` |
| `flutter_set_locale` | Change locale | `context.locale` |
| `flutter_set_text_scale` | Change text scale | N/A (Flutter-specific) |

### Dialogs & Overlays

| Tool | Description | Playwright Equivalent |
|------|-------------|----------------------|
| `flutter_dialog` | Handle alerts/dialogs | `page.on('dialog')` |
| `flutter_dismiss_overlay` | Dismiss overlays | N/A |

### Storage & State

| Tool | Description | Playwright Equivalent |
|------|-------------|----------------------|
| `flutter_storage_get` | Get storage value | `evaluate(localStorage)` |
| `flutter_storage_set` | Set storage value | `evaluate(localStorage)` |
| `flutter_storage_clear` | Clear storage | `storageState()` |
| `flutter_save_state` | Save app state | `storageState()` |
| `flutter_restore_state` | Restore app state | `context.storageState()` |

### Files

| Tool | Description | Playwright Equivalent |
|------|-------------|----------------------|
| `flutter_file_picker` | Mock file picker | `fileChooser.setFiles()` |

### Test Scenarios

| Tool | Description | Playwright Equivalent |
|------|-------------|----------------------|
| `flutter_run_scenario` | Run multi-step test | Test runner |

### Accessibility

| Tool | Description | Playwright Equivalent |
|------|-------------|----------------------|
| `flutter_accessibility_audit` | Run a11y audit | `axe.run()` |

### Golden Testing

| Tool | Description | Playwright Equivalent |
|------|-------------|----------------------|
| `flutter_expect_screenshot` | Compare against golden baseline | `expect(page).toHaveScreenshot()` |
| `flutter_update_goldens` | Update golden baselines | `--update-snapshots` flag |
| `flutter_list_goldens` | List all golden files | N/A |

### State Management Inspection

| Tool | Description | Playwright Equivalent |
|------|-------------|----------------------|
| `flutter_get_state` | Get state from Riverpod/Bloc/Provider | `evaluate()` |
| `flutter_dispatch_action` | Dispatch action/event to state | `evaluate()` |
| `flutter_watch_state` | Subscribe to state changes | N/A |
| `flutter_unwatch_state` | Unsubscribe from state changes | N/A |
| `flutter_list_state_providers` | List all registered providers | N/A |

### Platform Channel Mocking

| Tool | Description | Playwright Equivalent |
|------|-------------|----------------------|
| `flutter_mock_channel` | Mock platform channel responses | N/A (Flutter-specific) |
| `flutter_clear_channel_mocks` | Clear channel mocks | N/A |
| `flutter_channel_log` | Get platform channel call log | N/A |

### Sensor & Device Mocking

| Tool | Description | Playwright Equivalent |
|------|-------------|----------------------|
| `flutter_set_geolocation` | Set mock GPS coordinates | `context.setGeolocation()` |
| `flutter_set_permission` | Set mock permission state | `context.grantPermissions()` |
| `flutter_set_connectivity` | Set mock network connectivity | `context.setOffline()` |

### Clipboard

| Tool | Description | Playwright Equivalent |
|------|-------------|----------------------|
| `flutter_clipboard_read` | Read clipboard contents | `evaluate(navigator.clipboard)` |
| `flutter_clipboard_write` | Write to clipboard | `evaluate(navigator.clipboard)` |

### HAR Export

| Tool | Description | Playwright Equivalent |
|------|-------------|----------------------|
| `flutter_har_export` | Export network log as HAR 1.2 | HAR recording |

### Animation Control

| Tool | Description | Playwright Equivalent |
|------|-------------|----------------------|
| `flutter_animation_speed` | Control animation speed (0-10x) | N/A (Flutter-specific) |
| `flutter_pump` | Advance frame/duration | N/A (Flutter-specific) |

## Resources

| Resource | Description |
|----------|-------------|
| `flutter://widgets` | Complete widget catalog |
| `flutter://flows` | Navigation flow graph |
| `flutter://state` | Current app state |

## Example Usage

### Basic Interaction

```typescript
// Get widget snapshot
await mcp.callTool("flutter_snapshot", {});
// Returns: { currentScreen: "login", widgets: [...] }

// Type into email field
await mcp.callTool("flutter_type", {
  widgetId: "email_input",
  text: "test@example.com"
});

// Tap login button
await mcp.callTool("flutter_tap", {
  widgetId: "login_button"
});

// Assert navigation happened
await mcp.callTool("flutter_expect", {
  widgetId: "dashboard_title",
  assertion: "toBeVisible"
});
```

### Visual Regression

```typescript
// Create baseline
await mcp.callTool("flutter_expect_screenshot", {
  name: "login_screen",
  updateBaseline: true
});

// Compare against baseline
await mcp.callTool("flutter_expect_screenshot", {
  name: "login_screen",
  threshold: 0.1
});
```

### Network Mocking

```typescript
// Mock API response
await mcp.callTool("flutter_mock_http", {
  urlPattern: "*/api/users",
  response: {
    status: 200,
    body: { users: [{ id: 1, name: "Test" }] }
  }
});

// Wait for request
await mcp.callTool("flutter_wait_network", {
  urlPattern: "*/api/users",
  timeout: 5000
});
```

### Test Scenario

```typescript
await mcp.callTool("flutter_run_scenario", {
  name: "login_flow",
  steps: [
    { action: "navigate", params: { route: "/login" } },
    { action: "type", params: { widgetId: "email", text: "test@example.com" } },
    { action: "type", params: { widgetId: "password", text: "password123" } },
    { action: "tap", params: { widgetId: "submit" } },
    { action: "wait", params: { condition: "visible", widgetId: "dashboard" } },
    { action: "expect", params: { widgetId: "welcome_text", assertion: "toContainText", expected: "Welcome" } }
  ],
  stopOnError: true
});
```

### State Management Inspection

```typescript
// List all state providers
await mcp.callTool("flutter_list_state_providers", {});
// Returns: { providers: [{ id: "userProvider", type: "riverpod", ... }] }

// Get current state
await mcp.callTool("flutter_get_state", {
  providerId: "userProvider"
});
// Returns: { state: { name: "John", email: "john@example.com" } }

// Dispatch an action (Bloc)
await mcp.callTool("flutter_dispatch_action", {
  providerId: "authBloc",
  action: "LogoutRequested"
});

// Watch state changes
await mcp.callTool("flutter_watch_state", {
  providerId: "cartProvider"
});
// Returns: { subscriptionId: "sub_123" }
```

### Platform Channel Mocking

```typescript
// Mock a native plugin response
await mcp.callTool("flutter_mock_channel", {
  channel: "plugins.flutter.io/camera",
  method: "availableCameras",
  response: [{ id: "0", name: "Back Camera" }]
});

// View channel call log
await mcp.callTool("flutter_channel_log", {});
// Returns: { calls: [{ channel: "...", method: "...", arguments: {...} }] }
```

### Geolocation & Permission Mocking

```typescript
// Set mock GPS location
await mcp.callTool("flutter_set_geolocation", {
  latitude: 37.7749,
  longitude: -122.4194,
  accuracy: 10.0
});

// Set permission state
await mcp.callTool("flutter_set_permission", {
  permission: "camera",
  state: "granted"  // granted, denied, restricted, permanentDenied
});

// Set connectivity state
await mcp.callTool("flutter_set_connectivity", {
  state: "wifi",  // wifi, mobile, ethernet, none
  isConnected: true
});
```

### Golden Testing

```typescript
// Update golden baseline
await mcp.callTool("flutter_update_goldens", {
  names: ["login_screen", "dashboard"]  // or omit for all
});

// List golden files
await mcp.callTool("flutter_list_goldens", {});
// Returns: { goldens: [{ name: "login_screen", path: "...", size: 12345 }] }
```

### HAR Export

```typescript
// Export network log as HAR file
await mcp.callTool("flutter_har_export", {
  path: "/tmp/network.har"
});
```

### Animation Control

```typescript
// Slow down animations for debugging (2x slower)
await mcp.callTool("flutter_animation_speed", {
  speed: 0.5
});

// Disable animations entirely
await mcp.callTool("flutter_animation_speed", {
  speed: 0
});

// Advance time for animation testing
await mcp.callTool("flutter_pump", {
  milliseconds: 500
});
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `FLUTTER_APP_HOST` | `localhost` | Flutter app WebSocket host |
| `FLUTTER_APP_PORT` | `9999` | Flutter app WebSocket port |

## Troubleshooting

### "Connection refused"
1. Ensure Flutter app is running with `SelfTestBridge` started
2. Check port 9999 is not blocked
3. Verify `FLUTTER_APP_PORT` matches bridge port

### "Widget not found"
1. Use `flutter_snapshot` to see available widgets
2. Add `Semantics` labels to your widgets for stable IDs
3. Use `flutter_wait` before interacting with widgets

### "Unstable ID warning"
Add semantic labels to widgets:
```dart
Semantics(
  label: 'login_button',
  child: ElevatedButton(...),
)
```

## Development

```bash
# Watch mode
npm run dev

# Build
npm run build

# Run directly
npm start
```

## License

MIT
