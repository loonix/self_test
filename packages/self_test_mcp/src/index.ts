#!/usr/bin/env node

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { FlutterBridge } from "./flutter-bridge.js";

// Configuration from environment
const FLUTTER_HOST = process.env.FLUTTER_APP_HOST || "localhost";
const FLUTTER_PORT = parseInt(process.env.FLUTTER_APP_PORT || "9999", 10);
const GOLDENS_DIR = process.env.FLUTTER_GOLDENS_DIR || "test/goldens";
// BRIDGE_MODE: "client" (MCP connects to Flutter) or "server" (Flutter connects to MCP)
// Use "server" mode for Flutter Web since browsers can't run WebSocket servers
const BRIDGE_MODE = (process.env.BRIDGE_MODE || "server") as "client" | "server";

// Create MCP server
const server = new McpServer({
  name: "flutter-self-test",
  version: "2.0.0",
});

// Flutter bridge instance
let bridge: FlutterBridge | null = null;

// Initialize bridge connection
async function ensureBridge(): Promise<FlutterBridge> {
  if (!bridge) {
    bridge = new FlutterBridge(FLUTTER_HOST, FLUTTER_PORT, BRIDGE_MODE);
    await bridge.connect();
    console.error(`Bridge initialized in ${BRIDGE_MODE} mode`);
  }
  return bridge;
}

// Format snapshot for AI readability
function formatSnapshot(snapshot: any): string {
  let output = `# Flutter Screen Snapshot\n\n`;
  output += `**Current Screen:** ${snapshot.currentScreen}\n`;
  output += `**Widgets:** ${snapshot.widgets?.length || 0}\n\n`;

  const widgets = snapshot.widgets || [];
  const buttons = widgets.filter((w: any) => w.type === "button");
  const inputs = widgets.filter((w: any) => w.type === "text_input");
  const checkboxes = widgets.filter((w: any) => w.type === "checkbox");
  const others = widgets.filter((w: any) => !["button", "text_input", "checkbox"].includes(w.type));

  if (buttons.length > 0) {
    output += `## Buttons\n`;
    for (const btn of buttons) {
      const icon = btn.isStable ? "" : " ⚠️";
      const enabled = btn.isEnabled !== false ? "" : " (disabled)";
      output += `- [${btn.id}]${icon}${enabled}\n`;
    }
    output += "\n";
  }

  if (inputs.length > 0) {
    output += `## Text Inputs\n`;
    for (const input of inputs) {
      const icon = input.isStable ? "" : " ⚠️";
      const value = input.currentText ? ` = "${input.currentText}"` : "";
      output += `- [${input.id}]${icon}${value}\n`;
    }
    output += "\n";
  }

  if (checkboxes.length > 0) {
    output += `## Checkboxes/Toggles\n`;
    for (const cb of checkboxes) {
      const checked = cb.isChecked ? "☑" : "☐";
      output += `- ${checked} [${cb.id}]\n`;
    }
    output += "\n";
  }

  if (others.length > 0) {
    output += `## Other Interactive\n`;
    for (const w of others) {
      output += `- [${w.id}] (${w.type})\n`;
    }
    output += "\n";
  }

  return output;
}

// ============================================================================
// LOCATORS - Playwright-style element finding
// ============================================================================

server.tool(
  "flutter_snapshot",
  "Get accessibility snapshot of current screen. Returns all interactive widgets with IDs. Similar to Playwright's page snapshot.",
  {},
  async () => {
    const b = await ensureBridge();
    const snapshot = await b.send("getSnapshot", {});
    return { content: [{ type: "text", text: formatSnapshot(snapshot) }] };
  }
);

server.tool(
  "flutter_get_by_role",
  "Find widgets by their semantic role (button, textbox, checkbox, switch, slider, link, image, heading).",
  {
    role: z.enum(["button", "textbox", "checkbox", "switch", "slider", "link", "image", "heading"]),
    name: z.string().optional().describe("Filter by accessible name/label"),
  },
  async ({ role, name }) => {
    const b = await ensureBridge();
    const result = await b.send("getByRole", { role, name });
    return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
  }
);

server.tool(
  "flutter_get_by_text",
  "Find widgets containing specific text.",
  {
    text: z.string().describe("Text to search for"),
    exact: z.boolean().optional().describe("Exact match (default: false)"),
  },
  async ({ text, exact }) => {
    const b = await ensureBridge();
    const result = await b.send("getByText", { text, exact });
    return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
  }
);

// ============================================================================
// ACTIONS - User interactions
// ============================================================================

server.tool(
  "flutter_tap",
  "Tap/click a widget. Auto-waits for widget to be visible and enabled.",
  {
    widgetId: z.string().describe("Widget ID from snapshot"),
    timeout: z.number().optional().describe("Timeout in ms (default: 5000)"),
  },
  async ({ widgetId, timeout }) => {
    const b = await ensureBridge();
    try {
      await b.send("tap", { widgetId, timeout: timeout || 5000 });
      return { content: [{ type: "text", text: `✅ Tapped [${widgetId}]` }] };
    } catch (e: any) {
      return { content: [{ type: "text", text: `❌ Failed: ${e.message}` }], isError: true };
    }
  }
);

server.tool(
  "flutter_type",
  "Type text into an input field. Clears existing text first unless append is true.",
  {
    widgetId: z.string().describe("Input widget ID"),
    text: z.string().describe("Text to type"),
    append: z.boolean().optional().describe("Append to existing text (default: false)"),
    submit: z.boolean().optional().describe("Press enter/submit after typing"),
  },
  async ({ widgetId, text, append, submit }) => {
    const b = await ensureBridge();
    try {
      await b.send("type", { widgetId, text, append, submit });
      return { content: [{ type: "text", text: `✅ Typed "${text}" into [${widgetId}]` }] };
    } catch (e: any) {
      return { content: [{ type: "text", text: `❌ Failed: ${e.message}` }], isError: true };
    }
  }
);

server.tool(
  "flutter_clear",
  "Clear text from an input field.",
  {
    widgetId: z.string().describe("Input widget ID"),
  },
  async ({ widgetId }) => {
    const b = await ensureBridge();
    await b.send("clear", { widgetId });
    return { content: [{ type: "text", text: `✅ Cleared [${widgetId}]` }] };
  }
);

server.tool(
  "flutter_press_key",
  "Press a keyboard key (enter, tab, escape, backspace, etc.).",
  {
    key: z.enum(["enter", "tab", "escape", "backspace", "delete", "up", "down", "left", "right", "home", "end"]),
  },
  async ({ key }) => {
    const b = await ensureBridge();
    await b.send("pressKey", { key });
    return { content: [{ type: "text", text: `✅ Pressed ${key}` }] };
  }
);

server.tool(
  "flutter_scroll",
  "Scroll within a scrollable widget.",
  {
    widgetId: z.string().optional().describe("Scrollable widget ID (uses first if not specified)"),
    direction: z.enum(["up", "down", "left", "right"]),
    delta: z.number().optional().describe("Scroll amount in pixels (default: 300)"),
  },
  async ({ widgetId, direction, delta }) => {
    const b = await ensureBridge();
    await b.send("scroll", { widgetId, direction, delta: delta || 300 });
    return { content: [{ type: "text", text: `✅ Scrolled ${direction}` }] };
  }
);

server.tool(
  "flutter_scroll_to",
  "Scroll until a widget is visible.",
  {
    widgetId: z.string().describe("Widget to scroll to"),
    scrollableId: z.string().optional().describe("Container to scroll"),
    timeout: z.number().optional(),
  },
  async ({ widgetId, scrollableId, timeout }) => {
    const b = await ensureBridge();
    await b.send("scrollTo", { widgetId, scrollableId, timeout: timeout || 10000 });
    return { content: [{ type: "text", text: `✅ Scrolled to [${widgetId}]` }] };
  }
);

server.tool(
  "flutter_drag",
  "Drag from one widget to another (drag and drop).",
  {
    sourceId: z.string().describe("Widget to drag from"),
    targetId: z.string().describe("Widget to drop on"),
  },
  async ({ sourceId, targetId }) => {
    const b = await ensureBridge();
    await b.send("drag", { sourceId, targetId });
    return { content: [{ type: "text", text: `✅ Dragged [${sourceId}] to [${targetId}]` }] };
  }
);

server.tool(
  "flutter_long_press",
  "Long press on a widget (for context menus, etc.).",
  {
    widgetId: z.string(),
    duration: z.number().optional().describe("Duration in ms (default: 500)"),
  },
  async ({ widgetId, duration }) => {
    const b = await ensureBridge();
    await b.send("longPress", { widgetId, duration: duration || 500 });
    return { content: [{ type: "text", text: `✅ Long pressed [${widgetId}]` }] };
  }
);

server.tool(
  "flutter_double_tap",
  "Double tap on a widget.",
  { widgetId: z.string() },
  async ({ widgetId }) => {
    const b = await ensureBridge();
    await b.send("doubleTap", { widgetId });
    return { content: [{ type: "text", text: `✅ Double tapped [${widgetId}]` }] };
  }
);

server.tool(
  "flutter_hover",
  "Hover over a widget (for tooltips, etc.).",
  { widgetId: z.string() },
  async ({ widgetId }) => {
    const b = await ensureBridge();
    await b.send("hover", { widgetId });
    return { content: [{ type: "text", text: `✅ Hovering over [${widgetId}]` }] };
  }
);

server.tool(
  "flutter_focus",
  "Focus on a widget.",
  { widgetId: z.string() },
  async ({ widgetId }) => {
    const b = await ensureBridge();
    await b.send("focus", { widgetId });
    return { content: [{ type: "text", text: `✅ Focused [${widgetId}]` }] };
  }
);

server.tool(
  "flutter_select",
  "Select an option in a dropdown or picker.",
  {
    widgetId: z.string().describe("Dropdown widget ID"),
    value: z.string().describe("Option value or text to select"),
  },
  async ({ widgetId, value }) => {
    const b = await ensureBridge();
    await b.send("select", { widgetId, value });
    return { content: [{ type: "text", text: `✅ Selected "${value}" in [${widgetId}]` }] };
  }
);

server.tool(
  "flutter_toggle",
  "Toggle a checkbox or switch.",
  {
    widgetId: z.string(),
    checked: z.boolean().optional().describe("Set specific state (default: toggle)"),
  },
  async ({ widgetId, checked }) => {
    const b = await ensureBridge();
    await b.send("toggle", { widgetId, checked });
    return { content: [{ type: "text", text: `✅ Toggled [${widgetId}]` }] };
  }
);

server.tool(
  "flutter_slider",
  "Set slider value.",
  {
    widgetId: z.string(),
    value: z.number().describe("Value to set (0.0 to 1.0 or actual value)"),
  },
  async ({ widgetId, value }) => {
    const b = await ensureBridge();
    await b.send("setSlider", { widgetId, value });
    return { content: [{ type: "text", text: `✅ Set [${widgetId}] to ${value}` }] };
  }
);

// ============================================================================
// NAVIGATION
// ============================================================================

server.tool(
  "flutter_navigate",
  "Navigate to a route/screen.",
  {
    route: z.string().describe("Route path (e.g., '/home', '/settings')"),
    replace: z.boolean().optional().describe("Replace current route instead of push"),
  },
  async ({ route, replace }) => {
    const b = await ensureBridge();
    await b.send("navigate", { route, replace });
    return { content: [{ type: "text", text: `✅ Navigated to ${route}` }] };
  }
);

server.tool(
  "flutter_back",
  "Go back to previous screen (like browser back).",
  {},
  async () => {
    const b = await ensureBridge();
    await b.send("goBack", {});
    return { content: [{ type: "text", text: `✅ Navigated back` }] };
  }
);

server.tool(
  "flutter_reload",
  "Hot reload the app (preserves state).",
  {},
  async () => {
    const b = await ensureBridge();
    await b.send("reload", {});
    return { content: [{ type: "text", text: `✅ App reloaded` }] };
  }
);

server.tool(
  "flutter_restart",
  "Hot restart the app (resets state).",
  {},
  async () => {
    const b = await ensureBridge();
    await b.send("restart", {});
    return { content: [{ type: "text", text: `✅ App restarted` }] };
  }
);

// ============================================================================
// WAITING
// ============================================================================

server.tool(
  "flutter_wait",
  "Wait for various conditions.",
  {
    condition: z.enum([
      "visible",      // Wait for widget to be visible
      "hidden",       // Wait for widget to disappear
      "enabled",      // Wait for widget to be enabled
      "disabled",     // Wait for widget to be disabled
      "text",         // Wait for widget to have specific text
      "idle",         // Wait for app to be idle (no animations)
      "network_idle", // Wait for no pending network requests
      "duration",     // Wait for specific duration
    ]),
    widgetId: z.string().optional().describe("Widget ID (for widget conditions)"),
    text: z.string().optional().describe("Expected text (for text condition)"),
    timeout: z.number().optional().describe("Timeout in ms (default: 5000)"),
    duration: z.number().optional().describe("Duration in ms (for duration condition)"),
  },
  async ({ condition, widgetId, text, timeout, duration }) => {
    const b = await ensureBridge();
    try {
      await b.send("wait", { condition, widgetId, text, timeout: timeout || 5000, duration });
      return { content: [{ type: "text", text: `✅ Wait completed: ${condition}` }] };
    } catch (e: any) {
      return { content: [{ type: "text", text: `❌ Wait timeout: ${e.message}` }], isError: true };
    }
  }
);

// ============================================================================
// ASSERTIONS - Playwright expect() equivalent
// ============================================================================

server.tool(
  "flutter_expect",
  "Assert widget state. Similar to Playwright's expect().",
  {
    widgetId: z.string(),
    assertion: z.enum([
      "toBeVisible",
      "toBeHidden",
      "toBeEnabled",
      "toBeDisabled",
      "toBeChecked",
      "toBeUnchecked",
      "toHaveText",
      "toContainText",
      "toHaveValue",
      "toHaveCount",
      "toBeFocused",
    ]),
    expected: z.union([z.string(), z.number(), z.boolean()]).optional(),
    timeout: z.number().optional(),
  },
  async ({ widgetId, assertion, expected, timeout }) => {
    const b = await ensureBridge();
    const result = await b.send("expect", { widgetId, assertion, expected, timeout: timeout || 5000 });

    if (result.passed) {
      return { content: [{ type: "text", text: `✅ [${widgetId}] ${assertion}${expected !== undefined ? ` "${expected}"` : ""}` }] };
    } else {
      return {
        content: [{ type: "text", text: `❌ Assertion failed: [${widgetId}] ${assertion}\n   ${result.message}` }],
        isError: true,
      };
    }
  }
);

server.tool(
  "flutter_expect_screenshot",
  "Visual regression: compare current screenshot to file-based baseline. Golden files are stored in the goldens directory (default: test/goldens/) relative to project root.",
  {
    name: z.string().describe("Screenshot name for comparison (will be saved as name.png)"),
    widgetId: z.string().optional().describe("Widget to screenshot (full screen if not specified)"),
    threshold: z.number().optional().describe("Pixel difference threshold 0-1 (default: 0.01 = 1%)"),
    updateBaseline: z.boolean().optional().describe("Update baseline instead of comparing"),
    goldensDir: z.string().optional().describe("Golden files directory relative to project root (default: test/goldens/)"),
  },
  async ({ name, widgetId, threshold, updateBaseline, goldensDir }) => {
    const b = await ensureBridge();
    const result = await b.send("expectScreenshot", {
      name,
      widgetId,
      threshold: threshold || 0.01,
      updateBaseline,
      goldensDir: goldensDir || GOLDENS_DIR,
    });

    if (result.passed) {
      return { content: [{ type: "text" as const, text: `✅ Screenshot matches baseline: ${name}\n   Baseline: ${result.baselinePath}\n   Difference: ${(result.difference * 100).toFixed(2)}%` }] };
    } else if (result.baselineCreated) {
      return { content: [{ type: "text" as const, text: `📸 Baseline created: ${name}\n   Path: ${result.baselinePath}` }] };
    } else if (result.baselineUpdated) {
      return { content: [{ type: "text" as const, text: `📸 Baseline updated: ${name}\n   Path: ${result.baselinePath}` }] };
    } else {
      const content: Array<{ type: "text"; text: string } | { type: "image"; data: string; mimeType: string }> = [
        { type: "text", text: `❌ Screenshot mismatch: ${name}\n   Difference: ${(result.difference * 100).toFixed(2)}%\n   Threshold: ${((threshold || 0.01) * 100).toFixed(2)}%\n   Baseline: ${result.baselinePath}\n   Diff image: ${result.diffPath || 'N/A'}` },
      ];
      if (result.diffImage) {
        content.push({ type: "image", data: result.diffImage, mimeType: "image/png" });
      }
      return { content, isError: true };
    }
  }
);

server.tool(
  "flutter_update_goldens",
  "Update all golden baselines or specific ones. Use this when UI changes are intentional.",
  {
    names: z.array(z.string()).optional().describe("Specific golden names to update (updates all if not specified)"),
    goldensDir: z.string().optional().describe("Golden files directory relative to project root (default: test/goldens/)"),
  },
  async ({ names, goldensDir }) => {
    const b = await ensureBridge();
    const result = await b.send("updateGoldens", {
      names,
      goldensDir: goldensDir || GOLDENS_DIR,
    });

    if (result.error) {
      return { content: [{ type: "text", text: `❌ Failed to update goldens: ${result.error}` }], isError: true };
    }

    let output = `# Golden Baselines Updated\n\n`;
    output += `**Updated:** ${result.updated?.length || 0} files\n\n`;

    for (const file of result.updated || []) {
      output += `- ${file}\n`;
    }

    if (result.skipped?.length > 0) {
      output += `\n**Skipped:** ${result.skipped.length} files\n`;
      for (const file of result.skipped) {
        output += `- ${file}\n`;
      }
    }

    return { content: [{ type: "text", text: output }] };
  }
);

server.tool(
  "flutter_list_goldens",
  "List all golden baseline files in the goldens directory.",
  {
    goldensDir: z.string().optional().describe("Golden files directory relative to project root (default: test/goldens/)"),
  },
  async ({ goldensDir }) => {
    const b = await ensureBridge();
    const result = await b.send("listGoldens", {
      goldensDir: goldensDir || GOLDENS_DIR,
    });

    if (result.error) {
      return { content: [{ type: "text", text: `❌ Failed to list goldens: ${result.error}` }], isError: true };
    }

    let output = `# Golden Baselines\n\n`;
    output += `**Directory:** ${result.directory}\n`;
    output += `**Total:** ${result.goldens?.length || 0} files\n\n`;

    if (result.goldens?.length > 0) {
      output += `| Name | Size | Last Modified |\n`;
      output += `|------|------|---------------|\n`;
      for (const golden of result.goldens) {
        output += `| ${golden.name} | ${golden.size} | ${golden.modified} |\n`;
      }
    } else {
      output += `_No golden files found._\n`;
    }

    return { content: [{ type: "text", text: output }] };
  }
);

// ============================================================================
// SCREENSHOTS & VIDEO
// ============================================================================

server.tool(
  "flutter_screenshot",
  "Take a screenshot of the current screen or specific widget.",
  {
    name: z.string().optional().describe("Screenshot name"),
    widgetId: z.string().optional().describe("Widget to screenshot (full screen if not specified)"),
    fullPage: z.boolean().optional().describe("Capture entire scrollable content"),
  },
  async ({ name, widgetId, fullPage }) => {
    const b = await ensureBridge();
    const result = await b.send("screenshot", { name: name || "screenshot", widgetId, fullPage });

    const content: any[] = [{ type: "text", text: `📸 Screenshot: ${result.filename}` }];
    if (result.base64) {
      content.push({ type: "image", data: result.base64, mimeType: "image/png" });
    }
    return { content };
  }
);

server.tool(
  "flutter_record_start",
  "Start recording video of test execution.",
  {
    name: z.string().optional().describe("Recording name"),
  },
  async ({ name }) => {
    const b = await ensureBridge();
    await b.send("recordStart", { name: name || "recording" });
    return { content: [{ type: "text", text: `🎬 Recording started` }] };
  }
);

server.tool(
  "flutter_record_stop",
  "Stop video recording and save.",
  {},
  async () => {
    const b = await ensureBridge();
    const result = await b.send("recordStop", {});
    return { content: [{ type: "text", text: `🎬 Recording saved: ${result.filepath}` }] };
  }
);

// ============================================================================
// NETWORK INTERCEPTION
// ============================================================================

server.tool(
  "flutter_mock_http",
  "Mock HTTP responses (like Playwright route()).",
  {
    urlPattern: z.string().describe("URL pattern to match (regex or glob)"),
    response: z.object({
      status: z.number().optional().describe("HTTP status code"),
      body: z.any().optional().describe("Response body (JSON or string)"),
      headers: z.record(z.string()).optional(),
      delay: z.number().optional().describe("Response delay in ms"),
    }),
  },
  async ({ urlPattern, response }) => {
    const b = await ensureBridge();
    await b.send("mockHttp", { urlPattern, response });
    return { content: [{ type: "text", text: `✅ Mocking: ${urlPattern}` }] };
  }
);

server.tool(
  "flutter_block_http",
  "Block HTTP requests matching pattern.",
  {
    urlPattern: z.string().describe("URL pattern to block"),
  },
  async ({ urlPattern }) => {
    const b = await ensureBridge();
    await b.send("blockHttp", { urlPattern });
    return { content: [{ type: "text", text: `🚫 Blocking: ${urlPattern}` }] };
  }
);

server.tool(
  "flutter_clear_mocks",
  "Clear all HTTP mocks and blocks.",
  {},
  async () => {
    const b = await ensureBridge();
    await b.send("clearMocks", {});
    return { content: [{ type: "text", text: `✅ Mocks cleared` }] };
  }
);

server.tool(
  "flutter_network_log",
  "Get log of all HTTP requests made.",
  {
    limit: z.number().optional().describe("Number of requests to return (default: 50)"),
  },
  async ({ limit }) => {
    const b = await ensureBridge();
    const result = await b.send("networkLog", { limit: limit || 50 });

    let output = `# Network Log (${result.requests?.length || 0} requests)\n\n`;
    for (const req of result.requests || []) {
      const status = req.response?.status || "pending";
      output += `- ${req.method} ${req.url} → ${status}\n`;
    }
    return { content: [{ type: "text", text: output }] };
  }
);

server.tool(
  "flutter_wait_network",
  "Wait for a specific network request.",
  {
    urlPattern: z.string().describe("URL pattern to wait for"),
    timeout: z.number().optional(),
  },
  async ({ urlPattern, timeout }) => {
    const b = await ensureBridge();
    const result = await b.send("waitNetwork", { urlPattern, timeout: timeout || 10000 });
    return { content: [{ type: "text", text: `✅ Request completed: ${result.url}` }] };
  }
);

// ============================================================================
// CONSOLE & ERRORS
// ============================================================================

server.tool(
  "flutter_console",
  "Get console/debug output from the app.",
  {
    level: z.enum(["all", "error", "warning", "info", "debug"]).optional(),
    limit: z.number().optional(),
    clear: z.boolean().optional().describe("Clear console after reading"),
  },
  async ({ level, limit, clear }) => {
    const b = await ensureBridge();
    const result = await b.send("console", { level: level || "all", limit: limit || 100, clear });

    let output = `# Console Output\n\n`;
    for (const msg of result.messages || []) {
      const icon = msg.level === "error" ? "❌" : msg.level === "warning" ? "⚠️" : "ℹ️";
      output += `${icon} [${msg.level}] ${msg.message}\n`;
    }
    return { content: [{ type: "text", text: output }] };
  }
);

server.tool(
  "flutter_errors",
  "Get any Flutter errors/exceptions that occurred.",
  {
    clear: z.boolean().optional(),
  },
  async ({ clear }) => {
    const b = await ensureBridge();
    const result = await b.send("errors", { clear });

    if (!result.errors?.length) {
      return { content: [{ type: "text", text: `✅ No errors` }] };
    }

    let output = `# Errors (${result.errors.length})\n\n`;
    for (const err of result.errors) {
      output += `## ${err.type}\n\`\`\`\n${err.message}\n\`\`\`\n`;
      if (err.stackTrace) {
        output += `\nStack trace:\n\`\`\`\n${err.stackTrace}\n\`\`\`\n`;
      }
    }
    return { content: [{ type: "text", text: output }] };
  }
);

// ============================================================================
// TRACING
// ============================================================================

server.tool(
  "flutter_trace_start",
  "Start tracing all actions (for debugging).",
  {
    name: z.string().optional(),
    screenshots: z.boolean().optional().describe("Capture screenshots on each action"),
  },
  async ({ name, screenshots }) => {
    const b = await ensureBridge();
    await b.send("traceStart", { name: name || "trace", screenshots });
    return { content: [{ type: "text", text: `🔍 Tracing started` }] };
  }
);

server.tool(
  "flutter_trace_stop",
  "Stop tracing and save trace file.",
  {},
  async () => {
    const b = await ensureBridge();
    const result = await b.send("traceStop", {});
    return { content: [{ type: "text", text: `🔍 Trace saved: ${result.filepath}` }] };
  }
);

// ============================================================================
// DEVICE EMULATION
// ============================================================================

server.tool(
  "flutter_resize",
  "Resize the viewport/window.",
  {
    width: z.number(),
    height: z.number(),
  },
  async ({ width, height }) => {
    const b = await ensureBridge();
    await b.send("resize", { width, height });
    return { content: [{ type: "text", text: `✅ Resized to ${width}x${height}` }] };
  }
);

server.tool(
  "flutter_set_theme",
  "Switch between light/dark theme.",
  {
    theme: z.enum(["light", "dark", "system"]),
  },
  async ({ theme }) => {
    const b = await ensureBridge();
    await b.send("setTheme", { theme });
    return { content: [{ type: "text", text: `✅ Theme set to ${theme}` }] };
  }
);

server.tool(
  "flutter_set_locale",
  "Change app locale.",
  {
    locale: z.string().describe("Locale code (e.g., 'en_US', 'es_ES')"),
  },
  async ({ locale }) => {
    const b = await ensureBridge();
    await b.send("setLocale", { locale });
    return { content: [{ type: "text", text: `✅ Locale set to ${locale}` }] };
  }
);

server.tool(
  "flutter_set_text_scale",
  "Change text scale factor (accessibility).",
  {
    scale: z.number().describe("Scale factor (1.0 = normal, 2.0 = double)"),
  },
  async ({ scale }) => {
    const b = await ensureBridge();
    await b.send("setTextScale", { scale });
    return { content: [{ type: "text", text: `✅ Text scale set to ${scale}` }] };
  }
);

// ============================================================================
// DIALOGS & OVERLAYS
// ============================================================================

server.tool(
  "flutter_dialog",
  "Handle system dialogs and alerts.",
  {
    action: z.enum(["accept", "dismiss", "get_text"]),
    text: z.string().optional().describe("Text to enter (for prompt dialogs)"),
  },
  async ({ action, text }) => {
    const b = await ensureBridge();
    const result = await b.send("handleDialog", { action, text });
    return { content: [{ type: "text", text: `✅ Dialog ${action}ed${result.text ? `: "${result.text}"` : ""}` }] };
  }
);

server.tool(
  "flutter_dismiss_overlay",
  "Dismiss any overlay (snackbar, bottom sheet, modal).",
  {},
  async () => {
    const b = await ensureBridge();
    await b.send("dismissOverlay", {});
    return { content: [{ type: "text", text: `✅ Overlay dismissed` }] };
  }
);

// ============================================================================
// STORAGE & STATE
// ============================================================================

server.tool(
  "flutter_storage_get",
  "Get value from storage (SharedPreferences, secure storage).",
  {
    key: z.string(),
    storage: z.enum(["shared_prefs", "secure"]).optional(),
  },
  async ({ key, storage }) => {
    const b = await ensureBridge();
    const result = await b.send("storageGet", { key, storage: storage || "shared_prefs" });
    return { content: [{ type: "text", text: `${key} = ${JSON.stringify(result.value)}` }] };
  }
);

server.tool(
  "flutter_storage_set",
  "Set value in storage.",
  {
    key: z.string(),
    value: z.any(),
    storage: z.enum(["shared_prefs", "secure"]).optional(),
  },
  async ({ key, value, storage }) => {
    const b = await ensureBridge();
    await b.send("storageSet", { key, value, storage: storage || "shared_prefs" });
    return { content: [{ type: "text", text: `✅ Set ${key}` }] };
  }
);

server.tool(
  "flutter_storage_clear",
  "Clear all storage.",
  {
    storage: z.enum(["shared_prefs", "secure", "all"]).optional(),
  },
  async ({ storage }) => {
    const b = await ensureBridge();
    await b.send("storageClear", { storage: storage || "all" });
    return { content: [{ type: "text", text: `✅ Storage cleared` }] };
  }
);

server.tool(
  "flutter_save_state",
  "Save current app state for later restoration.",
  {
    name: z.string().describe("State snapshot name"),
  },
  async ({ name }) => {
    const b = await ensureBridge();
    await b.send("saveState", { name });
    return { content: [{ type: "text", text: `✅ State saved: ${name}` }] };
  }
);

server.tool(
  "flutter_restore_state",
  "Restore previously saved app state.",
  {
    name: z.string().describe("State snapshot name"),
  },
  async ({ name }) => {
    const b = await ensureBridge();
    await b.send("restoreState", { name });
    return { content: [{ type: "text", text: `✅ State restored: ${name}` }] };
  }
);

// ============================================================================
// FILES
// ============================================================================

server.tool(
  "flutter_file_picker",
  "Simulate file picker selection.",
  {
    files: z.array(z.string()).describe("File paths to select"),
  },
  async ({ files }) => {
    const b = await ensureBridge();
    await b.send("filePicker", { files });
    return { content: [{ type: "text", text: `✅ Selected ${files.length} file(s)` }] };
  }
);

// ============================================================================
// TEST SCENARIOS
// ============================================================================

server.tool(
  "flutter_run_scenario",
  "Run a complete test scenario with multiple steps.",
  {
    name: z.string().describe("Scenario name"),
    steps: z.array(z.object({
      action: z.string(),
      params: z.record(z.any()).optional(),
    })),
    stopOnError: z.boolean().optional(),
  },
  async ({ name, steps, stopOnError }) => {
    const b = await ensureBridge();
    const result = await b.send("runScenario", { name, steps, stopOnError: stopOnError ?? true });

    let output = `# Scenario: ${name}\n\n`;
    output += `**Result:** ${result.allPassed ? "✅ PASSED" : "❌ FAILED"}\n`;
    output += `**Steps:** ${result.passedCount}/${result.steps.length}\n\n`;

    for (const step of result.steps) {
      const icon = step.passed ? "✅" : "❌";
      output += `${icon} ${step.description}\n`;
      if (step.error) output += `   Error: ${step.error}\n`;
    }

    return { content: [{ type: "text", text: output }] };
  }
);

// ============================================================================
// ACCESSIBILITY
// ============================================================================

server.tool(
  "flutter_accessibility_audit",
  "Run accessibility audit on current screen.",
  {},
  async () => {
    const b = await ensureBridge();
    const result = await b.send("accessibilityAudit", {});

    let output = `# Accessibility Audit\n\n`;
    if (result.issues?.length === 0) {
      output += `✅ No accessibility issues found!\n`;
    } else {
      output += `⚠️ Found ${result.issues.length} issues:\n\n`;
      for (const issue of result.issues || []) {
        output += `- **${issue.severity}**: ${issue.message}\n`;
        output += `  Widget: [${issue.widgetId}]\n`;
        if (issue.suggestion) output += `  Fix: ${issue.suggestion}\n`;
        output += "\n";
      }
    }
    return { content: [{ type: "text", text: output }] };
  }
);

// ============================================================================
// SENSOR & DEVICE MOCKING
// ============================================================================

server.tool(
  "flutter_set_geolocation",
  "Set mock GPS coordinates for location-based testing. The app must register a callback via SelfTestBridge.onLocationChanged to receive updates.",
  {
    latitude: z.number().describe("Latitude coordinate (-90 to 90)"),
    longitude: z.number().describe("Longitude coordinate (-180 to 180)"),
    accuracy: z.number().optional().describe("Accuracy in meters (default: 10)"),
    altitude: z.number().optional().describe("Altitude in meters"),
    speed: z.number().optional().describe("Speed in m/s"),
    heading: z.number().optional().describe("Heading in degrees (0-360)"),
    timestamp: z.number().optional().describe("Unix timestamp in milliseconds"),
  },
  async ({ latitude, longitude, accuracy, altitude, speed, heading, timestamp }) => {
    const b = await ensureBridge();
    await b.send("setGeolocation", {
      latitude,
      longitude,
      accuracy: accuracy ?? 10,
      altitude,
      speed,
      heading,
      timestamp: timestamp ?? Date.now(),
    });
    return { content: [{ type: "text", text: `✅ Location set to (${latitude}, ${longitude})` }] };
  }
);

server.tool(
  "flutter_set_permission",
  "Set mock permission state for testing permission flows. The app must register a callback via SelfTestBridge.onPermissionRequested to receive mock states.",
  {
    permission: z.enum([
      "camera",
      "microphone",
      "location",
      "location_always",
      "location_when_in_use",
      "photos",
      "storage",
      "contacts",
      "calendar",
      "reminders",
      "notifications",
      "bluetooth",
      "sensors",
      "speech",
      "media_library",
    ]).describe("The permission type to mock"),
    state: z.enum([
      "granted",
      "denied",
      "restricted",
      "limited",
      "permanent_denied",
      "provisional",
    ]).describe("The permission state"),
  },
  async ({ permission, state }) => {
    const b = await ensureBridge();
    await b.send("setPermission", { permission, state });
    return { content: [{ type: "text", text: `✅ Permission ${permission} set to ${state}` }] };
  }
);

server.tool(
  "flutter_set_connectivity",
  "Set mock network connectivity state for testing offline scenarios. The app must register a callback via SelfTestBridge.onConnectivityChanged to receive updates.",
  {
    state: z.enum([
      "wifi",
      "mobile",
      "ethernet",
      "bluetooth",
      "vpn",
      "none",
    ]).describe("The connectivity state"),
    isConnected: z.boolean().optional().describe("Whether there is actual internet connectivity (default: true for non-none states)"),
  },
  async ({ state, isConnected }) => {
    const b = await ensureBridge();
    const connected = isConnected ?? (state !== "none");
    await b.send("setConnectivity", { state, isConnected: connected });
    return { content: [{ type: "text", text: `✅ Connectivity set to ${state}${connected ? "" : " (no internet)"}` }] };
  }
);

// ============================================================================
// PLATFORM CHANNEL MOCKING
// ============================================================================

server.tool(
  "flutter_mock_channel",
  "Mock a platform channel method. Returns specified response when the method is called.",
  {
    channel: z.string().describe("Platform channel name (e.g., 'plugins.flutter.io/path_provider')"),
    method: z.string().describe("Method name to mock (e.g., 'getApplicationDocumentsDirectory')"),
    response: z.any().describe("Response to return when method is called (JSON or primitive value)"),
    errorCode: z.string().optional().describe("If set, method will throw PlatformException with this code"),
    errorMessage: z.string().optional().describe("Error message for PlatformException"),
  },
  async ({ channel, method, response, errorCode, errorMessage }) => {
    const b = await ensureBridge();
    await b.send("mockChannel", { channel, method, response, errorCode, errorMessage });
    return { content: [{ type: "text", text: `✅ Mocked ${channel}:${method}` }] };
  }
);

server.tool(
  "flutter_clear_channel_mocks",
  "Clear all platform channel mocks or mocks for a specific channel.",
  {
    channel: z.string().optional().describe("Specific channel to clear (clears all if not specified)"),
  },
  async ({ channel }) => {
    const b = await ensureBridge();
    await b.send("clearChannelMocks", { channel });
    const target = channel ? `mocks for ${channel}` : "all channel mocks";
    return { content: [{ type: "text", text: `✅ Cleared ${target}` }] };
  }
);

server.tool(
  "flutter_channel_log",
  "Get log of all platform channel method calls.",
  {
    channel: z.string().optional().describe("Filter by channel name"),
    limit: z.number().optional().describe("Number of entries to return (default: 50)"),
    clear: z.boolean().optional().describe("Clear log after reading"),
  },
  async ({ channel, limit, clear }) => {
    const b = await ensureBridge();
    const result = await b.send("channelLog", { channel, limit: limit || 50, clear });

    let output = `# Platform Channel Log (${result.calls?.length || 0} calls)\n\n`;
    for (const call of result.calls || []) {
      const status = call.error ? "❌" : "✅";
      output += `${status} **${call.channel}**:${call.method}\n`;
      if (call.arguments) {
        output += `   Args: \`${JSON.stringify(call.arguments)}\`\n`;
      }
      if (call.result !== undefined) {
        output += `   Result: \`${JSON.stringify(call.result)}\`\n`;
      }
      if (call.error) {
        output += `   Error: ${call.error}\n`;
      }
      output += `   Time: ${call.timestamp}\n\n`;
    }
    return { content: [{ type: "text", text: output }] };
  }
);

// ============================================================================
// STATE MANAGEMENT INSPECTION
// ============================================================================

server.tool(
  "flutter_get_state",
  "Get current state from state management. Supports Riverpod providers, Bloc states, and Provider values. Returns serialized state as JSON.",
  {
    providerId: z.string().describe("Provider/Bloc identifier (e.g., 'userProvider', 'AuthBloc', 'counterProvider')"),
    path: z.string().optional().describe("Optional JSON path to extract specific state field (e.g., 'user.name', 'items[0].id')"),
    stateType: z.enum(["riverpod", "bloc", "provider", "auto"]).optional().describe("State management type (default: auto-detect)"),
  },
  async ({ providerId, path, stateType }) => {
    const b = await ensureBridge();
    try {
      const result = await b.send("getState", { providerId, path, stateType: stateType || "auto" });

      let output = `# State: ${providerId}\n\n`;
      output += `**Type:** ${result.stateType || "unknown"}\n`;
      output += `**Path:** ${path || "(root)"}\n\n`;
      output += "```json\n";
      output += JSON.stringify(result.state, null, 2);
      output += "\n```\n";

      if (result.metadata) {
        output += `\n**Metadata:**\n`;
        for (const [key, value] of Object.entries(result.metadata)) {
          output += `- ${key}: ${value}\n`;
        }
      }

      return { content: [{ type: "text", text: output }] };
    } catch (e: any) {
      return { content: [{ type: "text", text: `State read error: ${e.message}` }], isError: true };
    }
  }
);

server.tool(
  "flutter_dispatch_action",
  "Dispatch an action/event to state management. Supports Bloc events, Riverpod notifier methods, and Provider updates.",
  {
    providerId: z.string().describe("Provider/Bloc identifier"),
    action: z.string().describe("Action/event name (e.g., 'increment', 'LoginRequested', 'setUser')"),
    payload: z.any().optional().describe("Action payload/arguments (JSON object or primitive)"),
    stateType: z.enum(["riverpod", "bloc", "provider", "auto"]).optional().describe("State management type (default: auto-detect)"),
  },
  async ({ providerId, action, payload, stateType }) => {
    const b = await ensureBridge();
    try {
      const result = await b.send("dispatchAction", {
        providerId,
        action,
        payload,
        stateType: stateType || "auto",
      });

      let output = `Action dispatched: ${providerId}.${action}\n\n`;
      if (result.previousState !== undefined && result.newState !== undefined) {
        output += `**Previous State:**\n\`\`\`json\n${JSON.stringify(result.previousState, null, 2)}\n\`\`\`\n\n`;
        output += `**New State:**\n\`\`\`json\n${JSON.stringify(result.newState, null, 2)}\n\`\`\`\n`;
      }
      return { content: [{ type: "text", text: output }] };
    } catch (e: any) {
      return { content: [{ type: "text", text: `Action dispatch error: ${e.message}` }], isError: true };
    }
  }
);

server.tool(
  "flutter_watch_state",
  "Subscribe to state changes. Returns a subscription ID that can be used to retrieve accumulated changes or unsubscribe.",
  {
    providerId: z.string().describe("Provider/Bloc identifier to watch"),
    stateType: z.enum(["riverpod", "bloc", "provider", "auto"]).optional().describe("State management type (default: auto-detect)"),
    debounceMs: z.number().optional().describe("Debounce rapid changes by this many milliseconds (default: 100)"),
  },
  async ({ providerId, stateType, debounceMs }) => {
    const b = await ensureBridge();
    try {
      const result = await b.send("watchState", {
        providerId,
        stateType: stateType || "auto",
        debounceMs: debounceMs || 100,
      });

      return {
        content: [{
          type: "text",
          text: `Watching state: ${providerId}\n\n**Subscription ID:** ${result.subscriptionId}\n**Initial State:**\n\`\`\`json\n${JSON.stringify(result.initialState, null, 2)}\n\`\`\`\n\nUse \`flutter_get_state_changes\` to retrieve changes or \`flutter_unwatch_state\` to stop watching.`,
        }],
      };
    } catch (e: any) {
      return { content: [{ type: "text", text: `Watch error: ${e.message}` }], isError: true };
    }
  }
);

server.tool(
  "flutter_get_state_changes",
  "Get accumulated state changes from a watch subscription.",
  {
    subscriptionId: z.string().describe("Subscription ID from flutter_watch_state"),
    clear: z.boolean().optional().describe("Clear changes after reading (default: true)"),
  },
  async ({ subscriptionId, clear }) => {
    const b = await ensureBridge();
    try {
      const result = await b.send("getStateChanges", {
        subscriptionId,
        clear: clear ?? true,
      });

      if (!result.changes?.length) {
        return { content: [{ type: "text", text: `No state changes recorded for subscription ${subscriptionId}` }] };
      }

      let output = `# State Changes (${result.changes.length})\n\n`;
      for (const change of result.changes) {
        output += `## ${change.timestamp}\n`;
        output += `\`\`\`json\n${JSON.stringify(change.state, null, 2)}\n\`\`\`\n\n`;
      }

      return { content: [{ type: "text", text: output }] };
    } catch (e: any) {
      return { content: [{ type: "text", text: `Error: ${e.message}` }], isError: true };
    }
  }
);

server.tool(
  "flutter_unwatch_state",
  "Stop watching state changes and remove subscription.",
  {
    subscriptionId: z.string().describe("Subscription ID to remove"),
  },
  async ({ subscriptionId }) => {
    const b = await ensureBridge();
    try {
      await b.send("unwatchState", { subscriptionId });
      return { content: [{ type: "text", text: `Stopped watching: ${subscriptionId}` }] };
    } catch (e: any) {
      return { content: [{ type: "text", text: `Error: ${e.message}` }], isError: true };
    }
  }
);

server.tool(
  "flutter_list_state_providers",
  "List all available state providers, Blocs, and notifiers in the app. Useful for discovering what state can be inspected.",
  {
    stateType: z.enum(["riverpod", "bloc", "provider", "all"]).optional().describe("Filter by state management type (default: all)"),
  },
  async ({ stateType }) => {
    const b = await ensureBridge();
    try {
      const result = await b.send("listStateProviders", { stateType: stateType || "all" });

      let output = `# Available State Providers\n\n`;

      if (result.riverpod?.length) {
        output += `## Riverpod Providers (${result.riverpod.length})\n`;
        for (const p of result.riverpod) {
          const type = p.isNotifier ? "Notifier" : p.isAsync ? "Async" : "State";
          output += `- **${p.name}** (${type})\n`;
          if (p.currentValue !== undefined) {
            output += `  Current: \`${JSON.stringify(p.currentValue).slice(0, 100)}...\`\n`;
          }
        }
        output += "\n";
      }

      if (result.bloc?.length) {
        output += `## Bloc/Cubit (${result.bloc.length})\n`;
        for (const b of result.bloc) {
          output += `- **${b.name}** (${b.type})\n`;
          if (b.currentState !== undefined) {
            output += `  State: \`${JSON.stringify(b.currentState).slice(0, 100)}...\`\n`;
          }
        }
        output += "\n";
      }

      if (result.provider?.length) {
        output += `## Provider (${result.provider.length})\n`;
        for (const p of result.provider) {
          output += `- **${p.name}** (${p.type})\n`;
          if (p.currentValue !== undefined) {
            output += `  Value: \`${JSON.stringify(p.currentValue).slice(0, 100)}...\`\n`;
          }
        }
        output += "\n";
      }

      if (!result.riverpod?.length && !result.bloc?.length && !result.provider?.length) {
        output += "*No state providers detected. Make sure the app has state management configured and the bridge has access to the provider scope.*\n";
      }

      return { content: [{ type: "text", text: output }] };
    } catch (e: any) {
      return { content: [{ type: "text", text: `Error: ${e.message}` }], isError: true };
    }
  }
);

server.tool(
  "flutter_inject_state",
  "Directly inject state into a provider/bloc without UI interaction. Useful for testing specific state scenarios without navigating through the UI.",
  {
    providerId: z.string().describe("Provider/Bloc identifier to inject state into"),
    state: z.any().describe("State to inject (JSON object or primitive). Will be set directly on the provider."),
    notify: z.boolean().optional().describe("Whether to notify listeners after injection (default: true)"),
  },
  async ({ providerId, state, notify }) => {
    const b = await ensureBridge();
    try {
      const result = await b.send("injectState", {
        providerId,
        state,
        notify: notify ?? true,
      });

      let output = `State injected: ${providerId}\n\n`;
      output += `**Previous State:**\n\`\`\`json\n${JSON.stringify(result.previousState, null, 2)}\n\`\`\`\n\n`;
      output += `**New State:**\n\`\`\`json\n${JSON.stringify(result.newState, null, 2)}\n\`\`\`\n`;
      if (result.notified !== undefined) {
        output += `\n**Listeners notified:** ${result.notified ? "Yes" : "No"}\n`;
      }

      return { content: [{ type: "text", text: output }] };
    } catch (e: any) {
      return { content: [{ type: "text", text: `State injection error: ${e.message}` }], isError: true };
    }
  }
);

server.tool(
  "flutter_reset_state",
  "Reset a provider to its initial state (the state captured when the provider was first registered).",
  {
    providerId: z.string().describe("Provider/Bloc identifier to reset"),
  },
  async ({ providerId }) => {
    const b = await ensureBridge();
    try {
      const result = await b.send("resetState", { providerId });

      let output = `State reset: ${providerId}\n\n`;
      output += `**Previous State:**\n\`\`\`json\n${JSON.stringify(result.previousState, null, 2)}\n\`\`\`\n\n`;
      output += `**Reset to Initial State:**\n\`\`\`json\n${JSON.stringify(result.initialState, null, 2)}\n\`\`\`\n`;

      return { content: [{ type: "text", text: output }] };
    } catch (e: any) {
      return { content: [{ type: "text", text: `State reset error: ${e.message}` }], isError: true };
    }
  }
);

server.tool(
  "flutter_reset_all_state",
  "Reset all registered providers to their initial states. Useful for resetting app state between test scenarios.",
  {},
  async () => {
    const b = await ensureBridge();
    try {
      const result = await b.send("resetAllState", {});

      let output = `# All State Reset\n\n`;
      output += `**Providers reset:** ${result.reset?.length || 0}\n\n`;

      if (result.reset?.length > 0) {
        output += `## Reset Providers\n`;
        for (const providerId of result.reset) {
          output += `- ${providerId}\n`;
        }
      }

      if (result.failed?.length > 0) {
        output += `\n## Failed to Reset\n`;
        for (const failure of result.failed) {
          output += `- ${failure.providerId}: ${failure.error}\n`;
        }
      }

      return { content: [{ type: "text", text: output }] };
    } catch (e: any) {
      return { content: [{ type: "text", text: `Reset all state error: ${e.message}` }], isError: true };
    }
  }
);

server.tool(
  "flutter_state_history",
  "Get history of state changes for a provider. Useful for debugging state transitions and understanding how state evolved over time.",
  {
    providerId: z.string().describe("Provider/Bloc identifier to get history for"),
    limit: z.number().optional().describe("Maximum number of history entries to return (default: 20, max: 100)"),
  },
  async ({ providerId, limit }) => {
    const b = await ensureBridge();
    try {
      const result = await b.send("stateHistory", {
        providerId,
        limit: Math.min(limit || 20, 100),
      });

      let output = `# State History: ${providerId}\n\n`;
      output += `**Total entries:** ${result.totalEntries || 0}\n`;
      output += `**Showing:** ${result.history?.length || 0}\n\n`;

      if (result.history?.length > 0) {
        for (let i = 0; i < result.history.length; i++) {
          const entry = result.history[i];
          const date = new Date(entry.timestamp);
          output += `## ${i + 1}. ${date.toISOString()} (${entry.trigger})\n`;
          output += `\`\`\`json\n${JSON.stringify(entry.state, null, 2)}\n\`\`\`\n\n`;
        }
      } else {
        output += `_No history available for this provider._\n`;
      }

      return { content: [{ type: "text", text: output }] };
    } catch (e: any) {
      return { content: [{ type: "text", text: `State history error: ${e.message}` }], isError: true };
    }
  }
);

// ============================================================================
// CLIPBOARD
// ============================================================================

server.tool(
  "flutter_clipboard_read",
  "Read the current contents of the system clipboard.",
  {},
  async () => {
    const b = await ensureBridge();
    const result = await b.send("clipboardRead", {});

    if (result.error) {
      return { content: [{ type: "text", text: `Failed to read clipboard: ${result.error}` }], isError: true };
    }

    if (!result.hasData) {
      return { content: [{ type: "text", text: `Clipboard is empty` }] };
    }

    return { content: [{ type: "text", text: `Clipboard contents:\n\`\`\`\n${result.text}\n\`\`\`` }] };
  }
);

server.tool(
  "flutter_clipboard_write",
  "Write text to the system clipboard.",
  {
    text: z.string().describe("Text to write to clipboard"),
  },
  async ({ text }) => {
    const b = await ensureBridge();
    await b.send("clipboardWrite", { text });
    return { content: [{ type: "text", text: `Copied to clipboard: "${text.substring(0, 50)}${text.length > 50 ? '...' : ''}"` }] };
  }
);

// ============================================================================
// HAR EXPORT
// ============================================================================

server.tool(
  "flutter_har_export",
  "Export network log in HAR 1.2 format. Standard HTTP Archive format that can be imported into browser dev tools or analysis tools.",
  {},
  async () => {
    const b = await ensureBridge();
    const har = await b.send("harExport", {});

    const entries = har.log?.entries?.length || 0;
    let output = `# HAR Export\n\n`;
    output += `**Entries:** ${entries}\n`;
    output += `**Format:** HAR 1.2\n\n`;
    output += `\`\`\`json\n${JSON.stringify(har, null, 2)}\n\`\`\``;

    return { content: [{ type: "text", text: output }] };
  }
);

// ============================================================================
// ANIMATION CONTROL
// ============================================================================

server.tool(
  "flutter_animation_speed",
  "Set global animation speed. Use for debugging animations or speeding up tests.",
  {
    speed: z.number().describe("Animation speed multiplier: 0 = paused, 0.5 = slow motion, 1 = normal, 2 = fast, 10 = very fast"),
  },
  async ({ speed }) => {
    const b = await ensureBridge();
    await b.send("animationSpeed", { speed });

    let description: string;
    if (speed === 0) {
      description = "paused";
    } else if (speed < 1) {
      description = `slow motion (${speed}x)`;
    } else if (speed === 1) {
      description = "normal";
    } else {
      description = `fast (${speed}x)`;
    }

    return { content: [{ type: "text", text: `Animation speed set to ${description}` }] };
  }
);

server.tool(
  "flutter_pump",
  "Advance animations by specified duration. Similar to Flutter's WidgetTester.pump() - schedules frames to advance animation state.",
  {
    duration: z.number().optional().describe("Duration in milliseconds to advance. If 0 or omitted, pumps a single frame."),
  },
  async ({ duration }) => {
    const b = await ensureBridge();
    await b.send("pump", { duration: duration || 0 });

    if (duration && duration > 0) {
      return { content: [{ type: "text", text: `Pumped ${duration}ms of animation` }] };
    }
    return { content: [{ type: "text", text: `Pumped single frame` }] };
  }
);

// ============================================================================
// FRAME BUDGET ANALYSIS
// ============================================================================

server.tool(
  "flutter_frame_profiling_start",
  "Start frame timing profiling. Records frame durations to analyze performance and detect jank.",
  {
    budgetMs: z.number().optional().describe("Frame budget in ms (default: 16.67 for 60fps). Frames exceeding this are considered janky."),
  },
  async ({ budgetMs }) => {
    const b = await ensureBridge();
    await b.send("frameProfilingStart", { budgetMs: budgetMs || 16.67 });
    return { content: [{ type: "text", text: `Frame profiling started (budget: ${budgetMs || 16.67}ms)` }] };
  }
);

server.tool(
  "flutter_frame_profiling_stop",
  "Stop frame profiling and get performance analysis results.",
  {},
  async () => {
    const b = await ensureBridge();
    const result = await b.send("frameProfilingStop", {});

    if (result.error) {
      return { content: [{ type: "text", text: `Error: ${result.error}` }], isError: true };
    }

    let output = `# Frame Profiling Results\n\n`;
    output += `**Total Frames:** ${result.totalFrames}\n`;
    output += `**Janky Frames:** ${result.jankyFrames} (${result.totalFrames > 0 ? ((result.jankyFrames / result.totalFrames) * 100).toFixed(1) : 0}%)\n\n`;
    output += `## Timing Statistics\n`;
    output += `- **Average:** ${result.averageMs?.toFixed(2) || 0}ms\n`;
    output += `- **P50:** ${result.p50Ms?.toFixed(2) || 0}ms\n`;
    output += `- **P95:** ${result.p95Ms?.toFixed(2) || 0}ms\n`;
    output += `- **P99:** ${result.p99Ms?.toFixed(2) || 0}ms\n\n`;

    if (result.worstFrame) {
      output += `## Worst Frame\n`;
      output += `- **Frame #${result.worstFrame.index}:** ${result.worstFrame.durationMs?.toFixed(2) || 0}ms\n\n`;
    }

    if (result.histogram) {
      output += `## Histogram\n`;
      output += `| Range | Count |\n|-------|-------|\n`;
      for (const [range, count] of Object.entries(result.histogram)) {
        output += `| ${range} | ${count} |\n`;
      }
    }

    return { content: [{ type: "text", text: output }] };
  }
);

server.tool(
  "flutter_frame_budget_check",
  "Profile a specific action while measuring frame performance. Executes the action and returns frame analysis.",
  {
    action: z.enum(["scroll", "tap", "navigate", "type", "drag"]).describe("The action to profile"),
    widgetId: z.string().optional().describe("Widget ID for the action (required for tap, type, drag)"),
    params: z.record(z.any()).optional().describe("Additional parameters for the action"),
    budgetMs: z.number().optional().describe("Frame budget in ms (default: 16.67 for 60fps)"),
  },
  async ({ action, widgetId, params, budgetMs }) => {
    const b = await ensureBridge();
    const result = await b.send("frameBudgetCheck", {
      action,
      widgetId,
      params: params || {},
      budgetMs: budgetMs || 16.67,
    });

    if (result.error) {
      return { content: [{ type: "text", text: `Error: ${result.error}` }], isError: true };
    }

    let output = `# Frame Budget Analysis: ${action}\n\n`;
    output += `**Action Duration:** ${result.actionDuration?.toFixed(2) || 0}ms\n`;
    output += `**Total Frames:** ${result.totalFrames}\n`;
    output += `**Janky Frames:** ${result.jankyFrames} (${result.totalFrames > 0 ? ((result.jankyFrames / result.totalFrames) * 100).toFixed(1) : 0}%)\n\n`;

    const status = result.jankyFrames === 0 ? "PASS" : result.jankyFrames < 3 ? "WARN" : "FAIL";
    const icon = result.jankyFrames === 0 ? "green_circle" : result.jankyFrames < 3 ? "yellow_circle" : "red_circle";
    output += `**Status:** ${status}\n\n`;

    output += `## Timing Statistics\n`;
    output += `- **Average:** ${result.averageMs?.toFixed(2) || 0}ms\n`;
    output += `- **P50:** ${result.p50Ms?.toFixed(2) || 0}ms\n`;
    output += `- **P95:** ${result.p95Ms?.toFixed(2) || 0}ms\n`;
    output += `- **P99:** ${result.p99Ms?.toFixed(2) || 0}ms\n\n`;

    if (result.worstFrame) {
      output += `## Worst Frame\n`;
      output += `- **Frame #${result.worstFrame.index}:** ${result.worstFrame.durationMs?.toFixed(2) || 0}ms\n\n`;
    }

    if (result.histogram) {
      output += `## Histogram\n`;
      output += `| Range | Count |\n|-------|-------|\n`;
      for (const [range, count] of Object.entries(result.histogram)) {
        output += `| ${range} | ${count} |\n`;
      }
    }

    return { content: [{ type: "text", text: output }] };
  }
);

server.tool(
  "flutter_jank_detector",
  "Enable or disable continuous jank monitoring. When enabled, automatically logs janky frames.",
  {
    enabled: z.boolean().describe("Whether to enable jank detection"),
    threshold: z.number().optional().describe("Jank threshold in ms (default: 16.67). Frames exceeding this are logged."),
    callback: z.boolean().optional().describe("Whether to report jank events (default: true when enabled)"),
  },
  async ({ enabled, threshold, callback }) => {
    const b = await ensureBridge();
    const result = await b.send("jankDetector", {
      enabled,
      threshold: threshold || 16.67,
      callback: callback ?? enabled,
    });

    if (result.error) {
      return { content: [{ type: "text", text: `Error: ${result.error}` }], isError: true };
    }

    if (enabled) {
      let output = `Jank detector enabled (threshold: ${threshold || 16.67}ms)\n\n`;
      if (result.statistics) {
        output += `## Current Statistics\n`;
        output += `- **Total Frames:** ${result.statistics.totalFrames}\n`;
        output += `- **Janky Frames:** ${result.statistics.jankyFrames}\n`;
        output += `- **Jank Rate:** ${result.statistics.jankRate?.toFixed(1) || 0}%\n`;
      }
      return { content: [{ type: "text", text: output }] };
    } else {
      let output = `Jank detector disabled\n\n`;
      if (result.statistics) {
        output += `## Final Statistics\n`;
        output += `- **Total Frames:** ${result.statistics.totalFrames}\n`;
        output += `- **Janky Frames:** ${result.statistics.jankyFrames}\n`;
        output += `- **Jank Rate:** ${result.statistics.jankRate?.toFixed(1) || 0}%\n`;
        output += `- **Worst Frame:** ${result.statistics.worstFrameMs?.toFixed(2) || 0}ms\n`;
      }
      return { content: [{ type: "text", text: output }] };
    }
  }
);

// ============================================================================
// WIDGET REBUILD PROFILING
// ============================================================================

server.tool(
  "flutter_profile_rebuilds_start",
  "Start profiling widget rebuilds. Tracks all widget rebuilds with counts and reasons to identify unnecessary rebuilds.",
  {},
  async () => {
    const b = await ensureBridge();
    await b.send("profileRebuildsStart", {});
    return { content: [{ type: "text", text: `Widget rebuild profiling started. Interact with the app, then use flutter_profile_rebuilds_stop to see results.` }] };
  }
);

server.tool(
  "flutter_profile_rebuilds_stop",
  "Stop profiling widget rebuilds and get results. Returns a map of widgets with their rebuild counts and reasons.",
  {},
  async () => {
    const b = await ensureBridge();
    const result = await b.send("profileRebuildsStop", {});

    if (result.error) {
      return { content: [{ type: "text", text: `Error: ${result.error}` }], isError: true };
    }

    let output = `# Widget Rebuild Profile Results\n\n`;
    output += `**Profiling Duration:** ${result.durationMs?.toFixed(0) || 0}ms\n`;
    output += `**Total Rebuilds:** ${result.totalRebuilds || 0}\n`;
    output += `**Unique Widgets:** ${result.uniqueWidgets || 0}\n\n`;

    if (result.widgets && Object.keys(result.widgets).length > 0) {
      // Sort by rebuild count descending
      const sorted = Object.entries(result.widgets).sort((a: any, b: any) => b[1].count - a[1].count);

      output += `## Top Rebuilding Widgets\n`;
      output += `| Widget | Rebuilds | Reasons |\n`;
      output += `|--------|----------|----------|\n`;

      for (const [widgetId, info] of sorted.slice(0, 20) as Array<[string, { count: number; reasons: string[]; location?: string }]>) {
        const reasons = info.reasons?.join(", ") || "unknown";
        output += `| ${widgetId} | ${info.count} | ${reasons} |\n`;
      }

      if (sorted.length > 20) {
        output += `\n_...and ${sorted.length - 20} more widgets_\n`;
      }
    } else {
      output += `_No widget rebuilds detected during profiling._\n`;
    }

    return { content: [{ type: "text", text: output }] };
  }
);

server.tool(
  "flutter_profile_rebuilds_report",
  "Get detailed rebuild report with optional threshold filtering. Shows widgets sorted by rebuild count with reasons and locations.",
  {
    threshold: z.number().optional().describe("Only show widgets with rebuilds >= threshold (default: 1)"),
  },
  async ({ threshold }) => {
    const b = await ensureBridge();
    const result = await b.send("profileRebuildsReport", { threshold: threshold || 1 });

    if (result.error) {
      return { content: [{ type: "text", text: `Error: ${result.error}` }], isError: true };
    }

    if (!result.isActive && !result.widgets) {
      return { content: [{ type: "text", text: `No profiling data available. Start profiling with flutter_profile_rebuilds_start first.` }] };
    }

    let output = `# Widget Rebuild Report\n\n`;
    output += `**Status:** ${result.isActive ? "Profiling Active" : "Profiling Stopped"}\n`;
    output += `**Threshold:** >= ${threshold || 1} rebuilds\n`;
    output += `**Total Rebuilds:** ${result.totalRebuilds || 0}\n`;
    output += `**Matching Widgets:** ${result.matchingWidgets || 0}\n\n`;

    if (result.widgets && result.widgets.length > 0) {
      for (const widget of result.widgets) {
        output += `## ${widget.widgetId}\n`;
        output += `- **Rebuilds:** ${widget.count}\n`;
        if (widget.location) {
          output += `- **Location:** ${widget.location}\n`;
        }
        if (widget.reasons && widget.reasons.length > 0) {
          output += `- **Reasons:**\n`;
          for (const reason of widget.reasons) {
            output += `  - ${reason}\n`;
          }
        }
        output += `\n`;
      }
    } else {
      output += `_No widgets found with >= ${threshold || 1} rebuilds._\n`;
    }

    return { content: [{ type: "text", text: output }] };
  }
);

// ============================================================================
// STATE DEPENDENCY GRAPH
// ============================================================================

server.tool(
  "flutter_state_dependency_graph",
  "Get the dependency graph of all state providers. Returns nodes (providers) and edges (dependencies/notifications).",
  {},
  async () => {
    const b = await ensureBridge();
    const result = await b.send("stateDependencyGraph", {});

    if (result.error) {
      return { content: [{ type: "text", text: `Error: ${result.error}` }], isError: true };
    }

    let output = `# State Dependency Graph\n\n`;
    output += `**Nodes:** ${result.nodes?.length || 0} providers\n`;
    output += `**Edges:** ${result.edges?.length || 0} dependencies\n\n`;

    if (result.nodes?.length > 0) {
      output += `## Providers\n`;
      output += `| ID | Type | Name |\n`;
      output += `|----|------|------|\n`;
      for (const node of result.nodes) {
        output += `| ${node.id} | ${node.type} | ${node.name} |\n`;
      }
      output += `\n`;
    }

    if (result.edges?.length > 0) {
      output += `## Dependencies\n`;
      output += `| From | To | Type |\n`;
      output += `|------|-----|------|\n`;
      for (const edge of result.edges) {
        output += `| ${edge.from} | ${edge.to} | ${edge.type} |\n`;
      }
    }

    output += `\n\n\`\`\`json\n${JSON.stringify(result, null, 2)}\n\`\`\``;

    return { content: [{ type: "text", text: output }] };
  }
);

server.tool(
  "flutter_state_impact_analysis",
  "Analyze what would be affected by changing a provider. Shows direct dependents, transitive dependents, affected widgets, and an impact score.",
  {
    providerId: z.string().describe("The provider ID to analyze impact for"),
  },
  async ({ providerId }) => {
    const b = await ensureBridge();
    const result = await b.send("stateImpactAnalysis", { providerId });

    if (result.error) {
      return { content: [{ type: "text", text: `Error: ${result.error}` }], isError: true };
    }

    let output = `# Impact Analysis: ${providerId}\n\n`;
    output += `**Impact Score:** ${result.impactScore || 0}/100\n\n`;

    output += `## Direct Dependents (${result.directDependents?.length || 0})\n`;
    if (result.directDependents?.length > 0) {
      for (const dep of result.directDependents) {
        output += `- ${dep}\n`;
      }
    } else {
      output += `_No direct dependents_\n`;
    }
    output += `\n`;

    output += `## Transitive Dependents (${result.transitiveDependents?.length || 0})\n`;
    if (result.transitiveDependents?.length > 0) {
      for (const dep of result.transitiveDependents) {
        output += `- ${dep}\n`;
      }
    } else {
      output += `_No transitive dependents_\n`;
    }
    output += `\n`;

    output += `## Affected Widgets (${result.affectedWidgets?.length || 0})\n`;
    if (result.affectedWidgets?.length > 0) {
      for (const widget of result.affectedWidgets) {
        output += `- ${widget}\n`;
      }
    } else {
      output += `_No widgets directly affected_\n`;
    }

    return { content: [{ type: "text", text: output }] };
  }
);

server.tool(
  "flutter_state_trace",
  "Trace state flow from a source provider to widgets. Shows the path and any transformations applied.",
  {
    providerId: z.string().describe("The source provider ID to trace from"),
    widgetId: z.string().optional().describe("Optional target widget ID to trace to"),
  },
  async ({ providerId, widgetId }) => {
    const b = await ensureBridge();
    const result = await b.send("stateTrace", { providerId, widgetId });

    if (result.error) {
      return { content: [{ type: "text", text: `Error: ${result.error}` }], isError: true };
    }

    let output = `# State Trace: ${providerId}`;
    if (widgetId) {
      output += ` -> ${widgetId}`;
    }
    output += `\n\n`;

    if (result.path?.length > 0) {
      output += `## Flow Path\n`;
      for (let i = 0; i < result.path.length; i++) {
        const node = result.path[i];
        const prefix = i === 0 ? "Source" : i === result.path.length - 1 ? "Target" : "Via";
        output += `${i + 1}. **[${prefix}]** ${node.node} (${node.type})\n`;
      }
      output += `\n`;
    } else {
      output += `_No path found_\n\n`;
    }

    if (result.transformations?.length > 0) {
      output += `## Transformations\n`;
      for (const transform of result.transformations) {
        output += `- ${transform}\n`;
      }
    }

    return { content: [{ type: "text", text: output }] };
  }
);

server.tool(
  "flutter_orphan_state_check",
  "Find providers that are defined but never used. Helps identify dead code in state management.",
  {},
  async () => {
    const b = await ensureBridge();
    const result = await b.send("orphanStateCheck", {});

    if (result.error) {
      return { content: [{ type: "text", text: `Error: ${result.error}` }], isError: true };
    }

    let output = `# Orphan State Check\n\n`;

    const orphanCount = result.orphanedProviders?.length || 0;
    const unusedCount = result.unusedInWidgets?.length || 0;

    if (orphanCount === 0 && unusedCount === 0) {
      output += `All state providers are being used.\n`;
    } else {
      if (orphanCount > 0) {
        output += `## Orphaned Providers (${orphanCount})\n`;
        output += `_These providers are defined but have no dependents:_\n\n`;
        for (const provider of result.orphanedProviders) {
          output += `- ${provider}\n`;
        }
        output += `\n`;
      }

      if (unusedCount > 0) {
        output += `## Unused in Widgets (${unusedCount})\n`;
        output += `_These providers are not consumed by any widgets:_\n\n`;
        for (const provider of result.unusedInWidgets) {
          output += `- ${provider}\n`;
        }
      }
    }

    return { content: [{ type: "text", text: output }] };
  }
);

// ============================================================================
// APP LIFECYCLE TESTING
// ============================================================================

server.tool(
  "flutter_simulate_lifecycle",
  "Simulate app lifecycle events (paused, resumed, inactive, detached, hidden). Triggers the lifecycle callback in the app, notifying all WidgetsBindingObservers.",
  {
    state: z.enum(["paused", "resumed", "inactive", "detached", "hidden"]).describe("The lifecycle state to simulate"),
  },
  async ({ state }) => {
    const b = await ensureBridge();
    const result = await b.send("simulateLifecycle", { state });

    if (result.error) {
      return { content: [{ type: "text", text: `Error: ${result.error}` }], isError: true };
    }

    return {
      content: [{
        type: "text",
        text: `Lifecycle state changed: ${result.previousState} -> ${result.currentState}`
      }]
    };
  }
);

server.tool(
  "flutter_lifecycle_history",
  "Get history of lifecycle events that have occurred during testing.",
  {},
  async () => {
    const b = await ensureBridge();
    const result = await b.send("lifecycleHistory", {});

    if (result.error) {
      return { content: [{ type: "text", text: `Error: ${result.error}` }], isError: true };
    }

    let output = `# Lifecycle History\n\n`;
    output += `**Current State:** ${result.currentState}\n`;
    output += `**Total Events:** ${result.eventCount}\n\n`;

    if (result.events && result.events.length > 0) {
      output += `## Events\n`;
      output += `| State | Timestamp |\n`;
      output += `|-------|----------|\n`;

      for (const event of result.events) {
        const timestamp = new Date(event.timestamp).toISOString();
        output += `| ${event.state} | ${timestamp} |\n`;
      }
    } else {
      output += `_No lifecycle events recorded._\n`;
    }

    return { content: [{ type: "text", text: output }] };
  }
);

server.tool(
  "flutter_simulate_memory_pressure",
  "Simulate low memory warning. Clears image caches and notifies observers about memory pressure. Use this to test how your app handles low memory conditions.",
  {
    level: z.enum(["low", "critical"]).describe("Memory pressure level: 'low' clears caches, 'critical' performs more aggressive cleanup"),
  },
  async ({ level }) => {
    const b = await ensureBridge();
    const result = await b.send("simulateMemoryPressure", { level });

    if (result.error) {
      return { content: [{ type: "text", text: `Error: ${result.error}` }], isError: true };
    }

    let output = `Memory pressure simulated: ${level}\n\n`;
    output += `**Cleared Caches:**\n`;
    for (const cache of result.clearedCaches || []) {
      output += `- ${cache}\n`;
    }

    return { content: [{ type: "text", text: output }] };
  }
);

server.tool(
  "flutter_simulate_locale_change",
  "Simulate system locale change. Notifies all WidgetsBindingObservers about the locale change, triggering app localization updates.",
  {
    locale: z.string().describe("Locale code (e.g., 'en_US', 'fr_FR', 'es_ES', 'de_DE')"),
  },
  async ({ locale }) => {
    const b = await ensureBridge();
    const result = await b.send("simulateLocaleChange", { locale });

    if (result.error) {
      return { content: [{ type: "text", text: `Error: ${result.error}` }], isError: true };
    }

    return {
      content: [{
        type: "text",
        text: `Locale changed: ${result.previousLocale} -> ${result.currentLocale}`
      }]
    };
  }
);

server.tool(
  "flutter_simulate_text_scale_change",
  "Simulate system text scale change (accessibility). Notifies observers about text scale factor changes, useful for testing accessibility features.",
  {
    scale: z.number().describe("Text scale factor (e.g., 1.0 = normal, 1.5 = 150%, 2.0 = 200%)"),
  },
  async ({ scale }) => {
    const b = await ensureBridge();
    const result = await b.send("simulateTextScaleChange", { scale });

    if (result.error) {
      return { content: [{ type: "text", text: `Error: ${result.error}` }], isError: true };
    }

    return {
      content: [{
        type: "text",
        text: `Text scale changed: ${result.previousScale} -> ${result.currentScale}`
      }]
    };
  }
);

server.tool(
  "flutter_simulate_brightness_change",
  "Simulate system brightness mode change (light/dark). Notifies observers about platform brightness changes, triggering theme updates.",
  {
    brightness: z.enum(["light", "dark"]).describe("Brightness mode: 'light' or 'dark'"),
  },
  async ({ brightness }) => {
    const b = await ensureBridge();
    const result = await b.send("simulateBrightnessChange", { brightness });

    if (result.error) {
      return { content: [{ type: "text", text: `Error: ${result.error}` }], isError: true };
    }

    return {
      content: [{
        type: "text",
        text: `Brightness changed: ${result.previousBrightness} -> ${result.currentBrightness}`
      }]
    };
  }
);

// ============================================================================
// RESOURCES
// ============================================================================

server.resource(
  "flutter://widgets",
  "Complete widget catalog with all detected interactive widgets.",
  async () => {
    const b = await ensureBridge();
    const catalog = await b.send("getWidgetCatalog", {});
    return {
      contents: [{
        uri: "flutter://widgets",
        mimeType: "application/json",
        text: JSON.stringify(catalog, null, 2),
      }],
    };
  }
);

server.resource(
  "flutter://flows",
  "Navigation flow graph showing routes and user journeys.",
  async () => {
    const b = await ensureBridge();
    const flows = await b.send("getFlowGraph", {});
    return {
      contents: [{
        uri: "flutter://flows",
        mimeType: "application/json",
        text: JSON.stringify(flows, null, 2),
      }],
    };
  }
);

server.resource(
  "flutter://state",
  "Current app state summary.",
  async () => {
    try {
      const b = await ensureBridge();
      const state = await b.send("getCurrentState", {});

      let text = `# App State\n\n`;
      text += `- **Connected:** Yes\n`;
      text += `- **Screen:** ${state.currentScreen}\n`;
      text += `- **Widgets:** ${state.widgetCount}\n`;
      text += `- **Test Mode:** ${state.testModeActive ? "Active" : "Inactive"}\n`;

      return {
        contents: [{
          uri: "flutter://state",
          mimeType: "text/markdown",
          text,
        }],
      };
    } catch {
      return {
        contents: [{
          uri: "flutter://state",
          mimeType: "text/markdown",
          text: `# App State\n\n**Status:** Disconnected`,
        }],
      };
    }
  }
);

// ============================================================================
// TIME-TRAVEL STATE SNAPSHOTS
// ============================================================================

server.tool(
  "flutter_time_travel_start",
  "Start recording time-travel snapshots. Captures widget tree and state snapshots that can be restored later.",
  {
    captureOnInteraction: z.boolean().optional().describe("Automatically capture snapshots on user interactions (default: false)"),
    intervalMs: z.number().optional().describe("Capture snapshots at this interval in milliseconds (optional)"),
  },
  async ({ captureOnInteraction, intervalMs }) => {
    const b = await ensureBridge();
    const result = await b.send("timeTravelStart", {
      captureOnInteraction: captureOnInteraction || false,
      intervalMs,
    });

    if (result.error) {
      return { content: [{ type: "text", text: `Error: ${result.error}` }], isError: true };
    }

    let output = `# Time-Travel Recording Started\n\n`;
    output += `**Capture on Interaction:** ${result.captureOnInteraction ? "Yes" : "No"}\n`;
    if (result.intervalMs) {
      output += `**Auto-capture Interval:** ${result.intervalMs}ms\n`;
    }
    output += `\nUse \`flutter_time_travel_snapshot\` to manually capture snapshots.\n`;
    output += `Use \`flutter_time_travel_list\` to see all captured snapshots.\n`;
    output += `Use \`flutter_time_travel_goto\` to restore a previous state.\n`;

    return { content: [{ type: "text", text: output }] };
  }
);

server.tool(
  "flutter_time_travel_snapshot",
  "Manually capture a snapshot of the current app state.",
  {
    label: z.string().optional().describe("Optional label for this snapshot"),
  },
  async ({ label }) => {
    const b = await ensureBridge();
    const result = await b.send("timeTravelSnapshot", { label });

    if (result.error) {
      return { content: [{ type: "text", text: `Error: ${result.error}` }], isError: true };
    }

    let output = `# Snapshot Captured\n\n`;
    output += `**Snapshot ID:** ${result.snapshotId}\n`;
    if (result.label) {
      output += `**Label:** ${result.label}\n`;
    }
    output += `**Route:** ${result.route}\n`;
    output += `**Timestamp:** ${new Date(result.timestamp).toISOString()}\n`;

    return { content: [{ type: "text", text: output }] };
  }
);

server.tool(
  "flutter_time_travel_list",
  "List all captured time-travel snapshots.",
  {},
  async () => {
    const b = await ensureBridge();
    const result = await b.send("timeTravelList", {});

    let output = `# Time-Travel Snapshots\n\n`;
    output += `**Recording:** ${result.isRecording ? "Active" : "Stopped"}\n`;
    output += `**Total Snapshots:** ${result.totalCount}\n\n`;

    if (result.snapshots && result.snapshots.length > 0) {
      output += `| # | ID | Label | Route | Time |\n`;
      output += `|---|-------|-------|-------|------|\n`;

      for (let i = 0; i < result.snapshots.length; i++) {
        const snap = result.snapshots[i];
        const time = new Date(snap.timestamp).toLocaleTimeString();
        output += `| ${i} | ${snap.id.slice(-8)} | ${snap.label || "-"} | ${snap.route} | ${time} |\n`;
      }
    } else {
      output += `_No snapshots captured yet._\n`;
    }

    return { content: [{ type: "text", text: output }] };
  }
);

server.tool(
  "flutter_time_travel_goto",
  "Restore the app to a previously captured snapshot state. Restores navigation, provider states, and storage.",
  {
    snapshotId: z.string().optional().describe("ID of the snapshot to restore"),
    index: z.number().optional().describe("Index of the snapshot to restore (0-based)"),
  },
  async ({ snapshotId, index }) => {
    const b = await ensureBridge();
    const result = await b.send("timeTravelGoto", { snapshotId, index });

    if (!result.success) {
      return { content: [{ type: "text", text: `Error: ${result.error}` }], isError: true };
    }

    let output = `# State Restored\n\n`;
    output += `**Restored From:** ${result.restoredFrom}\n`;
    output += `**Route:** ${result.route}\n`;
    output += `**Original Time:** ${new Date(result.timestamp).toISOString()}\n\n`;
    output += `The app has been restored to this snapshot's state.\n`;

    return { content: [{ type: "text", text: output }] };
  }
);

server.tool(
  "flutter_time_travel_stop",
  "Stop recording time-travel snapshots.",
  {
    clear: z.boolean().optional().describe("Clear all captured snapshots (default: false)"),
  },
  async ({ clear }) => {
    const b = await ensureBridge();
    const result = await b.send("timeTravelStop", { clear: clear || false });

    let output = `# Time-Travel Recording Stopped\n\n`;
    output += `**Total Snapshots:** ${result.totalSnapshots}\n`;
    output += `**Cleared:** ${result.cleared ? "Yes" : "No"}\n`;

    if (!result.cleared && result.totalSnapshots > 0) {
      output += `\nSnapshots are still available. Use \`flutter_time_travel_list\` to see them.\n`;
    }

    return { content: [{ type: "text", text: output }] };
  }
);

server.tool(
  "flutter_time_travel_diff",
  "Compare two snapshots and show what changed between them.",
  {
    from: z.string().describe("ID of the starting snapshot"),
    to: z.string().describe("ID of the ending snapshot"),
  },
  async ({ from, to }) => {
    const b = await ensureBridge();
    try {
      const result = await b.send("timeTravelDiff", { from, to });

      let output = `# Snapshot Diff\n\n`;
      output += `**From:** ${result.from.id} (${result.from.label || "unlabeled"})\n`;
      output += `**To:** ${result.to.id} (${result.to.label || "unlabeled"})\n`;
      output += `**Time Delta:** ${result.timeDeltaMs}ms\n\n`;

      if (result.routeChanged) {
        output += `## Route Changed\n`;
        output += `- **From:** ${result.fromRoute}\n`;
        output += `- **To:** ${result.toRoute}\n\n`;
      }

      if (result.stateChanges && result.stateChanges.length > 0) {
        output += `## State Changes (${result.stateChanges.length})\n`;
        for (const change of result.stateChanges) {
          output += `### ${change.providerId}\n`;
          output += `- **Type:** ${change.type}\n`;
          if (change.oldValue) {
            output += `- **Old:** \`${JSON.stringify(change.oldValue).slice(0, 100)}...\`\n`;
          }
          if (change.newValue) {
            output += `- **New:** \`${JSON.stringify(change.newValue).slice(0, 100)}...\`\n`;
          }
          output += `\n`;
        }
      }

      if (result.storageChanges && result.storageChanges.length > 0) {
        output += `## Storage Changes (${result.storageChanges.length})\n`;
        for (const change of result.storageChanges) {
          output += `- **${change.key}** (${change.type})`;
          if (change.type === "changed") {
            output += `: \`${change.oldValue}\` -> \`${change.newValue}\``;
          }
          output += `\n`;
        }
        output += `\n`;
      }

      if (result.widgetChanges && result.widgetChanges.length > 0) {
        output += `## Widget Tree Changes\n`;
        output += `_The widget tree structure has changed between these snapshots._\n\n`;
      }

      if (!result.routeChanged &&
          (!result.stateChanges || result.stateChanges.length === 0) &&
          (!result.storageChanges || result.storageChanges.length === 0) &&
          (!result.widgetChanges || result.widgetChanges.length === 0)) {
        output += `_No differences detected between these snapshots._\n`;
      }

      return { content: [{ type: "text", text: output }] };
    } catch (e: any) {
      return { content: [{ type: "text", text: `Error: ${e.message}` }], isError: true };
    }
  }
);

// ============================================================================
// BIOMETRIC AUTHENTICATION MOCKING
// ============================================================================

server.tool(
  "flutter_set_biometric_availability",
  "Set which biometric types are available for authentication. Apps can use SelfTestBridge.getAvailableBiometrics() to check available types.",
  {
    faceId: z.boolean().optional().describe("Face ID availability (iOS)"),
    touchId: z.boolean().optional().describe("Touch ID availability (iOS)"),
    fingerprint: z.boolean().optional().describe("Fingerprint availability (Android)"),
    iris: z.boolean().optional().describe("Iris scanner availability"),
    deviceCredential: z.boolean().optional().describe("Device credential (PIN/pattern/password) availability"),
  },
  async ({ faceId, touchId, fingerprint, iris, deviceCredential }) => {
    const b = await ensureBridge();
    const result = await b.send("setBiometricAvailability", {
      faceId,
      touchId,
      fingerprint,
      iris,
      deviceCredential,
    });
    return {
      content: [{
        type: "text",
        text: `Biometric availability configured.\n\n**Available types:** ${(result.available || []).join(", ") || "none"}`,
      }],
    };
  }
);

server.tool(
  "flutter_set_biometric_result",
  "Set what the next biometric authentication attempt will return. Use this to test different authentication scenarios.",
  {
    result: z.enum(["success", "failed", "cancelled", "notAvailable", "notEnrolled", "lockedOut"])
      .describe("The result of the next biometric auth attempt"),
    errorMessage: z.string().optional().describe("Custom error message to return on failure"),
    delay: z.number().optional().describe("Delay in milliseconds before returning result (simulates user interaction time)"),
  },
  async ({ result, errorMessage, delay }) => {
    const b = await ensureBridge();
    await b.send("setBiometricResult", { result, errorMessage, delay });
    let output = `Biometric result configured: **${result}**`;
    if (errorMessage) output += `\n**Error message:** ${errorMessage}`;
    if (delay) output += `\n**Delay:** ${delay}ms`;
    return { content: [{ type: "text", text: output }] };
  }
);

server.tool(
  "flutter_biometric_auth_history",
  "Get history of all biometric authentication attempts made during testing.",
  {},
  async () => {
    const b = await ensureBridge();
    const result = await b.send("biometricAuthHistory", {});

    let output = `# Biometric Auth History\n\n`;
    output += `**Total attempts:** ${result.attempts?.length || 0}\n\n`;

    if (result.attempts && result.attempts.length > 0) {
      output += `| Time | Type | Result | Reason |\n`;
      output += `|------|------|--------|--------|\n`;

      for (const attempt of result.attempts) {
        const time = new Date(attempt.timestamp).toLocaleTimeString();
        const icon = attempt.result === "success" ? "ok" : "x";
        output += `| ${time} | ${attempt.type} | ${icon} ${attempt.result} | ${attempt.reason || "-"} |\n`;
      }
    } else {
      output += `_No biometric authentication attempts recorded._\n`;
    }

    return { content: [{ type: "text", text: output }] };
  }
);

server.tool(
  "flutter_simulate_biometric_prompt",
  "Trigger a biometric authentication prompt programmatically. Returns the configured result.",
  {
    reason: z.string().describe("The reason shown to the user (e.g., 'Verify your identity')"),
    type: z.string().optional().describe("Preferred biometric type (faceId, touchId, fingerprint, iris). Defaults to fingerprint."),
  },
  async ({ reason, type }) => {
    const b = await ensureBridge();
    try {
      const result = await b.send("simulateBiometricPrompt", { reason, type });

      if (result.success) {
        return {
          content: [{
            type: "text",
            text: `Biometric authentication successful.\n\n**Authenticated as:** ${result.authenticatedAs || "user"}\n**Reason:** ${reason}`,
          }],
        };
      } else {
        return {
          content: [{
            type: "text",
            text: `Biometric authentication failed.\n\n**Error:** ${result.error}\n**Reason:** ${reason}`,
          }],
          isError: true,
        };
      }
    } catch (e: any) {
      return { content: [{ type: "text", text: `Error: ${e.message}` }], isError: true };
    }
  }
);

server.tool(
  "flutter_clear_biometric_config",
  "Reset all biometric configuration to defaults. Clears availability settings, result configuration, and history.",
  {},
  async () => {
    const b = await ensureBridge();
    await b.send("clearBiometricConfig", {});
    return {
      content: [{
        type: "text",
        text: `Biometric configuration cleared.\n\n- All biometric types reset to unavailable (except deviceCredential)\n- Next result reset to "success"\n- Auth history cleared`,
      }],
    };
  }
);

// ============================================================================
// SEMANTIC LABEL AUTO-GENERATION
// ============================================================================

server.tool(
  "flutter_suggest_semantics",
  "Analyze widgets and suggest semantic labels for accessibility. Returns suggestions for interactive widgets lacking semantic labels.",
  {
    screen: z.string().optional().describe("Filter to specific screen name"),
    includeLabeled: z.boolean().optional().describe("Include widgets that already have labels (default: false)"),
  },
  async ({ screen, includeLabeled }) => {
    const b = await ensureBridge();
    const result = await b.send("suggestSemantics", { screen, includeLabeled: includeLabeled || false });

    if (result.error) {
      return { content: [{ type: "text", text: `Error: ${result.error}` }], isError: true };
    }

    let output = `# Semantic Label Suggestions\n\n`;
    output += `**Total Widgets Analyzed:** ${result.totalAnalyzed || 0}\n`;
    output += `**Suggestions:** ${result.suggestions?.length || 0}\n\n`;

    if (result.suggestions && result.suggestions.length > 0) {
      for (const s of result.suggestions) {
        output += `## ${s.widgetType}\n`;
        output += `- **ID:** ${s.id}\n`;
        output += `- **Current Label:** ${s.currentLabel || "(none)"}\n`;
        output += `- **Suggested Label:** \`${s.suggestedLabel}\`\n`;
        output += `- **Confidence:** ${(s.confidence * 100).toFixed(0)}%\n`;
        output += `- **Location:** ${s.location}\n`;
        output += `- **Reason:** ${s.reason}\n\n`;
      }
    } else {
      output += `_All interactive widgets have semantic labels!_\n`;
    }

    return { content: [{ type: "text", text: output }] };
  }
);

server.tool(
  "flutter_semantics_coverage",
  "Get semantics coverage report showing labeled vs unlabeled interactive widgets by type.",
  {},
  async () => {
    const b = await ensureBridge();
    const result = await b.send("semanticsCoverage", {});

    if (result.error) {
      return { content: [{ type: "text", text: `Error: ${result.error}` }], isError: true };
    }

    let output = `# Semantics Coverage Report\n\n`;
    output += `**Total Interactive Widgets:** ${result.totalWidgets || 0}\n`;
    output += `**Labeled Widgets:** ${result.labeledWidgets || 0}\n`;
    output += `**Coverage:** ${(result.coveragePercent || 0).toFixed(1)}%\n\n`;

    if (result.byType && Object.keys(result.byType).length > 0) {
      output += `## Coverage by Widget Type\n\n`;
      output += `| Widget Type | Total | Labeled | Coverage |\n`;
      output += `|-------------|-------|---------|----------|\n`;

      for (const [type, counts] of Object.entries(result.byType) as [string, { total: number; labeled: number }][]) {
        const pct = counts.total > 0 ? ((counts.labeled / counts.total) * 100).toFixed(0) : "100";
        output += `| ${type} | ${counts.total} | ${counts.labeled} | ${pct}% |\n`;
      }
      output += `\n`;
    }

    if (result.unlabeledInteractive && result.unlabeledInteractive.length > 0) {
      output += `## Unlabeled Interactive Widgets\n`;
      for (const id of result.unlabeledInteractive.slice(0, 20)) {
        output += `- ${id}\n`;
      }
      if (result.unlabeledInteractive.length > 20) {
        output += `_... and ${result.unlabeledInteractive.length - 20} more_\n`;
      }
    }

    return { content: [{ type: "text", text: output }] };
  }
);

server.tool(
  "flutter_semantics_tree",
  "Get the full semantics tree with detailed node information. More detailed than snapshot.",
  {
    includeHidden: z.boolean().optional().describe("Include hidden/invisible semantics nodes (default: false)"),
  },
  async ({ includeHidden }) => {
    const b = await ensureBridge();
    const result = await b.send("semanticsTree", { includeHidden: includeHidden || false });

    if (result.error) {
      return { content: [{ type: "text", text: `Error: ${result.error}` }], isError: true };
    }

    let output = `# Semantics Tree\n\n`;
    output += `**Total Nodes:** ${result.flatList?.length || 0}\n\n`;

    if (result.flatList && result.flatList.length > 0) {
      output += `## Semantic Nodes\n\n`;
      output += `| ID | Label | Role | Actions |\n`;
      output += `|----|-------|------|--------|\n`;

      for (const node of result.flatList.slice(0, 50)) {
        const label = node.label || "(no label)";
        const role = node.role || "generic";
        const actions = (node.actions || []).join(", ") || "(none)";
        output += `| ${node.id} | ${label.substring(0, 30)} | ${role} | ${actions} |\n`;
      }

      if (result.flatList.length > 50) {
        output += `\n_... and ${result.flatList.length - 50} more nodes_\n`;
      }
    }

    return { content: [{ type: "text", text: output }] };
  }
);

server.tool(
  "flutter_apply_suggested_semantics",
  "Generate code snippets to apply suggested semantic labels. Call flutter_suggest_semantics first to get suggestion IDs.",
  {
    suggestions: z.array(z.string()).describe("List of suggestion IDs to apply (from flutter_suggest_semantics)"),
  },
  async ({ suggestions }) => {
    const b = await ensureBridge();
    const result = await b.send("applySuggestedSemantics", { suggestions });

    if (result.error) {
      return { content: [{ type: "text", text: `Error: ${result.error}` }], isError: true };
    }

    let output = `# Code Snippets for Semantic Labels\n\n`;
    output += `**Applied:** ${result.appliedCount || 0} / ${result.requestedCount || 0}\n\n`;

    if (result.codeSnippets && result.codeSnippets.length > 0) {
      for (const snippet of result.codeSnippets) {
        output += `## ${snippet.widgetType}\n`;
        output += `**Suggested Label:** \`${snippet.suggestedLabel}\`\n`;
        output += `**Location:** ${snippet.file}\n\n`;
        output += `### Before\n\`\`\`dart\n${snippet.before}\n\`\`\`\n\n`;
        output += `### After\n\`\`\`dart\n${snippet.after}\n\`\`\`\n\n`;
      }
    } else {
      output += `_No code snippets generated. Make sure to call flutter_suggest_semantics first and use valid suggestion IDs._\n`;
    }

    return { content: [{ type: "text", text: output }] };
  }
);

// ============================================================================
// MEMORY PROFILING
// ============================================================================

server.tool(
  "flutter_memory_snapshot",
  "Get current memory usage snapshot. Returns heap usage, capacity, external memory, and image cache statistics.",
  {},
  async () => {
    const b = await ensureBridge();
    const result = await b.send("memorySnapshot", {});

    if (result.error) {
      return { content: [{ type: "text", text: `Error: ${result.error}` }], isError: true };
    }

    let output = `# Memory Snapshot\n\n`;
    output += `**Timestamp:** ${new Date(result.timestamp).toISOString()}\n\n`;
    output += `## Heap Memory\n`;
    output += `- **Used:** ${formatBytes(result.heapUsed)}\n`;
    output += `- **Capacity:** ${formatBytes(result.heapCapacity)}\n`;
    output += `- **External:** ${formatBytes(result.externalUsage)}\n\n`;
    output += `## Image Cache\n`;
    output += `- **Images:** ${result.imageCache?.count || 0}\n`;
    output += `- **Size:** ${formatBytes(result.imageCache?.sizeBytes || 0)}\n`;

    return { content: [{ type: "text", text: output }] };
  }
);

server.tool(
  "flutter_memory_profile_start",
  "Start memory profiling over time. Captures memory usage at regular intervals for analysis.",
  {
    intervalMs: z.number().optional().describe("Sampling interval in milliseconds (default: 1000)"),
  },
  async ({ intervalMs }) => {
    const b = await ensureBridge();
    const result = await b.send("memoryProfileStart", { intervalMs: intervalMs || 1000 });

    if (result.error) {
      return { content: [{ type: "text", text: `Error: ${result.error}` }], isError: true };
    }

    return {
      content: [{
        type: "text",
        text: `Memory profiling started (interval: ${intervalMs || 1000}ms)\n\nUse \`flutter_memory_profile_stop\` to stop and get results.`
      }]
    };
  }
);

server.tool(
  "flutter_memory_profile_stop",
  "Stop memory profiling and get results. Returns samples, peak usage, average, and potential leak warnings.",
  {},
  async () => {
    const b = await ensureBridge();
    const result = await b.send("memoryProfileStop", {});

    if (result.error) {
      return { content: [{ type: "text", text: `Error: ${result.error}` }], isError: true };
    }

    let output = `# Memory Profile Results\n\n`;
    output += `**Samples:** ${result.samples?.length || 0}\n`;
    output += `**Peak:** ${formatBytes(result.peak || 0)}\n`;
    output += `**Average:** ${formatBytes(result.average || 0)}\n\n`;

    if (result.leakSuspects && result.leakSuspects.length > 0) {
      output += `## Potential Issues\n`;
      for (const suspect of result.leakSuspects) {
        output += `- ${suspect}\n`;
      }
      output += `\n`;
    }

    if (result.samples && result.samples.length > 0) {
      output += `## Memory Timeline\n`;
      output += `| Time | Heap Used |\n`;
      output += `|------|----------|\n`;
      const step = Math.max(1, Math.floor(result.samples.length / 10));
      for (let i = 0; i < result.samples.length; i += step) {
        const sample = result.samples[i];
        const time = new Date(sample.timestamp).toLocaleTimeString();
        output += `| ${time} | ${formatBytes(sample.heapUsed)} |\n`;
      }
    }

    return { content: [{ type: "text", text: output }] };
  }
);

server.tool(
  "flutter_force_gc",
  "Force garbage collection. Clears image caches and triggers GC. Returns memory before and after.",
  {},
  async () => {
    const b = await ensureBridge();
    const result = await b.send("forceGc", {});

    if (result.error) {
      return { content: [{ type: "text", text: `Error: ${result.error}` }], isError: true };
    }

    let output = `# Garbage Collection\n\n`;
    output += `**Before:** ${formatBytes(result.memoryBefore || 0)}\n`;
    output += `**After:** ${formatBytes(result.memoryAfter || 0)}\n`;
    output += `**Freed:** ${formatBytes(result.freed || 0)}\n`;

    return { content: [{ type: "text", text: output }] };
  }
);

server.tool(
  "flutter_image_cache_stats",
  "Get image cache statistics. Shows current size, maximum size, and image counts.",
  {},
  async () => {
    const b = await ensureBridge();
    const result = await b.send("imageCacheStats", {});

    if (result.error) {
      return { content: [{ type: "text", text: `Error: ${result.error}` }], isError: true };
    }

    let output = `# Image Cache Statistics\n\n`;
    output += `**Current Images:** ${result.currentSize || 0} / ${result.maximumSize || 0}\n`;
    output += `**Live Images:** ${result.liveImages || 0}\n`;
    output += `**Pending Images:** ${result.pendingImages || 0}\n`;
    output += `**Current Size:** ${formatBytes(result.currentSizeBytes || 0)}\n`;
    output += `**Maximum Size:** ${formatBytes(result.maximumSizeBytes || 0)}\n`;

    return { content: [{ type: "text", text: output }] };
  }
);

server.tool(
  "flutter_clear_image_cache",
  "Clear the image cache. Frees memory used by cached images.",
  {},
  async () => {
    const b = await ensureBridge();
    const result = await b.send("clearImageCache", {});

    if (result.error) {
      return { content: [{ type: "text", text: `Error: ${result.error}` }], isError: true };
    }

    let output = `# Image Cache Cleared\n\n`;
    output += `**Images Cleared:** ${result.cleared || 0}\n`;
    output += `**Memory Freed:** ${formatBytes(result.freedBytes || 0)}\n`;

    return { content: [{ type: "text", text: output }] };
  }
);

server.tool(
  "flutter_memory_leak_check",
  "Run heuristic leak detection by repeating an action multiple times and monitoring memory growth.",
  {
    action: z.string().describe("The bridge command to repeat for leak detection (e.g., 'navigate', 'tap')"),
    iterations: z.number().optional().describe("Number of iterations (default: 5)"),
  },
  async ({ action, iterations }) => {
    const b = await ensureBridge();
    const result = await b.send("memoryLeakCheck", {
      action,
      iterations: iterations || 5,
    });

    if (result.error) {
      return { content: [{ type: "text", text: `Error: ${result.error}` }], isError: true };
    }

    let output = `# Memory Leak Check\n\n`;
    output += `**Action:** ${action}\n`;
    output += `**Iterations:** ${result.iterations || 0}\n\n`;
    output += `## Results\n`;
    output += `- **Potential Leaks:** ${result.potentialLeaks ? "Yes" : "No"}\n`;
    output += `- **Memory Before:** ${formatBytes(result.memoryBefore || 0)}\n`;
    output += `- **Memory After:** ${formatBytes(result.memoryAfter || 0)}\n`;
    output += `- **Memory Growth:** ${formatBytes(result.memoryGrowth || 0)}\n\n`;

    if (result.suspectedWidgets && result.suspectedWidgets.length > 0) {
      output += `## Warnings\n`;
      for (const warning of result.suspectedWidgets) {
        output += `- ${warning}\n`;
      }
      output += `\n`;
    }

    if (result.samples && result.samples.length > 0) {
      output += `## Memory per Iteration\n`;
      output += `| Iteration | Memory |\n`;
      output += `|-----------|--------|\n`;
      for (let i = 0; i < result.samples.length; i++) {
        output += `| ${i + 1} | ${formatBytes(result.samples[i])} |\n`;
      }
    }

    return { content: [{ type: "text", text: output }] };
  }
);

// Helper function to format bytes
function formatBytes(bytes: number): string {
  if (bytes === 0) return "0 B";
  const k = 1024;
  const sizes = ["B", "KB", "MB", "GB"];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + " " + sizes[i];
}

// ============================================================================
// WIDGET TEST GENERATION
// ============================================================================

server.tool(
  "flutter_record_test_start",
  "Start recording user interactions for widget test generation. Records taps, text input, scrolls, and other interactions to generate Flutter widget test code.",
  {
    testName: z.string().describe("Name for the generated test (e.g., 'login_flow', 'add_to_cart')"),
    description: z.string().optional().describe("Optional description for the test"),
  },
  async ({ testName, description }) => {
    const b = await ensureBridge();
    const result = await b.send("recordTestStart", { testName, description });

    if (result.error) {
      return { content: [{ type: "text", text: `Error: ${result.error}` }], isError: true };
    }

    let output = `# Test Recording Started\n\n`;
    output += `**Test Name:** ${testName}\n`;
    output += `**Test ID:** ${result.testId}\n`;
    if (description) {
      output += `**Description:** ${description}\n`;
    }
    output += `\nPerform interactions in the app. Use:\n`;
    output += `- \`flutter_record_add_assertion\` to add assertions\n`;
    output += `- \`flutter_record_add_comment\` to add comments\n`;
    output += `- \`flutter_get_recorded_steps\` to see current steps\n`;
    output += `- \`flutter_record_test_stop\` to stop and generate test code\n`;

    return { content: [{ type: "text", text: output }] };
  }
);

server.tool(
  "flutter_record_test_stop",
  "Stop recording and generate Flutter widget test code. Returns the complete test code with imports and all recorded interactions.",
  {
    format: z.enum(["widget_test", "integration_test", "patrol"]).optional().describe("Test format to generate (default: widget_test)"),
  },
  async ({ format }) => {
    const b = await ensureBridge();
    const result = await b.send("recordTestStop", { format: format || "widget_test" });

    if (result.error) {
      return { content: [{ type: "text", text: `Error: ${result.error}` }], isError: true };
    }

    let output = `# Generated Test Code\n\n`;
    output += `**Format:** ${format || "widget_test"}\n`;
    output += `**Interactions:** ${result.interactions}\n`;
    output += `**Assertions:** ${result.assertions}\n\n`;

    output += `## Imports\n\`\`\`dart\n`;
    for (const imp of result.imports || []) {
      output += `${imp}\n`;
    }
    output += `\`\`\`\n\n`;

    output += `## Test Code\n\`\`\`dart\n${result.testCode}\n\`\`\``;

    return { content: [{ type: "text", text: output }] };
  }
);

server.tool(
  "flutter_record_add_assertion",
  "Add an assertion to the current test recording. Call this during recording to verify widget state.",
  {
    widgetId: z.string().describe("Widget ID from snapshot to assert on"),
    assertion: z.enum([
      "toBeVisible",
      "toBeHidden",
      "toBeEnabled",
      "toBeDisabled",
      "toBeChecked",
      "toBeUnchecked",
      "toHaveText",
      "toContainText",
      "toHaveValue",
      "toBeFocused",
    ]).describe("Assertion type"),
    expected: z.union([z.string(), z.number(), z.boolean()]).optional().describe("Expected value (for toHaveText, toContainText, toHaveValue)"),
  },
  async ({ widgetId, assertion, expected }) => {
    const b = await ensureBridge();
    const result = await b.send("recordAddAssertion", { widgetId, assertion, expected });

    if (result.error) {
      return { content: [{ type: "text", text: `Error: ${result.error}` }], isError: true };
    }

    let output = `Assertion added (#${result.assertionIndex})\n`;
    output += `- Widget: [${widgetId}]\n`;
    output += `- Assert: ${assertion}`;
    if (expected !== undefined) {
      output += ` "${expected}"`;
    }

    return { content: [{ type: "text", text: output }] };
  }
);

server.tool(
  "flutter_record_add_comment",
  "Add a comment to the generated test code. Use this to document test sections or explain complex interactions.",
  {
    comment: z.string().describe("Comment text to add to the test"),
  },
  async ({ comment }) => {
    const b = await ensureBridge();
    const result = await b.send("recordAddComment", { comment });

    if (result.error) {
      return { content: [{ type: "text", text: `Error: ${result.error}` }], isError: true };
    }

    return { content: [{ type: "text", text: `Comment added: "${comment}"` }] };
  }
);

server.tool(
  "flutter_get_recorded_steps",
  "Get current recorded steps without stopping the recording. Use this to review what has been recorded.",
  {},
  async () => {
    const b = await ensureBridge();
    const result = await b.send("getRecordedSteps", {});

    if (result.error) {
      return { content: [{ type: "text", text: `Error: ${result.error}` }], isError: true };
    }

    if (!result.isRecording) {
      return { content: [{ type: "text", text: `No recording in progress. Start one with \`flutter_record_test_start\`.` }] };
    }

    let output = `# Recorded Steps\n\n`;
    output += `**Test Name:** ${result.testName}\n`;
    output += `**Steps:** ${result.steps?.length || 0}\n\n`;

    if (result.steps && result.steps.length > 0) {
      for (let i = 0; i < result.steps.length; i++) {
        const step = result.steps[i];
        const timestamp = new Date(step.timestamp).toISOString().split("T")[1].split(".")[0];
        output += `${i + 1}. [${timestamp}] **${step.type}**: ${step.action}`;
        if (step.details) {
          output += ` - ${JSON.stringify(step.details)}`;
        }
        output += `\n`;
      }
    } else {
      output += `_No steps recorded yet. Interact with the app to record steps._\n`;
    }

    return { content: [{ type: "text", text: output }] };
  }
);

server.tool(
  "flutter_generate_test_from_scenario",
  "Generate Flutter widget test code from a scenario definition. Same format as flutter_run_scenario but generates test code instead of running.",
  {
    scenario: z.object({
      name: z.string().describe("Test name"),
      description: z.string().optional().describe("Test description"),
      steps: z.array(z.object({
        action: z.string().describe("Action to perform (tap, type, scroll, expect, etc.)"),
        params: z.record(z.any()).optional().describe("Action parameters"),
      })),
    }).describe("Scenario definition with steps"),
    format: z.enum(["widget_test", "integration_test", "patrol"]).optional().describe("Test format (default: widget_test)"),
  },
  async ({ scenario, format }) => {
    const b = await ensureBridge();
    const result = await b.send("generateTestFromScenario", {
      scenario,
      format: format || "widget_test",
    });

    if (result.error) {
      return { content: [{ type: "text", text: `Error: ${result.error}` }], isError: true };
    }

    let output = `# Generated Test from Scenario\n\n`;
    output += `**Name:** ${scenario.name}\n`;
    output += `**Steps:** ${scenario.steps.length}\n`;
    output += `**Format:** ${format || "widget_test"}\n\n`;

    output += `## Imports\n\`\`\`dart\n`;
    for (const imp of result.imports || []) {
      output += `${imp}\n`;
    }
    output += `\`\`\`\n\n`;

    output += `## Test Code\n\`\`\`dart\n${result.testCode}\n\`\`\``;

    return { content: [{ type: "text", text: output }] };
  }
);

// ============================================================================
// NAVIGATION STACK INSPECTOR
// ============================================================================

server.tool(
  "flutter_navigation_stack",
  "Get the full navigation stack. Returns all routes currently in the navigator stack with their settings and position.",
  {},
  async () => {
    const b = await ensureBridge();
    const result = await b.send("navigationStack", {});

    if (result.error) {
      return { content: [{ type: "text", text: `Error: ${result.error}` }], isError: true };
    }

    let output = `# Navigation Stack\n\n`;
    output += `**Current Route:** ${result.currentRoute}\n`;
    output += `**Stack Depth:** ${result.depth}\n\n`;

    if (result.stack && result.stack.length > 0) {
      output += `## Routes (bottom to top)\n\n`;
      output += `| # | Route | Name | Arguments | Position |\n`;
      output += `|---|-------|------|-----------|----------|\n`;

      for (let i = 0; i < result.stack.length; i++) {
        const route = result.stack[i];
        const args = route.arguments ? JSON.stringify(route.arguments).slice(0, 30) : "-";
        const position = route.isCurrent ? "current" : route.isFirst ? "first" : "-";
        output += `| ${i} | ${route.route} | ${route.name || "-"} | ${args} | ${position} |\n`;
      }
    } else {
      output += `_Navigation stack is empty._\n`;
    }

    return { content: [{ type: "text", text: output }] };
  }
);

server.tool(
  "flutter_navigation_history",
  "Get navigation history. Returns a log of navigation events (push, pop, replace) with timestamps.",
  {
    limit: z.number().optional().describe("Maximum number of history entries to return (default: 20)"),
  },
  async ({ limit }) => {
    const b = await ensureBridge();
    const result = await b.send("navigationHistory", { limit: limit || 20 });

    if (result.error) {
      return { content: [{ type: "text", text: `Error: ${result.error}` }], isError: true };
    }

    let output = `# Navigation History\n\n`;
    output += `**Total Events:** ${result.history?.length || 0}\n\n`;

    if (result.history && result.history.length > 0) {
      output += `| Action | From | To | Time | Arguments |\n`;
      output += `|--------|------|-----|------|------------|\n`;

      for (const event of result.history) {
        const time = new Date(event.timestamp).toLocaleTimeString();
        const args = event.arguments ? JSON.stringify(event.arguments).slice(0, 20) : "-";
        output += `| ${event.action} | ${event.from || "-"} | ${event.to} | ${time} | ${args} |\n`;
      }
    } else {
      output += `_No navigation history recorded._\n`;
    }

    return { content: [{ type: "text", text: output }] };
  }
);

server.tool(
  "flutter_pop_until",
  "Pop routes until a condition is met. Can pop to a specific route name or using a predicate like 'isFirst'.",
  {
    route: z.string().optional().describe("Route name to pop until (e.g., '/home')"),
    predicate: z.enum(["isFirst", "isSecond"]).optional().describe("Predicate: 'isFirst' pops to root"),
  },
  async ({ route, predicate }) => {
    const b = await ensureBridge();

    if (!route && !predicate) {
      return { content: [{ type: "text", text: `Error: Either 'route' or 'predicate' must be specified` }], isError: true };
    }

    const result = await b.send("popUntil", { route, predicate });

    if (result.error) {
      return { content: [{ type: "text", text: `Error: ${result.error}` }], isError: true };
    }

    return {
      content: [{
        type: "text",
        text: `Popped ${result.poppedCount} route(s)\n**Current Route:** ${result.currentRoute}`
      }]
    };
  }
);

server.tool(
  "flutter_can_pop",
  "Check if the current route can be popped. Returns whether there are routes to pop and the current stack depth.",
  {},
  async () => {
    const b = await ensureBridge();
    const result = await b.send("canPop", {});

    if (result.error) {
      return { content: [{ type: "text", text: `Error: ${result.error}` }], isError: true };
    }

    const canPopText = result.canPop ? "Yes - route can be popped" : "No - this is the root route";
    return {
      content: [{
        type: "text",
        text: `**Can Pop:** ${canPopText}\n**Stack Depth:** ${result.stackDepth}`
      }]
    };
  }
);

server.tool(
  "flutter_navigation_listeners",
  "Get registered navigation observers and listeners. Shows what observers are attached to the navigator.",
  {},
  async () => {
    const b = await ensureBridge();
    const result = await b.send("navigationListeners", {});

    if (result.error) {
      return { content: [{ type: "text", text: `Error: ${result.error}` }], isError: true };
    }

    let output = `# Navigation Observers\n\n`;
    output += `**Total Observers:** ${result.observers?.length || 0}\n\n`;

    if (result.observers && result.observers.length > 0) {
      output += `| Type | Name |\n`;
      output += `|------|------|\n`;

      for (const observer of result.observers) {
        output += `| ${observer.type} | ${observer.name || "-"} |\n`;
      }
    } else {
      output += `_No navigation observers registered._\n`;
    }

    return { content: [{ type: "text", text: output }] };
  }
);

server.tool(
  "flutter_simulate_back_gesture",
  "Simulate iOS swipe-back or Android back button gesture. Triggers the system back navigation.",
  {
    type: z.enum(["swipe", "button"]).optional().describe("Gesture type: 'swipe' for iOS edge swipe, 'button' for Android back button (default: button)"),
  },
  async ({ type }) => {
    const b = await ensureBridge();
    const result = await b.send("simulateBackGesture", { type: type || "button" });

    if (result.error) {
      return { content: [{ type: "text", text: `Error: ${result.error}` }], isError: true };
    }

    const gestureType = type === "swipe" ? "swipe-back gesture" : "back button";
    const action = result.popped ? "Successfully popped" : "Could not pop (at root or pop cancelled)";
    return {
      content: [{
        type: "text",
        text: `**Simulated:** ${gestureType}\n**Result:** ${action}\n**Current Route:** ${result.currentRoute}`
      }]
    };
  }
);

server.tool(
  "flutter_route_settings",
  "Get settings for current or specific route. Returns route name, arguments, and maintainState flag.",
  {
    route: z.string().optional().describe("Route name to get settings for (uses current route if not specified)"),
  },
  async ({ route }) => {
    const b = await ensureBridge();
    const result = await b.send("routeSettings", { route });

    if (result.error) {
      return { content: [{ type: "text", text: `Error: ${result.error}` }], isError: true };
    }

    let output = `# Route Settings\n\n`;
    output += `**Name:** ${result.name || "(unnamed)"}\n`;
    output += `**Maintain State:** ${result.maintainState ? "Yes" : "No"}\n\n`;

    if (result.arguments) {
      output += `## Arguments\n\`\`\`json\n${JSON.stringify(result.arguments, null, 2)}\n\`\`\`\n`;
    } else {
      output += `_No arguments passed to this route._\n`;
    }

    return { content: [{ type: "text", text: output }] };
  }
);

// ============================================================================
// DEEP LINK TESTING
// ============================================================================

server.tool(
  "flutter_simulate_deep_link",
  "Simulate receiving a deep link / universal link. Tests how the app handles incoming URLs from external sources like notifications, shared links, or direct URL opens.",
  {
    url: z.string().describe("The deep link URL to simulate (e.g., 'myapp://products/123' or 'https://myapp.com/products/123')"),
    source: z.enum(["external", "notification", "share"]).optional().describe("Source of the deep link (default: 'external')"),
  },
  async ({ url, source }) => {
    const b = await ensureBridge();
    try {
      const result = await b.send("simulateDeepLink", { url, source: source || "external" });

      if (!result.success) {
        return { content: [{ type: "text", text: `Deep link not handled: ${url}\n\nThe app did not recognize or handle this deep link.` }], isError: true };
      }

      let output = `# Deep Link Simulated\n\n`;
      output += `**URL:** ${url}\n`;
      output += `**Source:** ${source || "external"}\n`;
      output += `**Handled By:** ${result.handledBy || "unknown"}\n`;
      output += `**Navigated To:** ${result.navigatedTo || "N/A"}\n`;

      return { content: [{ type: "text", text: output }] };
    } catch (e: any) {
      return { content: [{ type: "text", text: `Error simulating deep link: ${e.message}` }], isError: true };
    }
  }
);

server.tool(
  "flutter_deep_link_history",
  "Get history of deep links received during the testing session. Shows all deep links that were simulated or received, along with their handling status.",
  {},
  async () => {
    const b = await ensureBridge();
    const result = await b.send("deepLinkHistory", {});

    if (result.error) {
      return { content: [{ type: "text", text: `Error: ${result.error}` }], isError: true };
    }

    let output = `# Deep Link History\n\n`;
    output += `**Total Links:** ${result.links?.length || 0}\n\n`;

    if (result.links && result.links.length > 0) {
      output += `| URL | Source | Handled | Route | Time |\n`;
      output += `|-----|--------|---------|-------|------|\n`;

      for (const link of result.links) {
        const time = new Date(link.timestamp).toLocaleTimeString();
        const handled = link.handled ? "Yes" : "No";
        const route = link.route || "-";
        const source = link.source || "external";
        const urlShort = link.url.length > 40 ? link.url.substring(0, 37) + "..." : link.url;
        output += `| ${urlShort} | ${source} | ${handled} | ${route} | ${time} |\n`;
      }
    } else {
      output += `_No deep links recorded yet._\n`;
    }

    return { content: [{ type: "text", text: output }] };
  }
);

server.tool(
  "flutter_register_deep_link_schemes",
  "Register URL schemes that the app handles. This tells the test bridge which URL schemes and domains the app can process.",
  {
    schemes: z.array(z.string()).describe("URL schemes to register (e.g., ['myapp', 'https://myapp.com', 'https://www.myapp.com'])"),
  },
  async ({ schemes }) => {
    const b = await ensureBridge();
    const result = await b.send("registerDeepLinkSchemes", { schemes });

    if (result.error) {
      return { content: [{ type: "text", text: `Error: ${result.error}` }], isError: true };
    }

    let output = `# Deep Link Schemes Registered\n\n`;
    output += `**Registered Schemes:**\n`;
    for (const scheme of result.registered || []) {
      output += `- ${scheme}\n`;
    }

    if (result.previousSchemes?.length > 0) {
      output += `\n**Previously Registered (kept):**\n`;
      for (const scheme of result.previousSchemes) {
        output += `- ${scheme}\n`;
      }
    }

    return { content: [{ type: "text", text: output }] };
  }
);

server.tool(
  "flutter_test_deep_link_routing",
  "Test that a deep link routes correctly without actually navigating. Validates URL parsing and route matching.",
  {
    url: z.string().describe("The deep link URL to test"),
    expectedRoute: z.string().describe("The expected route path (e.g., '/products/123')"),
    expectedParams: z.record(z.any()).optional().describe("Expected route parameters as key-value pairs"),
  },
  async ({ url, expectedRoute, expectedParams }) => {
    const b = await ensureBridge();
    try {
      const result = await b.send("testDeepLinkRouting", { url, expectedRoute, expectedParams });

      let output = `# Deep Link Routing Test\n\n`;
      output += `**URL:** ${url}\n`;
      output += `**Expected Route:** ${expectedRoute}\n`;
      output += `**Actual Route:** ${result.actualRoute}\n`;
      output += `**Match:** ${result.match ? "PASS" : "FAIL"}\n\n`;

      if (expectedParams) {
        output += `## Expected Parameters\n`;
        output += `\`\`\`json\n${JSON.stringify(expectedParams, null, 2)}\n\`\`\`\n\n`;
      }

      output += `## Actual Parameters\n`;
      output += `\`\`\`json\n${JSON.stringify(result.actualParams, null, 2)}\n\`\`\`\n`;

      if (!result.match) {
        output += `\n## Mismatch Details\n`;
        if (result.actualRoute !== expectedRoute) {
          output += `- Route mismatch: expected "${expectedRoute}", got "${result.actualRoute}"\n`;
        }
        if (result.paramMismatches?.length > 0) {
          for (const mismatch of result.paramMismatches) {
            output += `- Param "${mismatch.key}": expected "${mismatch.expected}", got "${mismatch.actual}"\n`;
          }
        }
      }

      return { content: [{ type: "text", text: output }], isError: !result.match };
    } catch (e: any) {
      return { content: [{ type: "text", text: `Error testing deep link: ${e.message}` }], isError: true };
    }
  }
);

server.tool(
  "flutter_clear_deep_link_history",
  "Clear the deep link history. Useful for starting fresh between test scenarios.",
  {},
  async () => {
    const b = await ensureBridge();
    const result = await b.send("clearDeepLinkHistory", {});

    if (result.error) {
      return { content: [{ type: "text", text: `Error: ${result.error}` }], isError: true };
    }

    return { content: [{ type: "text", text: `Cleared ${result.cleared || 0} deep link history entries.` }] };
  }
);

// ============================================================================
// PUSH NOTIFICATION MOCKING
// ============================================================================

server.tool(
  "flutter_simulate_push_notification",
  "Simulate receiving a push notification. Can simulate receiving, tapping, or dismissing. The app must register callbacks via SelfTestBridge.onNotificationReceived/onNotificationTap/onNotificationDismiss to handle notifications.",
  {
    title: z.string().describe("Notification title"),
    body: z.string().describe("Notification body text"),
    data: z.record(z.any()).optional().describe("Optional notification data payload (JSON object). Include 'deep_link' to trigger navigation on tap."),
    action: z.enum(["tap", "dismiss", "received"]).optional().describe("What action to simulate (default: 'received'). 'received' = notification appears, 'tap' = user taps it, 'dismiss' = user dismisses it"),
    delay: z.number().optional().describe("Delay in milliseconds before triggering the notification (useful for testing timing)"),
  },
  async ({ title, body, data, action, delay }) => {
    const b = await ensureBridge();
    try {
      const result = await b.send("simulatePushNotification", {
        title,
        body,
        data: data || {},
        action: action || "received",
        delay,
      });

      if (!result.success) {
        return { content: [{ type: "text", text: `Error: ${result.error}` }], isError: true };
      }

      let output = `Notification simulated (${action || "received"})\n\n`;
      output += `**Notification ID:** ${result.notificationId}\n`;
      output += `**Title:** ${title}\n`;
      output += `**Body:** ${body}\n`;
      if (data && Object.keys(data).length > 0) {
        output += `**Data:** \`${JSON.stringify(data)}\`\n`;
      }
      if (delay) {
        output += `**Delay:** ${delay}ms\n`;
      }

      return { content: [{ type: "text", text: output }] };
    } catch (e: any) {
      return { content: [{ type: "text", text: `Error: ${e.message}` }], isError: true };
    }
  }
);

server.tool(
  "flutter_simulate_notification_tap",
  "Simulate user tapping on an existing notification. If the notification has a 'deep_link' in its data, the app will navigate to that route.",
  {
    notificationId: z.string().describe("ID of the notification to tap (from flutter_simulate_push_notification or flutter_notification_history)"),
    actionId: z.string().optional().describe("Optional action button ID if tapping a specific notification action"),
  },
  async ({ notificationId, actionId }) => {
    const b = await ensureBridge();
    try {
      const result = await b.send("simulateNotificationTap", { notificationId, actionId });

      if (!result.success) {
        return { content: [{ type: "text", text: `Error: ${result.error}` }], isError: true };
      }

      let output = `Notification tapped: ${notificationId}\n`;
      if (result.navigatedTo) {
        output += `\n**Navigated to:** ${result.navigatedTo}`;
      }

      return { content: [{ type: "text", text: output }] };
    } catch (e: any) {
      return { content: [{ type: "text", text: `Error: ${e.message}` }], isError: true };
    }
  }
);

server.tool(
  "flutter_notification_history",
  "Get the history of all simulated notifications in the current session. Shows notification details and their current action state.",
  {},
  async () => {
    const b = await ensureBridge();
    const result = await b.send("notificationHistory", {});

    let output = `# Notification History\n\n`;
    output += `**Total Notifications:** ${result.count || 0}\n\n`;

    if (result.notifications && result.notifications.length > 0) {
      output += `| ID | Title | Body | Action | Time |\n`;
      output += `|----|-------|------|--------|------|\n`;

      for (const notif of result.notifications) {
        const time = new Date(notif.timestamp).toLocaleTimeString();
        const title = notif.title.length > 20 ? notif.title.slice(0, 20) + "..." : notif.title;
        const body = notif.body.length > 25 ? notif.body.slice(0, 25) + "..." : notif.body;
        output += `| ${notif.id.slice(-8)} | ${title} | ${body} | ${notif.action} | ${time} |\n`;
      }
    } else {
      output += `_No notifications simulated yet._\n`;
    }

    return { content: [{ type: "text", text: output }] };
  }
);

server.tool(
  "flutter_set_notification_handler",
  "Enable or disable notification handler callbacks. When enabled, the app's registered callbacks will be invoked for notification events.",
  {
    onReceive: z.boolean().optional().describe("Enable/disable callback when notification is received"),
    onTap: z.boolean().optional().describe("Enable/disable callback when notification is tapped"),
    onDismiss: z.boolean().optional().describe("Enable/disable callback when notification is dismissed"),
  },
  async ({ onReceive, onTap, onDismiss }) => {
    const b = await ensureBridge();
    const result = await b.send("setNotificationHandler", { onReceive, onTap, onDismiss });

    let output = `# Notification Handlers Updated\n\n`;
    output += `**Handlers Set:** ${result.handlersSet?.join(", ") || "none"}\n\n`;
    output += `**Current State:**\n`;
    output += `- onReceive: ${result.onReceive ? "enabled" : "disabled"}\n`;
    output += `- onTap: ${result.onTap ? "enabled" : "disabled"}\n`;
    output += `- onDismiss: ${result.onDismiss ? "enabled" : "disabled"}\n`;

    return { content: [{ type: "text", text: output }] };
  }
);

server.tool(
  "flutter_clear_notifications",
  "Clear the notification history. Useful for starting fresh between test scenarios.",
  {},
  async () => {
    const b = await ensureBridge();
    const result = await b.send("clearNotifications", {});

    return { content: [{ type: "text", text: `Cleared ${result.cleared || 0} notifications from history.` }] };
  }
);

server.tool(
  "flutter_get_fcm_token",
  "Get a mock FCM token for testing. Returns a consistent mock token for the session that can be used to simulate push notification registration.",
  {},
  async () => {
    const b = await ensureBridge();
    const result = await b.send("getFcmToken", {});

    let output = `# Mock FCM Token\n\n`;
    output += `**Token:** \`${result.token}\`\n\n`;
    output += `_This is a mock token for testing purposes. Use it to simulate FCM registration in your app._`;

    return { content: [{ type: "text", text: output }] };
  }
);

// ============================================================================
// START SERVER
// ============================================================================

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("Flutter self_test MCP server v2.0.0 running (Playwright parity)");

  // In server mode, eagerly start the WebSocket server so Flutter Web can connect
  if (BRIDGE_MODE === "server") {
    console.error(`Starting WebSocket server on port ${FLUTTER_PORT} (server mode)...`);
    await ensureBridge();
  }
}

main().catch(console.error);
