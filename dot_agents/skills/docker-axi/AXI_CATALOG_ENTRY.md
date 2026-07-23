# AXI Catalog Entry

Use this entry when contributing `docker-axi` to the `kunchenguid/axi`
community catalog so it appears on axi.md.

| AXI | Author | Domain | Description |
| --- | --- | --- | --- |
| [`docker-axi`](https://github.com/thatdudealso/docker-axi) | thatdudealso | Docker | Discover, build, run, debug, publish, inspect, and clean up Docker apps through safe token-efficient CLI workflows. |

## Upstream Checklist

```sh
git -C /Users/thatdudealso/axi fetch origin
git -C /Users/thatdudealso/axi switch -C docs/add-docker-axi-catalog-entry origin/main
pnpm install --frozen-lockfile
pnpm run format:check
pnpm run lint
pnpm --dir packages/axi-sdk-js run build
pnpm --dir packages/axi-sdk-js test
no-mistakes init --fork-url git@github.com:thatdudealso/axi.git
git push no-mistakes
```

Commit message:

```sh
docs: add docker-axi to community catalog
```
