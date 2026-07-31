---
name: oci-vault-secrets
description: >
  Creates and manages secrets in Oracle Cloud Infrastructure (OCI) Vault.
  Can create secrets from environment variables or user-provided values,
  retrieve existing secret OCIDs, and update local config files with
  the new OCIDs. Supports OpenCode Telegram bot, Linkwarden, and other
  Docker Compose services that use vault-init.sh for secret injection.
  Trigger: user mentions "OCI Vault", "create secret", "vault secret",
  "sweep secrets", "oracle vault", "oci vault create", "oci vault secrets"
license: MIT
compatibility: opencode
metadata:
  tools: oci-cli
  services: opencode-telegram-bot,linkwarden
  oci-services: kms,vault,secrets
---
