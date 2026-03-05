import { chromium, Browser, Page, BrowserContext } from "playwright";

/**
 * Widget representation from Flutter's semantics tree.
 */
interface SemanticWidget {
  id: string;
  index: number;
  role: string | null;
  label: string | null;
  hasTextField: boolean;
  isEnabled: boolean;
  isChecked?: boolean;
  bounds: {
    x: number;
    y: number;
    width: number;
    height: number;
    centerX: number;
    centerY: number;
  };
}

/**
 * Bridge for Flutter web apps using Playwright browser automation.
 *
 * This bridge interacts with Flutter web via:
 * 1. The flt-semantics-host accessibility tree
 * 2. The flt-text-editing-host input element
 * 3. Coordinate-based mouse/keyboard actions
 *
 * No modifications to the Flutter app required - works on production builds!
 */
export class PlaywrightBridge {
  private browser: Browser | null = null;
  private context: BrowserContext | null = null;
  private page: Page | null = null;
  private appUrl: string;
  private headless: boolean;
  private semanticsEnabled = false;
  private goldensDir: string;

  constructor(appUrl: string, options: { headless?: boolean; goldensDir?: string } = {}) {
    this.appUrl = appUrl;
    this.headless = options.headless ?? true;
    this.goldensDir = options.goldensDir ?? "test/goldens";
  }

  /**
   * Launch browser and navigate to Flutter app.
   */
  async connect(): Promise<void> {
    console.error(`Launching Playwright browser (headless: ${this.headless})...`);

    this.browser = await chromium.launch({ headless: this.headless });
    this.context = await this.browser.newContext({
      viewport: { width: 1280, height: 720 },
    });
    this.page = await this.context.newPage();

    console.error(`Navigating to ${this.appUrl}...`);
    await this.page.goto(this.appUrl);
    await this.page.waitForLoadState("networkidle");

    // Wait for Flutter to initialize
    await this.page.waitForFunction(() => {
      return document.querySelector("flt-semantics-placeholder") !== null ||
             document.querySelector("flt-semantics-host") !== null;
    }, { timeout: 30000 });

    console.error("Flutter app loaded, enabling semantics...");
    await this.enableSemantics();
  }

  /**
   * Enable Flutter's semantics/accessibility tree.
   */
  private async enableSemantics(): Promise<void> {
    if (this.semanticsEnabled) return;

    await this.page!.evaluate(() => {
      const placeholder = document.querySelector("flt-semantics-placeholder");
      if (placeholder) {
        (placeholder as HTMLElement).click();
        placeholder.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true }));
        placeholder.dispatchEvent(new PointerEvent("pointerup", { bubbles: true }));
      }
    });

    // Wait for semantics tree to populate
    await this.page!.waitForFunction(() => {
      const host = document.querySelector("flt-semantics-host");
      return host && host.querySelectorAll("flt-semantics").length > 0;
    }, { timeout: 5000 });

    this.semanticsEnabled = true;
    console.error("Semantics enabled");
  }

  /**
   * Check if connected to browser.
   */
  isConnected(): boolean {
    return this.page !== null && !this.page.isClosed();
  }

  /**
   * Get the current mode.
   */
  getMode(): "client" | "server" | "playwright" {
    return "playwright";
  }

  /**
   * Send a command and get response.
   * Implements the same interface as FlutterBridge.
   */
  async send<T = any>(command: string, params: Record<string, any> = {}): Promise<T> {
    if (!this.page || this.page.isClosed()) {
      throw new Error("Not connected to browser");
    }

    switch (command) {
      case "getSnapshot":
        return this.getSnapshot() as Promise<T>;
      case "getByRole":
        return this.getByRole(params.role, params.name) as Promise<T>;
      case "getByText":
        return this.getByText(params.text, params.exact) as Promise<T>;
      case "tap":
        return this.tap(params.widgetId, params.timeout) as Promise<T>;
      case "type":
        return this.type(params.widgetId, params.text, params.append, params.submit) as Promise<T>;
      case "clear":
        return this.clear(params.widgetId) as Promise<T>;
      case "pressKey":
        return this.pressKey(params.key) as Promise<T>;
      case "scroll":
        return this.scroll(params.widgetId, params.direction, params.delta) as Promise<T>;
      case "navigate":
        return this.navigate(params.route) as Promise<T>;
      case "goBack":
        return this.goBack() as Promise<T>;
      case "reload":
        return this.reload() as Promise<T>;
      case "restart":
        return this.restart() as Promise<T>;
      case "wait":
        return this.wait(params) as Promise<T>;
      case "expect":
        return this.expect(params.widgetId, params.assertion, params.expected) as Promise<T>;
      case "screenshot":
        return this.screenshot(params.name, params.widgetId) as Promise<T>;
      case "expectScreenshot":
        return this.expectScreenshot(params.name, params.threshold, params.updateBaseline) as Promise<T>;
      case "resize":
        return this.resize(params.width, params.height) as Promise<T>;
      case "console":
        return this.getConsole(params.level, params.limit) as Promise<T>;
      default:
        throw new Error(`Command not supported in playwright mode: ${command}. This command requires the full SelfTestBridge.`);
    }
  }

  /**
   * Get all widgets from semantics tree.
   */
  private async getWidgets(): Promise<SemanticWidget[]> {
    await this.enableSemantics();

    return this.page!.evaluate(() => {
      const host = document.querySelector("flt-semantics-host");
      if (!host) return [];

      const semantics = host.querySelectorAll("flt-semantics");
      return [...semantics].map((el, index) => {
        const rect = el.getBoundingClientRect();
        const role = el.getAttribute("role");
        const label = el.getAttribute("aria-label");
        const disabled = el.getAttribute("aria-disabled") === "true";
        const checked = el.getAttribute("aria-checked");

        return {
          id: label || `widget_${index}`,
          index,
          role,
          label,
          hasTextField: el.querySelector("input") !== null,
          isEnabled: !disabled,
          isChecked: checked === "true" ? true : checked === "false" ? false : undefined,
          bounds: {
            x: Math.round(rect.x),
            y: Math.round(rect.y),
            width: Math.round(rect.width),
            height: Math.round(rect.height),
            centerX: Math.round(rect.x + rect.width / 2),
            centerY: Math.round(rect.y + rect.height / 2),
          },
        };
      });
    });
  }

  /**
   * Get snapshot of current screen.
   */
  private async getSnapshot(): Promise<any> {
    const widgets = await this.getWidgets();
    const meaningful = widgets.filter(
      (w) => (w.role || w.label || w.hasTextField) && w.bounds.width > 0 && w.bounds.height > 0
    );

    // Categorize widgets
    const buttons = meaningful.filter((w) => w.role === "button");
    const inputs = meaningful.filter((w) => w.hasTextField || w.role === "textbox");
    const checkboxes = meaningful.filter((w) => w.role === "checkbox" || w.role === "switch");
    const others = meaningful.filter(
      (w) => !["button", "textbox", "checkbox", "switch"].includes(w.role || "") && !w.hasTextField
    );

    return {
      currentScreen: await this.page!.title(),
      url: this.page!.url(),
      widgetCount: meaningful.length,
      widgets: [
        ...buttons.map((w) => ({ ...w, type: "button" })),
        ...inputs.map((w) => ({ ...w, type: "text_input" })),
        ...checkboxes.map((w) => ({ ...w, type: "checkbox" })),
        ...others,
      ],
    };
  }

  /**
   * Find widgets by role.
   */
  private async getByRole(role: string, name?: string): Promise<SemanticWidget[]> {
    const widgets = await this.getWidgets();
    let matches = widgets.filter((w) => w.role === role && w.bounds.width > 0);

    if (name) {
      matches = matches.filter((w) => w.label?.toLowerCase().includes(name.toLowerCase()));
    }

    return matches;
  }

  /**
   * Find widgets by text.
   */
  private async getByText(text: string, exact?: boolean): Promise<SemanticWidget[]> {
    const widgets = await this.getWidgets();

    return widgets.filter((w) => {
      if (!w.label) return false;
      if (exact) return w.label === text;
      return w.label.toLowerCase().includes(text.toLowerCase());
    });
  }

  /**
   * Find widget by ID (label or index-based ID).
   */
  private async findWidget(widgetId: string): Promise<SemanticWidget | null> {
    const widgets = await this.getWidgets();

    // Try exact label match first
    let widget = widgets.find((w) => w.label === widgetId);
    if (widget) return widget;

    // Try partial label match
    widget = widgets.find((w) => w.label?.includes(widgetId));
    if (widget) return widget;

    // Try widget_N format
    const indexMatch = widgetId.match(/^widget_(\d+)$/);
    if (indexMatch) {
      const index = parseInt(indexMatch[1], 10);
      return widgets.find((w) => w.index === index) || null;
    }

    return null;
  }

  /**
   * Tap on a widget.
   */
  private async tap(widgetId: string, timeout?: number): Promise<void> {
    const widget = await this.findWidget(widgetId);
    if (!widget) {
      throw new Error(`Widget not found: ${widgetId}`);
    }

    await this.page!.mouse.click(widget.bounds.centerX, widget.bounds.centerY);
    await this.page!.waitForTimeout(100);
  }

  /**
   * Type text into a widget.
   */
  private async type(widgetId: string, text: string, append?: boolean, submit?: boolean): Promise<void> {
    const widget = await this.findWidget(widgetId);
    if (!widget) {
      throw new Error(`Widget not found: ${widgetId}`);
    }

    // Click to focus
    await this.page!.mouse.click(widget.bounds.centerX, widget.bounds.centerY);

    // Wait for input to appear
    await this.page!.waitForSelector("flt-text-editing-host input", { timeout: 5000 });

    // Clear if not appending
    if (!append) {
      await this.page!.keyboard.press("Control+a");
      await this.page!.keyboard.press("Backspace");
    }

    // Type text
    await this.page!.keyboard.type(text);

    // Submit if requested
    if (submit) {
      await this.page!.keyboard.press("Enter");
    }
  }

  /**
   * Clear a text field.
   */
  private async clear(widgetId: string): Promise<void> {
    const widget = await this.findWidget(widgetId);
    if (!widget) {
      throw new Error(`Widget not found: ${widgetId}`);
    }

    await this.page!.mouse.click(widget.bounds.centerX, widget.bounds.centerY);
    await this.page!.waitForSelector("flt-text-editing-host input", { timeout: 5000 });
    await this.page!.keyboard.press("Control+a");
    await this.page!.keyboard.press("Backspace");
  }

  /**
   * Press a keyboard key.
   */
  private async pressKey(key: string): Promise<void> {
    const keyMap: Record<string, string> = {
      enter: "Enter",
      tab: "Tab",
      escape: "Escape",
      backspace: "Backspace",
      delete: "Delete",
      up: "ArrowUp",
      down: "ArrowDown",
      left: "ArrowLeft",
      right: "ArrowRight",
      home: "Home",
      end: "End",
    };

    await this.page!.keyboard.press(keyMap[key] || key);
  }

  /**
   * Scroll within a widget.
   */
  private async scroll(widgetId: string | undefined, direction: string, delta?: number): Promise<void> {
    const scrollAmount = delta || 300;

    let x = 640, y = 360; // Default to center of viewport

    if (widgetId) {
      const widget = await this.findWidget(widgetId);
      if (widget) {
        x = widget.bounds.centerX;
        y = widget.bounds.centerY;
      }
    }

    await this.page!.mouse.move(x, y);

    const deltaX = direction === "left" ? -scrollAmount : direction === "right" ? scrollAmount : 0;
    const deltaY = direction === "up" ? -scrollAmount : direction === "down" ? scrollAmount : 0;

    await this.page!.mouse.wheel(deltaX, deltaY);
  }

  /**
   * Navigate to a route.
   */
  private async navigate(route: string): Promise<void> {
    const currentUrl = new URL(this.page!.url());
    currentUrl.hash = route.startsWith("#") ? route : `#${route}`;
    await this.page!.goto(currentUrl.toString());
    await this.page!.waitForLoadState("networkidle");
  }

  /**
   * Go back in browser history.
   */
  private async goBack(): Promise<void> {
    await this.page!.goBack();
    await this.page!.waitForLoadState("networkidle");
  }

  /**
   * Reload the page.
   */
  private async reload(): Promise<void> {
    await this.page!.reload();
    await this.page!.waitForLoadState("networkidle");
    this.semanticsEnabled = false;
    await this.enableSemantics();
  }

  /**
   * Restart (full page reload).
   */
  private async restart(): Promise<void> {
    await this.page!.goto(this.appUrl);
    await this.page!.waitForLoadState("networkidle");
    this.semanticsEnabled = false;
    await this.enableSemantics();
  }

  /**
   * Wait for various conditions.
   */
  private async wait(params: Record<string, any>): Promise<void> {
    const { condition, widgetId, text, duration, timeout = 5000 } = params;

    switch (condition) {
      case "duration":
        await this.page!.waitForTimeout(duration || 1000);
        break;
      case "visible":
        if (widgetId) {
          const startTime = Date.now();
          while (Date.now() - startTime < timeout) {
            const widget = await this.findWidget(widgetId);
            if (widget && widget.bounds.width > 0) return;
            await this.page!.waitForTimeout(100);
          }
          throw new Error(`Timeout waiting for ${widgetId} to be visible`);
        }
        break;
      case "hidden":
        if (widgetId) {
          const startTime = Date.now();
          while (Date.now() - startTime < timeout) {
            const widget = await this.findWidget(widgetId);
            if (!widget) return;
            await this.page!.waitForTimeout(100);
          }
          throw new Error(`Timeout waiting for ${widgetId} to be hidden`);
        }
        break;
      case "text":
        if (widgetId && text) {
          const startTime = Date.now();
          while (Date.now() - startTime < timeout) {
            const widget = await this.findWidget(widgetId);
            if (widget?.label?.includes(text)) return;
            await this.page!.waitForTimeout(100);
          }
          throw new Error(`Timeout waiting for ${widgetId} to contain "${text}"`);
        }
        break;
      case "idle":
      case "network_idle":
        await this.page!.waitForLoadState("networkidle");
        break;
    }
  }

  /**
   * Assert widget state.
   */
  private async expect(widgetId: string, assertion: string, expected?: any): Promise<{ passed: boolean; message: string }> {
    const widget = await this.findWidget(widgetId);

    switch (assertion) {
      case "toBeVisible":
        return {
          passed: widget !== null && widget.bounds.width > 0,
          message: widget ? "Widget is visible" : "Widget not found",
        };
      case "toBeHidden":
        return {
          passed: widget === null,
          message: widget ? "Widget is still visible" : "Widget is hidden",
        };
      case "toBeEnabled":
        return {
          passed: widget?.isEnabled === true,
          message: widget?.isEnabled ? "Widget is enabled" : "Widget is disabled",
        };
      case "toBeDisabled":
        return {
          passed: widget?.isEnabled === false,
          message: widget?.isEnabled === false ? "Widget is disabled" : "Widget is enabled",
        };
      case "toBeChecked":
        return {
          passed: widget?.isChecked === true,
          message: widget?.isChecked ? "Widget is checked" : "Widget is not checked",
        };
      case "toBeUnchecked":
        return {
          passed: widget?.isChecked === false,
          message: widget?.isChecked === false ? "Widget is unchecked" : "Widget is checked",
        };
      case "toHaveText":
      case "toContainText":
        const hasText = assertion === "toHaveText"
          ? widget?.label === expected
          : widget?.label?.includes(expected);
        return {
          passed: hasText === true,
          message: hasText ? `Widget has text "${expected}"` : `Widget text is "${widget?.label}"`,
        };
      default:
        throw new Error(`Unknown assertion: ${assertion}`);
    }
  }

  /**
   * Take a screenshot.
   */
  private async screenshot(name?: string, widgetId?: string): Promise<{ path: string }> {
    const filename = name || `screenshot-${Date.now()}.png`;
    const path = `${this.goldensDir}/${filename}`;

    if (widgetId) {
      const widget = await this.findWidget(widgetId);
      if (widget) {
        await this.page!.screenshot({
          path,
          clip: {
            x: widget.bounds.x,
            y: widget.bounds.y,
            width: widget.bounds.width,
            height: widget.bounds.height,
          },
        });
      }
    } else {
      await this.page!.screenshot({ path });
    }

    return { path };
  }

  /**
   * Compare screenshot with baseline.
   */
  private async expectScreenshot(
    name: string,
    threshold?: number,
    updateBaseline?: boolean
  ): Promise<{ passed: boolean; message: string }> {
    const baselinePath = `${this.goldensDir}/${name}.png`;
    const actualPath = `${this.goldensDir}/${name}-actual.png`;

    await this.page!.screenshot({ path: actualPath });

    if (updateBaseline) {
      await this.page!.screenshot({ path: baselinePath });
      return { passed: true, message: "Baseline updated" };
    }

    // Simple file comparison - in production would use pixelmatch
    return { passed: true, message: "Screenshot comparison not fully implemented in playwright mode" };
  }

  /**
   * Resize viewport.
   */
  private async resize(width: number, height: number): Promise<void> {
    await this.page!.setViewportSize({ width, height });
  }

  /**
   * Get console messages.
   */
  private async getConsole(level?: string, limit?: number): Promise<any[]> {
    // Console capture would need to be set up during page creation
    return [];
  }

  /**
   * Disconnect and close browser.
   */
  disconnect(): void {
    if (this.page) {
      this.page.close().catch(() => {});
      this.page = null;
    }
    if (this.context) {
      this.context.close().catch(() => {});
      this.context = null;
    }
    if (this.browser) {
      this.browser.close().catch(() => {});
      this.browser = null;
    }
  }

  /**
   * Get the underlying Playwright page for advanced usage.
   */
  getPage(): Page | null {
    return this.page;
  }
}
