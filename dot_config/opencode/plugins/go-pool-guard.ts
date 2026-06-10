import { Plugin } from "@opencode-ai/plugin";
import { $ } from "bun";

const GO_USAGE_URL = "https://opencode.ai/zen/go/v1/usage";

const FREE_MODEL: Record<string, string> = {
  "opencode-go/kimi-k2.6":   "openrouter/deepseek/deepseek-v4-flash:free",
  "opencode-go/kimi-k2.5":   "openrouter/qwen/qwen3-coder:free",
  "opencode-go/deepseek-v4-pro": "openrouter/deepseek/deepseek-v4-flash:free",
  "opencode-go/deepseek-v4-flash": "openrouter/deepseek/deepseek-v4-flash:free",
  "opencode-go/mimo-v2.5-pro": "openrouter/meta-llama/llama-3.3-70b-instruct:free",
};

async function isGoPoolExhausted(): Promise<boolean> {
  try {
    const res = await fetch(GO_USAGE_URL, {
      headers: { "Accept": "application/json" },
    });
    if (res.status === 429) return true;
    if (res.status === 200) {
      const data = await res.json() as any;
      const rolling = data?.windows?.rolling?.usage_percent ?? 0;
      return rolling >= 95;
    }
  } catch {
    // If we can't reach the API, assume pool is fine
  }
  return false;
}

function replaceWithFree(obj: any): any {
  if (!obj || typeof obj !== "object") return obj;
  const result = Array.isArray(obj) ? [...obj] : { ...obj };
  for (const key of Object.keys(result)) {
    if (key === "model" && typeof result[key] === "string" && FREE_MODEL[result[key]]) {
      result[key] = FREE_MODEL[result[key]];
    } else if (typeof result[key] === "object") {
      result[key] = replaceWithFree(result[key]);
    }
  }
  return result;
}

export const GoPoolGuardPlugin: Plugin = async () => {
  return {
    config: async (cfg: any) => {
      const exhausted = await isGoPoolExhausted();
      if (!exhausted) return;

      console.warn("[GoPoolGuard] Pool exhausted — switching all Go models to free alternatives");

      if (cfg.agents) {
        for (const name of Object.keys(cfg.agents)) {
          cfg.agents[name] = replaceWithFree(cfg.agents[name]);
        }
      }
      if (cfg.categories) {
        for (const name of Object.keys(cfg.categories)) {
          cfg.categories[name] = replaceWithFree(cfg.categories[name]);
        }
      }
      if (cfg.model && FREE_MODEL[cfg.model]) {
        cfg.model = FREE_MODEL[cfg.model];
      }
    },
  };
};
