/**
 * Command line parsing.
 *
 * Deliberately dependency-free and side-effect-free: `--help` and `--version`
 * have to work on a machine with no Flutter app running, no bridge, and no
 * browser downloaded. A CLI that cannot be introspected without a live app is
 * not installable software, so nothing here opens a socket or a browser.
 */

export type BridgeMode = "client" | "server" | "web-external";

export interface CliOptions {
  help: boolean;
  version: boolean;
  token?: string;
  host: string;
  port: number;
  mode: BridgeMode;
  appUrl: string;
  goldensDir: string;
  headless: boolean;
  /** Anything wrong with the invocation. Non-empty means: print and exit 2. */
  errors: string[];
}

const BRIDGE_MODES: BridgeMode[] = ["client", "server", "web-external"];

export const BIN_NAME = "self-test-mcp";

export function usageText(version: string): string {
  return `${BIN_NAME} ${version}

MCP server that lets an AI agent drive a Flutter app built with self_test.
Speaks the Model Context Protocol over stdio, so it is normally launched by
an MCP client rather than by hand.

Usage:
  ${BIN_NAME} [options]
  ${BIN_NAME} --help
  ${BIN_NAME} --version

Options:
  -h, --help              Print this help and exit.
  -v, --version           Print the version and exit.
      --token <token>     Token the bridge requires. The Flutter app prints
                          its bridge URL at startup, for example
                          ws://127.0.0.1:9999?token=abc123 - the token is the
                          query parameter. Overrides SELF_TEST_TOKEN.
      --host <host>       Bridge host (default: 127.0.0.1).
      --port <port>       Bridge port (default: 9999).
      --mode <mode>       client | server | web-external (default: server).
                            client        connect to the app's bridge socket
                            server        listen and let the app connect in
                            web-external  drive Flutter Web with Playwright
      --url <url>         Flutter Web app URL for web-external mode
                          (default: http://localhost:8080).
      --goldens-dir <dir> Where golden images live (default: test/goldens).
      --headless          Run the web-external browser headless (default).
      --no-headless       Show the web-external browser.

Environment:
  SELF_TEST_TOKEN         Bridge token, if --token is not given.
  FLUTTER_APP_HOST        Same as --host.
  FLUTTER_APP_PORT        Same as --port.
  BRIDGE_MODE             Same as --mode.
  FLUTTER_APP_URL         Same as --url.
  FLUTTER_GOLDENS_DIR     Same as --goldens-dir.
  PLAYWRIGHT_HEADLESS     Set to "false" for --no-headless.

The bridge binds to loopback and requires a token. Connecting without one, or
with the wrong one, is refused with HTTP 403 and reported as a wrong or
missing token rather than as a socket error.
`;
}

interface Env {
  [key: string]: string | undefined;
}

/**
 * Parse argv (without node and the script path).
 *
 * A flag always beats the matching environment variable, because the flag is
 * the thing the person typed just now.
 */
export function parseCliArgs(argv: string[], env: Env = process.env): CliOptions {
  const errors: string[] = [];

  const options: CliOptions = {
    help: false,
    version: false,
    token: env.SELF_TEST_TOKEN || undefined,
    host: env.FLUTTER_APP_HOST || "127.0.0.1",
    port: parsePort(env.FLUTTER_APP_PORT, 9999, errors, "FLUTTER_APP_PORT"),
    mode: parseMode(env.BRIDGE_MODE, "server", errors, "BRIDGE_MODE"),
    appUrl: env.FLUTTER_APP_URL || "http://localhost:8080",
    goldensDir: env.FLUTTER_GOLDENS_DIR || "test/goldens",
    headless: env.PLAYWRIGHT_HEADLESS !== "false",
    errors,
  };

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];

    // Support both `--token x` and `--token=x`.
    const eq = arg.indexOf("=");
    const hasInlineValue = arg.startsWith("--") && eq > 2;
    const name = hasInlineValue ? arg.slice(0, eq) : arg;
    const inlineValue = hasInlineValue ? arg.slice(eq + 1) : undefined;

    const takeValue = (): string | undefined => {
      if (inlineValue !== undefined) return inlineValue;
      const next = argv[i + 1];
      if (next === undefined || next.startsWith("-")) {
        errors.push(`${name} needs a value.`);
        return undefined;
      }
      i++;
      return next;
    };

    switch (name) {
      case "-h":
      case "--help":
        options.help = true;
        break;
      case "-v":
      case "--version":
        options.version = true;
        break;
      case "--token": {
        const value = takeValue();
        if (value !== undefined) options.token = value;
        break;
      }
      case "--host": {
        const value = takeValue();
        if (value !== undefined) options.host = value;
        break;
      }
      case "--port": {
        const value = takeValue();
        if (value !== undefined) options.port = parsePort(value, options.port, errors, "--port");
        break;
      }
      case "--mode": {
        const value = takeValue();
        if (value !== undefined) options.mode = parseMode(value, options.mode, errors, "--mode");
        break;
      }
      case "--url": {
        const value = takeValue();
        if (value !== undefined) options.appUrl = value;
        break;
      }
      case "--goldens-dir": {
        const value = takeValue();
        if (value !== undefined) options.goldensDir = value;
        break;
      }
      case "--headless":
        options.headless = true;
        break;
      case "--no-headless":
        options.headless = false;
        break;
      default:
        errors.push(`Unknown option ${JSON.stringify(arg)}.`);
        break;
    }
  }

  return options;
}

function parsePort(
  raw: string | undefined,
  fallback: number,
  errors: string[],
  source: string
): number {
  if (raw === undefined || raw === "") return fallback;
  const port = Number(raw);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    errors.push(`${source} must be a port between 1 and 65535, got ${JSON.stringify(raw)}.`);
    return fallback;
  }
  return port;
}

function parseMode(
  raw: string | undefined,
  fallback: BridgeMode,
  errors: string[],
  source: string
): BridgeMode {
  if (raw === undefined || raw === "") return fallback;
  if (!BRIDGE_MODES.includes(raw as BridgeMode)) {
    errors.push(
      `${source} must be one of ${BRIDGE_MODES.join(", ")}, got ${JSON.stringify(raw)}.`
    );
    return fallback;
  }
  return raw as BridgeMode;
}
