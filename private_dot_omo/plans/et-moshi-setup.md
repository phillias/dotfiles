# et-moshi-setup - Work Plan

## TL;DR (For humans)

**What you'll get:** Eternal Terminal (ET) installed on three servers — kali, phillias55522, and kalione — each running its own `etserver` behind its own Cloudflare tunnel route. Configs tracked in your dotfiles repo via chezmoi. The Moshi mobile app connects to any host for a persistent, reconnection-tolerant shell session.

**Why this approach:** Each host already has its own cloudflared tunnel connector with the DNS routes pointing to `tcp://127.0.0.1:2022`. ET is installed directly from official APT repos (the previous attempt failed because the plan used a dead repo URL — fixed here). Each host is independent, no central hub needed. Configs are versioned in dotfiles for reproducibility.

**What it will NOT do:** Modify your existing Cloudflare Tunnel configuration, change SSH access, expose port 2022 to the public internet, install the Moshi app, or touch any existing Docker/selfhost infrastructure.

**Effort:** Medium — 3 hosts, 3 installs, config files, systemd services, verification.
**Risk:** Low — ET has a mature APT package; the main risk was the dead repo URL, which is now corrected.
**Decisions to sanity-check:** Debian APT repo chosen for all three hosts. Kali uses `trixie` suite override (because `kali-rolling` isn't a valid Debian suite). Config is `/etc/et.cfg` (INI, not YAML). Service is the packaged `et.service`. Chezmoi manages root configs via `run_onchange` script (not `sudo chezmoi add`).

**Your next move:** Approve this plan, then run `$start-work et-moshi-setup`.

---

> TL;DR (machine): Medium effort, Low risk — install etserver on 3 hosts via Debian APT repo, configure `/etc/et.cfg`, enable `et.service`, verify tunnel routes, version in dotfiles via run_onchange script.

## Scope

### Must have
- ET (et + etserver) installed on Kali host (CabinInspiron22Kali)
- etserver installed on phillias55522 (primary55522 on OCI)
- etserver installed on kalione
- `/etc/et.cfg` configured on each host (bind 127.0.0.1:2022)
- `et.service` enabled and running on each host (from APT package)
- SSH config entries on Kali for `et` CLI connections (via tunnel hostnames)
- Moshi connection parameters documented per host
- ET config versioned in dotfiles repo via `run_onchange` script
- Acceptance tests passing for each phase

### Must NOT have (guardrails, anti-slop, scope boundaries)
- Do NOT modify existing cloudflared tunnel configuration on any host
- Do NOT modify existing SSH config entries (only append new ET-specific blocks)
- Do NOT restart any cloudflared service
- Do NOT expose port 2022 directly to the internet
- Do NOT install the Moshi app itself
- Do NOT change any godoxy/selfhost routing
- Do NOT remove or disable existing SSH access
- Do NOT use `https://pkgs.eternalterminal.dev` — it's a dead domain
- Do NOT create a custom systemd unit — the packaged `et.service` is sufficient
- Do NOT use YAML config format — ET uses INI-style `/etc/et.cfg`

## Verification strategy
> Zero human intervention — all verification is agent-executed.
- **Test decision:** tests-after (verify each install + config with direct commands)
- **Evidence:** `.omo/evidence/et-moshi-setup/`

## Execution strategy

### Parallel execution waves

**Wave 1 — Pre-flight (can parallelize across all 3 hosts)**
- Verify OS, cloudflared status, port availability, DNS resolution

**Wave 2 — Install et/etserver (can parallelize across all 3 hosts)**
- Add APT repo, install et package, verify binary

**Wave 3 — Configure etserver (can parallelize across all 3 hosts)**
- Edit `/etc/et.cfg`, enable + start `et.service`, verify running

**Wave 4 — Client config + Moshi docs + dotfiles**
- Add SSH config entries on Kali, document Moshi parameters, create chezmoi run_onchange

### Dependency matrix

| Todo | Depends on | Blocks | Can parallelize with |
| --- | --- | --- | --- |
| 1 (pre-flight Kali) | — | 2 | 3 |
| 2 (install Kali) | 1 | 6 | 4 |
| 3 (pre-flight remotes) | — | 4,5 | 1 |
| 4 (install phillias55522) | 3 | 6 | 2,5 |
| 5 (install kalione) | 3 | 6 | 2,4 |
| 6 (config all three) | 2,4,5 | 7 | — |
| 7 (SSH + Moshi + dotfiles) | 6 | — | — |

## Todos

- [x] 1. Pre-flight: verify prerequisites on Kali host
  **What to do / Must NOT do:** Verify all prerequisites on Kali locally and on remote hosts via SSH. On Kali, check locally. On phillias55522 and kalione, SSH via `ssh primary55522` / `ssh kalione`.
  - Check cloudflared is running: `systemctl is-active cloudflared` → expect `active` on all 3 hosts
  - Check OS: `lsb_release -a` locally; `ssh primary55522 "lsb_release -a"` and `ssh kalione "lsb_release -a"` — record codename for APT suite selection
  - Check port 2022 free: `ss -tlnp | grep 2022` → expect empty on all 3 hosts
  - Check curl available: `which curl` → expect path on all 3 hosts
  - Check ET not already installed: `which et etserver` → expect nothing on all 3
  - Verify DNS resolution: `host et.phillias.us` / `.cc` / `.org` — expect each to resolve
  - Verify Kali's `/etc/os-release`: `grep VERSION_ID /etc/os-release` → `trixie`
  - Do NOT restart any services
  **Parallelization:** Wave 1 | Blocked by: nothing | Blocks: 2
  **References (executor has NO interview context — be exhaustive):**
  - Kali local: `/etc/os-release`, `/etc/systemd/system/cloudflared.service`
  - Remote hosts via SSH: `~/.ssh/config` lines 18-23 (primary55522), 32-37 (kalione)
  **Acceptance criteria (agent-executable):**
  1. `systemctl is-active cloudflared` returns `active` on all 3 hosts
  2. `ss -tlnp | grep 2022` returns empty on all 3 hosts
  3. `host et.phillias.cc` exits 0 (domain resolves)
  4. `which curl` returns a path on all 3 hosts
  5. `which et` returns empty on all 3 hosts
  6. `grep VERSION_ID /etc/os-release` outputs `trixie` on Kali
  **QA scenarios (name the exact tool + invocation):**
  - Happy: All checks pass on all hosts
  - Failure (port 2022 in use): `ss -tlnp | grep 2022` shows a process → report what's using it. If it's a stale etserver from a prior install, stop it: `sudo systemctl stop et`
  - Failure (cloudflared inactive): `ssh hostname "sudo systemctl start cloudflared && systemctl is-active cloudflared"` → if still fails, report and abort
  - Evidence: `.omo/evidence/et-moshi-setup/task-1-preflight.log`
  **Commit:** N

- [x] 2. Install et + etserver on Kali host (CabinInspiron22Kali)
  **Status:** ✅ Already complete — ET v7.0.0-trixie1 installed via APT. Service disabled, will configure in Task 6.
  **What to do / Must NOT do:** Add the official ET Debian APT repo, install the et package (provides both `et` and `etserver`), verify binaries work.
  - Do NOT use `https://pkgs.eternalterminal.dev` — it does not resolve
  - Do NOT use `kali-rolling` as the APT suite — it doesn't exist in the repo
  - Force `trixie` as the suite because Kali's VERSION_ID is `trixie`
  **Commands:**
  ```bash
  # Add GPG key (correct URL from official docs)
  sudo mkdir -m 0755 -p /etc/apt/keyrings
  curl -sSL https://github.com/MisterTea/debian-et/raw/master/et.gpg | sudo tee /etc/apt/keyrings/et.gpg >/dev/null

  # Add repo with FORCED trixie suite (NOT kali-rolling)
  echo "deb [signed-by=/etc/apt/keyrings/et.gpg] https://mistertea.github.io/debian-et/debian-source/ trixie main" | sudo tee /etc/apt/sources.list.d/et.list

  # Install
  sudo apt update
  sudo apt install -y et
  ```
  **Parallelization:** Wave 2 | Blocked by: 1 | Blocks: 6
  **References (executor has NO interview context — be exhaustive):**
  - Official download page: `https://eternalterminal.dev/download/`
  - GPG key source: `https://github.com/MisterTea/debian-et/raw/master/et.gpg`
  - Supported Debian suites in repo: `bookworm` (Debian 12), `forky` (Debian 13), `trixie` (Debian 14/testing)
  **Acceptance criteria (agent-executable):**
  1. `et --version` outputs a version string (≥ v6.x)
  2. `etserver --version` outputs a version string
  3. `/usr/bin/et` exists and is executable
  4. `/usr/bin/etserver` exists and is executable
  5. `ldd /usr/bin/etserver | grep "not found"` returns empty
  **QA scenarios (name the exact tool + invocation):**
  - Happy: `et --version && etserver --version` both succeed
  - Failure (APT 404 — wrong suite): Run `grep VERSION_CODENAME /etc/os-release`. Use these known supported suites in order of likelihood: `trixie`, `bookworm`, `forky`. Create a new source list entry with the correct suite and retry.
  - Failure (GPG key): If `apt update` warns about missing key, verify key was written: `ls -la /etc/apt/keyrings/et.gpg`
  - Evidence: `.omo/evidence/et-moshi-setup/task-2-install-kali.log`
  **Commit:** N

- [x] 3. Pre-flight: verify prerequisites on phillias55522 and kalione
  **What to do / Must NOT do:** SSH into each remote host and run the same pre-flight checks as task 1.
  - Check cloudflared: `ssh primary55522 "systemctl is-active cloudflared"` → expect `active`
  - Check OS: `ssh primary55522 "grep VERSION_CODENAME /etc/os-release"` → record codename for suite decision
  - Check port 2022: `ssh primary55522 "ss -tlnp | grep 2022"` → expect empty
  - Check curl: `ssh primary55522 "which curl"` → expect path
  - If OS shows Ubuntu (VERSION_CODENAME like `noble`, `jammy`, etc.), note that for task 4 (needs PPA)
  - Do NOT restart any services or modify any configs
  **Parallelization:** Wave 1 | Blocked by: nothing | Blocks: 4,5
  **References (executor has NO interview context — be exhaustive):**
  - `~/.ssh/config` lines 18-23 (primary55522) and 32-37 (kalione)
  **Acceptance criteria (agent-executable):**
  1. `ssh primary55522 "systemctl is-active cloudflared"` → `active`
  2. `ssh kalione "systemctl is-active cloudflared"` → `active`
  3. `ssh primary55522 "ss -tlnp | grep 2022"` → empty
  4. `ssh kalione "ss -tlnp | grep 2022"` → empty
  5. `ssh primary55522 "which curl"` → path
  6. OS codename recorded for both (for suite selection)
  **QA scenarios (name the exact tool + invocation):**
  - Happy: All checks pass on both hosts
  - Failure (SSH connection): `ssh -v primary55522 2>&1 | tail -20` to diagnose
  - Failure (port in use): Same as task 1 — identify and report
  - Evidence: `.omo/evidence/et-moshi-setup/task-3-preflight-remote.log`
  **Commit:** N

- [x] 4. Install et on phillias55522 and kalione
  **What to do / Must NOT do:** SSH into each remote host and install ET. Use the Debian APT repo with the correct suite from task 3. If the host is Ubuntu, use the PPA instead.
  **Commands (Debian — use suite from task 3, e.g. `bookworm`):**
  ```bash
  SUITE=<codename-from-task-3>  # e.g. bookworm, trixie, forky
  ssh <hostname> "sudo mkdir -m 0755 -p /etc/apt/keyrings && \
    curl -sSL https://github.com/MisterTea/debian-et/raw/master/et.gpg | sudo tee /etc/apt/keyrings/et.gpg >/dev/null && \
    echo 'deb [signed-by=/etc/apt/keyrings/et.gpg] https://mistertea.github.io/debian-et/debian-source/ $SUITE main' | sudo tee /etc/apt/sources.list.d/et.list && \
    sudo apt update && sudo apt install -y et"
  ```
  **For Ubuntu hosts (PPA):**
  ```bash
  ssh <hostname> "sudo apt-get install -y software-properties-common && \
    sudo add-apt-repository -y ppa:jgmath2000/et && \
    sudo apt-get update && sudo apt-get install -y et"
  ```
  **Parallelization:** Wave 2 | Blocked by: 3 | Blocks: 6
  **References (executor has NO interview context — be exhaustive):**
  - Official download page: `https://eternalterminal.dev/download/`
  - Supported Debian suites: `bookworm`, `forky`, `trixie` — verified at `https://github.com/MisterTea/debian-et/tree/master/debian-source/dists`
  **Acceptance criteria (agent-executable):**
  1. `ssh primary55522 "etserver --version"` returns a version string
  2. `ssh kalione "etserver --version"` returns a version string
  3. `ssh primary55522 "which etserver"` → `/usr/bin/etserver`
  4. `ssh kalione "which etserver"` → `/usr/bin/etserver`
  **QA scenarios (name the exact tool + invocation):**
  - Happy: `etserver --version` succeeds on both hosts
  - Failure (APT 404): The suite from task 3 might not be in the ET repo. Supported suites are: `bookworm` (Debian 12), `forky` (Debian 13), `trixie` (testing). If the OS codename isn't one of these, try `trixie` (the testing/sid branch is usually compatible), or use the PPA instead.
  - Failure (Ubuntu detected): Switch to PPA method
  - Evidence: `.omo/evidence/et-moshi-setup/task-4-install-remote.log`
  **Commit:** N

- [x] 5. [No-op — et client installed alongside etserver in task 2]
  The `et` package includes both the client (`et`) and server (`etserver`). Already installed on Kali in task 2. Verification was done there. Mark completed.
  **Parallelization:** N/A
  **Commit:** N

- [x] 6. Configure etserver on all three hosts
  **What to do / Must NOT do:** Edit `/etc/et.cfg` to bind to 127.0.0.1:2022, then enable and start the packaged `et.service`. The APT package provides the systemd unit at `/lib/systemd/system/et.service` — do NOT create a custom unit.
  - Do NOT create a file at `/etc/et.yaml` — ET uses INI-style `/etc/et.cfg`
  - Do NOT create `/etc/systemd/system/etserver.service` — the package already provides `et.service`
  - Do NOT bind to `0.0.0.0` — bind to `127.0.0.1:2022` since cloudflared is co-located
  - Do NOT expose port 2022 to the public internet
  - Do NOT restart cloudflared
  **Config file — `/etc/et.cfg` (INI format, same on all three):**
  ```ini
  [Networking]
  port = 2022
  bind_ip = 127.0.0.1
  ```
  **Commands per host:**
  ```bash
  # If the config file already exists, replace it:
  sudo tee /etc/et.cfg << 'EOF'
  [Networking]
  port = 2022
  bind_ip = 127.0.0.1
  EOF

  # Check the packaged service file exists:
  ls -la /lib/systemd/system/et.service

  # The packaged service already uses:
  #   ExecStart=/usr/bin/etserver --cfgfile=/etc/et.cfg --logtostdout
  # Verify this:
  grep ExecStart /lib/systemd/system/et.service

  # Enable and start:
  sudo systemctl daemon-reload
  sudo systemctl enable --now et.service

  # If et.service was already enabled from a previous attempt, disable + re-enable:
  # sudo systemctl disable --now et.service
  # sudo systemctl enable --now et.service
  ```
  For remote hosts, prefix every command with `ssh hostname "..."`.
  **Parallelization:** Wave 3 | Blocked by: 2,4 | Blocks: 7
  **References (executor has NO interview context — be exhaustive):**
  - Official ET config: `https://github.com/MisterTea/EternalTerminal#configuring` — references `/etc/et.cfg`
  - Packaged service file: `/lib/systemd/system/et.service` (installed by APT)
  - NixOS module shows the INI format: `settings.Networking.bind_ip` / `settings.Networking.port`
  **Acceptance criteria (agent-executable):**
  1. `sudo systemctl is-active et.service` → `active` on all 3 hosts
  2. `sudo systemctl is-enabled et.service` → `enabled` on all 3 hosts
  3. `ss -tlnp | grep 2022` shows `etserver` listening on `127.0.0.1:2022` on all 3 hosts
  4. `cat /etc/et.cfg` contains `bind_ip = 127.0.0.1` and `port = 2022`
  5. `grep ExecStart /lib/systemd/system/et.service` contains `--cfgfile=/etc/et.cfg`
  6. `sudo journalctl -u et.service -n 10 --no-pager` shows no errors
  **QA scenarios (name the exact tool + invocation):**
  - Happy: Service active, listening on 127.0.0.1:2022, config correct, logs clean
  - Failure (service won't start): `sudo journalctl -u et.service -n 50 --no-pager` → check for "Permission denied", missing binary, or config parse errors
  - Failure (wrong bind): If bound to 0.0.0.0 instead of 127.0.0.1: `sudo sed -i 's/bind_ip = .*/bind_ip = 127.0.0.1/' /etc/et.cfg && sudo systemctl restart et.service`
  - Failure (port conflict): `ss -tlnp | grep 2022` shows another process → either stop the other process or change ET port: `sudo sed -i 's/port = 2022/port = 2023/' /etc/et.cfg && sudo systemctl restart et.service`
  - Failure (stale previous install): If `et.service` exists in a broken state: `sudo systemctl disable --now et.service && sudo systemctl enable --now et.service`
  - Evidence: `.omo/evidence/et-moshi-setup/task-6-config.log`
  **Commit:** N

- [x] 7. Configure ET client SSH aliases + Moshi parameters + dotfiles versioning
  **What to do / Must NOT do:**
  1. Add ET SSH config aliases to `~/.ssh/config` (for CLI `et` usage via tunnel hostnames)
  2. Document Moshi connection parameters to `.omo/evidence/et-moshi-setup/moshi-params.txt`
  3. Create chezmoi `run_onchange` script + store ET config in dotfiles for versioning
  - Do NOT modify existing SSH config entries — only append new ET-specific blocks
  - Do NOT use `HostName 127.0.0.1` for remote hosts — use the tunnel DNS names
  - Do NOT set `Port` in ET SSH aliases — ET reads the port from the SSH config as sshd's port (default 22), not ET's server port
  - Do NOT use `sudo chezmoi add /etc/et.cfg` — chezmoi source is home-rooted; use a run_onchange script instead

  **Part A: SSH config entries to append to `~/.ssh/config`**
  ```
  # ET — Eternal Terminal host aliases (for CLI et connections)
  # Usage: et et-kali  (connects to etserver via tunnel DNS on port 2022)
  Host et-kali
    HostName et.phillias.us
    User phillias

  Host et-55522
    HostName et.phillias.cc
    User ubuntu

  Host et-kalione
    HostName et.phillias.org
    User phillias
  ```
  **How these work:** `et et-kali` reads SSH config → finds `HostName et.phillias.us` → connects TCP to `et.phillias.us:2022` (the default ET server port) → etserver authenticates → etserver SSHes to `phillias@et.phillias.us:22` (through the tunnel, which loops back to the same host — this is fine). For remote hosts, `et et-55522` connects to `et.phillias.cc:2022` → reaches etserver on phillias55522 → etserver SSHes to `ubuntu@localhost:22` on phillias55522.

  **Part B: Moshi connection parameters** (write to `.omo/evidence/et-moshi-setup/moshi-params.txt`):
  ```csv
  Host,Tunnel address,Port,SSH user,Notes
  kali,et.phillias.us,2022,phillias,Connects through tunnel to Kali's etserver
  phillias55522,et.phillias.cc,2022,ubuntu,Connects through tunnel to phillias55522's etserver
  kalione,et.phillias.org,2022,phillias,Connects through tunnel to kalione's etserver
  ```
  Each Moshi connection profile:
  - Protocol: Cloudflare Tunnel / TCP
  - Host: `et.phillias.XX`
  - Port: `2022`
  - SSH user: as above
  - SSH auth: key-based (same key as current SSH access)

  **Part C: Version ET config in dotfiles via chezmoi run_onchange script**
  Since your chezmoi source is home-directory-rooted (not `/`-rooted), you cannot `sudo chezmoi add /etc/et.cfg` directly. Instead:
  1. Create the config template in your dotfiles repo:
     ```
     ~/.local/share/chezmoi/scripts/etserver/et.cfg
     ```
     Contents:
     ```
     [Networking]
     port = 2022
     bind_ip = 127.0.0.1
     ```
  2. Create a run_onchange script:
     ```
     ~/.local/share/chezmoi/run_onchange_install-etserver-config.sh.tmpl
     ```
     ```bash
     #!/bin/bash
     # Install ET server config to /etc/ — runs when script contents change
     sudo install -m 644 -o root -g root \
       "${CHEZMOI_SOURCE_DIR}/scripts/etserver/et.cfg" \
       /etc/et.cfg
     sudo systemctl restart et.service || true
     ```
  3. Make it executable: `chmod +x run_onchange_install-etserver-config.sh.tmpl`
  4. Run `/ce-commit-push-pr` to branch, commit, push, and open a PR with message:
     ```
     feat(et): add etserver config and run_onchange installer
     ```
  5. Verify: `gh pr view --json state --jq '.state'` → `OPEN`
  **Parallelization:** Wave 4 | Blocked by: 6 | Blocks: nothing
  **References (executor has NO interview context — be exhaustive):**
  - SSH config format: `man ssh_config`
  - ET CLI usage: `et --help`
  - ET SSH config support: `https://github.com/MisterTea/EternalTerminal#using`
  - Dotfiles skill: `/home/phillias/.config/opencode/skills/dotfiles/SKILL.md`
  - Chezmoi run_onchange docs: `chezmoi --help` or `man chezmoi` (scripts section)
  - Dotfiles repo: `git@github.com:phillias/dotfiles.git`
  - PR convention: `feat(et): <description>`
  **Acceptance criteria (agent-executable):**
  1. `grep "Host et-kali" ~/.ssh/config` returns the block
  2. `grep "Host et-55522" ~/.ssh/config` returns the block
  3. `grep "Host et-kalione" ~/.ssh/config` returns the block
  4. `.omo/evidence/et-moshi-setup/moshi-params.txt` exists with all 3 hosts
  5. `ls ~/.local/share/chezmoi/scripts/etserver/et.cfg` exists
  6. `ls ~/.local/share/chezmoi/run_onchange_install-etserver-config.sh.tmpl` exists and is executable
  7. `gh pr view --json state --jq '.state'` returns `OPEN`
  **QA scenarios (name the exact tool + invocation):**
  - Happy: SSH entries present, params file created, chezmoi files in place, PR open
  - Failure (SSH config parse error): `ssh -G et-kali 2>&1 | grep -i error` → fix syntax
  - Failure (ET connection test): `et et-kali "hostname"` → if fails, check `sudo systemctl status et.service` on Kali
  - Failure (et remote connection): `et et-55522 "hostname"` → should return `primary55522`. If fails, check `sudo systemctl status et.service` on phillias55522 and DNS resolution of `et.phillias.cc`
  - Failure (PR not created): Check `gh auth status`. Re-run `/ce-commit-push-pr` manually from chezmoi source dir.
  - Failure (run_onchange not executable): `chmod +x ~/.local/share/chezmoi/run_onchange_install-etserver-config.sh.tmpl`
  - Evidence: `.omo/evidence/et-moshi-setup/task-7-client-dotfiles.log`
  **Commit:** Y — this is the only commit-worthy task (dotfiles change via PR)

## Final verification wave
> Runs in parallel after ALL todos. ALL must APPROVE. Surface results and wait for the user's explicit okay before declaring complete.

- [x] F1. Plan compliance audit
  Verify all 7 todos completed. Check each acceptance criterion against actual state. Run every acceptance test command. Report pass/fail per todo.

- [x] F2. Config review
  Review `/etc/et.cfg` on all three hosts — verify `[Networking] port = 2022`, `bind_ip = 127.0.0.1`.
  Review packaged service file: `grep ExecStart /lib/systemd/system/et.service` — verify `--cfgfile=/etc/et.cfg`.
  Review SSH config additions — verify HostName uses tunnel DNS names, not 127.0.0.1.

- [x] F3. Real end-to-end QA
  Execute ET connection tests:
  1. On Kali: Run `et et-kali "hostname"` — expect output `kali` (or the Kali hostname)
  2. On Kali: Run `et et-55522 "hostname"` — expect output `primary55522`
  3. On Kali: Run `et et-kalione "hostname"` — expect output `kalione`
  4. Test reconnection: `sudo systemctl restart et.service && sleep 2 && et et-kali "echo reconnected"` — expect success
  5. Verify all three services clean: `sudo journalctl -u et.service -n 5 --no-pager` on each host
  6. Document any issues found

- [x] F4. Scope fidelity
  Verify Must-NOT-Have items:
  - No cloudflared restarted: `systemctl show cloudflared -p ActiveEnterTimestamp` — compare to session start time
  - No port 2022 exposed externally: `ss -tlnp | grep "0.0.0.0:2022"` → must be empty on all hosts
  - Original SSH config entries intact: `grep "Host primary55522" ~/.ssh/config` still present
  - No changes to docker/selfhost: `git -C ~/docker/selfhost status --short` → clean (or unchanged relevant files)
  - No custom systemd unit created: `ls /etc/systemd/system/et.service` should NOT exist (only `/lib/systemd/system/et.service` from package)

## Commit strategy
One commit, made only by Task 7 via `/ce-commit-push-pr` in the dotfiles repo:
`feat(et): add etserver config and run_onchange installer`

No other tasks produce commits — they are infrastructure setup on remote machines, captured via evidence logs.

## Success criteria
- `sudo systemctl is-active et.service` returns `active` on all three hosts
- `ss -tlnp` shows `etserver` listening on `127.0.0.1:2022` on all three hosts
- `et et-kali "hostname"` returns Kali's hostname
- `et et-55522 "hostname"` returns `primary55522` (or its hostname)
- `et et-kalione "hostname"` returns `kalione` (or its hostname)
- All evidence logs written to `.omo/evidence/et-moshi-setup/`
- PR open on dotfiles repo: `gh pr view --json title,url`
