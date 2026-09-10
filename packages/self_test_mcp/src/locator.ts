/**
 * Universal locators.
 *
 * A widget is addressed by what is on screen, not by an id the app had to
 * register in advance. The wire shape is exactly what the bridge expects:
 *
 *   { "by": "text", "value": "Sign in", "exact": true, "index": 0 }
 *
 * `exact` (default true) applies to `by: "text"` only, so it is omitted for
 * every other strategy rather than sent and ignored. `index` (default 0)
 * picks between duplicates.
 */

import { z } from "zod";

export const LOCATOR_STRATEGIES = [
  "text",
  "key",
  "id",
  "semanticsLabel",
  "type",
  "tooltip",
] as const;

export type LocatorStrategy = (typeof LOCATOR_STRATEGIES)[number];

/** A locator as an agent supplies it: everything but `by` and `value` optional. */
export interface LocatorInput {
  by: LocatorStrategy;
  value: string;
  exact?: boolean;
  index?: number;
}

/** A locator as it goes on the wire: defaults resolved, `exact` narrowed. */
export interface WireLocator {
  by: LocatorStrategy;
  value: string;
  index: number;
  exact?: boolean;
}

/** Whether `exact` means anything for a given strategy. */
export function supportsExact(by: LocatorStrategy): boolean {
  return by === "text";
}

export const locatorShape = {
  by: z
    .enum(LOCATOR_STRATEGIES)
    .describe(
      "How to address the widget. 'text' matches visible text, 'key' a " +
        "ValueKey, 'id' a self_test id the app registered, 'semanticsLabel' " +
        "an accessibility label, 'type' a widget class name such as " +
        "ElevatedButton, and 'tooltip' a tooltip message."
    ),
  value: z.string().describe("The value to match, for example 'Sign in'."),
  exact: z
    .boolean()
    .optional()
    .describe(
      "Match the whole string rather than a substring. Applies to " +
        "by:'text' only and defaults to true; ignored for every other strategy."
    ),
  index: z
    .number()
    .int()
    .min(0)
    .optional()
    .describe("Which match to use when several widgets match. Defaults to 0."),
};

export const locatorSchema = z.object(locatorShape);

/**
 * Resolve a locator's defaults and drop the fields the bridge would ignore.
 *
 * Throws rather than guessing: a locator that cannot match anything is a
 * mistake worth reporting before a connection is even opened.
 */
export function serialiseLocator(input: LocatorInput): WireLocator {
  if (input === null || typeof input !== "object") {
    throw new Error(
      "A locator must be an object, for example {by: 'text', value: 'Sign in'}."
    );
  }

  const by = input.by;
  if (!LOCATOR_STRATEGIES.includes(by)) {
    throw new Error(
      `Unknown locator strategy ${JSON.stringify(by)}. ` +
        `Use one of: ${LOCATOR_STRATEGIES.join(", ")}.`
    );
  }

  if (typeof input.value !== "string" || input.value.trim() === "") {
    throw new Error(`Locator by:'${by}' needs a non-empty value.`);
  }

  const index = input.index ?? 0;
  if (!Number.isInteger(index) || index < 0) {
    throw new Error(
      `Locator index must be a non-negative integer, got ${JSON.stringify(input.index)}.`
    );
  }

  const wire: WireLocator = { by, value: input.value, index };
  if (supportsExact(by)) {
    wire.exact = input.exact ?? true;
  }
  return wire;
}

/** A short human-readable form for tool results and error messages. */
export function describeLocator(input: LocatorInput): string {
  const wire = serialiseLocator(input);
  const parts = [`${wire.by}=${JSON.stringify(wire.value)}`];
  if (wire.exact === false) parts.push("(substring)");
  if (wire.index !== 0) parts.push(`#${wire.index}`);
  return parts.join(" ");
}

/** What an agent passed to address a widget: a locator, or a legacy id. */
export interface WidgetTarget {
  locator?: LocatorInput;
  widgetId?: string;
}

/**
 * Turn a target into bridge params.
 *
 * The id-based path stays supported because apps that predate locators still
 * register ids, but exactly one of the two must be given: silently preferring
 * one over the other hides a caller's mistake.
 */
export function targetParams(target: WidgetTarget): Record<string, unknown> {
  const hasLocator = target.locator !== undefined && target.locator !== null;
  const hasId = typeof target.widgetId === "string" && target.widgetId !== "";

  if (hasLocator && hasId) {
    throw new Error(
      "Pass either a locator or a widgetId, not both. Prefer the locator; " +
        "widgetId exists for apps that still register ids."
    );
  }
  if (hasLocator) {
    return { locator: serialiseLocator(target.locator as LocatorInput) };
  }
  if (hasId) {
    return { widgetId: target.widgetId };
  }
  throw new Error(
    "No widget given. Pass a locator such as {by: 'text', value: 'Sign in'} " +
      "(call flutter_describe_screen first to see what is on screen), or a " +
      "widgetId if the app still registers ids."
  );
}

/** Human-readable form of whichever addressing the caller used. */
export function describeTarget(target: WidgetTarget): string {
  if (target.locator) return describeLocator(target.locator);
  if (target.widgetId) return `[${target.widgetId}]`;
  return "(no widget)";
}
