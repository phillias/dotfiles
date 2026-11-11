# issue-automation

Automated GitHub issue triage and implementation workflow for agents. Load when triaging, implementing, or working with GitHub issues in an automated workflow.

## Quick reference

```
issue-work <number>                          # triage + implement if confidence >= 95
issue-work triage <number> --dry-run         # triage only, no mutations
issue-work list --repo owner/name --untriaged # list untriaged issues
issue-work comment <number> --body "text"    # post a comment
```

## Flow

### 1. Triage (always runs first)

```
issue-work triage <number> -R owner/name --dry-run
```

This classifies the issue, estimates confidence, and outputs structured triage. Use `--dry-run` first for safety.

Read the output. If confidence < threshold (default 95):
- Review the blockers listed
- If you can clarify the issue (ask the author, check linked PRs/docs), do so
- Re-run triage after gathering more context
- Post findings as a comment if helpful

If confidence >= threshold, proceed to implementation.

### 2. Implementation (confidence >= 95 only)

Follow this flow, adapted from the `lfg` skill:

1. **Branch**: `git checkout -b issue-<number>-<slug>` (use the branch name from triage output)
2. **Explore**: read the codebase to understand the change needed
3. **Implement**: make minimal, correct changes
4. **Verify**: run lint, typecheck, tests
5. **PR**: open a pull request with a description referencing `Closes #<number>`
6. **Stop**: captain reviews and merges — no auto-merge

Single-issue branches: one issue = one branch = one PR. Never mix.

### 3. Fleet repos (swarm-runbook enhancements)

When the target repo is fleet-managed (dotfiles, fleetdeck, etc.), apply swarm-runbook conventions:

- **Sync-freeze**: check for active fleet operations before modifying host configs
- **FLEET_NODE**: use `$FLEET_NODE` in attestation comments (not `hostname -s`)
- **Staggered deployment**: changes that touch fleet host configs deploy via `chezmoi apply` on each host
- **Per-host verification**: verify on each host after deployment

### 4. Post-implementation

- Post verification results as a comment on the issue
- Include: what was changed, how it was verified, any findings
- Do NOT close the issue — captain closes after review

## Confidence rubric

The `issue-work` CLI estimates confidence from issue content. As an agent, you can override the CLI's estimate if you have additional context (e.g. you know the codebase well, or you've already explored the relevant code).

**Override up**: if you've already explored the code and are confident you can implement correctly, bump confidence (e.g. CLI says 88 but you've read the relevant module and the fix is obvious → proceed).

**Override down**: if the CLI says >= 95 but you see a pitfall it missed (security, fleet impact, cross-repo dependency), treat it as below threshold and triage-only.

## Guardrails

- **PR required**: never push to the default branch
- **Single-issue branches**: one issue per branch/PR
- **Captain approval for**: closing issues, applying labels, breaking changes, security-sensitive code
- **Dry-run first**: always `--dry-run` on first pass
- **No auto-close**: captain closes issues manually after merge
- **No auto-label in MVP**: suggest labels in triage output but don't apply them

## When to escalate

Escalate to captain when:
- The issue touches security-sensitive code (auth, secrets, networking)
- A breaking change is required
- Multi-repo coordination is needed
- The fix requires external API changes
- Confidence is borderline (90–94) and the area is unfamiliar

## Integration with other skills

| Skill | Use |
|---|---|
| `gh-axi` | All GitHub API access (issue CRUD, comments, PRs) |
| `lfg` | Implementation engine — same branch→implement→PR flow |
| `swarm-runbook` | Fleet-slice conventions when repo is fleet-managed |
| `no-mistakes` | PR review gate (recommended but not required in MVP) |
| `dotfiles` | When target is phillias/dotfiles — use dotfiles commit/PR flow |
