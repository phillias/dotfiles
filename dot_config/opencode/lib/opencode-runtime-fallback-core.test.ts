import { describe, expect, test } from "bun:test";
import {
  type FallbackConfig,
  lookupChain,
  resolveChain,
  entryModel,
  sustainedCooldownSeconds,
} from "./opencode-runtime-fallback-core";

const GLOBAL = ["global/a", "global/b"];

function cfg(extra: Partial<FallbackConfig> = {}): FallbackConfig {
  return { fallback_models: GLOBAL, ...extra };
}

describe("lookupChain", () => {
  const map = {
    "ce-correctness-reviewer": { model: "pinned/exact" },
    "ce-*": { model: "pinned/wild" },
    "ce-code-review-*": { model: "pinned/longer" },
  };

  test("exact match wins over wildcard", () => {
    const got = lookupChain(map, "ce-correctness-reviewer");
    expect(got?.model).toBe("pinned/exact");
  });

  test("longest wildcard prefix wins", () => {
    const got = lookupChain(map, "ce-code-review-something");
    expect(got?.model).toBe("pinned/longer");
  });

  test("short wildcard catches non-exact ce-* names", () => {
    const got = lookupChain(map, "ce-security-reviewer");
    expect(got?.model).toBe("pinned/wild");
  });

  test("no match returns undefined", () => {
    expect(lookupChain(map, "explore")).toBeUndefined();
    expect(lookupChain(map, undefined)).toBeUndefined();
  });
});

describe("resolveChain", () => {
  test("global ladder is appended by default (deduped)", () => {
    const chain = resolveChain(cfg(), undefined).map(entryModel);
    expect(chain).toEqual(["global/a", "global/b"]);
  });

  test("no_global_tail on agent skips the global ladder", () => {
    const c = cfg({ agents: { "oracle": { model: "opencode/gpt-5.5", no_global_tail: true } } });
    const chain = resolveChain(c, "oracle").map(entryModel);
    expect(chain).toEqual(["opencode/gpt-5.5"]);
  });

  test("wildcard agent entry applies to any ce-* persona", () => {
    const c = cfg({
      agents: {
        "ce-*": {
          fallback_models: ["commandcode/moonshotai/Kimi-K2.6", "opencode-zen/kimi-k2.6"],
          no_global_tail: true,
        },
      },
    });
    const chain = resolveChain(c, "ce-correctness-reviewer").map(entryModel);
    expect(chain).toEqual(["commandcode/moonshotai/Kimi-K2.6", "opencode-zen/kimi-k2.6"]);
  });

  test("exact agent key beats a matching wildcard", () => {
    const c = cfg({
      agents: {
        "ce-correctness-reviewer": { model: "opencode-go/glm-5.1", no_global_tail: true },
        "ce-*": { fallback_models: ["commandcode/deepseek/deepseek-v4-flash"] },
      },
    });
    const chain = resolveChain(c, "ce-correctness-reviewer").map(entryModel);
    expect(chain).toEqual(["opencode-go/glm-5.1"]);
  });

  test("categories apply only when no agent entry matches", () => {
    const c = cfg({
      agents: { "quick": { model: "opencode-zen/big-pickle" } },
      categories: { "quick": { model: "cloudflare/workers-ai/@cf/openai/gpt-oss-20b" } },
    });
    expect(resolveChain(c, "quick").map(entryModel)[0]).toBe("opencode-zen/big-pickle");
  });

  test("pinned model + fallback order GOAT -> Zen with no_global_tail", () => {
    const c = cfg({
      categories: {
        "ultrabrain": {
          model: "opencode-go/deepseek-v4-pro",
          fallback_models: ["commandcode/deepseek/deepseek-v4-pro", "opencode-zen/deepseek-v4-pro"],
          no_global_tail: true,
        },
      },
    });
    const chain = resolveChain(c, "ultrabrain").map(entryModel);
    expect(chain).toEqual([
      "opencode-go/deepseek-v4-pro",
      "commandcode/deepseek/deepseek-v4-pro",
      "opencode-zen/deepseek-v4-pro",
    ]);
  });
});

describe("sustainedCooldownSeconds", () => {
  test("returns 0 for non-sustained errors", () => {
    expect(sustainedCooldownSeconds("server_error: upstream unavailable")).toBe(0);
    expect(sustainedCooldownSeconds("")).toBe(0);
    expect(sustainedCooldownSeconds("timeout")).toBe(0);
  });

  test("parses Z.AI 5-hour limit with reset timestamp", () => {
    const future = new Date(Date.now() + 3 * 3600 * 1000);
    const ts = future.toISOString().replace("T", " ").slice(0, 19);
    const reason = `Usage limit reached for 5 hour. Your limit will reset at ${ts}`;
    const seconds = sustainedCooldownSeconds(reason);
    expect(seconds).toBeGreaterThanOrEqual(2 * 3600);
    expect(seconds).toBeLessThanOrEqual(3 * 3600 + 10);
  });

  test("returns 5-hour default when sustained but no parseable timestamp", () => {
    expect(sustainedCooldownSeconds("Usage limit reached for 5 hour")).toBe(5 * 3600);
    expect(sustainedCooldownSeconds("hourly limit exceeded")).toBe(5 * 3600);
  });

  test("floors at 60 seconds even if reset is imminent", () => {
    const reason = "Usage limit reached for 5 hour. Your limit will reset at 2020-01-01 00:00:00";
    expect(sustainedCooldownSeconds(reason)).toBe(60);
  });
});
