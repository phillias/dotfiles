import { describe, expect, test } from "bun:test";
import {
  type FallbackConfig,
  lookupChain,
  resolveChain,
  entryModel,
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
      categories: { "quick": { model: "cloudflare/@cf/openai/gpt-oss-20b" } },
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
