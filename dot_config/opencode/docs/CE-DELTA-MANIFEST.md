# CE Delta Manifest — Local vs Upstream

**Generated**: 2026-08-04
**Upstream reference**: [EveryInc/compound-engineering-plugin](https://github.com/EveryInc/compound-engineering-plugin) @ `6a2a0f9` (MIT, 23.7K★, head 2026-08-04)
**Local**: `~/.agents/skills/ce-*` (chezmoi-tracked under `dot_agents/skills/`)
**Method**: per-skill diff of local SKILL.md + file inventory vs upstream (cloned at `/tmp/opencode/ce-upstream`)

## Verdict: 0 of 32 upstream skills are identical to local

## Triage

### 15 STRIPPED — upstream files dropped in the CE→OmO port (rebase candidates)

| Skill | Local lines | Upstream lines | Files missing | Diff lines |
|---|---|---|---|---|
| ce-brainstorm | 245 | 368 | 18 | 277 |
| ce-plan | 719 | 846 | 25 | 555 |
| ce-work | 365 | 432 | 19 | 351 |
| ce-code-review | 903 | 570 | 27 | 989 |
| ce-compound | 595 | 801 | 16 | 536 |
| ce-doc-review | 220 | 279 | 14 | 149 |
| ce-optimize | 657 | 694 | 6 | 119 |
| ce-ideate | 397 | 433 | 9 | 304 |
| ce-debug | 250 | 338 | 2 | 152 |
| ce-test-browser | 356 | 241 | 2 | 273 |
| ce-compound-refresh | 629 | 201 | 4 | 650 |
| ce-simplify-code | 84 | 77 | 4 | 95 |
| ce-resolve-pr-feedback | 47 | 67 | 6 | 58 |
| ce-setup | 164 | 148 | 1 | 170 |
| ce-riffrec-feedback-analysis | 36 | 37 | 1 | 11 |

Missing files are almost entirely `references/` + `scripts/` — upstream's progressive-disclosure architecture (e.g., ce-brainstorm's 14 references + 4 scripts). The local port stripped them; **ce-brainstorm's SKILL.md references files that don't exist locally** (dangling pointers).

### 7 MODIFIED — genuinely locally edited (no missing files; keep as documented patches or rebase per review)

`ce-commit-push-pr` (197 diff), `ce-proof` (387), `ce-test-xcode` (48), `ce-strategy` (6), `ce-product-pulse` (74), `ce-commit` (80), `ce-worktree` (92)

### 10 NOT INSTALLED — deliberate drops

`lfg` (autonomous loop — matches the no-looping priority), `ce-babysit-pr`, `ce-dogfood`, `ce-explain`, `ce-handoff`, `ce-polish`, `ce-pov`, `ce-promote`, `ce-retune`, `ce-sweep` (automation/maintenance tools)

### 14 LOCAL CUSTOMS — ce-* skills with no upstream equivalent (the OmO layer worth preserving)

`ce-workflow`, `ce-sessions`, `ce-frontend-design`, `ce-agent-native-architecture`, `ce-agent-native-audit`, `ce-slack-research`, `ce-demo-reel`, `ce-polish-beta`, `ce-dhh-rails-style`, `ce-gemini-imagegen`, `ce-release-notes`, `ce-report-bug`, `ce-clean-gone-branches`, `ce-work-beta`

## Modification history (chezmoi git attribution)

| Commit | What | Author |
|---|---|---|
| `432eae3` | Skills migration to `~/.agents/skills` — **origin of the stripped state** (references never tracked) | `glm-5.2@primary` |
| `10eb180` | ce-plan migration — merged orphaned references (config-side remnant) | `big-pickle@CabinInspiron22Kali` |
| `d1f90e4`, `2d04209` | Executable-script source naming for ce-* skills | `opencode-zen/big-pickle@primary` |
| `a6e88f9` | dispatch-rules.json birth — "build-vs-adapt Option B" (firstmate-style supervision port, 26 starter rules) | `opencode-zen/big-pickle@primary` |
| `0eec228` | MCP divestment — purged mcp-* skills + 1 dispatch rule | `opencode/claude-opus-4-7@InspironOne` |

## Recommendation

- **15 stripped** → rebase onto upstream `6a2a0f9` (restore `references/` + `scripts/`), preserving the 4-gate-core pivot (Metis→plan→build→verify) as the overlay.
- **7 modified** → review each; keep as documented patches (add `source`/`upstream_sha` frontmatter) or rebase.
- **14 customs** → the genuine OmO layer; add provenance frontmatter.
- **10 dropped** → leave dropped; `lfg` aligns with the no-looping priority.
- **Attribution discipline going forward**: every absorbed skill gets an ADR/README credit (upstream silently absorbed finding-unknowns' blindspot-pass without credit — counter-pattern established in `~/.agents/MVP-README.md`).
