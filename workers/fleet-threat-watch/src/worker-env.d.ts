// Minimal Workers platform declarations for offline typechecking.
// Regenerate the full set at deploy time with `wrangler types`
// (worker-configuration.d.ts); the generated file replaces this stub.
interface KVNamespace {
  get(key: string, type: "json"): Promise<unknown>;
  get(key: string, type: "text"): Promise<string | null>;
  put(key: string, value: string): Promise<void>;
}

interface ScheduledEvent {
  cron: string;
  scheduledTime: number;
}

interface ExecutionContext {
  waitUntil(promise: Promise<unknown>): void;
  passThroughOnException(): void;
}

// Minimal web-platform globals used by src/index.ts (fetch, Response,
// RequestInit, btoa, console). The full generated file from `wrangler types`
// declares these via @cloudflare/workers-types and replaces this stub.
declare function fetch(url: string, init?: RequestInit): Promise<Response>;

interface RequestInit {
  method?: string;
  headers?: Record<string, string>;
  body?: string;
}

interface Response {
  readonly status: number;
  readonly ok: boolean;
  readonly headers: Headers;
  json(): Promise<unknown>;
}

interface Headers {
  get(name: string): string | null;
}

declare function btoa(data: string): string;

declare const console: { log(message: string): void };
