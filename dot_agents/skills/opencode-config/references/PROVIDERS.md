# Provider & Model Catalog — MOVED

Provider and model facts (provider stack, gateway routing, BYOK mechanics,
per-provider models/pricing/quotas/quirks, rate limits, live statuses) are
owned by the `provider-catalog` skill: `~/.agents/skills/provider-catalog/references/PROVIDERS.md`.

Load `provider-catalog` when this skill needs provider/model facts. This file
previously duplicated that catalog; keep it a stub per the one-owner rule.

Opencode-specific provider mechanics that are NOT shared provider facts live
in `references/DESIGN.md` (opencode-fallback design, axi-memory design,
GPT routing across opencode prefixes, provider concurrency profiles,
retry_on_errors handling).
