import WebSocket, { WebSocketServer } from "ws";

/**
 * Bridge for communicating with the Flutter app via WebSocket.
 *
 * Supports two modes:
 * - CLIENT mode: Connects to Flutter app's WebSocket server (for native platforms)
 * - SERVER mode: Runs a WebSocket server that Flutter app connects to (for web)
 */
export class FlutterBridge {
  private ws: WebSocket | null = null;
  private wss: WebSocketServer | null = null;
  private host: string;
  private port: number;
  private mode: "client" | "server";
  private messageId = 0;
  private pendingRequests = new Map<number, {
    resolve: (value: any) => void;
    reject: (error: Error) => void;
    timeout: NodeJS.Timeout;
  }>();
  private connectionPromise: Promise<void> | null = null;
  private connectionResolve: (() => void) | null = null;

  constructor(host: string, port: number, mode: "client" | "server" = "client") {
    this.host = host;
    this.port = port;
    this.mode = mode;
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

      this.wss = new WebSocketServer({ port: this.port });

      this.wss.on("listening", () => {
        console.error(`WebSocket server listening on ws://${this.host}:${this.port}`);
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
      const url = `ws://${this.host}:${this.port}`;
      console.error(`Connecting to Flutter app at ${url}...`);

      this.ws = new WebSocket(url);
      this.setupSocketHandlers(this.ws);

      this.ws.on("open", () => {
        console.error("Connected to Flutter app");
        resolve();
      });

      this.ws.on("error", (error) => {
        console.error("WebSocket error:", error.message);
        reject(new Error(`Failed to connect to Flutter app: ${error.message}`));
      });

      // Connection timeout
      setTimeout(() => {
        if (this.ws?.readyState !== WebSocket.OPEN) {
          reject(new Error("Connection timeout"));
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
