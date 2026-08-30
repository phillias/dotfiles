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
  cloudflare: { baseURL: string; models: Record<string, unknown> };
}> {
  const raw = await readFile("../opencode.json", "utf-8");
  const cfg = JSON.parse(raw);
  const cf = cfg.provider?.cloudflare;
  if (!cf?.models)
    throw new Error("cloudflare provider missing models registry");
  return {
    cloudflare: { baseURL: cf.options?.baseURL ?? "", models: cf.models },
  };
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

describe("cloudflare gateway model-id prefix contract", () => {
  test("every cloudflare fallback reference resolves to a registered model", async () => {
    const reg = await loadProviderRegistry();
    const fb = await loadFallbackConfig();
    const refs = collectModelRefs(fb).filter((m) =>
      m.startsWith("cloudflare/"),
    );
    expect(refs.length).toBeGreaterThan(0);

    for (const ref of refs) {
      // parseModel splits on the FIRST slash — exactly what the fallback plugin
      // does before handing modelID to the provider as the on-wire id.
      const { providerID, modelID } = parseModel(ref);
      expect(providerID).toBe("cloudflare");
      const registered = Object.keys(reg.cloudflare.models);
      expect(
        registered,
        `cloudflare model registry must contain ${modelID}`,
      ).toContain(modelID);
    }
  });

  test("every @cf/ on-wire id keeps the workers-ai namespace-free native form", async () => {
    const fb = await loadFallbackConfig();
    const refs = collectModelRefs(fb).filter((m) => m.includes("@cf/"));
    for (const ref of refs) {
      // The on-wire id (after the provider split) must be the bare Workers AI id.
      const { modelID } = parseModel(ref);
      expect(
        modelID,
        `${ref} → modelID "${modelID}" must be a bare @cf/ id`,
      ).toMatch(/^@cf\//);
      expect(modelID).not.toMatch(/^workers-ai\//);
    }
  });

  test("cloudflare provider points at the native Workers AI REST endpoint", async () => {
    const reg = await loadProviderRegistry();
    expect(reg.cloudflare.baseURL).toMatch(/\/ai\/v1$/);
  });

  test("resolveChain emits prefixed cloudflare ids that resolve to the registry", async () => {
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
