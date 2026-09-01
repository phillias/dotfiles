import { describe, expect, test } from "bun:test";
import { readFile } from "node:fs/promises";
import {
  parseModel,
  stripJsonc,
  entryModel,
  resolveChain,
} from "./opencode-runtime-fallback-core";

// Load the real opencode.json provider registry.
async function loadProviderRegistry(): Promise<{
  cloudflare: {
    baseURL: string;
    headers: Record<string, string>;
    models: Record<string, unknown>;
  };
}> {
  const raw = await readFile("../opencode.json", "utf-8");
  const cfg = JSON.parse(raw);
  const cf = cfg.provider?.cloudflare;
  if (!cf?.models)
    throw new Error("cloudflare provider missing models registry");
  return {
    cloudflare: {
      baseURL: cf.options?.baseURL ?? "",
      headers: cf.options?.headers ?? {},
      models: cf.models,
    },
  };
}

// Load all gateway-routed providers from opencode.json.
async function loadGatewayProviders(): Promise<
  Record<
    string,
    { baseURL: string; apiKey: string; models: Record<string, unknown> }
  >
> {
  const raw = await readFile("../opencode.json", "utf-8");
  const cfg = JSON.parse(raw);
  const ids = [
    "opencode-zen",
    "opencode-go",
    "commandcode",
    "zai-coding",
    "openrouter",
  ];
  const out: Record<
    string,
    { baseURL: string; apiKey: string; models: Record<string, unknown> }
  > = {};
  for (const id of ids) {
    const prov = cfg.provider?.[id];
    if (!prov?.models)
      throw new Error(`${id} provider missing models registry`);
    out[id] = {
      baseURL: prov.options?.baseURL ?? "",
      apiKey: prov.options?.apiKey ?? "",
      models: prov.models,
    };
  }
  return out;
}

// Load the real fallback config (JSONC).
async function loadFallbackConfig() {
  const raw = await readFile("../opencode-fallback.jsonc", "utf-8");
  return JSON.parse(stripJsonc(raw));
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
          else if (e && typeof e === "object" && typeof e.model === "string")
            out.push(e.model);
        }
      }
      Object.values(rec).forEach(visit);
    }
  };
  visit(o);
  return out;
}

describe("cloudflare AI Gateway REST API provider contract", () => {
  test("no fallback chain references the cloudflare provider (CF @cf excluded by captain)", async () => {
    const fb = await loadFallbackConfig();
    const refs = collectModelRefs(fb).filter((m) =>
      m.startsWith("cloudflare/"),
    );
    expect(
      refs,
      "no chain may select a cloudflare/ model after the CF drop",
    ).toEqual([]);
  });

  test("cloudflare ids are bare @cf/ (the /compat workers-ai/ prefix scheme is gone)", async () => {
    const reg = await loadProviderRegistry();
    const fb = await loadFallbackConfig();

    // On the REST API, Workers AI model ids MUST be bare @cf/... — the
    // deprecated /compat endpoint required the workers-ai/ namespace prefix,
    // but REST rejects it. Guard against any reintroduction of either mistake.
    for (const key of Object.keys(reg.cloudflare.models)) {
      expect(key, `registry key "${key}" must match ^@cf/`).toMatch(/^@cf\//);
      expect(
        key,
        `registry key "${key}" must not carry workers-ai/`,
      ).not.toContain("workers-ai/");
    }

    const refs = collectModelRefs(fb).filter((m) => m.includes("@cf/"));
    for (const ref of refs) {
      const { modelID } = parseModel(ref);
      expect(modelID, `${ref} → modelID "${modelID}" must match ^@cf/`).toMatch(
        /^@cf\//,
      );
      expect(
        modelID,
        `${ref} → modelID "${modelID}" must not carry workers-ai/`,
      ).not.toContain("workers-ai/");
    }
  });

  test("cloudflare provider points at the AI Gateway REST API with the gateway header", async () => {
    const reg = await loadProviderRegistry();
    expect(reg.cloudflare.baseURL).toMatch(/\/ai\/v1$/);
    expect(reg.cloudflare.baseURL).not.toContain("/compat");
    // Workers AI on the REST API requires the gateway header: without it,
    // requests bypass the named gateway's analytics, caching, and spend cap.
    expect(
      reg.cloudflare.headers["cf-aig-gateway-id"],
      "options.headers['cf-aig-gateway-id']",
    ).toBeTruthy();
  });

  test("resolveChain emits bare @cf/ cloudflare ids that resolve to the registry", async () => {
    const reg = await loadProviderRegistry();
    const fb = await loadFallbackConfig();
    const registered = Object.keys(reg.cloudflare.models);

    // Exercise resolveChain for a representative set of configured agent keys.
    const agentKeys = Object.keys({
      ...(fb.agents ?? {}),
      ...(fb.categories ?? {}),
    });
    expect(agentKeys.length).toBeGreaterThan(0);
    for (const key of agentKeys) {
      const chain = resolveChain(fb, key).map(entryModel);
      for (const m of chain.filter((id) => id.startsWith("cloudflare/"))) {
        const { modelID } = parseModel(m);
        expect(registered, `resolveChain produced unresolvable ${m}`).toContain(
          modelID,
        );
      }
    }
  });
});

describe("gateway-routed provider contract (BYOK through gateway 'opencode')", () => {
  const gatewayProviderIds = [
    "opencode-zen",
    "opencode-go",
    "commandcode",
    "zai-coding",
    "openrouter",
  ];
  const gatewayTokenFile = "{file:~/.config/opencode/.cf-ai-gw-token}";
  const perProviderKeyFiles = [
    ".zen-key",
    ".opencode-key",
    ".command-code.key",
    ".zai-key",
    ".openrouter-key",
  ];

  test("every gateway-routed provider has a gateway.ai.cloudflare.com baseURL", async () => {
    const providers = await loadGatewayProviders();
    for (const id of gatewayProviderIds) {
      const url = providers[id].baseURL;
      expect(url, `${id} baseURL must match gateway pattern`).toMatch(
        /^https:\/\/gateway\.ai\.cloudflare\.com\/v1\//,
      );
    }
  });

  test("custom-slug providers use /opencode/custom- prefix; openrouter uses /opencode/openrouter", async () => {
    const providers = await loadGatewayProviders();
    for (const id of gatewayProviderIds) {
      const url = providers[id].baseURL;
      if (id === "openrouter") {
        expect(url, `${id} must use native passthrough slug`).toContain(
          "/opencode/openrouter",
        );
        expect(url, `${id} must NOT use custom- prefix`).not.toContain(
          "/opencode/custom-openrouter",
        );
      } else {
        expect(url, `${id} must use custom- slug`).toContain(
          "/opencode/custom-",
        );
      }
    }
  });

  test("apiKey is the gateway token file indirection with no per-provider key", async () => {
    const providers = await loadGatewayProviders();
    for (const id of gatewayProviderIds) {
      const key = providers[id].apiKey;
      expect(key, `${id} apiKey must be the gateway token file`).toBe(
        gatewayTokenFile,
      );
      for (const kf of perProviderKeyFiles) {
        expect(key, `${id} apiKey must not contain ${kf}`).not.toContain(kf);
      }
    }
  });

  test("version segment: custom slugs end /v1, zai-coding ends /v4", async () => {
    const providers = await loadGatewayProviders();
    for (const id of gatewayProviderIds) {
      const url = providers[id].baseURL;
      if (id === "zai-coding") {
        expect(url, `${id} baseURL must end with /v4`).toMatch(/\/v4$/);
      } else {
        expect(url, `${id} baseURL must end with /v1`).toMatch(/\/v1$/);
      }
    }
  });
});
