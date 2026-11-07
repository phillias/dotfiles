---
name: swarm-runbook
description: Fleet swarm coordination runbook for GitHub-issue-driven multi-node work. Load when creating or triaging issues in fleet repos (phillias/dotfiles, phillias/selfhost), kickstarting a cross-node workstream, posting a node audit/attestation, classifying a newly found problem, or closing a node slice.
---

# swarm-runbook

Coordination contract for fleet swarm activities (bws migration, sslh retirement,
firstmate/no-mistakes/herdr upgrades, …). Refined 2026-11-07 from a full
classification of every open/recent issue in dotfiles + selfhost.

## Core principle

The repo is the desired state. Issues coordinate; git decides. Desired-state
changes go through PRs only — never issue consensus. Take as little human
(captain) attention as possible: speak when a person must act or can use a
result; one concrete question at a time.

## Issue classes (assign exactly one at creation)

| Class | Meaning | Label |
|---|---|---|
| EXECUTION | Workstream ledger: goal + node slices + checkboxes + completion criteria | `swarm/execution` |
| DECISION | Policy/design question; resolves via PR to the repo, not thread debate | `swarm/decision` |
| DEFECT | Adjacent defect: standalone but must be linked to its owning workstream | `swarm/defect` |
| INVESTIGATION | Time-boxed one-off diagnostic; findings fold into a workstream, follow-ups become linked issues, then close | `swarm/investigation` |
| PARKED | Idea/observation, explicitly no-action-now | `swarm/parked` |

Classification is a first-class field, not prose inference. Reclassification is
captain-only. Scope-creep control: every newly discovered problem gets exactly
one of these labels inside the audit comment that discovered it, same turn.

## Charter (every EXECUTION issue, in the body)

```markdown
## Goal
<one paragraph, testable>

## Desired state ref
<file/PR in the repo that defines target state, e.g. docs/selfhost-bws-migration.md @ master>

## Node matrix
| Node | Arch | Role | Variance | Slice |
|---|---|---|---|---|
| primary | ARM64 | anchor dockhand | live checkout ~/firstmate/projects/selfhost | [state] |
| kali    | AMD64 | edge | sslh demux; live setup.sh may lag master | [state] |
| kalione | AMD64 | edge | | [state] |
| oci1    | ARM64 | edge, greenfield | no-sslh ET pattern; new node — confirm doc covers it | [state] |

## Completion criteria
- [ ] <criterion per node slice + fleet-wide criterion>

## Captain gates
- Canary: <node>, validated by captain before leg 1 (see "Canary node")
<merges / rotations / reclassifications that require explicit captain word>

## Findings parking lot
<one line each; promoted issues link back here>
```

The node matrix is mandatory on any multi-node execution issue — fleet
variance (arch, role, stale-checkout, greenfield) is load-bearing in every
multi-node issue to date and must be structural, not prose.

## Node audit / attestation comment (fixed format)

```markdown
### Node audit — <node> — <ISO date>Z
| Claim | Verdict | Evidence (fingerprint-only) |
|---|---|---|
| <live state == vault/repo state for X> | MATCH/MISMATCH | sha256 prefix ab12cd34… |
Divergences: <each mismatch = finding with one of the taxonomy labels>
Next actions: <what this node does next, or BLOCKED: <reason>>
```

Rules: fingerprint-only (sha256 prefixes, never secret values); append-only —
corrections are new comments; closure of a node slice requires its attestation
comment plus any reboot/verification test named in the completion criteria.

## Decision issues

A decision resolves by merging a PR (or recording an ADR/decision doc in the
repo), not by comment consensus. The decision issue states the question,
options, and the ruling; the PR is the artifact. Known inline-violation
patterns to avoid: naming policy settled in an execution thread (selfhost#93),
captain rulings with no decision record (selfhost#99 attic role), agreed-path
recorded only in a closed execution issue (dotfiles#486).

## Canary node (first leg)

Every multi-node execution workstream starts on exactly one **canary node**:
the first leg proves the work is sound before any other node begins. The
canary is chosen by a **fleet suitability evaluation**, recorded in the
charter beside the node matrix.

Suitability evaluation (write the conclusion into the charter, one line per
factor):

- **Representativeness** — the canary should exercise the change's main
  variance axes (arch, role) without being the hardest case. If the fleet
  splits ARM64/AMD64, the canary proves one arch and the matrix names the
  follow-up leg that proves the other.
- **Blast radius** — edges before the anchor. The anchor dockhand (primary)
  runs last unless the change is anchor-only; a failed leg on an edge is
  cheaper than on the node every other node depends on.
- **Greenfield vs load-bearing** — a greenfield node (e.g. oci1) is a cheap
  canary for greenfield work; a node carrying live traffic is a canary only
  for the class of work it actually hosts.
- **Peripheral work in flight** — a node may be running other work at the
  captain's behest. The evaluation must check current holds and active
  slices (open workstream issues, watcher holds, captain-directed side
  work) for each candidate. A node with in-flight peripheral work is canary
  only if the captain validates the collision risk; that validation is the
  canary captain gate below.

**Captain gate:** the canary choice is captain-validated at charter creation
or before leg 1 starts. No node begins work on the workstream until that
gate is explicit in the issue.

**Canary completion contract:** the canary runs the full slice end-to-end:
apply, timed validation probes, the external peer probe (see cross-node
verification), and a reboot/restart test where the work affects units; then
it posts its attestation. Only then does leg 2 start.

**Canary failure:** if canary validation fails, the critical-path rules
apply (rollback, `HOLD` comment, captain-gated lift). If the failure looks
node-specific rather than work-specific, re-run the suitability evaluation
and pick a different canary before retrying — do not retry the same node
blind.

## Outliers and special handling

- **Bug/defect discovered mid-work** → `swarm/defect` issue, linked to the
  workstream, noted in the parking lot. Do not bury it in a comment on an
  issue that may close (the kali hawser gap nearly died inside selfhost#98).
- **One-off investigation** (e.g. selfhost#98) → allowed as its own issue;
  must name where findings land and move follow-ups out before closing.
- **Non-deterministic changes** (probes, live-state captures, reboot tests)
  → allowed anywhere, but the evidence rule tightens: capture timestamps,
  command output excerpts, and fingerprints; never claim state without the
  command that observed it.
- **Thin backlog cards** (single checkbox, no charter) → acceptable intake
  state; promote to charter format before work starts, or absorb into an
  existing workstream (as selfhost#75/#76 folded into dotfiles#502).
- **Cross-repo workstreams** → the canonical ledger lives in the repo that
  owns the desired state; fragments in the other repo are cross-linked and
  must not carry their own checkboxes for the same slice.
- **Fleet variances** (arch/role/staleness): never assume a procedure is
  node-uniform. ARM64 vs AMD64 package/distro differences (e.g. netdata noble
  vs focal, selfhost#109), anchor vs edge roles, greenfield nodes without a
  migration baseline, and per-node `__<server>` key suffixes all require the
  node matrix row to state the variance explicitly.

## Risk tiers: critical access paths

Services whose failure locks out the fleet or a node — ssh, Eternal Terminal,
cloudflared/tunnels, godoxy (reverse proxy), and any loader/key change that
gates agent access itself — are **critical-path changes** and get extra
process, always:

1. **Rollback snapshot before the change.** Capture the exact revert unit:
   previous config file(s) copied aside, previous binary/version pinned
   (mise/mise-shim or package version), previous systemd unit state. A
   rollback you cannot execute from the snapshot is not a rollback plan.
2. **Per-node sequencing.** One node at a time, never fleet-wide (exemplar:
   selfhost#88 kalione → kali → primary with captain GO before each leg).
   The node currently holding a validation hold blocks the queue.
3. **Timed validation window.** Name it in the charter per critical-path leg
   (e.g. 15–30 min from apply). Validation = concrete probes (tunnel up +
   route reachable, ET session established, ssh round-trip), not "looks fine".
4. **Failed validation → timed rollback, then HOLD.** If probes fail inside
   the window, roll back to the snapshot immediately (do not debug on the
   broken state). After rollback, post a `HOLD` comment on the workstream
   issue naming the node, the failed probe, and the rollback evidence. A hold
   is captain-gated to lift; while any hold is open, **no other node may
   start a critical-path change** in the same workstream.
5. **Silent-failure guard.** The hold comment is the miss-prevention
   mechanism, but the validating agent must also re-probe once after rollback
   and post restoration evidence — a rollback that did not restore access is
   itself an emergency, not a hold.

## Secrets discipline

Never post secret values in issues, comments, or commits. Evidence is
fingerprints (sha256 prefix), counts, and HTTP status codes. Rotations are
captain-gated per batch; the procedure is: edit vault secret → re-render via
setup.sh with the node's ENV_FILE → recreate affected services → attestation.

## Communication economy

- Confirm once, name what you will do, stay quiet while working, report when
  a result is ready or a decision is needed.
- Short messages in the thread where the request was made.
- Report honestly: a draft says unfinished; a failure says failure; a limit
  is never bypassed to avoid asking.
- A design decision stops work with one concrete question; do not guess.

## Closure

A workstream closes when: every node slice has an attestation, every checkbox
in completion criteria is checked, every parking-lot item is either a linked
issue or explicitly dropped by the captain, and a terminal summary comment
exists per node. Retirement sweeps (old secrets/projects) come last, after
all dependent issues close.

## GitHub mechanics

- Use repo issue templates (see `.github/ISSUE_TEMPLATE/` YAML forms) when
  present; they front-load class, node matrix, and variance fields.
- Labels are the machine-readable classification surface; the `swarm/*`
  vocabulary above should exist in both fleet repos.
- Agent-created issues follow these templates even when using `gh issue
  create --body` directly.

## Verification phases: cross-node third-party verification

Multi-phase verification in a workstream ledger mixes two probe classes:

1. **In-node check** — the node under test probes itself (local config,
   unit state, rendered files). Required, but shares blind spots with the
   thing it verifies: local DNS cache, `/etc/hosts`, localhost shortcuts,
   ambient env, session state.
2. **External probe** — a *different* fleet node verifies from outside over
   the mesh: DNS resolution of the target's names, HTTP status/route checks,
   fetching and rendering an artifact (page loads, cert served, correct
   backend answered). This proves what an outside client sees, which an
   in-node check structurally cannot.

Rules:

- The verifier is a different fleet node than the node under test; name both
  in the attestation (`probe from <peer> → <target>`).
- Probes are unauthenticated where possible (DNS, HTTP status, TLS subject,
  artifact bytes). No secrets ever travel to the verifier; tokens stay on
  the node under test. If a check needs auth, the node under test performs
  it and the peer verifies only the observable outside surface.
- Probe command + output land in the fixed-format attestation comment of the
  node under test's slice, fingerprint-only where values could be sensitive.
- A verification phase completes only when both classes pass; the ledger
  tracks them as separate checkboxes: `[ ] in-node check (node)` and
  `[ ] external probe (peer)`.
- One peer per probe. Do not fan a single probe out to every node — that is
  noise, not verification.

## Node-to-node messaging policy

Default: **no direct node-to-node messaging for swarm work.** The issue
ledger is the only decision and record surface; untracked channels create
shadow state that no audit, attestation, or closure rule can see.

- Coordination traffic goes through tracked paths: issue comments, firstmate
  steering (`fm-send.sh` through the owning firstmate), or watcher wakes.
- If fleet-chat (dotfiles#508) later lands, it is **transport, not record**:
  any decision, assignment, or finding that arises in chat must be posted to
  the owning issue in the same turn, or it did not happen.
- The one sanctioned direct node↔node exchange is a verification probe
  request (section above) — and both the request and its result must land as
  issue comments to count.

## Classification enforcement (no-memory guarantee)

Classification must never depend on an agent remembering to do it.

- **At creation (structural):** issue templates with blank issues disabled
  mean every new issue is classified as it is filed. Nothing to remember.
- **For the existing backlog (mechanical lint):** `swarm-lint.sh` (this
  skill's directory) lists open issues carrying no `swarm/*` label that show
  work activity (assignee, or ≥2 comments). Those are thin cards being
  picked up without promotion — promote them to a charter before starting
  work. The script is silent when conforming, so it doubles as an fm-check
  script: registered on a node's watcher it wakes only on violations.
- Run the lint at task intake on any fleet issue you are about to touch, and
  keep a scheduled run on one node (see firstmate check registration).
