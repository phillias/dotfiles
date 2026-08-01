import type { Plugin } from "@opencode-ai/plugin";
import { execFile } from "node:child_process";

// ── tmux subagent pane activator ───────────────────────────────────────
// oh-my-openagent >= 4.19 spawns background-subagent tmux panes as
// PLACEHOLDERS ("OMO subagent pane ready: <desc> / Focus this pane to
// attach.") unless running under cmux: `spawnTmuxPane` etc. choose
// `buildTmuxPlaceholderCommand()` when `isCmuxCompatEnvironment()` is
// false (regular tmux), and the pane only goes live once the user
// focuses/clicks it (tmux-session-manager.activateFocusedPanes, 2s poll).
//
// This plugin restores the pre-4.19 streaming behavior: on `session.created`
// for a subagent session (has parentID), it watches for the placeholder pane
// (title `omo-subagent-<desc>`, command `sleep`) to appear and immediately
// respawns it with `opencode attach <url> --session <id> --dir <dir>` —
// the same command OmO's own activation path uses.
//
// ATTACH TARGET (verified 2026-07-31): `opencode attach` requires the full
// REST API. A bare `opencode` TUI's embedded server serves only `/` — every
// route 404s ("Error: not found", pane dies instantly). The embedded server
// serves the full API only when the TUI is launched with an explicit port
// (`opencode --port N` — the `oc` launcher does this) or is itself attached
// to a serve daemon. Resolution priority (self-first, portable):
//   1. input.serverUrl (SELF) if it answers a capabilities probe — works for
//      `opencode --port N` TUIs and attach-client TUIs on any machine
//   2. $OPENCODE_SERVE_URL (explicit override, may embed basic auth)
//   3. $OPENCODE_PORT || 4096 (OmO convention; fails gracefully if idle)
//
// Guards:
//   - Only panes still in placeholder state (command sleep/sh, no opencode)
//     are touched, so team-layout panes (already attached) and already-
//     activated panes are never double-respawned.
//   - Not inside tmux -> no-op.
//   - Pending sessions expire after PENDING_TTL_MS if no pane appears
//     (e.g. spawn deferred by capacity) and are silently dropped.
// ────────────────────────────────────────────────────────────────────────

const POLL_INTERVAL_MS = 700;
const PENDING_TTL_MS = 90_000;
const TITLE_PREFIX = "omo-subagent-";

interface Pending {
  sessionId: string;
  title: string;
  createdAt: number;
}

function shellSingleQuote(value: string): string {
  return `'${value.replace(/'/g, `'\\''`)}'`;
}

function runTmux(args: string[]): Promise<string | null> {
  return new Promise((resolve) => {
    execFile("tmux", args, { timeout: 5000 }, (err, stdout) => {
      if (err) {
        resolve(null);
        return;
      }
      resolve(stdout);
    });
  });
}

interface PaneInfo {
  paneId: string;
  title: string;
  command: string;
}

async function listPanes(): Promise<PaneInfo[]> {
  const out = await runTmux([
    "list-panes",
    "-a",
    "-F",
    "#{pane_id}\t#{pane_title}\t#{pane_current_command}",
  ]);
  if (!out) return [];
  return out
    .split("\n")
    .filter(Boolean)
    .map((line) => {
      const [paneId, title, command] = line.split("\t");
      return { paneId, title: title ?? "", command: command ?? "" };
    });
}

/** True only for panes still running the placeholder idle loop. */
function isPlaceholder(pane: PaneInfo): boolean {
  if (!pane.title.startsWith(TITLE_PREFIX)) return false;
  if (pane.command.includes("opencode")) return false; // already activated
  return pane.command === "sleep" || pane.command === "sh";
}

function buildAttachCommand(serverUrl: string, sessionId: string, directory: string): string {
  // Same shape as oh-my-openagent's buildTmuxAttachCommand + the old
  // tmux-patch-keeper keep-open wrapper (printf %b, POSIX read with a var —
  // bare `read` errors on dash: "read: arg count", killing the pane).
  return (
    `/bin/sh -c 'opencode attach ${shellSingleQuote(serverUrl)} --session ${shellSingleQuote(sessionId)} --dir ${shellSingleQuote(directory)}; ` +
    `printf "%b\\n\\n" "[Session ended. Press any key to close pane.]"; read x'`
  );
}

/** True when the URL serves the full API that `opencode attach` requires. */
async function isFullServer(url: string): Promise<boolean> {
  try {
    const res = await fetch(`${url}/experimental/capabilities`, {
      signal: AbortSignal.timeout(1500),
    });
    return res.ok;
  } catch {
    return false;
  }
}

export const TmuxSubagentActivatorPlugin: Plugin = async (input) => {
  if (!process.env.TMUX) {
    return {}; // not inside tmux — nothing to activate
  }

  const pending = new Map<string, Pending>();
  const activatedSessions = new Set<string>();
  const activatedPanes = new Set<string>();
  let timer: ReturnType<typeof setTimeout> | undefined;
  let ticking = false;

  // Attach target, self-first and portable: `opencode attach` needs the full
  // REST API, which the embedded server only serves when the TUI runs with an
  // explicit port or as an attach client. Probe input.serverUrl before falling
  // back to the env override, then the OmO convention.
  const selfUrl = (() => {
    const url = input.serverUrl;
    if (url && url.port && url.port !== "0") return url.origin;
    return null;
  })();
  const serverUrl =
    (selfUrl && (await isFullServer(selfUrl)) ? selfUrl : null) ??
    (process.env.OPENCODE_SERVE_URL?.trim().replace(/\/+$/, "") || null) ??
    `http://localhost:${process.env.OPENCODE_PORT || "4096"}`;

  function scheduleTick(): void {
    if (!timer && pending.size > 0) {
      timer = setTimeout(() => {
        void tick();
      }, POLL_INTERVAL_MS);
    }
  }

  async function tick(): Promise<void> {
    timer = undefined;
    if (ticking) return;
    ticking = true;
    try {
      const now = Date.now();
      for (const [sessionId, p] of pending) {
        if (now - p.createdAt > PENDING_TTL_MS) pending.delete(sessionId);
      }
      if (pending.size === 0) return;

      const placeholders = (await listPanes()).filter(
        (pl) => isPlaceholder(pl) && !activatedPanes.has(pl.paneId),
      );

      for (const [sessionId, p] of pending) {
        if (activatedSessions.has(sessionId)) {
          pending.delete(sessionId);
          continue;
        }
        if (placeholders.length === 0) break;

        const wantExact = p.title ? `${TITLE_PREFIX}${p.title.slice(0, 20)}` : "";
        const wantPrefix = p.title ? `${TITLE_PREFIX}${p.title.slice(0, 12)}` : "";

        let pane = placeholders.find((pl) => wantExact && pl.title === wantExact);
        if (!pane) pane = placeholders.find((pl) => wantPrefix && pl.title.startsWith(wantPrefix));
        if (!pane && placeholders.length === 1 && now - p.createdAt >= 3000) {
          pane = placeholders[0]; // best effort: sole unmatched placeholder
        }
        if (!pane) continue; // wait for the pane to appear / disambiguate

        const command = buildAttachCommand(serverUrl, sessionId, input.directory);
        const result = await runTmux(["respawn-pane", "-k", "-t", pane.paneId, command]);
        if (result === null) continue; // tmux hiccup — retry next tick

        // Keep a naturally-ended pane inspectable: the running tmux server
        // predates the config's `remain-on-exit on` and closes panes on exit.
        const windowId = await runTmux(["display", "-p", "-t", pane.paneId, "#{window_id}"]);
        if (windowId !== null && windowId.trim()) {
          await runTmux(["set-option", "-t", windowId.trim(), "remain-on-exit", "on"]);
        }

        activatedSessions.add(sessionId);
        activatedPanes.add(pane.paneId);
        pending.delete(sessionId);
        placeholders.splice(placeholders.indexOf(pane), 1);
        console.log(`[tmux-subagent-activator] activated pane ${pane.paneId} (session ${sessionId})`);
      }

      if (pending.size > 0) scheduleTick();
    } catch (err) {
      console.error("[tmux-subagent-activator] tick error:", err);
    } finally {
      ticking = false;
    }
  }

  return {
    event: async ({ event }) => {
      try {
        if (event.type !== "session.created") return;
        const props = event.properties as { info?: { id?: string; parentID?: string; title?: string }; sessionID?: string } | undefined;
        const info = props?.info;
        const sessionId = info?.id ?? props?.sessionID;
        const parentID = info?.parentID;
        if (!sessionId || !parentID) return; // only subagent sessions get panes
        pending.set(sessionId, { sessionId, title: info?.title ?? "", createdAt: Date.now() });
        scheduleTick();
      } catch (err) {
        console.error("[tmux-subagent-activator] event error:", err);
      }
    },
  };
};
