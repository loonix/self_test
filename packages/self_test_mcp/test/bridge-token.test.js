import { test } from "node:test";
import assert from "node:assert/strict";
import { WebSocketServer } from "ws";

import {
  FlutterBridge,
  describeConnectionError,
  statusFromErrorMessage,
  tokenFromRequest,
  bridgeUrl,
  redactToken,
  BridgeAuthError,
  TOKEN_HEADER,
} from "../dist/flutter-bridge.js";

// ---------------------------------------------------------------------------
// The mapping on its own
// ---------------------------------------------------------------------------

test("a 403 is reported as a wrong or missing token, not a socket error", () => {
  const message = describeConnectionError(
    { statusCode: 403 },
    { url: "ws://127.0.0.1:9999", hasToken: false }
  );
  assert.match(message, /wrong or missing token/);
  assert.match(message, /403/);
  assert.match(message, /SELF_TEST_TOKEN/);
  assert.match(message, /--token/);
});

test("the 403 message says whether a token was even supplied", () => {
  const withToken = describeConnectionError(
    { statusCode: 403 },
    { url: "ws://127.0.0.1:9999", hasToken: true }
  );
  const without = describeConnectionError(
    { statusCode: 403 },
    { url: "ws://127.0.0.1:9999", hasToken: false }
  );
  assert.match(withToken, /does not match/);
  assert.match(without, /No token was supplied/);
});

test("ws's own wording for a rejected handshake is recognised as a 403", () => {
  assert.equal(statusFromErrorMessage("Unexpected server response: 403"), 403);
  assert.equal(statusFromErrorMessage("Unexpected server response: 401"), 401);
  assert.equal(statusFromErrorMessage("connect ECONNREFUSED 127.0.0.1:9999"), undefined);
  assert.equal(statusFromErrorMessage(undefined), undefined);

  const message = describeConnectionError(
    { message: "Unexpected server response: 403" },
    { url: "ws://127.0.0.1:9999", hasToken: true }
  );
  assert.match(message, /wrong or missing token/);
});

test("other failures keep their own wording", () => {
  const refused = describeConnectionError(
    { message: "connect ECONNREFUSED 127.0.0.1:9999" },
    { url: "ws://127.0.0.1:9999", hasToken: true }
  );
  assert.match(refused, /ECONNREFUSED/);
  assert.doesNotMatch(refused, /wrong or missing token/);

  const notFound = describeConnectionError(
    { statusCode: 404 },
    { url: "ws://127.0.0.1:9999", hasToken: true }
  );
  assert.match(notFound, /HTTP 404/);
  assert.doesNotMatch(notFound, /wrong or missing token/);
});

// ---------------------------------------------------------------------------
// Carrying the token
// ---------------------------------------------------------------------------

test("the URL carries the token the way the app prints it", () => {
  assert.equal(bridgeUrl("127.0.0.1", 9999), "ws://127.0.0.1:9999");
  assert.equal(bridgeUrl("127.0.0.1", 9999, "abc123"), "ws://127.0.0.1:9999?token=abc123");
  assert.equal(bridgeUrl("127.0.0.1", 9999, "a b/c"), "ws://127.0.0.1:9999?token=a%20b%2Fc");
});

test("the token is kept out of the logs", () => {
  assert.equal(
    redactToken("ws://127.0.0.1:9999?token=s3cret"),
    "ws://127.0.0.1:9999?token=<redacted>"
  );
});

test("an incoming token is read from the header or the query", () => {
  assert.equal(tokenFromRequest({ headers: { [TOKEN_HEADER]: "from-header" } }), "from-header");
  assert.equal(tokenFromRequest({ url: "/?token=from-query", headers: {} }), "from-query");
  assert.equal(
    tokenFromRequest({ url: "/?token=from-query", headers: { [TOKEN_HEADER]: "from-header" } }),
    "from-header"
  );
  assert.equal(tokenFromRequest({ url: "/", headers: {} }), undefined);
});

// ---------------------------------------------------------------------------
// Against a real socket that rejects the handshake
// ---------------------------------------------------------------------------

/** A loopback bridge stand-in that demands `token`, exactly as the app does. */
async function startTokenServer(token) {
  const seen = [];
  const wss = new WebSocketServer({
    host: "127.0.0.1",
    port: 0,
    verifyClient: (info, done) => {
      seen.push({
        url: info.req.url,
        header: info.req.headers[TOKEN_HEADER],
      });
      const presented = tokenFromRequest(info.req);
      if (presented === token) done(true);
      else done(false, 403, "wrong or missing token");
    },
  });
  await new Promise((resolve) => wss.once("listening", resolve));
  return { wss, port: wss.address().port, seen };
}

test("connecting with the wrong token gives the token message, not a socket error", async () => {
  const { wss, port } = await startTokenServer("right-token");
  try {
    const bridge = new FlutterBridge("127.0.0.1", port, "client", { token: "wrong-token" });
    await assert.rejects(
      () => bridge.connect(),
      (error) => {
        assert.ok(error instanceof BridgeAuthError, "expected a BridgeAuthError");
        assert.equal(error.statusCode, 403);
        assert.match(error.message, /wrong or missing token/);
        assert.doesNotMatch(error.message, /Unexpected server response/);
        return true;
      }
    );
    bridge.disconnect();
  } finally {
    wss.close();
  }
});

test("connecting with no token at all gives the same guidance", async () => {
  const { wss, port } = await startTokenServer("right-token");
  try {
    const bridge = new FlutterBridge("127.0.0.1", port, "client");
    await assert.rejects(
      () => bridge.connect(),
      (error) => {
        assert.match(error.message, /wrong or missing token/);
        assert.match(error.message, /No token was supplied/);
        return true;
      }
    );
    bridge.disconnect();
  } finally {
    wss.close();
  }
});

test("the right token connects, and arrives in both the query and the header", async () => {
  const { wss, port, seen } = await startTokenServer("right-token");
  try {
    const bridge = new FlutterBridge("127.0.0.1", port, "client", { token: "right-token" });
    await bridge.connect();
    assert.equal(bridge.isConnected(), true);
    assert.equal(seen.length, 1);
    assert.equal(seen[0].url, "/?token=right-token");
    assert.equal(seen[0].header, "right-token");
    bridge.disconnect();
  } finally {
    wss.close();
  }
});
