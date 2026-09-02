# Projects — fleet registry (merged 2026-08-27 from phillias-dev, primary55522, kali)
<!-- Hostnames are zone-relative: each project is served from its own Cloudflare zone. -->

- mybiz [no-mistakes-prod-only] - Harbor: AI-native Astro + Convex product site at its zone apex, Cloudflare Pages, GitHub phillias/mybiz (added 2026-08-12)
- miaction [no-mistakes] - Go + React bill tracker; live on its Cloudflare zone subdomain (Pages + Container backend) (added 2026-08-27, from kali)
- llpoa [no-mistakes] - Go + React bylaw search with RAG; live on its Cloudflare zone subdomain (Pages + Container backend) (added 2026-08-27, from kali)
- dotfiles [no-mistakes] - chezmoi source at ~/.local/share/chezmoi (canonical, no separate checkouts); apply target is the ENTIRE home directory, so the repo .no-mistakes.yaml zeroes all auto_fix — every finding escalates, never blanket --action fix; ask-user findings always captain-gated per captain.md (posture set 2026-09-02 after the stale-path incident; pipeline exonerated by forensics, driver-layer failures covered by escalation rules)
