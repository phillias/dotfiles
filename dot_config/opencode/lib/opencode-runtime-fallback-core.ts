export interface ChainEntrySettings {
  temperature?: number;
  maxOutputTokens?: number;
  options?: Record<string, unknown>;
}

export type ChainEntry = string | (ChainEntrySettings & { model: string });

export interface ChainCfg {
  model?: string;
  variant?: string;
  temperature?: number;
  fallback_models?: ChainEntry[];
  /** When true, skip appending the global `fallback_models` ladder — the
   *  chain ends here and surfaces a visible failure instead of degrading to
   *  the free tier (specialized/pinned-agent carve-out). */
  no_global_tail?: boolean;
}

export interface FallbackConfig {
  enabled?: boolean;
  retry_on_errors?: number[];
  max_fallback_attempts?: number;
  cooldown_seconds?: number;
  timeout_seconds?: number;
  notify_on_fallback?: boolean;
  fallback_models?: ChainEntry[];
  agents?: Record<string, ChainCfg>;
  categories?: Record<string, ChainCfg>;
}

export function stripJsonc(src: string): string {
  let out = "";
  let inString = false;
  let inLineComment = false;
  let inBlockComment = false;
  for (let i = 0; i < src.length; i++) {
    const c = src[i];
    const n = src[i + 1];
    if (inLineComment) {
      if (c === "\n") { inLineComment = false; out += c; }
      continue;
    }
    if (inBlockComment) {
      if (c === "*" && n === "/") { inBlockComment = false; i++; }
      continue;
    }
    if (inString) {
      out += c;
      if (c === "\\" && n) { out += n; i++; }
      else if (c === '"') inString = false;
      continue;
    }
    if (c === '"') { inString = true; out += c; continue; }
    if (c === "/" && n === "/") { inLineComment = true; i++; continue; }
    if (c === "/" && n === "*") { inBlockComment = true; i++; continue; }
    out += c;
  }
  return out.replace(/,(\s*[}\]])/g, "$1");
}

export function entryModel(e: ChainEntry): string {
  return typeof e === "string" ? e : e.model;
}

export function entrySettings(e: ChainEntry): ChainEntrySettings | undefined {
  return typeof e === "string" ? undefined : e;
}

export function parseModel(m: string): { providerID: string; modelID: string } {
  const slash = m.indexOf("/");
  if (slash <= 0 || slash === m.length - 1) return { providerID: "unknown", modelID: m };
  return { providerID: m.slice(0, slash), modelID: m.slice(slash + 1) };
}

export function isRetryableStatusCode(code: number | undefined, cfg: FallbackConfig): boolean {
  if (code === undefined) return false;
  return (cfg.retry_on_errors ?? [429, 500, 502, 503, 504, 529]).includes(code);
}

const RETRYABLE_PATTERN = /rate\s?limit|quota|insufficient_quota|server_error|overloaded|timed?\s?out|timeout|429|5\d\d|529|pool.*exhaust/i;

export function classifyError(err: unknown, cfg: FallbackConfig): string {
  const d = (err as any)?.data ?? (err as any)?.error ?? err;
  const name = (err as any)?.name ?? "";
  let code: number | undefined;
  let message = "";
  if (typeof d === "object" && d !== null) {
    code = typeof d.statusCode === "number" ? d.statusCode : typeof d.status === "number" ? d.status : undefined;
    message = String(d.message ?? "");
  } else if (typeof d === "string") {
    message = d;
  }
  if (isRetryableStatusCode(code, cfg)) return "retryable";
  if (name === "ProviderAuthError") return "retryable";
  if (message && RETRYABLE_PATTERN.test(message)) return "retryable";
  return "none";
}

/** Resolve a chain config for an agent name: exact key wins, then the longest
 *  trailing-`*` wildcard prefix (e.g. `ce-*` covers every ce-* persona). */
export function lookupChain(map: Record<string, ChainCfg> | undefined, name: string | undefined): ChainCfg | undefined {
  if (!map || !name) return undefined;
  if (map[name]) return map[name];
  let best: ChainCfg | undefined;
  let bestLen = -1;
  for (const [key, v] of Object.entries(map)) {
    if (!key.endsWith("*")) continue;
    const prefix = key.slice(0, -1);
    if (name.startsWith(prefix) && key.length > bestLen) {
      best = v;
      bestLen = key.length;
    }
  }
  return best;
}

export function resolveChain(cfg: FallbackConfig, agentName: string | undefined): ChainEntry[] {
  const merged: ChainEntry[] = [];
  const push = (list: ChainEntry[] | undefined) => {
    for (const e of list ?? []) {
      const m = entryModel(e);
      if (!merged.some((x) => entryModel(x) === m)) merged.push(e);
    }
  };
  const ag = lookupChain(cfg.agents, agentName);
  const cat = lookupChain(cfg.categories, agentName);
  let tail = true;
  push(ag?.model ? [ag.model] : undefined);
  push(ag?.fallback_models);
  if (ag?.no_global_tail) tail = false;
  if (!ag) {
    push(cat?.model ? [cat.model] : undefined);
    push(cat?.fallback_models);
    if (cat?.no_global_tail) tail = false;
  }
  if (tail) push(cfg.fallback_models);
  return merged;
}

export function nextCandidate(chain: string[], failedModel: string, isCooling: (m: string) => number): string | undefined {
  const pos = chain.indexOf(failedModel);
  const start = pos >= 0 ? pos + 1 : 0;
  for (let i = start; i < chain.length; i++) {
    if (chain[i] === failedModel) continue;
    if (isCooling(chain[i]) === 0) return chain[i];
  }
  return undefined;
}

export function remaining(chain: string[], index: number): number {
  return Math.max(0, chain.length - 1 - index);
}

export function primaryAvailable(chain: string[], activeModel: string | undefined, isCooling: (m: string) => number): boolean {
  if (chain.length === 0) return false;
  const primary = chain[0];
  return primary !== activeModel && isCooling(primary) === 0;
}

export function annotationFor(activeModel: string | undefined, index: number, chain: string[]): string | undefined {
  if (!activeModel || index <= 0) return undefined;
  return `[model: active on ${activeModel}; ${remaining(chain, index)} left in fallback chain]`;
}
