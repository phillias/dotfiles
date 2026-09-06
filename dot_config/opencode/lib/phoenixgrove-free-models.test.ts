import { describe, expect, test } from "bun:test";
import { readFile } from "node:fs/promises";
import {
  parseModel,
  stripJsonc,
  entryModel,
  resolveChain,
} from "./opencode-runtime-fallback-core";

// This test exercises the REAL declarative config artifacts (opencode.json,
// opencode-fallback.jsonc, private_dot_pi/private_agent/models.json,
// private_dot_pi/fallback-chains.json) through the real consumer's parser
// functions (stripJsonc / resolveChain / parseModel) — the same pipeline the
// opencode-runtime-fallback.ts plugin and the pi gate agent use at runtime.
//
// Intent under test (branch fix/phoenixgrove-free-models): Phoenix Grove credit
// consumption is fixed by routing the provider through the Cloudflare AI
// Gateway (custom-phoenixgrove) with the gateway token, and by switching from
// the paid Frontier-band glm-5.3 to the free Everyday-band flash models
// (glm-5.3-flash 321B/18B 1M ctx, glm-4.7-flash, deepseek-v4-flash,
// deepseek-v4-flash-0731). The pi gate chain is re-ordered to gate-chain v4:
// openrouter :free trio leads (nemotron-3.5-lightning, minimax-m3, inkling),
// followed by opencode-zen gemini-3.5-flash, the GOAT paid-pool 1M models,
// paid lanes (openrouter/openai/gpt-5.6-luna), then phoenixgrove/glm-5.3-flash
// and gemini/gemini-2.5-flash at the tail as manual fallbacks. These assertions
// fail on the pre-fix config (direct api.pgsgrove.com URL, .phoenixgrove-key,
// paid glm-5.3, v3 gate ordering) and pass after the fix.

const PI_DIR = "../../../private_dot_pi";

const GATEWAY_HOST = "gateway.ai.cloudflare.com";
const GATEWAY_TOKEN_FILE = "{file:~/.config/opencode/.cf-ai-gw-token}";
const GATEWAY_TOKEN_ENV = "$CF_AI_GATEWAY_TOKEN";
const FREE_EVERYDAY_MODELS = [
  "glm-5.3-flash",
  "glm-4.7-flash",
  "deepseek-v4-flash",
  "deepseek-v4-flash-0731",
] as const;
const PAID_FRONTIER_MODEL = "glm-5.3";

async function loadOpencodeProviderRegistry(): Promise<Record<string, any>> {
  const raw = await readFile("../opencode.json", "utf-8");
  const cfg = JSON.parse(raw);
  if (!cfg.provider?.phoenixgrove)
    throw new Error("phoenixgrove provider missing from opencode.json");
  return cfg.provider;
}

async function loadFallbackConfig(): Promise<any> {
  const raw = await readFile("../opencode-fallback.jsonc", "utf-8");
  return JSON.parse(stripJsonc(raw));
}

async function loadPiModels(): Promise<any> {
  const raw = await readFile(`${PI_DIR}/private_agent/models.json`, "utf-8");
  return JSON.parse(raw);
}

async function loadPiChains(): Promise<any> {
  const raw = await readFile(`${PI_DIR}/fallback-chains.json`, "utf-8");
  return JSON.parse(raw);
}

/** Collect every model id string anywhere in a fallback config tree. */
function collectModelRefs(o: unknown): string[] {
  const out: string[] = [];
  const visit = (v: unknown) => {
    if (Array.isArray(v)) {
      v.forEach(visit);
      return;
    }
    if (v && typeof v === "object") {
      const rec = v as Record<string, unknown>;
      if (typeof rec.model === "string") out.push(rec.model);
      if (Array.isArray(rec.fallback_models)) {
        for (const e of rec.fallback_models) {
          if (typeof e === "string") out.push(e);
          else if (
            e &&
            typeof e === "object" &&
            typeof (e as any).model === "string"
          )
            out.push((e as any).model);
        }
      }
      Object.values(rec).forEach(visit);
    }
  };
  visit(o);
  return out;
}

describe("opencode.json phoenixgrove provider routes through the AI Gateway", () => {
  test("baseURL is the Cloudflare AI Gateway custom-phoenixgrove slug, not the direct PGS API", async () => {
    const providers = await loadOpencodeProviderRegistry();
    const url = providers.phoenixgrove.options.baseURL;
    expect(url, "must be on the gateway host").toContain(GATEWAY_HOST);
    expect(url, "must target the custom-phoenixgrove slug").toContain(
      "/opencode/custom-phoenixgrove/",
    );
    expect(url, "must end on the openai-compatible /v1").toMatch(/\/v1$/);
    // Regression guard: the direct PGS API must be gone.
    expect(url, "direct api.pgsgrove.com must be removed").not.toContain(
      "api.pgsgrove.com",
    );
  });

  test("apiKey is the gateway token file indirection, not the PGS provider key", async () => {
    const providers = await loadOpencodeProviderRegistry();
    const key = providers.phoenixgrove.options.apiKey;
    expect(key, "must use the shared gateway token file").toBe(
      GATEWAY_TOKEN_FILE,
    );
    expect(
      key,
      "must not reference the legacy .phoenixgrove-key",
    ).not.toContain(".phoenixgrove-key");
  });

  test("registry contains every free Everyday-band flash model and not the paid Frontier glm-5.3", async () => {
    const providers = await loadOpencodeProviderRegistry();
    const registered = Object.keys(providers.phoenixgrove.models);
    for (const id of FREE_EVERYDAY_MODELS) {
      expect(
        registered,
        `free Everyday model ${id} must be registered`,
      ).toContain(id);
    }
    expect(registered, "paid Frontier glm-5.3 must be removed").not.toContain(
      PAID_FRONTIER_MODEL,
    );
  });

  test("glm-5.3-flash is configured with the advertised 1M context window", async () => {
    const providers = await loadOpencodeProviderRegistry();
    const limit = providers.phoenixgrove.models["glm-5.3-flash"].limit;
    expect(
      limit.context,
      "glm-5.3-flash context must be 1_000_000 (321B/18B active)",
    ).toBe(1_000_000);
    expect(limit.output, "glm-5.3-flash output must be capped").toBe(8192);
  });
});

describe("opencode-fallback.jsonc chains resolve to the free PGS flash models", () => {
  test("global ladder and utility agent/category chains include the free flash models", async () => {
    const fb = await loadFallbackConfig();
    // Global ladder (agent=undefined resolves here) — the deduped tail of every
    // non-no_global_tail chain, so this also proves the free models reach every
    // utility chain.
    const globalChain = resolveChain(fb, undefined).map(entryModel);
    expect(globalChain, "global ladder must include glm-5.3-flash").toContain(
      "phoenixgrove/glm-5.3-flash",
    );
    expect(
      globalChain,
      "global ladder must include deepseek-v4-flash",
    ).toContain("phoenixgrove/deepseek-v4-flash");

    // Representative utility categories whose explicit fallback_models were
    // extended with the free PGS models.
    for (const cat of ["quick", "unspecified-low"]) {
      const chain = resolveChain(fb, cat).map(entryModel);
      expect(chain, `${cat} chain must include glm-5.3-flash`).toContain(
        "phoenixgrove/glm-5.3-flash",
      );
      expect(chain, `${cat} chain must include deepseek-v4-flash`).toContain(
        "phoenixgrove/deepseek-v4-flash",
      );
    }
    // Representative utility agent (general/explore) whose explicit
    // fallback_models were extended.
    for (const ag of ["general", "explore"]) {
      const chain = resolveChain(fb, ag).map(entryModel);
      expect(chain, `${ag} agent chain must include glm-5.3-flash`).toContain(
        "phoenixgrove/glm-5.3-flash",
      );
      expect(
        chain,
        `${ag} agent chain must include deepseek-v4-flash`,
      ).toContain("phoenixgrove/deepseek-v4-flash");
    }
  });

  test("every phoenixgrove fallback reference resolves to a registered free model", async () => {
    const providers = await loadOpencodeProviderRegistry();
    const registered = Object.keys(providers.phoenixgrove.models);
    const fb = await loadFallbackConfig();
    const refs = collectModelRefs(fb).filter((m) =>
      m.startsWith("phoenixgrove/"),
    );
    expect(
      refs.length,
      "there must be phoenixgrove references in the ladder",
    ).toBeGreaterThan(0);
    for (const ref of refs) {
      const { providerID, modelID } = parseModel(ref);
      expect(providerID).toBe("phoenixgrove");
      expect(
        registered,
        `${ref} → ${modelID} must be a registered free model`,
      ).toContain(modelID);
    }
  });

  test("no fallback reference selects the paid Frontier glm-5.3", async () => {
    const fb = await loadFallbackConfig();
    const refs = collectModelRefs(fb).filter((m) =>
      m.startsWith("phoenixgrove/"),
    );
    for (const ref of refs) {
      const { modelID } = parseModel(ref);
      expect(modelID, `${ref} must not be the paid Frontier glm-5.3`).not.toBe(
        PAID_FRONTIER_MODEL,
      );
    }
  });
});

describe("pi gate boundary mirrors the gateway + free flash fix", () => {
  test("pi models.json phoenixgrove provider points at the gateway with the gateway token", async () => {
    const models = await loadPiModels();
    const pg = models.providers.phoenixgrove;
    expect(pg.baseUrl, "pi phoenixgrove baseUrl must be the gateway").toContain(
      GATEWAY_HOST,
    );
    expect(
      pg.baseUrl,
      "pi phoenixgrove baseUrl must use the custom-phoenixgrove slug",
    ).toContain("/opencode/custom-phoenixgrove/");
    expect(pg.baseUrl, "direct api.pgsgrove.com must be removed").not.toContain(
      "api.pgsgrove.com",
    );
    expect(
      pg.apiKey,
      "pi phoenixgrove apiKey must be the gateway token env var",
    ).toBe(GATEWAY_TOKEN_ENV);
    expect(
      pg.apiKey,
      "must not reference legacy PHOENIXGROVE_API_KEY",
    ).not.toContain("PHOENIXGROVE_API_KEY");
    expect(
      pg.headers?.["cf-aig-gateway-id"],
      "must carry the gateway id header",
    ).toBe("opencode");
  });

  test("pi phoenixgrove registry has the free flash models, not the paid Frontier glm-5.3", async () => {
    const models = await loadPiModels();
    const ids = models.providers.phoenixgrove.models.map((m: any) => m.id);
    expect(ids, "must register glm-5.3-flash").toContain("glm-5.3-flash");
    expect(ids, "must register deepseek-v4-flash").toContain(
      "deepseek-v4-flash",
    );
    expect(ids, "paid Frontier glm-5.3 must be removed").not.toContain(
      PAID_FRONTIER_MODEL,
    );
    const flash = models.providers.phoenixgrove.models.find(
      (m: any) => m.id === "glm-5.3-flash",
    );
    expect(
      flash.contextWindow,
      "pi glm-5.3-flash context must be 1_000_000",
    ).toBe(1_000_000);
  });

  test("openrouter z-ai paid fallback is registered for pi", async () => {
    const models = await loadPiModels();
    const ids = models.providers.openrouter.models.map((m: any) => m.id);
    expect(
      ids,
      "openrouter must register a z-ai paid fallback for pi",
    ).toContain("z-ai/glm-5");
  });

  test("pi gate chain is re-ordered to v4: openrouter :free trio leads, gemini-2.5-flash tail", async () => {
    const chains = await loadPiChains();
    const gate = chains.gate as string[];
    expect(gate.length, "gate chain must be non-empty").toBeGreaterThan(0);
    expect(
      gate[0],
      "gate head must be the first openrouter :free model",
    ).toBe("openrouter/nvidia/nemotron-3.5-lightning:free");
    expect(
      gate,
      "gate must lead with the openrouter :free trio for limit-testing",
    ).toEqual(
      expect.arrayContaining([
        "openrouter/nvidia/nemotron-3.5-lightning:free",
        "openrouter/minimax/minimax-m3:free",
        "openrouter/thinkingmachines/inkling:free",
      ]),
    );
    expect(
      gate,
      "gate must include all five GOAT paid-pool entries after the :free trio",
    ).toEqual(
      expect.arrayContaining([
        "commandcode/gpt-5.6-luna",
        "commandcode/zai-org/GLM-5.2",
        "commandcode/nvidia/nemotron-3-ultra-550b-a55b",
        "commandcode/moonshotai/Kimi-K3",
        "commandcode/deepseek/deepseek-v4-flash",
      ]),
    );
    expect(
      gate,
      "phoenixgrove/glm-5.3-flash must still be present as manual fallback",
    ).toContain("phoenixgrove/glm-5.3-flash");
    expect(
      gate[gate.length - 1],
      "gate tail must be gemini/gemini-2.5-flash in v4",
    ).toBe("gemini/gemini-2.5-flash");
    expect(
      gate,
      "gemini-2.5-flash must be demoted to a low-tier fallback (not lead)",
    ).toContain("gemini/gemini-2.5-flash");
    expect(
      gate.indexOf("gemini/gemini-2.5-flash"),
      "gemini-2.5-flash must NOT head the gate chain",
    ).toBeGreaterThan(0);
    expect(
      gate,
      "paid Frontier glm-5.3 must not appear in the gate chain",
    ).not.toContain("phoenixgrove/glm-5.3");
  });
});
