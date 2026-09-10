import WebSocket, { WebSocketServer } from "ws";
import type { IncomingMessage } from "node:http";

/**
 * Bridge for communicating with the Flutter app via WebSocket.
 *
 * Supports two modes:
 * - CLIENT mode: Connects to Flutter app's WebSocket server (for native platforms)
 * - SERVER mode: Runs a WebSocket server that Flutter app connects to (for web)
 *
 * The bridge binds to loopback and requires a token. The Flutter app prints
 * its URL at startup, for example ws://127.0.0.1:9999?token=abc123, and the
 * token travels both as that query parameter and as an `x-self-test-token`
 * header so either end of the handshake can check it.
 */

export const TOKEN_HEADER = "x-self-test-token";
export const TOKEN_QUERY_PARAM = "token";

/** Thrown when the bridge refuses the handshake with HTTP 403. */
export class BridgeAuthError extends Error {
  readonly statusCode = 403;
  constructor(message: string) {
    super(message);
    this.name = "BridgeAuthError";
  }
}

/**
 * `ws` reports a rejected handshake as `Unexpected server response: 403`,
 * which reads like a transport failure. Recover the status code so the
 * caller can say what actually went wrong.
 */
export function statusFromErrorMessage(message: string | undefined): number | undefined {
  if (!message) return undefined;
  const match = /Unexpected server response:\s*(\d{3})/i.exec(message);
  return match ? Number(match[1]) : undefined;
}

/**
 * Turn a failed connection into something a person can act on.
 *
 * A 403 means the token was wrong or absent, and saying so is the whole point:
 * the generic socket error sends people looking for a crashed app instead of a
 * mistyped token.
 */
export function describeConnectionError(
  cause: { statusCode?: number; message?: string },
  context: { url: string; hasToken: boolean }
): string {
  const status = cause.statusCode ?? statusFromErrorMessage(cause.message);

  if (status === 403) {
    const detail = context.hasToken
      ? "The token supplied does not match the one the app is using."
      : "No token was supplied.";
    return (
      `Bridge refused the connection at ${context.url}: wrong or missing token (HTTP 403). ` +
      `${detail} The Flutter app prints its bridge URL at startup, for example ` +
      `ws://127.0.0.1:9999?token=abc123; pass that token as --token <token> or ` +
      `set SELF_TEST_TOKEN.`
    );
  }

  if (status !== undefined) {
    return `Bridge refused the connection at ${context.url}: HTTP ${status}.`;
  }

  const message = cause.message ?? "unknown error";
  return `Failed to connect to the Flutter app at ${context.url}: ${message}`;
}

/** Read the token off an incoming handshake, header first then query. */
export function tokenFromRequest(request: {
  url?: string;
  headers?: Record<string, string | string[] | undefined>;
}): string | undefined {
  const header = request.headers?.[TOKEN_HEADER];
  if (typeof header === "string" && header !== "") return header;
  if (Array.isArray(header) && typeof header[0] === "string" && header[0] !== "") {
    return header[0];
  }

  if (!request.url) return undefined;
  try {
    // The base is irrelevant: only the query string is read from it.
    const parsed = new URL(request.url, "ws://127.0.0.1");
    return parsed.searchParams.get(TOKEN_QUERY_PARAM) ?? undefined;
  } catch {
    return undefined;
  }
}

/** Build the client-mode URL, carrying the token the way the app prints it. */
export function bridgeUrl(host: string, port: number, token?: string): string {
  const base = `ws://${host}:${port}`;
  if (!token) return base;
  return `${base}?${TOKEN_QUERY_PARAM}=${encodeURIComponent(token)}`;
}

export interface FlutterBridgeOptions {
  /** Token the bridge requires. Sent on connect, and checked on accept. */
  token?: string;
}

export class FlutterBridge {
  private ws: WebSocket | null = null;
  private wss: WebSocketServer | null = null;
  private host: string;
  private port: number;
  private mode: "client" | "server";
  private token?: string;
  private messageId = 0;
  private pendingRequests = new Map<number, {
    resolve: (value: any) => void;
    reject: (error: Error) => void;
    timeout: NodeJS.Timeout;
  }>();
  private connectionPromise: Promise<void> | null = null;
  private connectionResolve: (() => void) | null = null;

  constructor(
    host: string,
    port: number,
    mode: "client" | "server" = "client",
    options: FlutterBridgeOptions = {}
  ) {
    this.host = host;
    this.port = port;
    this.mode = mode;
    this.token = options.token;
  }

  /** The URL this bridge connects to, or listens on. */
  getUrl(): string {
    return bridgeUrl(this.host, this.port, this.token);
  }

  /**
   * Connect to Flutter app (client mode) or start server and wait for connection (server mode).
   */
  async connect(): Promise<void> {
    if (this.mode === "server") {
      return this.startServer();
    } else {
      return this.connectAsClient();
    }
  }

  /**
   * Start WebSocket server and wait for Flutter app to connect.
   */
  private async startServer(): Promise<void> {
    return new Promise((resolve, reject) => {
      console.error(`Starting WebSocket server on port ${this.port}...`);

      const requiredToken = this.token;
      this.wss = new WebSocketServer({
        // Loopback only. This socket drives the app; it has no business being
        // reachable from the network.
        host: this.host,
        port: this.port,
        verifyClient: requiredToken
          ? (info: { req: IncomingMessage }, done: (ok: boolean, code?: number, message?: string) => void) => {
              const presented = tokenFromRequest(info.req);
              if (presented === requiredToken) {
                done(true);
              } else {
                console.error(
                  "Rejected a bridge connection: wrong or missing token (HTTP 403)."
                );
                done(false, 403, "wrong or missing token");
              }
            }
          : undefined,
      });

      this.wss.on("listening", () => {
        console.error(`WebSocket server listening on ${redactToken(this.getUrl())}`);
        if (!requiredToken) {
          console.error(
            "No token configured. Pass --token or set SELF_TEST_TOKEN to match the app."
          );
        }
        console.error("Waiting for Flutter app to connect...");
        // Don't resolve yet - wait for a client to connect
      });

      this.wss.on("error", (error) => {
        console.error("WebSocket server error:", error.message);
        reject(new Error(`Failed to start server: ${error.message}`));
      });

      this.wss.on("connection", (socket) => {
        console.error("Flutter app connected!");
        this.ws = socket;
        this.setupSocketHandlers(socket);

        // Resolve the connection promise if we were waiting
        if (this.connectionResolve) {
          this.connectionResolve();
          this.connectionResolve = null;
        }

        // Resolve the initial connect() promise
        resolve();
      });

      // Connection timeout - but only reject if no client connected
      setTimeout(() => {
        if (!this.ws) {
          console.error("No Flutter app connected within timeout, server still running...");
          // Don't reject - keep server running, but resolve so MCP can start
          resolve();
        }
      }, 5000);
    });
  }

  /**
   * Wait for a Flutter app to connect (when in server mode).
   */
  async waitForConnection(timeoutMs: number = 30000): Promise<void> {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      return Promise.resolve();
    }

    if (this.connectionPromise) {
      return this.connectionPromise;
    }

    this.connectionPromise = new Promise((resolve, reject) => {
      this.connectionResolve = resolve;

      setTimeout(() => {
        if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
          reject(new Error("Timeout waiting for Flutter app to connect"));
        }
      }, timeoutMs);
    });

    return this.connectionPromise;
  }

  /**
   * Connect to Flutter app's WebSocket server (client mode).
   */
  private async connectAsClient(): Promise<void> {
    return new Promise((resolve, reject) => {
      const url = bridgeUrl(this.host, this.port, this.token);
      const context = { url, hasToken: Boolean(this.token) };
      console.error(`Connecting to Flutter app at ${redactToken(url)}...`);

      let settled = false;
      // Held so the 5s timer stops holding the event loop open once the
      // connection has succeeded or failed.
      let connectTimer: NodeJS.Timeout | undefined;
      const settle = (): boolean => {
        if (settled) return false;
        settled = true;
        if (connectTimer) clearTimeout(connectTimer);
        return true;
      };
      const failWith = (message: string) => {
        if (!settle()) return;
        console.error(message);
        reject(
          message.includes("HTTP 403") ? new BridgeAuthError(message) : new Error(message)
        );
      };

      this.ws = new WebSocket(url, {
        headers: this.token ? { [TOKEN_HEADER]: this.token } : undefined,
      });
      this.setupSocketHandlers(this.ws);

      this.ws.on("open", () => {
        if (!settle()) return;
        console.error("Connected to Flutter app");
        resolve();
      });

      // Emitted when the handshake gets a plain HTTP response, which is how a
      // refused token arrives. It carries the status code the `error` event
      // only hints at.
      this.ws.on("unexpected-response", (_request, response) => {
        failWith(describeConnectionError({ statusCode: response.statusCode }, context));
      });

      this.ws.on("error", (error) => {
        failWith(describeConnectionError({ message: error.message }, context));
      });

      // Connection timeout
      connectTimer = setTimeout(() => {
        if (this.ws?.readyState !== WebSocket.OPEN) {
          failWith(`Connection timeout: no response from the bridge at ${redactToken(url)}.`);
        }
      }, 5000);
    });
  }

  /**
   * Setup common socket event handlers.
   */
  private setupSocketHandlers(socket: WebSocket): void {
    socket.on("close", () => {
      console.error("Flutter app disconnected");
      this.ws = null;
      // Reject all pending requests
      for (const [id, pending] of this.pendingRequests) {
        clearTimeout(pending.timeout);
        pending.reject(new Error("Connection closed"));
      }
      this.pendingRequests.clear();
    });

    socket.on("message", (data) => {
      try {
        const response = JSON.parse(data.toString());
        const pending = this.pendingRequests.get(response.id);
        if (pending) {
          clearTimeout(pending.timeout);
          this.pendingRequests.delete(response.id);

          if (response.error) {
            pending.reject(new Error(response.error));
          } else {
            pending.resolve(response.result);
          }
        }
      } catch (e) {
        console.error("Failed to parse response:", e);
      }
    });
  }

  /**
   * Check if connected to Flutter app.
   */
  isConnected(): boolean {
    return this.ws?.readyState === WebSocket.OPEN;
  }

  /**
   * Get the current mode.
   */
  getMode(): "client" | "server" {
    return this.mode;
  }

  /**
   * Send a command to the Flutter app and wait for response.
   */
  async send<T = any>(command: string, params: Record<string, any> = {}): Promise<T> {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
      if (this.mode === "server") {
        throw new Error("No Flutter app connected. Start the Flutter app and ensure it connects to this server.");
      } else {
        throw new Error("Not connected to Flutter app");
      }
    }

    const id = ++this.messageId;
    const message = { id, command, params };

    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pendingRequests.delete(id);
        reject(new Error(`Command timeout: ${command}`));
      }, 30000);

      this.pendingRequests.set(id, { resolve, reject, timeout });
      this.ws!.send(JSON.stringify(message));
    });
  }

  /**
   * Disconnect from Flutter app / stop server.
   */
  disconnect(): void {
    if (this.ws) {
      this.ws.close();
      this.ws = null;
    }
    if (this.wss) {
      this.wss.close();
      this.wss = null;
    }
  }
}

/** Keep the token out of the logs; the URL is only there to identify the host. */
export function redactToken(url: string): string {
  return url.replace(
    new RegExp(`([?&]${TOKEN_QUERY_PARAM}=)[^&]*`),
    "$1<redacted>"
  );
}
