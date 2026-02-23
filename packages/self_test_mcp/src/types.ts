/**
 * Types for the self_test MCP server.
 */

// ===========================================================================
// WIDGET TYPES
// ===========================================================================

export interface WidgetInfo {
  id: string;
  type: "button" | "text_input" | "interactive" | "unknown";
  screen: string;
  isStable: boolean;
  capabilities: {
    canTap: boolean;
    canEnterText: boolean;
  };
  currentText?: string;
  needsSemanticLabel?: boolean;
}

export interface WidgetSnapshot {
  currentScreen: string;
  widgets: WidgetInfo[];
  timestamp: string;
}

export interface WidgetCatalog {
  screens: Record<string, string[]>;
  widgets: Record<string, WidgetInfo>;
  stats: {
    totalWidgets: number;
    tappableWidgets: number;
    textInputWidgets: number;
    stableWidgets: number;
    unstableWidgets: number;
    screens: number;
  };
}

// ===========================================================================
// NAVIGATION TYPES
// ===========================================================================

export interface RouteInfo {
  path: string;
  name?: string;
  childRoutes: string[];
  parameters: string[];
  requiresAuth: boolean;
}

export interface FlowSequence {
  name: string;
  description: string;
  steps: string[];
  category: string;
}

export interface FlowGraph {
  routes: RouteInfo[];
  sequences: FlowSequence[];
  stats: {
    totalRoutes: number;
    authRequired: number;
    publicRoutes: number;
    parametrizedRoutes: number;
    flowSequences: number;
  };
  categories: Record<string, number>;
}

export interface ScreenInfo {
  name: string;
  path: string;
  requiresAuth: boolean;
  widgetCount: number;
}

// ===========================================================================
// STATE TYPES
// ===========================================================================

export interface AppState {
  currentScreen: string;
  widgetCount: number;
  testModeActive: boolean;
  autoDetectionEnabled: boolean;
}

// ===========================================================================
// TEST TYPES
// ===========================================================================

export interface TestStep {
  action: "tap" | "type" | "navigate" | "wait" | "screenshot" | "assert";
  widgetId?: string;
  text?: string;
  route?: string;
  duration?: number;
  assertion?: string;
}

export interface TestStepResult {
  description: string;
  passed: boolean;
  error?: string;
  screenshotPath?: string;
}

export interface TestScenarioResult {
  name: string;
  allPassed: boolean;
  passedCount: number;
  failedCount: number;
  steps: TestStepResult[];
  timestamp: string;
}

export interface AssertionResult {
  passed: boolean;
  message: string;
}

// ===========================================================================
// SCREENSHOT TYPES
// ===========================================================================

export interface ScreenshotResult {
  filename: string;
  filepath?: string;
  base64?: string;
}

// ===========================================================================
// BRIDGE PROTOCOL TYPES
// ===========================================================================

export interface BridgeCommand {
  id: number;
  command: string;
  params: Record<string, any>;
}

export interface BridgeResponse {
  id: number;
  result?: any;
  error?: string;
}
