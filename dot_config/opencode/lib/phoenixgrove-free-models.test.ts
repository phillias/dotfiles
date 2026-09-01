import { describe, expect, test } from "bun:test";
import { readFile } from "node:fs/promises";
import {
  stripJsonc,
  entryModel,
  resolveChain,
} from "./opencode-runtime-fallback-core";

// This test exercises the REAL declarative config artifacts (opencode.json,
// opencode-fallback.jsonc, private_dot_pi/private_agent/models.json) through
// the real consumer's parser functions (stripJsonc / resolveChain) — the same
// pipeline the opencode-runtime-fallback.ts plugin and the pi gate agent use
// at runtime.
//
// Intent under test (branch fm/glm51-interactive-ladder): the opencode
// interactive chains are unified on the GLM-5.1 ladder
// (big-pickle → opencode-go/glm-5.1 → commandcode/zai-org/GLM-5.2 →
// openrouter/z-ai/glm-5 → opencode-zen/glm-5.1). PGS, Cloudflare Workers, and
// the openrouter :free trio are retired from the opencode interactive ladders
// (PGS burns Coding Plan credits; CF @cf excluded by captain; the :free trio
// is GATE-chain-only via private_dot_pi/fallback-chains.json and is NOT asserted
// here). The pi gate chain is unchanged by this branch. Phoenix Grove is still
// registered as a provider in opencode.json (the phoenixgrove provider config
// tests below are kept as the gateway indirection contract for the no-mistakes
// gate), but no opencode chain selects it.

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

describe("opencode-fallback.jsonc chains run the GLM-5.1 ladder, no PGS", () => {
  const GLM_5_1_LADDER = [
    "opencode-zen/big-pickle",
    "opencode-go/glm-5.1",
    "commandcode/zai-org/GLM-5.2",
    "openrouter/z-ai/glm-5",
    "opencode-zen/glm-5.1",
  ] as const;

  test("global ladder is exactly the GLM-5.1 ladder", async () => {
    const fb = await loadFallbackConfig();
    const globalChain = resolveChain(fb, undefined).map(entryModel);
    expect(globalChain, "global ladder must be the GLM-5.1 ladder").toEqual([
      ...GLM_5_1_LADDER,
    ]);
  });

  test("utility agent and category chains contain the GLM-5.1 ladder", async () => {
    const fb = await loadFallbackConfig();
    for (const ag of ["general", "explore"]) {
      const chain = resolveChain(fb, ag).map(entryModel);
      for (const step of GLM_5_1_LADDER) {
        expect(
          chain,
          `${ag} agent chain must contain ${step}`,
        ).toContain(step);
      }
    }
    for (const cat of ["quick", "unspecified-low"]) {
      const chain = resolveChain(fb, cat).map(entryModel);
      for (const step of GLM_5_1_LADDER) {
        expect(
          chain,
          `${cat} category chain must contain ${step}`,
        ).toContain(step);
      }
    }
  });

  test("no opencode chain references phoenixgrove (PGS is GATE-chain-only)", async () => {
    const fb = await loadFallbackConfig();
    const refs = collectModelRefs(fb);
    const pgs = refs.filter((m) => m.startsWith("phoenixgrove/"));
    expect(
      pgs,
      "no opencode chain may select a phoenixgrove model",
    ).toEqual([]);
  });

  test("no opencode chain references the Cloudflare Workers @cf namespace", async () => {
    const fb = await loadFallbackConfig();
    const refs = collectModelRefs(fb);
    const cf = refs.filter((m) => m.startsWith("cloudflare/@cf/"));
    expect(
      cf,
      "no opencode chain may select a Cloudflare Workers @cf model",
    ).toEqual([]);
  });
});

describe("pi provider registry mirrors the gateway + free flash contract", () => {
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
});
