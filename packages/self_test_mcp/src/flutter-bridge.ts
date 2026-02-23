import WebSocket from "ws";

/**
 * Bridge for communicating with the Flutter app via WebSocket.
 */
export class FlutterBridge {
  private ws: WebSocket | null = null;
  private host: string;
  private port: number;
  private messageId = 0;
  private pendingRequests = new Map<number, {
    resolve: (value: any) => void;
    reject: (error: Error) => void;
    timeout: NodeJS.Timeout;
  }>();

  constructor(host: string, port: number) {
    this.host = host;
    this.port = port;
  }

  /**
   * Connect to the Flutter app's WebSocket server.
   */
  async connect(): Promise<void> {
    return new Promise((resolve, reject) => {
      const url = `ws://${this.host}:${this.port}`;
      console.error(`Connecting to Flutter app at ${url}...`);

      this.ws = new WebSocket(url);

      this.ws.on("open", () => {
        console.error("Connected to Flutter app");
        resolve();
      });

      this.ws.on("error", (error) => {
        console.error("WebSocket error:", error.message);
        reject(new Error(`Failed to connect to Flutter app: ${error.message}`));
      });

      this.ws.on("close", () => {
        console.error("Disconnected from Flutter app");
        this.ws = null;
        // Reject all pending requests
        for (const [id, pending] of this.pendingRequests) {
          clearTimeout(pending.timeout);
          pending.reject(new Error("Connection closed"));
        }
        this.pendingRequests.clear();
      });

      this.ws.on("message", (data) => {
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

      // Connection timeout
      setTimeout(() => {
        if (this.ws?.readyState !== WebSocket.OPEN) {
          reject(new Error("Connection timeout"));
        }
      }, 5000);
    });
  }

  /**
   * Check if connected to Flutter app.
   */
  isConnected(): boolean {
    return this.ws?.readyState === WebSocket.OPEN;
  }

  /**
   * Send a command to the Flutter app and wait for response.
   */
  async send<T = any>(command: string, params: Record<string, any> = {}): Promise<T> {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
      throw new Error("Not connected to Flutter app");
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
   * Disconnect from Flutter app.
   */
  disconnect(): void {
    if (this.ws) {
      this.ws.close();
      this.ws = null;
    }
  }
}
