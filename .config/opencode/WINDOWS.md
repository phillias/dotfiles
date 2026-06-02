# Windows Opencode Config

When running chezmoi on native Windows, .config/opencode/ maps to:
  %USERPROFILE%\.config\opencode\

Files are cross-platform compatible (JSON/text). No OS-specific changes needed.

Opencode install methods on Windows:
  - scoop install opencode
  - choco install opencode
  - npm install -g opencode-ai
  - Desktop app: https://opencode.ai/download

Serve.env may need different credentials per machine — use chezmoi templates
with {{ if eq .chezmoi.os "windows" }} conditionals if needed.
