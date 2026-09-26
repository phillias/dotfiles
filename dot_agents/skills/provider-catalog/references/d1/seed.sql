INSERT INTO models(provider, model, display_name, context_tokens, price_input_per_m, price_output_per_m, free_tier, status, status_source, status_updated_at, notes) VALUES
  ('custom-opencode-zen','mimo-v2.5-free','MiMo V2.5 Free',131072,NULL,NULL,1,'degraded','live probe + opencode run 2026-09-25','2026-09-25T16:05:00Z','Free tier requires OpenCode client context. Direct API calls: 403 FreeTierError. Call from inside OpenCode on 2026-09-25: accepted but rate-limited.'),
  ('custom-opencode-zen','glm-5.1','GLM 5.1',NULL,NULL,NULL,0,'unknown',NULL,NULL,NULL),
  ('custom-opencode-zen','glm-5.2','GLM 5.2',NULL,NULL,NULL,0,'unknown',NULL,NULL,NULL),
  ('custom-opencode-zen','glm-5.3-flash','GLM 5.3 Flash',NULL,NULL,NULL,0,'unknown',NULL,NULL,NULL),
  ('custom-commandcode','zai-org/GLM-5.1','Command Code GLM 5.1',NULL,NULL,NULL,0,'unknown',NULL,NULL,NULL),
  ('custom-phoenixgrove','glm-5.2','Phoenixgrove GLM 5.2',NULL,NULL,NULL,0,'unknown',NULL,NULL,NULL),
  ('custom-commandcode','zai-org/GLM-5.2','Command Code GLM 5.2',NULL,NULL,NULL,0,'unknown',NULL,NULL,NULL),
  ('custom-commandcode','z-ai/glm-5.3-flash','Command Code GLM 5.3 Flash',NULL,NULL,NULL,0,'unknown',NULL,NULL,NULL),
  ('custom-phoenixgrove','glm-5.3-flash','Phoenixgrove GLM 5.3 Flash',NULL,NULL,NULL,0,'unknown',NULL,NULL,NULL),
  ('openrouter','z-ai/glm-5.1','Z-AI GLM 5.1',NULL,NULL,NULL,0,'ok','live probe 2026-09-25','2026-09-25T16:05:00Z','Served dynamic/TUI successfully after upstream fallback.'),
  ('openrouter','stealth/space-bunny-alpha','Space Bunny Alpha',1000000,NULL,NULL,1,'quarantined','captain decision 2026-09-25','2026-09-25T16:05:00Z','Removed from CfAiGw dynamic/TUI and Vercel vmc/tui on 2026-09-25 after captain-reported tangents, unrelated topics, and tool misuse. Do not re-add without explicit captain approval.')
ON CONFLICT(provider, model) DO UPDATE SET
  display_name=excluded.display_name,
  context_tokens=COALESCE(excluded.context_tokens, models.context_tokens),
  free_tier=excluded.free_tier,
  status=excluded.status,
  status_source=excluded.status_source,
  status_updated_at=excluded.status_updated_at,
  notes=excluded.notes;

INSERT INTO routes(gateway, route, active_version, deployed_at, updated_at, notes) VALUES
  ('cloudflare-ai-gateway','dynamic/TUI','cce0c37c-48dd-44a3-aa7e-e0739abcd85c','2026-09-25T14:08:36Z','2026-09-25T16:05:00Z','Space-bunny removed as head on 2026-09-25; START now routes to mimo-v2.5-free.'),
  ('vercel-ai-gateway','vmc/tui',NULL,NULL,'2026-09-25T16:05:00Z','Space-bunny removed as head on 2026-09-25; six-model ladder retained.')
ON CONFLICT(gateway, route) DO UPDATE SET
  active_version=excluded.active_version,
  deployed_at=excluded.deployed_at,
  updated_at=excluded.updated_at,
  notes=excluded.notes;

INSERT INTO route_models(gateway, route, position, provider, model, notes) VALUES
  ('cloudflare-ai-gateway','dynamic/TUI',1,'custom-opencode-zen','mimo-v2.5-free',NULL),
  ('cloudflare-ai-gateway','dynamic/TUI',2,'custom-opencode-zen','glm-5.1',NULL),
  ('cloudflare-ai-gateway','dynamic/TUI',3,'custom-opencode-zen','glm-5.2',NULL),
  ('cloudflare-ai-gateway','dynamic/TUI',4,'custom-opencode-zen','glm-5.3-flash',NULL),
  ('cloudflare-ai-gateway','dynamic/TUI',5,'custom-commandcode','zai-org/GLM-5.1',NULL),
  ('cloudflare-ai-gateway','dynamic/TUI',6,'custom-phoenixgrove','glm-5.2',NULL),
  ('cloudflare-ai-gateway','dynamic/TUI',7,'custom-commandcode','zai-org/GLM-5.2',NULL),
  ('cloudflare-ai-gateway','dynamic/TUI',8,'custom-commandcode','z-ai/glm-5.3-flash',NULL),
  ('cloudflare-ai-gateway','dynamic/TUI',9,'custom-phoenixgrove','glm-5.3-flash',NULL),
  ('cloudflare-ai-gateway','dynamic/TUI',10,'openrouter','z-ai/glm-5.1',NULL),
  ('vercel-ai-gateway','vmc/tui',1,'alibaba','qwen3.7-flash',NULL),
  ('vercel-ai-gateway','vmc/tui',2,'deepseek','deepseek-v4-flash-0731',NULL),
  ('vercel-ai-gateway','vmc/tui',3,'zai','glm-5.3-flash',NULL),
  ('vercel-ai-gateway','vmc/tui',4,'openai','gpt-5-nano',NULL),
  ('vercel-ai-gateway','vmc/tui',5,'google','gemini-2.5-flash-lite',NULL),
  ('vercel-ai-gateway','vmc/tui',6,'openai','gpt-4o-mini',NULL)
ON CONFLICT(gateway, route, position) DO UPDATE SET
  provider=excluded.provider,
  model=excluded.model,
  notes=excluded.notes;

INSERT INTO observations(ts, kind, subject, metric, value_num, value_text, source, details) VALUES
  ('2026-09-25T14:10:00Z','availability','route:cloudflare-ai-gateway/dynamic/TUI','availability',1,'ok','live probe','Served z-ai/glm-5.1 after mimo head failed; HTTP 200.'),
  ('2026-09-25T15:55:51Z','availability','model:custom-opencode-zen/mimo-v2.5-free','availability',0,'rate_limited','opencode run','OpenCode-internal call accepted free-tier context but returned rate limit exceeded.'),
  ('2026-09-25T15:50:00Z','availability','model:custom-opencode-zen/mimo-v2.5-free','availability',0,'free_tier_context_required','direct API probe','403 FreeTierError: OpenCode''s free tier can only be used from within OpenCode.'),
  ('2026-09-25T14:12:00Z','availability','route:vercel-ai-gateway/vmc/tui','availability',1,'ok','live probe','HTTP 200 after space-bunny removal.'),
  ('2026-09-25T00:00:00Z','quality','model:openrouter/stealth/space-bunny-alpha','quality',NULL,'unusable_interactive','captain report','Captain-reported tangents, unrelated topics, and tool misuse; quarantined from interactive TUI routes.');
