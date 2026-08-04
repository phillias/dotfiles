# World Monitor Self-Hosted Deployment

## TL;DR

> **Quick Summary**: Deploy koala73/worldmonitor as a 4-container Docker stack on the home server, configured with OpenRouter free-tier AI models, exposed on port 3080, with Godoxy reverse proxy labels for automatic subdomain routing at worldmonitor.phillias.org.
>
> **Deliverables**:
> - Running World Monitor stack (4 containers: worldmonitor, ais-relay, redis, redis-rest)
> - OpenRouter free-tier AI integration (Nemotron 3 Ultra primary, Gemma 4 multimodal, GPT-OSS fallback)
> - Godoxy proxy labels for auto-discovery (worldmonitor.phillias.org)
> - Populated data seeders (news feeds, market data, conflict data)
> - Deployment documentation for future reference
>
> **Estimated Effort**: Short (30-60 min execution)
> **Parallel Execution**: YES - 3 waves
> **Critical Path**: Task 1 → Task 2 → Task 3 → Task 4 → Task 5

---

## Context

### Original Request
Deploy koala73/worldmonitor using Docker on the home server with OpenRouter free-tier models, exposed on a unique TCP port, with Godoxy proxy labels for auto-discovery. Do NOT restart godoxy or edit its config.

### Interview Summary
**Key Discussions**:
- World Monitor is a 4-container Docker stack built from source (no pre-built full-stack image)
- Server: Intel i3-3240T, 7.7GB RAM, 912GB disk, 9 existing containers, Kali Linux
- Godoxy auto-discovers services via Docker labels (proxy.<name>.port, proxy.<name>.alias)
- Domain: phillias.org (from selfhost .env), subdomain: worldmonitor.phillias.org
- Port 3080 selected (unique, no conflicts with existing services)
- User explicitly prohibited restarting godoxy or editing its config

**Research Findings**:
- 3 required secrets: RELAY_SHARED_SECRET, REDIS_PASSWORD, REDIS_TOKEN (openssl rand -hex 32)
- AI config: GROQ_API_KEY (primary), OPENROUTER_API_KEY (fallback), or LLM_API_URL+KEY+MODEL
- OpenRouter free tier: 50 req/day (no credits) or 1000/day (after $10 lifetime credits)
- Seeders run on HOST via scripts/run-seeders.sh (not inside containers)
- ais-relay needs UPSTASH_ALLOW_INSECURE_HTTP=true for internal HTTP proxy
- Redis is bundled (redis:7-alpine), no external DB needed

### Metis Review
**Identified Gaps** (addressed):
- OpenRouter API key must be obtained from user before deployment
- Port binding should be 0.0.0.0 for godoxy (host network) to reach it
- OIDC protection decision deferred (not in scope unless user requests)
- Seeder cron scheduling deferred (manual run acceptable for initial deploy)
- Domain confirmed as phillias.org from selfhost .env

---

## Work Objectives

### Core Objective
Deploy a fully functional self-hosted World Monitor instance with AI-powered news analysis using free OpenRouter models, accessible via Godoxy reverse proxy.

### Concrete Deliverables
- `~/docker/worldmonitor/` - Cloned repo with custom .env and docker-compose.override.yml
- 4 running Docker containers (worldmonitor, ais-relay, redis, redis-rest)
- Godoxy auto-discovery labels on the worldmonitor container
- Populated Redis cache via seeders
- Health-verified deployment accessible at worldmonitor.phillias.org

### Definition of Done
- [ ] `docker ps` shows all 4 World Monitor containers healthy
- [ ] `curl -s http://localhost:3080/api/sidecar-health` returns 200
- [ ] `curl -sI https://worldmonitor.phillias.org` returns 200 via Godoxy
- [ ] OpenRouter AI features work (news synthesis, analyst chat)
- [ ] Seeders have populated initial data

### Must Have
- Docker stack built from source (not frontend-only GHCR image)
- OpenRouter free-tier models configured (nvidia/nemotron-3-ultra-550b-a55b:free)
- Port 3080 exposed and accessible
- Godoxy labels for auto-discovery (proxy.worldmonitor.port, proxy.worldmonitor.alias)
- All 3 secrets generated and stored in .env
- Resource limits set to prevent OOM on 7.7GB server

### Must NOT Have (Guardrails)
- Do NOT restart godoxy container
- Do NOT edit ~/docker/selfhost/godoxy/config/config.yml
- Do NOT run `docker compose up -d` without service names (targeted startup only)
- Do NOT expose Redis or redis-rest ports to 0.0.0.0 (keep internal)
- Do NOT install Node.js on the host (everything runs in Docker)
- Do NOT use the frontend-only GHCR image (ghcr.io/koala73/worldmonitor) - it lacks the API sidecar
- Do NOT set up OIDC authentication (out of scope unless explicitly requested)
- Do NOT create cron jobs for seeder re-run (out of scope unless explicitly requested)

---

## Verification Strategy

> **ZERO HUMAN INTERVENTION** - ALL verification is agent-executed. No exceptions.

### Test Decision
- **Infrastructure exists**: YES (Docker)
- **Automated tests**: None (deployment verification via health checks and curl)
- **Framework**: Docker health checks + curl + docker logs

### QA Policy
Every task MUST include agent-executed QA scenarios.
Evidence saved to `.omo/evidence/task-{N}-{scenario-slug}.{ext}`.

- **Docker containers**: Use Bash - docker ps, docker logs, curl health endpoints
- **Proxy routing**: Use Bash - curl -sI through Godoxy
- **AI features**: Use Bash - curl API with OpenRouter model test

---

## Execution Strategy

### Parallel Execution Waves

```
Wave 1 (Start Immediately - preparation):
├── Task 1: Clone repo + generate secrets + create .env [quick]
└── Task 2: Research OpenRouter API key setup [quick]

Wave 2 (After Wave 1 - build and configure):
├── Task 3: Create docker-compose.override.yml [quick]
└── Task 4: Build Docker images [quick]

Wave 3 (After Wave 2 - deploy and verify):
├── Task 5: Start stack + run seeders [quick]
├── Task 6: Verify deployment + health checks [quick]
└── Task 7: Document deployment for reference [quick]

Wave FINAL (After ALL tasks - verification):
├── Task F1: Plan compliance audit (oracle)
├── Task F2: Code quality review (unspecified-high)
├── Task F3: Real manual QA (unspecified-high)
└── Task F4: Scope fidelity check (deep)
-> Present results -> Get explicit user okay

Critical Path: Task 1 → Task 3 → Task 5 → Task 6 → F1-F4 → user okay
Parallel Speedup: ~40% faster than sequential
Max Concurrent: 2 (Waves 1 & 2)
```

### Dependency Matrix

| Task | Depends On | Blocks |
|------|-----------|--------|
| 1 | None | 3, 4, 5 |
| 2 | None | 1 (parallel) |
| 3 | 1 | 5 |
| 4 | 1 | 5 |
| 5 | 3, 4 | 6 |
| 6 | 5 | 7, F1-F4 |
| 7 | 6 | F1-F4 |

### Agent Dispatch Summary

- **Wave 1**: 2 tasks - T1 → `quick`, T2 → `quick`
- **Wave 2**: 2 tasks - T3 → `quick`, T4 → `quick`
- **Wave 3**: 3 tasks - T5 → `quick`, T6 → `quick`, T7 → `quick`
- **FINAL**: 4 tasks - F1 → `oracle`, F2 → `unspecified-high`, F3 → `unspecified-high`, F4 → `deep`

---

## TODOs

- [ ] 1. Clone repo + generate secrets + create .env

  **What to do**:
  - Clone `https://github.com/koala73/worldmonitor.git` to `~/docker/worldmonitor/`
  - Generate 3 secrets: `openssl rand -hex 32` (run 3 times)
  - Create `~/docker/worldmonitor/.env` with:
    - `RELAY_SHARED_SECRET=<hex>`
    - `REDIS_PASSWORD=<hex>`
    - `REDIS_TOKEN=<hex>`
    - `OPENROUTER_API_KEY=<from ~/.local/share/opencode/auth.json>`
    - `GROQ_API_KEY=<user-provided or placeholder>`
    - `OPENROUTER_PRIMARY_MODEL=nvidia/nemotron-3-ultra-550b-a55b:free`
    - `OPENROUTER_SECONDARY_MODEL=google/gemma-4-26b-a4b-it:free`
    - `OPENROUTER_FALLBACK_MODEL=openai/gpt-oss-20b:free`
  - Verify `.env` file exists and has correct permissions (600)

  **Must NOT do**:
  - Do NOT commit .env to git
  - Do NOT expose secrets in docker inspect (use env_file, not inline)

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Simple file operations, no complex logic
  - **Skills**: []
    - No special skills needed

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Task 2)
  - **Blocks**: Tasks 3, 4, 5
  - **Blocked By**: None

  **References**:
  - `~/docker/selfhost/.env` - Reference for env var format and domain config
  - `https://github.com/koala73/worldmonitor/blob/main/.env.example` - Official env var template

  **Acceptance Criteria**:
  - [ ] `~/docker/worldmonitor/` exists and contains cloned repo
  - [ ] `~/docker/worldmonitor/.env` exists with 600 permissions
  - [ ] `.env` contains all 3 generated secrets (RELAY_SHARED_SECRET, REDIS_PASSWORD, REDIS_TOKEN)
  - [ ] `.env` contains OPENROUTER_API_KEY (placeholder or real)
  - [ ] `.env` contains model ID variables

  **QA Scenarios**:

  ```
  Scenario: Verify repo cloned and secrets generated
    Tool: Bash
    Preconditions: None
    Steps:
      1. ls ~/docker/worldmonitor/.env
      2. grep -c "RELAY_SHARED_SECRET=" ~/docker/worldmonitor/.env
      3. grep -c "REDIS_PASSWORD=" ~/docker/worldmonitor/.env
      4. grep -c "REDIS_TOKEN=" ~/docker/worldmonitor/.env
      5. stat -c "%a" ~/docker/worldmonitor/.env
    Expected Result: File exists, 3 secrets found, permissions are 600
    Failure Indicators: Missing file, missing secrets, wrong permissions
    Evidence: .omo/evidence/task-1-secrets-generated.txt

  Scenario: Verify env var format
    Tool: Bash
    Preconditions: .env file created
    Steps:
      1. grep "OPENROUTER_PRIMARY_MODEL=" ~/docker/worldmonitor/.env
      2. grep "nvidia/nemotron-3-ultra-550b-a55b:free" ~/docker/worldmonitor/.env
    Expected Result: Model IDs present in .env
    Failure Indicators: Missing model config
    Evidence: .omo/evidence/task-1-model-config.txt
  ```

  **Commit**: YES
  - Message: `chore(worldmonitor): add deployment config and secrets template`
  - Files: `~/docker/worldmonitor/.env`

- [ ] 2. Verify OpenRouter API key source and add to .env

  **What to do**:
  - The OpenRouter API key is stored in `~/.local/share/opencode/auth.json` under the `openrouter` key
  - Copy the key from there into `~/docker/worldmonitor/.env` as `OPENROUTER_API_KEY`
  - Verify the key format is correct (starts with `sk-or-v1-`)
  - Optionally: suggest user add $10 credits to OpenRouter to unlock 1000 req/day (from 50/day free tier)

  **Must NOT do**:
  - Do NOT store the API key in any file other than .env
  - Do NOT echo the key to logs
  - Do NOT modify the auth.json file

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Simple key copy and verification
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Task 1)
  - **Blocks**: Task 5 (AI features need key)
  - **Blocked By**: None

  **References**:
  - `~/.local/share/opencode/auth.json` - Source of OpenRouter API key (key: "openrouter", field: "key")
  - `~/docker/worldmonitor/.env` - Destination for the key

  **Acceptance Criteria**:
  - [ ] OPENROUTER_API_KEY in .env contains the real key (not placeholder)
  - [ ] Key starts with `sk-or-v1-`
  - [ ] Key is the same one from auth.json

  **QA Scenarios**:

  ```
  Scenario: Verify API key matches source
    Tool: Bash
    Preconditions: .env created in Task 1
    Steps:
      1. SOURCE_KEY=$(python3 -c "import json; print(json.load(open('/home/phillias/.local/share/opencode/auth.json'))['openrouter']['key'])")
      2. ENV_KEY=$(grep "OPENROUTER_API_KEY=" ~/docker/worldmonitor/.env | cut -d= -f2)
      3. [ "$SOURCE_KEY" = "$ENV_KEY" ] && echo "MATCH" || echo "MISMATCH"
    Expected Result: MATCH
    Failure Indicators: Keys differ, env key is placeholder
    Evidence: .omo/evidence/task-2-api-key-verify.txt
  ```

  **Commit**: NO (key is in .env, committed in Task 1)

- [ ] 3. Create docker-compose.override.yml with port, labels, and resource limits

  **What to do**:
  - Create `~/docker/worldmonitor/docker-compose.override.yml` with:
    ```yaml
    services:
      worldmonitor:
        ports:
          - "3080:8080"
        labels:
          proxy.worldmonitor.port: "3080"
          proxy.worldmonitor.alias: worldmonitor
          proxy.worldmonitor.homepage.show: "true"
          proxy.worldmonitor.homepage.name: "World Monitor"
          proxy.worldmonitor.healthcheck.disable: "true"
        deploy:
          resources:
            limits:
              memory: 1500M
        networks:
          - default

      ais-relay:
        deploy:
          resources:
            limits:
              memory: 512M

      redis:
        deploy:
          resources:
            limits:
              memory: 384M

      redis-rest:
        deploy:
          resources:
            limits:
              memory: 256M
    ```
  - Verify the override file is valid YAML: `docker compose -f docker-compose.yml -f docker-compose.override.yml config > /dev/null`
  - Note: The `proxy.worldmonitor.port` label tells Godoxy which port to route to. Since Godoxy runs on host network, it can reach the container via the mapped port 3080.

  **Must NOT do**:
  - Do NOT use `network_mode: host` on worldmonitor (use bridge with port mapping)
  - Do NOT expose redis-rest to 0.0.0.0:8079 (keep internal only)
  - Do NOT modify the base docker-compose.yml

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: YAML file creation, straightforward
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Task 4)
  - **Blocks**: Task 5
  - **Blocked By**: Task 1

  **References**:
  - `~/docker/worldmonitor/docker-compose.yml` - Base compose file to override
  - `~/docker/selfhost/skill.md` - Godoxy label convention (proxy.<name>.port, proxy.<name>.alias)
  - `~/docker/worldmonitor/docker-compose.override.yml` - File to create

  **Acceptance Criteria**:
  - [ ] `docker-compose.override.yml` exists and is valid YAML
  - [ ] Port 3080 is mapped (3080:8080)
  - [ ] Godoxy labels present (proxy.worldmonitor.port, proxy.worldmonitor.alias)
  - [ ] Resource limits set (worldmonitor: 1500M, ais-relay: 512M, redis: 384M, redis-rest: 256M)
  - [ ] `docker compose config` validates without errors

  **QA Scenarios**:

  ```
  Scenario: Verify override file is valid
    Tool: Bash
    Preconditions: docker-compose.override.yml created
    Steps:
      1. cd ~/docker/worldmonitor && docker compose config > /dev/null 2>&1
      2. echo $?
    Expected Result: Exit code 0 (valid config)
    Failure Indicators: Non-zero exit, YAML parse errors
    Evidence: .omo/evidence/task-3-config-valid.txt

  Scenario: Verify port mapping
    Tool: Bash
    Preconditions: override file exists
    Steps:
      1. grep "3080:8080" ~/docker/worldmonitor/docker-compose.override.yml
      2. grep "proxy.worldmonitor.port" ~/docker/worldmonitor/docker-compose.override.yml
    Expected Result: Port mapping and label found
    Failure Indicators: Missing port or label
    Evidence: .omo/evidence/task-3-port-labels.txt
  ```

  **Commit**: YES
  - Message: `chore(worldmonitor): add Docker override with port mapping and Godoxy labels`
  - Files: `~/docker/worldmonitor/docker-compose.override.yml`

- [ ] 4. Build Docker images

  **What to do**:
  - Run `docker compose build` in `~/docker/worldmonitor/` to build all 3 custom images:
    - `worldmonitor` (main app: nginx + Node.js API sidecar)
    - `ais-relay` (AIS vessel tracking + market seeding)
    - `redis-rest` (Upstash-compatible REST proxy)
  - Monitor build output for errors
  - Verify all 3 images built: `docker images | grep worldmonitor`
  - Note: Redis (redis:7-alpine) is pulled, not built

  **Must NOT do**:
  - Do NOT use `--no-cache` unless build fails (saves time on first build)
  - Do NOT push images to any registry

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Docker build command, monitoring output
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Task 3)
  - **Blocks**: Task 5
  - **Blocked By**: Task 1

  **References**:
  - `~/docker/worldmonitor/Dockerfile` - Main app Dockerfile
  - `~/docker/worldmonitor/Dockerfile.relay` - Relay Dockerfile
  - `~/docker/worldmonitor/docker/Dockerfile.redis-rest` - Redis REST proxy Dockerfile

  **Acceptance Criteria**:
  - [ ] `docker images` shows worldmonitor, worldmonitor-ais-relay, worldmonitor-redis-rest
  - [ ] No build errors in output
  - [ ] All images are <1GB each (reasonable size)

  **QA Scenarios**:

  ```
  Scenario: Verify images built
    Tool: Bash
    Preconditions: Build completed
    Steps:
      1. docker images --format "table {{.Repository}}\t{{.Size}}" | grep worldmonitor
      2. docker images | grep -c "worldmonitor"
    Expected Result: 3 images found (main, relay, redis-rest)
    Failure Indicators: Missing images, zero count
    Evidence: .omo/evidence/task-4-images-built.txt

  Scenario: Check image sizes
    Tool: Bash
    Preconditions: Images built
    Steps:
      1. docker images --format "{{.Repository}}:{{.Tag}} {{.Size}}" | grep worldmonitor
    Expected Result: All images under 1GB
    Failure Indicators: Oversized images (>2GB)
    Evidence: .omo/evidence/task-4-image-sizes.txt
  ```

  **Commit**: NO (build artifacts, not source)

- [ ] 5. Start stack and run seeders

  **What to do**:
  - Start all 4 services in order:
    ```bash
    cd ~/docker/worldmonitor
    docker compose up -d redis redis-rest
    sleep 5
    docker compose up -d ais-relay
    sleep 5
    docker compose up -d worldmonitor
    ```
  - Wait for health checks to pass (30-60 seconds)
  - Run seeders on HOST (not in containers):
    ```bash
    cd ~/docker/worldmonitor
    ./scripts/run-seeders.sh
    ```
  - Monitor seeder output for errors
  - Verify containers are healthy: `docker ps --filter "name=worldmonitor"`

  **Must NOT do**:
  - Do NOT run `docker compose up -d` without service names
  - Do NOT run seeders inside containers (they run on host)
  - Do NOT restart godoxy

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Docker compose commands, sequential startup
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 3 (sequential start)
  - **Blocks**: Tasks 6, 7
  - **Blocked By**: Tasks 3, 4

  **References**:
  - `~/docker/worldmonitor/docker-compose.yml` - Service definitions
  - `~/docker/worldmonitor/scripts/run-seeders.sh` - Seeder script (runs on host)

  **Acceptance Criteria**:
  - [ ] `docker ps` shows all 4 worldmonitor containers with status "Up"
  - [ ] `docker ps --filter "name=worldmonitor" --format "{{.Status}}" | grep -c "healthy"` returns 2 (worldmonitor + ais-relay have healthchecks)
  - [ ] Seeder script completes without errors
  - [ ] Redis has data: `curl -s http://localhost:8079/GET/news:latest | head -c 200`

  **QA Scenarios**:

  ```
  Scenario: Verify all containers running
    Tool: Bash
    Preconditions: Stack started
    Steps:
      1. docker ps --filter "name=worldmonitor" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
      2. docker ps --filter "name=worldmonitor" --format "{{.Names}}" | wc -l
    Expected Result: 4 containers, all with "Up" status
    Failure Indicators: Container not running, restart loop, unhealthy
    Evidence: .omo/evidence/task-5-containers-running.txt

  Scenario: Verify health checks
    Tool: Bash
    Preconditions: Containers running for 60+ seconds
    Steps:
      1. curl -s http://localhost:3080/api/sidecar-health
      2. curl -s http://localhost:3080/ | head -c 100
    Expected Result: Health endpoint returns 200, main page returns HTML
    Failure Indicators: Connection refused, 5xx errors
    Evidence: .omo/evidence/task-5-health-check.txt
  ```

  **Commit**: NO (runtime state)

- [ ] 6. Verify deployment + Godoxy proxy routing

  **What to do**:
  - Verify local access: `curl -sI http://localhost:3080`
  - Verify Godoxy labels are visible: `docker inspect worldmonitor | grep proxy`
  - Wait for Godoxy auto-discovery (may take 30-60 seconds)
  - Verify proxy routing: `curl -sI https://worldmonitor.phillias.org`
  - If proxy not working, check Godoxy logs: `docker compose -f ~/docker/selfhost/compose.yml logs app --tail 20 | grep worldmonitor`
  - Test OpenRouter AI (if endpoint exists): attempt a news synthesis request
  - Document any issues found

  **Must NOT do**:
  - Do NOT restart godoxy
  - Do NOT edit godoxy config
  - Do NOT modify container labels after start (restart needed)

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: curl commands, log checking
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Tasks 5, 7)
  - **Blocks**: Task 7, F1-F4
  - **Blocked By**: Task 5

  **References**:
  - `~/docker/selfhost/compose.yml` - Godoxy compose for log checking
  - `~/docker/selfhost/godoxy/config/config.yml` - Reference only (DO NOT EDIT)

  **Acceptance Criteria**:
  - [ ] `curl -sI http://localhost:3080` returns HTTP 200
  - [ ] `docker inspect worldmonitor | grep proxy.worldmonitor` shows labels
  - [ ] `curl -sI https://worldmonitor.phillias.org` returns HTTP 200 (after Godoxy discovers)
  - [ ] Godoxy logs show worldmonitor route discovered

  **QA Scenarios**:

  ```
  Scenario: Verify local access
    Tool: Bash
    Preconditions: Stack running
    Steps:
      1. curl -sI http://localhost:3080
      2. grep -i "HTTP" <<< "$(curl -sI http://localhost:3080)"
    Expected Result: HTTP/1.1 200 OK
    Failure Indicators: Connection refused, 404, 502
    Evidence: .omo/evidence/task-6-local-access.txt

  Scenario: Verify Godoxy labels
    Tool: Bash
    Preconditions: Container running
    Steps:
      1. docker inspect worldmonitor --format '{{json .Config.Labels}}' | python3 -m json.tool | grep proxy
    Expected Result: Labels show proxy.worldmonitor.port and proxy.worldmonitor.alias
    Failure Indicators: Missing labels, wrong values
    Evidence: .omo/evidence/task-6-godoxy-labels.txt

  Scenario: Verify proxy routing
    Tool: Bash
    Preconditions: Godoxy running, labels set
    Steps:
      1. sleep 30  # Wait for Godoxy auto-discovery
      2. curl -sI https://worldmonitor.phillias.org
      3. grep -i "HTTP" <<< "$(curl -sI https://worldmonitor.phillias.org)"
    Expected Result: HTTP/2 200 (via Godoxy)
    Failure Indicators: 502 Bad Gateway, timeout, 404
    Evidence: .omo/evidence/task-6-proxy-routing.txt
  ```

  **Commit**: NO

- [ ] 7. Document deployment for reference

  **What to do**:
  - Create `~/docker/worldmonitor/DEPLOYMENT.md` with:
    - Deployment date and summary
    - Port mapping (3080:8080)
    - Godoxy labels used
    - OpenRouter models configured
    - Secrets location (~/docker/worldmonitor/.env)
    - Seeder re-run command: `cd ~/docker/worldmonitor && ./scripts/run-seeders.sh`
    - Useful commands:
      - Start: `cd ~/docker/worldmonitor && docker compose up -d`
      - Stop: `cd ~/docker/worldmonitor && docker compose stop`
      - Logs: `cd ~/docker/worldmonitor && docker compose logs -f`
      - Re-seed: `cd ~/docker/worldmonitor && ./scripts/run-seeders.sh`
    - OpenRouter free tier limits (50 req/day without credits)
    - Resource limits applied
    - Known issues or notes

  **Must NOT do**:
  - Do NOT include secrets in the documentation
  - Do NOT include API keys in plain text

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Markdown documentation creation
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Tasks 5, 6)
  - **Blocks**: F1-F4
  - **Blocked By**: Task 6

  **References**:
  - `~/docker/worldmonitor/.env` - Secrets location (DO NOT include in docs)
  - `~/docker/worldmonitor/docker-compose.override.yml` - Config reference

  **Acceptance Criteria**:
  - [ ] `~/docker/worldmonitor/DEPLOYMENT.md` exists
  - [ ] Document contains port, labels, models, commands
  - [ ] Document does NOT contain secrets or API keys

  **QA Scenarios**:

  ```
  Scenario: Verify documentation
    Tool: Bash
    Preconditions: DEPLOYMENT.md created
    Steps:
      1. grep -c "3080" ~/docker/worldmonitor/DEPLOYMENT.md
      2. grep -c "proxy.worldmonitor" ~/docker/worldmonitor/DEPLOYMENT.md
      3. grep -c "nvidia/nemotron" ~/docker/worldmonitor/DEPLOYMENT.md
      4. grep -ci "secret\|password\|api_key" ~/docker/worldmonitor/DEPLOYMENT.md
    Expected Result: Port, labels, model found; secrets count = 0
    Failure Indicators: Missing info, secrets exposed
    Evidence: .omo/evidence/task-7-documentation.txt
  ```

  **Commit**: YES
  - Message: `docs(worldmonitor): add deployment reference`
  - Files: `~/docker/worldmonitor/DEPLOYMENT.md`

---

## Final Verification Wave (MANDATORY — after ALL implementation tasks)

> 4 review agents run in PARALLEL. ALL must APPROVE. Present consolidated results to user and get explicit "okay" before completing.

- [ ] F1. **Plan Compliance Audit** — `oracle`
  Read the plan end-to-end. For each "Must Have": verify implementation exists (read file, curl endpoint, run command). For each "Must NOT Have": search codebase for forbidden patterns — reject with file:line if found. Check evidence files exist in .omo/evidence/. Compare deliverables against plan.
  Output: `Must Have [N/N] | Must NOT Have [N/N] | Tasks [N/N] | VERDICT: APPROVE/REJECT`

- [ ] F2. **Code Quality Review** — `unspecified-high`
  Review docker-compose.override.yml and .env for: hardcoded secrets (should be generated), exposed ports that should be internal, missing resource limits, incorrect network modes. Check for AI slop: unnecessary comments, over-engineering, verbose configs.
  Output: `Config [CLEAN/N issues] | Secrets [SAFE/EXPOSED] | Resources [SET/MISSING] | VERDICT`

- [ ] F3. **Real Manual QA** — `unspecified-high`
  Start from clean state. Execute EVERY QA scenario from EVERY task — follow exact steps, capture evidence. Test cross-task integration (containers communicating, proxy routing, AI responding). Test edge cases: container restart, seed re-run, empty state. Save to `.omo/evidence/final-qa/`.
  Output: `Scenarios [N/N pass] | Integration [N/N] | Edge Cases [N tested] | VERDICT`

- [ ] F4. **Scope Fidelity Check** — `deep`
  For each task: read "What to do", read actual changes. Verify 1:1 — everything in spec was built (no missing), nothing beyond spec was built (no creep). Check "Must NOT do" compliance: godoxy not restarted, config not edited, no host Node.js installed. Flag unaccounted changes.
  Output: `Tasks [N/N compliant] | Scope [CLEAN/N issues] | Unaccounted [CLEAN/N files] | VERDICT`

---

## Commit Strategy

- **Task 1**: `chore(worldmonitor): add deployment config and secrets template` - .env, docker-compose.override.yml
- **Task 5**: No commit (runtime state only)
- **Task 7**: `docs(worldmonitor): add deployment reference` - DEPLOYMENT.md

---

## Success Criteria

### Verification Commands
```bash
# All 4 containers running
docker ps --filter "name=worldmonitor" --format "table {{.Names}}\t{{.Status}}" | grep -c "Up"  # Expected: 4

# Health check
curl -s http://localhost:3080/api/sidecar-health  # Expected: 200 OK

# Godoxy proxy
curl -sI https://worldmonitor.phillias.org  # Expected: 200 (after godoxy auto-discovers)

# OpenRouter AI test
curl -s http://localhost:3080/api/test-openrouter  # Expected: model response (if endpoint exists)
```

### Final Checklist
- [ ] All "Must Have" present
- [ ] All "Must NOT Have" absent
- [ ] All 4 containers healthy
- [ ] Port 3080 accessible locally
- [ ] Godoxy routing works (worldmonitor.phillias.org)
- [ ] OpenRouter AI features functional
