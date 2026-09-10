import { test } from "node:test";
import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { fileURLToPath } from "node:url";

import { parseCliArgs, usageText, BIN_NAME } from "../dist/cli.js";

const BIN = fileURLToPath(new URL("../dist/index.js", import.meta.url));

/**
 * Run the built binary and resolve with its exit code and output.
 *
 * The point of these tests is that the CLI answers on a machine with no
 * Flutter app running, so the environment is stripped of anything that would
 * let it find one.
 */
function run(args, env = {}) {
  return new Promise((resolve) => {
    execFile(
      process.execPath,
      [BIN, ...args],
      { env: { PATH: process.env.PATH, ...env }, timeout: 20000 },
      (error, stdout, stderr) => {
        resolve({ code: error?.code ?? 0, stdout, stderr });
      }
    );
  });
}

test("--help prints usage and exits 0 without connecting", async () => {
  const { code, stdout } = await run(["--help"]);
  assert.equal(code, 0);
  assert.match(stdout, /Usage:/);
  assert.match(stdout, new RegExp(BIN_NAME));
  assert.match(stdout, /--token/);
});

test("-h is the same as --help", async () => {
  const { code, stdout } = await run(["-h"]);
  assert.equal(code, 0);
  assert.match(stdout, /Usage:/);
});

test("--version prints a version and exits 0", async () => {
  const { code, stdout } = await run(["--version"]);
  assert.equal(code, 0);
  assert.match(stdout.trim(), /^\d+\.\d+\.\d+/);
});

test("an unknown option is reported and exits non-zero", async () => {
  const { code, stderr } = await run(["--wat"]);
  assert.equal(code, 2);
  assert.match(stderr, /Unknown option/);
});

test("the token comes from the flag or the environment, flag first", () => {
  assert.equal(parseCliArgs([], {}).token, undefined);
  assert.equal(parseCliArgs([], { SELF_TEST_TOKEN: "from-env" }).token, "from-env");
  assert.equal(
    parseCliArgs(["--token", "from-flag"], { SELF_TEST_TOKEN: "from-env" }).token,
    "from-flag"
  );
  assert.equal(parseCliArgs(["--token=inline"], {}).token, "inline");
});

test("the defaults put the bridge on loopback", () => {
  const options = parseCliArgs([], {});
  assert.equal(options.host, "127.0.0.1");
  assert.equal(options.port, 9999);
  assert.equal(options.mode, "server");
  assert.deepEqual(options.errors, []);
});

test("a bad port or mode is an error, not a silent fallback", () => {
  assert.match(parseCliArgs(["--port", "nope"], {}).errors[0], /port between 1 and 65535/);
  assert.match(parseCliArgs(["--mode", "sideways"], {}).errors[0], /must be one of/);
  assert.match(parseCliArgs(["--token"], {}).errors[0], /needs a value/);
});

test("--no-headless turns the browser on", () => {
  assert.equal(parseCliArgs([], {}).headless, true);
  assert.equal(parseCliArgs(["--no-headless"], {}).headless, false);
  assert.equal(parseCliArgs([], { PLAYWRIGHT_HEADLESS: "false" }).headless, false);
});

test("the usage text documents the token and its 403", () => {
  const usage = usageText("9.9.9");
  assert.match(usage, /SELF_TEST_TOKEN/);
  assert.match(usage, /403/);
  assert.match(usage, /9\.9\.9/);
});
