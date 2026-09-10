import { test } from "node:test";
import assert from "node:assert/strict";

import {
  LOCATOR_STRATEGIES,
  serialiseLocator,
  describeLocator,
  supportsExact,
  targetParams,
  describeTarget,
} from "../dist/locator.js";

test("the strategies are exactly the ones the bridge understands", () => {
  assert.deepEqual([...LOCATOR_STRATEGIES], [
    "text",
    "key",
    "id",
    "semanticsLabel",
    "type",
    "tooltip",
  ]);
});

test("a text locator serialises to the documented wire shape", () => {
  assert.deepEqual(serialiseLocator({ by: "text", value: "Sign in" }), {
    by: "text",
    value: "Sign in",
    exact: true,
    index: 0,
  });
});

test("exact defaults to true and can be turned off", () => {
  assert.equal(serialiseLocator({ by: "text", value: "Sign" }).exact, true);
  assert.equal(serialiseLocator({ by: "text", value: "Sign", exact: false }).exact, false);
});

test("exact is omitted for every strategy but text", () => {
  for (const by of LOCATOR_STRATEGIES) {
    const wire = serialiseLocator({ by, value: "x", exact: false });
    if (by === "text") {
      assert.equal(wire.exact, false, "text keeps exact");
      assert.equal(supportsExact(by), true);
    } else {
      assert.equal("exact" in wire, false, `${by} must not send exact`);
      assert.equal(supportsExact(by), false);
    }
  }
});

test("index defaults to 0 and is carried through", () => {
  assert.equal(serialiseLocator({ by: "key", value: "row" }).index, 0);
  assert.equal(serialiseLocator({ by: "key", value: "row", index: 3 }).index, 3);
});

test("the serialised locator has no stray keys", () => {
  assert.deepEqual(Object.keys(serialiseLocator({ by: "key", value: "row" })).sort(), [
    "by",
    "index",
    "value",
  ]);
  assert.deepEqual(
    Object.keys(serialiseLocator({ by: "text", value: "row" })).sort(),
    ["by", "exact", "index", "value"]
  );
});

test("a bad locator is refused before any connection is opened", () => {
  assert.throws(() => serialiseLocator({ by: "label", value: "x" }), /Unknown locator strategy/);
  assert.throws(() => serialiseLocator({ by: "text", value: "" }), /non-empty value/);
  assert.throws(() => serialiseLocator({ by: "text", value: "   " }), /non-empty value/);
  assert.throws(() => serialiseLocator({ by: "text", value: "x", index: -1 }), /non-negative/);
  assert.throws(() => serialiseLocator({ by: "text", value: "x", index: 1.5 }), /non-negative/);
  assert.throws(() => serialiseLocator(null), /must be an object/);
});

test("describeLocator reads back what was asked for", () => {
  assert.equal(describeLocator({ by: "text", value: "Sign in" }), 'text="Sign in"');
  assert.equal(
    describeLocator({ by: "text", value: "Sign", exact: false }),
    'text="Sign" (substring)'
  );
  assert.equal(describeLocator({ by: "key", value: "row", index: 2 }), 'key="row" #2');
});

test("a locator becomes the locator param", () => {
  assert.deepEqual(targetParams({ locator: { by: "text", value: "Sign in" } }), {
    locator: { by: "text", value: "Sign in", exact: true, index: 0 },
  });
});

test("the legacy id path still sends widgetId", () => {
  assert.deepEqual(targetParams({ widgetId: "login-button" }), { widgetId: "login-button" });
  assert.equal(describeTarget({ widgetId: "login-button" }), "[login-button]");
});

test("giving both, or neither, is an error rather than a guess", () => {
  assert.throws(
    () => targetParams({ locator: { by: "text", value: "a" }, widgetId: "b" }),
    /not both/
  );
  assert.throws(() => targetParams({}), /No widget given/);
});
