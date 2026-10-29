---
name: selfhost
description: >
  Runbook for the selfhost stack services. Currently covers Linkwarden
  (bookmarks) and its OCI Object Storage backend: architecture, scoped-IAM
  secrets layout, S3 verification, and credential-rewire procedure.
  Designed for AI consumption: teaches discovery over static reference.
  Use when working on selfhost stack services, especially Linkwarden and its OCI storage backend.
compatibility: opencode
metadata:
  stacks: selfhost
  services: linkwarden
  tools: docker compose,bws,oci,boto3
---

# Selfhost Stack Runbook

Ops runbook for AI agents for the selfhost stack. Teaches how to discover
live state rather than hardcoding it, plus the non-discoverable knowledge:
secret-store layout, failure archetypes, and verified procedures.

For Godoxy reverse-proxy routing, use the `godoxy-axi` CLI (ambient context)
— do not guess route config locations.

---

### linkwarden (Bookmarks)

**Architecture:**
```bash
docker inspect linkwarden --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}'
# compose: <workdir>/compose.yml — container `linkwarden`, env_file: .env
# web UI: :3001 (verify with root HTTP 200), public URL https://linkwarden.phillias.cc
```

**Storage backend (OCI Object Storage):**
- Bucket `linkwarden`, namespace `axh7zpa5qpqc`, region `us-chicago-1`
- Endpoint: `https://axh7zpa5qpqc.compat.objectstorage.us-chicago-1.oraclecloud.com`
- Scoped IAM (2026-10-25): user `linkwarden-spaces` in group
  `linkwarden-storage`, policy:
  `Allow group linkwarden-storage to manage objects in tenancy where target.bucket.name = 'linkwarden'`
  Blast radius of the pair is one bucket; other buckets return `NoSuchBucket`.

**Secrets — three stores, kept in sync (NEVER delete entries; rotate in place):**
1. Canonical: BWS project `phillias`, `SELFHOST_LINKWARDEN_OCI_BUCKET_KEY` /
   `SELFHOST_LINKWARDEN_OCI_BUCKET_SECRET`. `SELFHOST_*` names auto-export to
   every shell by `load-keys.sh`; `BWS_*` names are deploy-time only.
2. BWS project `SelfHost-Prod`: `BWS_LINKWARDEN_SPACES_KEY` /
   `BWS_LINKWARDEN_SPACES_SECRET` (legacy names, updated in place).
3. Legacy OCI Vault (superseded but maintained): KEY secret stores the
   **plaintext string**; SECRET secret stores **base64-decoded raw bytes**
   (decode the 44-char secret before storing). The two use different
   encodings — do not copy-paste one procedure to the other.

**Red flags:**
- `SignatureDoesNotMatch` / S3 403 in linkwarden logs = the container's
  SPACES pair is dead server-side. OCI customer secret keys: **max 2 per
  IAM user** — creating a new key on a maxed user can displace an existing
  one silently (this exact failure bit us: a global key creation killed the
  linkwarden pair while the container kept running on dead creds).
- Storage errors that name a different bucket than `linkwarden` = wrong
  pair in env (scoped pair cannot see other buckets).

**Health check:**
```bash
docker compose -f <workdir>/compose.yml ps linkwarden
docker logs linkwarden --tail=30 2>&1 | grep -i 'signature\|s3\|error'
curl -s -o /dev/null -w '%{http_code}' http://localhost:3001/   # expect 200
```

**Credential rewire procedure:**
1. Update `.env` in place (backup first, mode 600; sed with shell-captured
   vars — never echo values).
2. `docker compose up -d --force-recreate linkwarden`
3. Verify: container env `SPACES_KEY` prefix matches the new access id,
   logs clean of S3 errors, web 200.

**S3 verification (proves pair + policy scope):**
```python
# system python3 (3.8) + boto3; the checksum flags are REQUIRED —
# OCI S3-compat rejects AWS chunked encoding ('NotImplemented')
import boto3
from botocore.config import Config
s3 = boto3.client("s3", endpoint_url=ENDPOINT, region_name="us-chicago-1",
    aws_access_key_id=KEY, aws_secret_access_key=SECRET,
    config=Config(signature_version="s3v4",
        s3={"payload_signing_enabled": True},
        request_checksum_calculation="when_required",
        response_checksum_validation="when_required"))
s3.list_objects_v2(Bucket="linkwarden", MaxKeys=1)          # list OK
s3.put_object(Bucket="linkwarden", Key="probe", Body=b"x")   # put/get/delete
s3.list_objects_v2(Bucket="Dev", MaxKeys=1)                  # expect NoSuchBucket
```

**OCI CLI notes:**
- `~/.local/bin/oci` (3.82.0); export `SUPPRESS_LABEL_WARNING=True` for
  quiet output.
- Update a vault secret: `oci vault secret update --secret-id <ocid>
  --secret-content '{"content":"<b64>","contentType":"BASE64","stage":"CURRENT"}'
  --force` (NOT `--secret-content-content`; `--force` skips the y/N prompt).
  Read back with `oci secrets secret-bundle get`. Always verify read-back —
  bad flags have failed silently under redirected output.
- oci-sdk on py3.8 raises `TypeError: Unrecognized keyword arguments:
  user_id` for customer-secret-key calls — use the CLI instead.
- cryptography version pin: oci-cli requires `cryptography<47`; boto3 does
  not care. After any `pip3 install --user cryptography` upgrade, re-test
  `oci --version` and downgrade if the CLI breaks.
