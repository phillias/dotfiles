---
name: xspace-pipeline
description: >
  Process X Spaces into AI-generated articles published on Beehiiv. Download Space audio,
  transcribe via OpenRouter Whisper, generate article via Gemini, publish as draft.
  Trigger: user mentions "process this space", "space to article", "x space", provides
  an X Spaces URL, or asks to run the pipeline.
compatibility: opencode
---

# X Spaces → Article Pipeline

## Trigger
User provides an X Spaces URL or says "process this space" / "run the pipeline".

## Quick Commands

### Process a specific space by URL:
```bash
python3 /data/pipeline/scripts/pipeline.py --space https://x.com/i/spaces/1YpJkwXXDrjJj
```

### Process by space ID:
```bash
python3 /data/pipeline/scripts/pipeline.py --space 1YpJkwXXDrjJj
```

### Poll for new spaces (one-shot):
```bash
python3 /data/pipeline/scripts/pipeline.py --once
```

### Continuous monitoring:
```bash
python3 /data/pipeline/scripts/pipeline.py
```

## What It Does
1. Downloads Space audio via `twspace_dl` (uses X cookies)
2. Uploads audio to OCI Object Storage
3. Transcribes via OpenRouter (Whisper large-v3)
4. Generates article via OpenRouter (Gemini 2.0 Flash)
5. Publishes as draft to Beehiiv (via Playwright + browser cookies)
6. Cleans up local audio, keeps transcript in OCI

## Requirements
- X cookies in `/data/pipeline/config/cookies.txt` (auth_token + ct0)
- OpenRouter API key in `.env`
- Beehiiv cookies in `.env`
- OCI CLI configured
- `twspace_dl` installed

## Output Locations
- Audio (transient): `/data/pipeline/tmp/{space_id}.m4a`
- Transcript (kept): `/data/pipeline/transcripts/{space_id}.md`
- State tracking: `/data/pipeline/config/state.json`
- Logs: `/data/pipeline/logs/pipeline.log`

## Troubleshooting
- Check logs: `tail -f /data/pipeline/logs/pipeline.log`
- If download fails: cookies may be expired — refresh from browser
- If transcription fails: check OpenRouter API key and rate limits
- If Beehiiv publish fails: session expired — re-login to studio.beehiiv.com
- Query IDs rotate every 2-4 weeks — update in `x-timeline.py` if polling breaks
