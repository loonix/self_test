# Playwright Feature Parity

This document tracks feature parity between Playwright and self_test MCP.

## Implementation Status

| Component | Status |
|-----------|--------|
| **MCP Server (TypeScript)** | ✅ Complete - 40+ tools |
| **Flutter Bridge (Dart)** | ✅ Complete - All commands |

## Feature Comparison

| Category | Playwright | self_test MCP | MCP Tool | Bridge Status |
|----------|-----------|---------------|----------|---------------|
| **Locators** | | | | |
| getByRole() | ✅ | ✅ via Semantics | `flutter_get_by_role` | ✅ |
| getByText() | ✅ | ✅ via text search | `flutter_get_by_text` | ✅ |
| getByLabel() | ✅ | ✅ via Semantics.label | `flutter_get_by_role` | ✅ |
| getByTestId() | ✅ | ✅ via ValueKey | `flutter_snapshot` | ✅ |
| Snapshot | ✅ | ✅ Widget tree | `flutter_snapshot` | ✅ |
| CSS selectors | ✅ | ❌ N/A (no DOM) | N/A | N/A |
| XPath | ✅ | ❌ N/A | N/A | N/A |
| **Actions** | | | | |
| click() | ✅ | ✅ | `flutter_tap` | ✅ |
| fill() / type() | ✅ | ✅ | `flutter_type` | ✅ |
| clear() | ✅ | ✅ | `flutter_clear` | ✅ |
| press() (keyboard) | ✅ | ✅ | `flutter_press_key` | ✅ |
| scroll() | ✅ | ✅ | `flutter_scroll` | ✅ |
| scrollTo() | ✅ | ✅ | `flutter_scroll_to` | ✅ |
| dragAndDrop() | ✅ | ✅ | `flutter_drag` | ✅ |
| hover() | ✅ | ✅ | `flutter_hover` | ✅ |
| focus() | ✅ | ✅ | `flutter_focus` | ✅ |
| selectOption() | ✅ | ✅ | `flutter_select` | ✅ |
| check() / uncheck() | ✅ | ✅ | `flutter_toggle` | ✅ |
| longPress() | ✅ | ✅ | `flutter_long_press` | ✅ |
| dblclick() | ✅ | ✅ | `flutter_double_tap` | ✅ |
| slider | N/A | ✅ | `flutter_slider` | ✅ |
| **Navigation** | | | | |
| goto() | ✅ | ✅ | `flutter_navigate` | ✅ |
| goBack() | ✅ | ✅ | `flutter_back` | ✅ |
| reload() | ✅ | ✅ | `flutter_reload` | ✅ |
| restart() | N/A | ✅ | `flutter_restart` | ✅ |
| **Waiting** | | | | |
| waitForSelector() | ✅ | ✅ | `flutter_wait` (visible) | ✅ |
| waitForHidden() | ✅ | ✅ | `flutter_wait` (hidden) | ✅ |
| waitForEnabled() | ✅ | ✅ | `flutter_wait` (enabled) | ✅ |
| waitForText() | ✅ | ✅ | `flutter_wait` (text) | ✅ |
| waitForLoadState() | ✅ | ✅ | `flutter_wait` (idle) | ✅ |
| waitForResponse() | ✅ | ✅ | `flutter_wait_network` | ✅ |
| waitForTimeout() | ✅ | ✅ | `flutter_wait` (duration) | ✅ |
| Auto-waiting | ✅ | ✅ | Built-in to all actions | ✅ |
| **Assertions** | | | | |
| toBeVisible() | ✅ | ✅ | `flutter_expect` | ✅ |
| toBeHidden() | ✅ | ✅ | `flutter_expect` | ✅ |
| toBeEnabled() | ✅ | ✅ | `flutter_expect` | ✅ |
| toBeDisabled() | ✅ | ✅ | `flutter_expect` | ✅ |
| toHaveText() | ✅ | ✅ | `flutter_expect` | ✅ |
| toContainText() | ✅ | ✅ | `flutter_expect` | ✅ |
| toHaveValue() | ✅ | ✅ | `flutter_expect` | ✅ |
| toBeChecked() | ✅ | ✅ | `flutter_expect` | ✅ |
| toHaveCount() | ✅ | ✅ | `flutter_expect` | ✅ |
| toBeFocused() | ✅ | ✅ | `flutter_expect` | ✅ |
| toHaveScreenshot() | ✅ | ✅ | `flutter_expect_screenshot` | ✅ |
| **Visual Testing** | | | | |
| screenshot() | ✅ | ✅ | `flutter_screenshot` | ✅ |
| Visual comparison | ✅ | ✅ | `flutter_expect_screenshot` | ✅ |
| Full page screenshot | ✅ | ✅ | `flutter_screenshot` (fullPage) | ✅ |
| Element screenshot | ✅ | ✅ | `flutter_screenshot` (widgetId) | ✅ |
| Video recording | ✅ | ✅ | `flutter_record_start/stop` | ✅ |
| **Network** | | | | |
| route() / intercept | ✅ | ✅ | `flutter_mock_http` | ✅ |
| Mock responses | ✅ | ✅ | `flutter_mock_http` | ✅ |
| Block requests | ✅ | ✅ | `flutter_block_http` | ✅ |
| Clear mocks | ✅ | ✅ | `flutter_clear_mocks` | ✅ |
| Network log | ✅ | ✅ | `flutter_network_log` | ✅ |
| Wait for request | ✅ | ✅ | `flutter_wait_network` | ✅ |
| **Tracing & Debug** | | | | |
| tracing.start() | ✅ | ✅ | `flutter_trace_start` | ✅ |
| tracing.stop() | ✅ | ✅ | `flutter_trace_stop` | ✅ |
| console messages | ✅ | ✅ | `flutter_console` | ✅ |
| page errors | ✅ | ✅ | `flutter_errors` | ✅ |
| **Device Emulation** | | | | |
| Viewport size | ✅ | ✅ | `flutter_resize` | ✅ |
| Dark mode | ✅ | ✅ | `flutter_set_theme` | ✅ |
| Locale | ✅ | ✅ | `flutter_set_locale` | ✅ |
| Text scale | N/A | ✅ | `flutter_set_text_scale` | ✅ |
| **Dialogs** | | | | |
| Alert handling | ✅ | ✅ | `flutter_dialog` (accept) | ✅ |
| Confirm handling | ✅ | ✅ | `flutter_dialog` (dismiss) | ✅ |
| Prompt handling | ✅ | ✅ | `flutter_dialog` (get_text) | ✅ |
| Dismiss overlay | ✅ | ✅ | `flutter_dismiss_overlay` | ✅ |
| **Storage** | | | | |
| Get storage | ✅ | ✅ | `flutter_storage_get` | ✅ |
| Set storage | ✅ | ✅ | `flutter_storage_set` | ✅ |
| Clear storage | ✅ | ✅ | `flutter_storage_clear` | ✅ |
| State snapshot | ✅ | ✅ | `flutter_save_state` | ✅ |
| Restore state | ✅ | ✅ | `flutter_restore_state` | ✅ |
| **Files** | | | | |
| File picker mock | ✅ | ✅ | `flutter_file_picker` | ✅ |
| **Test Organization** | | | | |
| Test scenarios | ✅ | ✅ | `flutter_run_scenario` | ✅ |
| **Accessibility** | | | | |
| Accessibility audit | ✅ | ✅ | `flutter_accessibility_audit` | ✅ |

## Legend
- ✅ Implemented and tested
- ⚠️ Partial implementation
- 🔄 In progress
- N/A Not applicable (no equivalent in Flutter)

## Notes

### Network Mocking
Network interception requires app-level HTTP client configuration. The bridge stores mock patterns, but the app needs to use a mockable HTTP client (like `dio` with interceptors) to apply them.

### Device Emulation
Theme, locale, and text scale changes require app-level callbacks. The bridge sends change requests but the app must be configured to respond.

### Video Recording
Full video encoding requires native plugins. The bridge captures frames that can be assembled into video with external tools.

### Hot Reload/Restart
These features work best with the VM service. The bridge provides fallback behavior (route refresh, navigate to root).
