# shellcheck shell=sh
# Shared key loader for ~/.agents/keys/default profile
# Sourced by .zshenv (all zsh shells) and .profile (login shells)

# Load keys from the default profile only (~/.agents/keys/default symlink)
# Non-default profiles are selected by consumers via explicit path, never auto-loaded.
_default_profile="$(readlink "$HOME/.agents/keys/default" 2>/dev/null)" || _default_profile=""
if [ -z "$_default_profile" ] || [ ! -d "$HOME/.agents/keys/$_default_profile" ]; then
    # Silently skip if no default profile - non-interactive shells must not emit noise
    unset _default_profile
    return 0 2>/dev/null || exit 0
fi

# CF AI Gateway token - used by opencode, claude code, codex routing
if [ -r "$HOME/.agents/keys/$_default_profile/.cf-ai-gw" ]; then
    CF_AI_GATEWAY_TOKEN="$(cat "$HOME/.agents/keys/$_default_profile/.cf-ai-gw")" && export CF_AI_GATEWAY_TOKEN
fi

# Treg token
if [ -r "$HOME/.agents/keys/$_default_profile/.treg-token" ]; then
    TREG_TOKEN="$(cat "$HOME/.agents/keys/$_default_profile/.treg-token")" && export TREG_TOKEN
fi

# Treg key
if [ -r "$HOME/.agents/keys/$_default_profile/.treg-key" ]; then
    TREG_KEY="$(cat "$HOME/.agents/keys/$_default_profile/.treg-key")" && export TREG_KEY
fi

# Abliteration API
if [ -r "$HOME/.agents/keys/$_default_profile/.abliteration-key" ]; then
    ABLITERATION_API_KEY="$(cat "$HOME/.agents/keys/$_default_profile/.abliteration-key")" && export ABLITERATION_API_KEY
fi

# TSFM API
if [ -r "$HOME/.agents/keys/$_default_profile/.tsfm-key" ]; then
    TSFM_API_KEY="$(cat "$HOME/.agents/keys/$_default_profile/.tsfm-key")" && export TSFM_API_KEY
fi

# Phoenixgrove coding plan key
if [ -r "$HOME/.agents/keys/$_default_profile/.phoenixgrove-coding-plan-key" ]; then
    PHOENIXGROVE_CODING_PLAN_API_KEY="$(cat "$HOME/.agents/keys/$_default_profile/.phoenixgrove-coding-plan-key")" && export PHOENIXGROVE_CODING_PLAN_API_KEY
fi

# Provider API keys (flat key loading from default profile)
# Format: .<provider>-key -> <PROVIDER>_API_KEY

# Groq
if [ -r "$HOME/.agents/keys/$_default_profile/.groq-key" ]; then
    GROQ_API_KEY="$(cat "$HOME/.agents/keys/$_default_profile/.groq-key")" && export GROQ_API_KEY
fi

# Cerebras
if [ -r "$HOME/.agents/keys/$_default_profile/.cerebras-key" ]; then
    CEREBRAS_API_KEY="$(cat "$HOME/.agents/keys/$_default_profile/.cerebras-key")" && export CEREBRAS_API_KEY
fi

# Mistral
if [ -r "$HOME/.agents/keys/$_default_profile/.mistral-key" ]; then
    MISTRAL_API_KEY="$(cat "$HOME/.agents/keys/$_default_profile/.mistral-key")" && export MISTRAL_API_KEY
fi

# SambaNova
if [ -r "$HOME/.agents/keys/$_default_profile/.sambanova-key" ]; then
    SAMBANOVA_API_KEY="$(cat "$HOME/.agents/keys/$_default_profile/.sambanova-key")" && export SAMBANOVA_API_KEY
fi

# Google
if [ -r "$HOME/.agents/keys/$_default_profile/.google-key" ]; then
    GOOGLE_API_KEY="$(cat "$HOME/.agents/keys/$_default_profile/.google-key")" && export GOOGLE_API_KEY
fi

# Together
if [ -r "$HOME/.agents/keys/$_default_profile/.together-key" ]; then
    TOGETHER_API_KEY="$(cat "$HOME/.agents/keys/$_default_profile/.together-key")" && export TOGETHER_API_KEY
fi

# Zen (OpenCode Zen routing)
if [ -r "$HOME/.agents/keys/$_default_profile/.zen-key" ]; then
    OPENCODE_ZEN_API_KEY="$(cat "$HOME/.agents/keys/$_default_profile/.zen-key")" && export OPENCODE_ZEN_API_KEY
fi

# Cloudflare
if [ -r "$HOME/.agents/keys/$_default_profile/.cloudflare-key" ]; then
    CLOUDFLARE_API_KEY="$(cat "$HOME/.agents/keys/$_default_profile/.cloudflare-key")" && export CLOUDFLARE_API_KEY
fi

# Command Code
if [ -r "$HOME/.agents/keys/$_default_profile/.command-code-key" ]; then
    COMMAND_CODE_API_KEY="$(cat "$HOME/.agents/keys/$_default_profile/.command-code-key")" && export COMMAND_CODE_API_KEY
fi

# HuggingFace
if [ -r "$HOME/.agents/keys/$_default_profile/.hf-key" ]; then
    HF_API_KEY="$(cat "$HOME/.agents/keys/$_default_profile/.hf-key")" && export HF_API_KEY
fi

# NVIDIA
if [ -r "$HOME/.agents/keys/$_default_profile/.nvidia-key" ]; then
    NVIDIA_API_KEY="$(cat "$HOME/.agents/keys/$_default_profile/.nvidia-key")" && export NVIDIA_API_KEY
fi

# Baseten
if [ -r "$HOME/.agents/keys/$_default_profile/.baseten-key" ]; then
    BASETEN_API_KEY="$(cat "$HOME/.agents/keys/$_default_profile/.baseten-key")" && export BASETEN_API_KEY
fi

# Intern
if [ -r "$HOME/.agents/keys/$_default_profile/.intern-key" ]; then
    INTERN_API_KEY="$(cat "$HOME/.agents/keys/$_default_profile/.intern-key")" && export INTERN_API_KEY
fi

# OpenRouter
if [ -r "$HOME/.agents/keys/$_default_profile/.openrouter-key" ]; then
    OPENROUTER_API_KEY="$(cat "$HOME/.agents/keys/$_default_profile/.openrouter-key")" && export OPENROUTER_API_KEY
fi

# Zhipu (ZAI)
if [ -r "$HOME/.agents/keys/$_default_profile/.zai-key" ]; then
    ZHIPU_API_KEY="$(cat "$HOME/.agents/keys/$_default_profile/.zai-key")" && export ZHIPU_API_KEY
fi

# Google Workspace OAuth (MCP)
if [ -r "$HOME/.agents/keys/$_default_profile/.google-client-id" ]; then
    GOOGLE_CLIENT_ID="$(cat "$HOME/.agents/keys/$_default_profile/.google-client-id")" && export GOOGLE_CLIENT_ID
fi

if [ -r "$HOME/.agents/keys/$_default_profile/.google-client-secret" ]; then
    GOOGLE_CLIENT_SECRET="$(cat "$HOME/.agents/keys/$_default_profile/.google-client-secret")" && export GOOGLE_CLIENT_SECRET
fi

# Fireworks
if [ -r "$HOME/.agents/keys/$_default_profile/.fireworks-key" ]; then
    FIREWORKS_API_KEY="$(cat "$HOME/.agents/keys/$_default_profile/.fireworks-key")" && export FIREWORKS_API_KEY
fi

# Exa
if [ -r "$HOME/.agents/keys/$_default_profile/.exa-key" ]; then
    EXA_API_KEY="$(cat "$HOME/.agents/keys/$_default_profile/.exa-key")" && export EXA_API_KEY
fi

# Composio
if [ -r "$HOME/.agents/keys/$_default_profile/.composio-key" ]; then
    COMPOSIO_API_KEY="$(cat "$HOME/.agents/keys/$_default_profile/.composio-key")" && export COMPOSIO_API_KEY
fi

# DeepInfra
if [ -r "$HOME/.agents/keys/$_default_profile/.deepinfra-key" ]; then
    DEEPINFRA_API_KEY="$(cat "$HOME/.agents/keys/$_default_profile/.deepinfra-key")" && export DEEPINFRA_API_KEY
fi

# Friendli
if [ -r "$HOME/.agents/keys/$_default_profile/.friendli-key" ]; then
    FRIENDLI_API_KEY="$(cat "$HOME/.agents/keys/$_default_profile/.friendli-key")" && export FRIENDLI_API_KEY
fi

# Greptile
if [ -r "$HOME/.agents/keys/$_default_profile/.greptile-key" ]; then
    GREPTILE_API_KEY="$(cat "$HOME/.agents/keys/$_default_profile/.greptile-key")" && export GREPTILE_API_KEY
fi

# Qwen
if [ -r "$HOME/.agents/keys/$_default_profile/.qwen-key" ]; then
    QWEN_API_KEY="$(cat "$HOME/.agents/keys/$_default_profile/.qwen-key")" && export QWEN_API_KEY
fi

# Kenari
if [ -r "$HOME/.agents/keys/$_default_profile/.kenari-key" ]; then
    KENARI_API_KEY="$(cat "$HOME/.agents/keys/$_default_profile/.kenari-key")" && export KENARI_API_KEY
fi

# Synthetic
if [ -r "$HOME/.agents/keys/$_default_profile/.synthetic-key" ]; then
    SYNTHETIC_API_KEY="$(cat "$HOME/.agents/keys/$_default_profile/.synthetic-key")" && export SYNTHETIC_API_KEY
fi

# Seevio
if [ -r "$HOME/.agents/keys/$_default_profile/.seevio-key" ]; then
    SEEVIO_API_KEY="$(cat "$HOME/.agents/keys/$_default_profile/.seevio-key")" && export SEEVIO_API_KEY
fi

# AtlasCloud
if [ -r "$HOME/.agents/keys/$_default_profile/.atlascloud-key" ]; then
    ATLASCLOUD_API_KEY="$(cat "$HOME/.agents/keys/$_default_profile/.atlascloud-key")" && export ATLASCLOUD_API_KEY
fi

# Vercel AI Gateway
if [ -r "$HOME/.agents/keys/$_default_profile/.vercel-gateway-key" ]; then
    AI_GATEWAY_API_KEY="$(cat "$HOME/.agents/keys/$_default_profile/.vercel-gateway-key")" && export AI_GATEWAY_API_KEY
fi

# Vercel platform token (team-scoped, for virtual-model management)
if [ -r "$HOME/.agents/keys/$_default_profile/.vercel-token" ]; then
    VERCEL_TOKEN="$(cat "$HOME/.agents/keys/$_default_profile/.vercel-token")" && export VERCEL_TOKEN
fi

# Agnes
if [ -r "$HOME/.agents/keys/$_default_profile/.agnes-key" ]; then
    AGNES_API_KEY="$(cat "$HOME/.agents/keys/$_default_profile/.agnes-key")" && export AGNES_API_KEY
fi

# OpenCode (direct API key for opencode.ai)
if [ -r "$HOME/.agents/keys/$_default_profile/.opencode-key" ]; then
    OPENCODE_API_KEY="$(cat "$HOME/.agents/keys/$_default_profile/.opencode-key")" && export OPENCODE_API_KEY
fi

# Phoenixgrove (main API key; coding-plan key is separate)
if [ -r "$HOME/.agents/keys/$_default_profile/.phoenixgrove-key" ]; then
    PHOENIXGROVE_API_KEY="$(cat "$HOME/.agents/keys/$_default_profile/.phoenixgrove-key")" && export PHOENIXGROVE_API_KEY
fi

# Telegram bot token
if [ -r "$HOME/.agents/keys/$_default_profile/.telegram-key" ]; then
    TELEGRAM_API_KEY="$(cat "$HOME/.agents/keys/$_default_profile/.telegram-key")" && export TELEGRAM_API_KEY
fi

# GitHub Models
if [ -r "$HOME/.agents/keys/$_default_profile/.github-models-key" ]; then
    GITHUB_MODELS_API_KEY="$(cat "$HOME/.agents/keys/$_default_profile/.github-models-key")" && export GITHUB_MODELS_API_KEY
fi

# Meta Model API (muse harness native provider)
if [ -r "$HOME/.agents/keys/$_default_profile/.meta-key" ]; then
    META_API_KEY="$(cat "$HOME/.agents/keys/$_default_profile/.meta-key")" && export META_API_KEY
fi

unset _default_profile
