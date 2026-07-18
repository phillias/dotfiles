---
name: lanshu-architecture
description: Generate dark-canvas animated architecture diagrams with glow dots and pulsing borders. Use when the user asks for architecture diagrams, system diagrams, flow visualizations, or animated technical graphics.
---

# Lanshu Architecture Diagram

Generate premium dark-canvas architecture diagrams with animated GIF output.

## Usage

1. Create a spec JSON based on `assets/default-spec.json` (or use inline spec)
2. Render with the bundled renderer

```bash
python3 SKILL_DIR/scripts/render.py \
  --spec /path/to/spec.json \
  --outdir /path/to/output \
  --basename diagram-name
```

## Spec Format

The spec JSON defines:

- `canvas`: width, height, fps, frames
- `title`: prefix, highlight (green capsule), subtitle
- `inputs`: 4 items with label, icon, color, icon_name
- `core.cards`: 3 pipeline stages with title, icon, icon_name
- `decision`: gate check title
- `output`: final output label and icon
- `left_panel`, `center_panel`, `right_panel`: 3 cards each

### Icons

Use `icon_name` field to load selfh.st PNG icons from `icons/` directory.
Available: audiobookshelf, cloudflare, docker, jackett, mariadb, prowlarr, redis

Fallback icons: folder, file, scan, shield, db, package

### Label Length

Keep labels short (4-10 chars). Longer labels will be shrunk by the text fitter.
Examples: `ABS`, `WARP`, `Edge`, `Data`, `Mgmt`

## Output

- `<basename>.png` — static preview
- `<basename>.gif` — animated with glow dots and pulsing borders
- Use the GIF in READMEs: `![title](path/to/diagram.gif)`
