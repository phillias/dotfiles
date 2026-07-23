# docker-axi

Agent-facing Docker operations AXI for discovering, planning, building,
running, debugging, publishing, inspecting, and cleaning up Docker-based apps
through safe token-efficient CLI workflows.

The project follows the AXI creation guidelines installed with
`npx skills add kunchenguid/axi`.

## Goals

- Show useful live Docker context with `docker-axi`, not help text.
- Use compact TOON-style stdout for agent parsing.
- Keep every command non-interactive.
- Fail loudly on unknown flags before side effects.
- Default to read-only discovery, planning, or dry-run behavior.
- Require `--execute` for mutations and cleanup.
- Truncate long logs and inspect output by default.
- Redact credentials and secrets from env, labels, build args, compose files,
  inspect output, and logs.

## Usage

```sh
npm test
./bin/docker-axi.js
./bin/docker-axi.js doctor
./bin/docker-axi.js services
./bin/docker-axi.js discover
./bin/docker-axi.js recommend --goal fullstack
./bin/docker-axi.js plan --target <id> --environment local
./bin/docker-axi.js build --target <id> --tag app:local
./bin/docker-axi.js run --target <id> --name app --ports 8080:8080 --env-file .env
./bin/docker-axi.js compose up --file docker-compose.yml
./bin/docker-axi.js clean --kind containers
```

Mutating operations are dry-run by default. Add `--execute` only after reviewing
the generated command and preflight output.

## Docker Domains

- Build: Dockerfile, BuildKit, multi-stage builds, build args with redaction
- Runtime: containers, ports, env files, health checks, restart policy
- Compose: compose files, services, dependencies, profiles, volumes, networks
- Registry: login status, tags, pull/push planning, Docker Hub, GHCR, ECR naming
- Debugging: logs, inspect, events, exec, stats
- Storage/networking: volumes, bind mounts, networks
- Cleanup: safe dry-run prune workflows
- Security: secret redaction, non-root hints, exposed ports, image size
- Local dev: devcontainers and compose-based dev stacks
- CI/CD: build and publish command planning

## Custom Targets

`docker-axi.config.json` can define project-specific workflows:

```json
{
  "targets": [
    {
      "id": "api",
      "type": "custom",
      "path": ".",
      "tag": "ghcr.io/thatdudealso/api:local",
      "commands": {
        "plan": ["docker", "buildx", "bake", "--print"],
        "apply": ["docker", "compose", "up", "--build", "-d"]
      }
    }
  ]
}
```

Command templates may use `${environment}`. Do not put secrets in command
templates; use env files or Docker secrets instead.

## Hooks and Skill

Install ambient session context hooks after explicit opt-in:

```sh
docker-axi hooks install --agent all --scope project --execute
```

Generate or verify installable skill guidance:

```sh
docker-axi skill generate
docker-axi skill generate --check
```

## AXI Catalog Entry

The upstream `kunchenguid/axi` community catalog entry should be:

- AXI: `docker-axi`
- Author: `thatdudealso`
- Domain: `Docker`
- Description: `Discover, build, run, debug, publish, inspect, and clean up Docker apps through safe token-efficient CLI workflows.`
- Link: `https://github.com/thatdudealso/docker-axi`
