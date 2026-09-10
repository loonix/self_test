# self_test MCP Server

An MCP (Model Context Protocol) server that enables AI agents to interact with Flutter apps using the self_test framework. Provides **Playwright feature parity** for Flutter testing.

## Quick Start

```bash
# Check it runs, without needing an app, a bridge or a browser
npx self-test-mcp --help
npx self-test-mcp --version

# Or from a clone
npm install && npm run build && npm test

# Add to Claude Code (interactive)
./scripts/setup-claude.sh
```

`--help` and `--version` answer and exit 0 before anything connects, so the
CLI can be introspected on a machine with nothing running.

## The bridge token

The bridge binds to loopback and **requires a token**. The Flutter app prints
its URL at startup:

```
self_test bridge listening on ws://127.0.0.1:9999?token=7f3c9a1b2e
```

Give that token to the MCP server as a flag or an environment variable:

```bash
self-test-mcp --token 7f3c9a1b2e
SELF_TEST_TOKEN=7f3c9a1b2e self-test-mcp
```

The flag wins over the environment variable. The token travels both as the
`?token=` query parameter and as an `x-self-test-token` header, so either end
of the handshake can check it, and it is redacted from the server's own log
lines.

If the token is wrong or absent the bridge refuses the handshake with HTTP
403. That arrives from `ws` as `Unexpected server response: 403`, which reads
like a crashed app; the server reports it as what it is instead:

```
Bridge refused the connection at ws://127.0.0.1:9999: wrong or missing token
(HTTP 403). No token was supplied. The Flutter app prints its bridge URL at
startup, for example ws://127.0.0.1:9999?token=abc123; pass that token as
--token <token> or set SELF_TEST_TOKEN.
```

## Locators

A widget is addressed by what is on screen, not by an id the app had to
register in advance. Every action tool takes a locator:

```json
{ "by": "text", "value": "Sign in", "exact": true, "index": 0 }
```

| Field | Meaning |
|---|---|
| `by` | `text`, `key`, `id`, `semanticsLabel`, `type` or `tooltip` |
| `value` | What to match, for example `"Sign in"` |
| `exact` | Whole string rather than substring. **`by: "text"` only.** Default `true` |
| `index` | Which match to use when several match. Default `0` |

Call `flutter_describe_screen` first: it lists every widget on screen with a
ready-made locator for each, so nothing has to be guessed.

`widgetId` still works on every action tool for apps that register self_test
ids. Pass a locator or a `widgetId`, not both — the server refuses a call
that gives both rather than silently picking one.

## Command line

| Flag | Default | Environment variable |
|---|---|---|
| `--token <token>` | none | `SELF_TEST_TOKEN` |
| `--host <host>` | `127.0.0.1` | `FLUTTER_APP_HOST` |
| `--port <port>` | `9999` | `FLUTTER_APP_PORT` |
| `--mode <mode>` | `server` | `BRIDGE_MODE` |
| `--url <url>` | `http://localhost:8080` | `FLUTTER_APP_URL` |
| `--goldens-dir <dir>` | `test/goldens` | `FLUTTER_GOLDENS_DIR` |
| `--headless` / `--no-headless` | headless | `PLAYWRIGHT_HEADLESS` |
| `-h`, `--help` | | |
| `-v`, `--version` | | |

Playwright is only loaded in `web-external` mode, so the `postinstall` that
downloads Chromium is optional. An install run with `--ignore-scripts`, as CI
does, still builds and starts the server in `client` and `server` modes.

## Architecture

### With Bridge (client/server modes)
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
│  │  - Locators: describeScreen, find, exists, readText         ││
│  │  - Actions: tap, type, scroll, drag, hover, focus           ││
│  │  - Assertions: expect, expectScreenshot, goldens            ││
│  │  - Network: mockHttp, blockHttp, networkLog, harExport      ││
│  │  - State: getState, dispatchAction, watchState              ││
│  │  - Platform: mockChannel, setGeolocation, setPermission     ││
│  │  - Tracing: traceStart, traceStop, console, errors          ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────┬───────────────────────────────────┘
                              │ WebSocket (ws://127.0.0.1:9999?token=...)
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

### Web-External Mode (no bridge needed!)
```
┌─────────────────────────────────────────────────────────────────┐
│                         AI Agent (Claude)                        │
└─────────────────────────────┬───────────────────────────────────┘
                              │ MCP Protocol (JSON-RPC over stdio)
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     self_test MCP Server                         │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │  PlaywrightBridge (web-external mode)                       ││
│  │  - Launches Chromium browser                                ││
│  │  - Navigates to Flutter web app URL                         ││
│  │  - Interacts via flt-semantics-host accessibility tree      ││
│  │  - Types via flt-text-editing-host input element           ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────┬───────────────────────────────────┘
                              │ Playwright (Chrome DevTools Protocol)
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                 Flutter Web App (any production build)           │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │  No SelfTestBridge needed!                                  ││
│  │  Uses Flutter's built-in accessibility tree:                ││
│  │  - flt-semantics-placeholder → enables semantics            ││
│  │  - flt-semantics-host → widget tree with roles/labels       ││
│  │  - flt-text-editing-host → real <input> for text fields    ││
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
      "command": "npx",
      "args": ["-y", "self-test-mcp", "--port", "9999"],
      "env": {
        "SELF_TEST_TOKEN": "the-token-the-app-printed"
      }
    }
  }
}
```

Keep the token in `env` rather than in `args`: an argument is visible to
anything that can list processes.

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
| `flutter_describe_screen` | **Call this first.** Every widget on screen, each with a ready-made locator | `page.accessibility.snapshot()` |
| `flutter_find` | One widget by locator, or null | `page.locator().first()` |
| `flutter_exists` | Whether a widget is in the tree | `locator.count() > 0` |
| `flutter_is_visible` | Whether a widget is on screen and painted | `locator.isVisible()` |
| `flutter_read_text` | The widget's text, or null | `locator.textContent()` |
| `flutter_snapshot` | Older id-based snapshot | `page.accessibility.snapshot()` |
| `flutter_get_by_role` | Find widgets by semantic role | `page.getByRole()` |
| `flutter_get_by_text` | Find widgets by text content | `page.getByText()` |

### Actions

Tools marked with a locator take `{by, value, exact, index}`, or a `widgetId`
for apps that still register ids.

| Tool | Locator | Description | Playwright Equivalent |
|------|:---:|-------------|----------------------|
| `flutter_tap` | yes | Tap/click a widget | `locator.click()` |
| `flutter_type` | yes | Type text into input | `locator.fill()` |
| `flutter_clear` | | Clear input field | `locator.clear()` |
| `flutter_press_key` | | Press keyboard key | `keyboard.press()` |
| `flutter_scroll` | yes | Scroll by `dx`/`dy`, or by direction | `mouse.wheel()` |
| `flutter_scroll_to` | | Scroll until widget visible | `locator.scrollIntoViewIfNeeded()` |
| `flutter_drag` | yes | Drag by `dx`/`dy`, or drop onto another widget | `page.dragAndDrop()` |
| `flutter_long_press` | yes | Long press widget | N/A (Flutter-specific) |
| `flutter_double_tap` | yes | Double tap widget | `locator.dblclick()` |
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

## Bridge Modes

The MCP server supports three modes for connecting to Flutter apps:

| Mode | Bridge Required | Use Case |
|------|-----------------|----------|
| `server` | ✅ Yes | Flutter Web with `SelfTestBridge` (MCP runs WebSocket server) |
| `client` | ✅ Yes | Native platforms with `SelfTestBridge` (MCP connects to app) |
| `web-external` | ❌ **No** | Any Flutter Web app via Playwright + semantics tree |

### web-external Mode (New in v2.1)

Test **any Flutter web app** without code changes! Uses Playwright browser automation + Flutter's accessibility/semantics tree.

```bash
# Configure for web-external mode
export BRIDGE_MODE=web-external
export FLUTTER_APP_URL=https://your-flutter-app.com
export PLAYWRIGHT_HEADLESS=false  # Set to true for CI

# Run MCP server
npm start
```

**How it works:**
1. Launches Chromium via Playwright
2. Navigates to your Flutter web app
3. Enables Flutter's semantics tree (`flt-semantics-host`)
4. Interacts with widgets via coordinate-based clicks
5. Types into text fields via `flt-text-editing-host input`

**Supported tools in web-external mode:**
- ✅ `flutter_snapshot`, `flutter_get_by_role`, `flutter_get_by_text`
- ✅ `flutter_tap`, `flutter_type`, `flutter_clear`, `flutter_press_key`
- ✅ `flutter_scroll`, `flutter_navigate`, `flutter_back`, `flutter_reload`
- ✅ `flutter_expect`, `flutter_screenshot`, `flutter_resize`
- ⚠️ State inspection tools require full bridge
- ⚠️ Network mocking requires full bridge

**Best for:**
- E2E smoke tests on production builds
- Testing third-party Flutter apps
- CI/CD pipelines without app modifications
- Quick exploratory testing

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `BRIDGE_MODE` | `server` | Bridge mode: `client`, `server`, or `web-external` |
| `SELF_TEST_TOKEN` | none | Token the bridge requires (client/server modes) |
| `FLUTTER_APP_HOST` | `127.0.0.1` | WebSocket host (client/server modes) |
| `FLUTTER_APP_PORT` | `9999` | WebSocket port (client/server modes) |
| `FLUTTER_APP_URL` | `http://localhost:8080` | Flutter app URL (web-external mode) |
| `PLAYWRIGHT_HEADLESS` | `true` | Run browser headless (web-external mode) |
| `FLUTTER_GOLDENS_DIR` | `test/goldens` | Directory for golden/screenshot files |

## Troubleshooting

### "wrong or missing token (HTTP 403)"
The bridge rejected the handshake. This is not a network problem.
1. Read the token from the URL the Flutter app printed at startup
2. Pass it as `--token <token>`, or set `SELF_TEST_TOKEN`
3. Restarting the app usually issues a new token, so copy it again

### "Connection refused"
1. Ensure Flutter app is running with `SelfTestBridge` started
2. Check port 9999 is not blocked
3. Verify `FLUTTER_APP_PORT` matches bridge port
4. The bridge binds to loopback, so connect to `127.0.0.1`, not a LAN address

### "Widget not found"
1. Use `flutter_describe_screen` to see what is on screen and copy a locator
2. Try `exact: false` on a `by: "text"` locator to match a substring
3. If several widgets match, pick one with `index`
4. Use `flutter_wait` before interacting with widgets

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
