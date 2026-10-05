# Live evidence — chore/test-timeout-25m (test_agent_timeout 12m -> 25m)

Product: no-mistakes v1.84.0 (mise-managed binary). The change edits
dot_no-mistakes/config.yaml (applies to ~/.no-mistakes/config.yaml via chezmoi)
and the provider-catalog Budgets reference doc.

## 1. Applied artifact via the end-user pathway (scoped chezmoi apply, disposable home)

    HOME=/tmp/nmtest.JyDzx3/czhome chezmoi --source <worktree> apply --source-path dot_no-mistakes/config.yaml
    -> /tmp/nmtest.JyDzx3/czhome/.no-mistakes/config.yaml  (10567 bytes)
    review_agent_timeout: "12m"
    test_agent_timeout: "25m"
    comment: "(2026-10-04, later) test_agent_timeout raised 12m -> 25m: two consecutive
             glm-headed test drives were cut at 12m while ACTIVELY working ... review_agent_timeout stays 12m"

## 2. Real consumer (daemon) accepts the changed config; parses the exact key

Negative control (poisoned value at the same key, same file path):
    no-mistakes daemon run --root /tmp/.../live   # root/config.yaml has test_agent_timeout: "not-a-duration"
    > load config: parse test_agent_timeout "not-a-duration": time: invalid duration "not-a-duration"
    > exit 1
=> the daemon reads and duration-parses test_agent_timeout from the config path this change edits.

Positive (this change's applied config):
    no-mistakes daemon run --root /tmp/.../live   # root/config.yaml = chezmoi-applied change artifact
    -> daemon stays up serving (killed after probe); NM_HOME=<root> no-mistakes daemon status -> "daemon running"

## 3. Typed semantic parse (Go time.ParseDuration — same parser as the consumer)

    test_agent_timeout = 25m -> 25 minutes
    review_agent_timeout = 12m -> 12 minutes
    ASSERT: test=25m (25 min), review=12m (12 min) — OK

## 4. Doc/diff consistency

- git diff base..target touches exactly 2 files: dot_no-mistakes/config.yaml, NO_MISTAKES_MODELS.md.
- Budgets section (line 48): review 12m; test 25m; both were 60m until 2026-10-04; test raised 12m->25m same day.
  Matches the applied config (test 25m / review 12m). Reference doc has no runtime consumer (agent-read natural-language
  reference), so this claim is verified by cross-check against the live-applied config.
