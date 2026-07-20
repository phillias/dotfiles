import type { Plugin } from "@opencode-ai/plugin";
import { readFileSync, writeFileSync, existsSync } from "fs";
import { createHash } from "crypto";
import { join } from "path";
import { homedir } from "os";

// ── tmux patch persistence ───────────────────────────────────────────
// Upstream oh-my-openagent v4.9.1 ships `buildTmuxPlaceholderCommand()`
// in 4 spawn functions: spawnTmuxPane, replaceTmuxPane, spawnTmuxWindow,
// spawnTmuxSession. We prefer `buildTmuxAttachCommand()` so the agent's
// output streams immediately into the tmux pane rather than showing a
// "click to attach" placeholder.
//
// This plugin re-applies the patch on session.created when upstream's
// fingerprint is detected. It does NOT touch files in an unknown state.
// ──────────────────────────────────────────────────────────────────────

const PATCH_TARGET = join(
  homedir(),
  ".cache/opencode/packages/oh-my-openagent@latest/node_modules/oh-my-openagent/dist/index.js",
);

const FINGERPRINT_UPSTREAM_V4_9_1 = "c20c800c1ea3785533e2bc8dac076439a0d33622";
const UNPATCHED_SIGNATURE = "const placeholderCmd = buildTmuxPlaceholderCommand(description);";
const UNPATCHED_ATTACH_SIGNATURE = "return `opencode attach ${shellSingleQuote(serverUrl)} --session ${shellSingleQuote(member.sessionId)} --dir ${shellSingleQuote(getPaneWorkingDirectory(member))}`;";
const UNPATCHED_TMUX_ATTACH_SIGNATURE = 'return `${TMUX_COMMAND_SHELL} -c "opencode attach ${escapedUrl} --session ${escapedSessionId} --dir ${escapedDirectory}"`;';

const TRACKED_FUNCTIONS = new Set(["spawnTmuxPane", "replaceTmuxPane", "spawnTmuxWindow", "spawnTmuxSession"]);
const SERVER_VAR: Record<string, string> = {
  spawnTmuxPane: "serverUrl",
  replaceTmuxPane: "_serverUrl",
  spawnTmuxWindow: "serverUrl",
  spawnTmuxSession: "serverUrl",
};

let patchAppliedThisProcess = false;

function sha1hex(content: Buffer | string): string {
  return createHash("sha1").update(content).digest("hex");
}

function isUnpatched(content: string): boolean {
  return content.includes(UNPATCHED_SIGNATURE) || content.includes(UNPATCHED_ATTACH_SIGNATURE) || content.includes(UNPATCHED_TMUX_ATTACH_SIGNATURE);
}

function applyPatch(content: string): string {
  const lines = content.split("\n");
  const out: string[] = [];
  let currentFunction = "";

  for (const line of lines) {
    const openFn = line.match(/^async function (\w+)\b/);
    if (openFn) {
      currentFunction = TRACKED_FUNCTIONS.has(openFn[1]) ? openFn[1] : "";
    }

    if (line.includes(UNPATCHED_SIGNATURE)) {
      const sv = currentFunction ? SERVER_VAR[currentFunction] : "serverUrl";
      const indent = (line.match(/^(\s*)/) ?? ["", ""])[1];
      out.push(`${indent}const attachCmd = buildTmuxAttachCommand(${sv}, sessionId, _directory);`);
      continue;
    }

    // Patch buildAttachCommand to keep pane open after session ends
    if (line.includes(UNPATCHED_ATTACH_SIGNATURE)) {
      const indent = (line.match(/^(\s*)/) ?? ["", ""])[1];
      out.push(`${indent}const escapedUrl = shellSingleQuote(serverUrl);`);
      out.push(`${indent}const escapedSessionId = shellSingleQuote(member.sessionId);`);
      out.push(`${indent}const escapedDir = shellSingleQuote(getPaneWorkingDirectory(member));`);
      out.push(`${indent}return \`/bin/sh -c 'opencode attach \${escapedUrl} --session \${escapedSessionId} --dir \${escapedDir} ; echo "\\\\n\\\\n[Session ended. Press any key to close pane.]"; read -n1 -s'\`;`);
      continue;
    }

    // Patch buildTmuxAttachCommand to keep pane open after session ends
    if (line.includes(UNPATCHED_TMUX_ATTACH_SIGNATURE)) {
      const indent = (line.match(/^(\s*)/) ?? ["", ""])[1];
      out.push(`${indent}return \`\${TMUX_COMMAND_SHELL} -c "opencode attach \${escapedUrl} --session \${escapedSessionId} --dir \${escapedDirectory} ; echo '\\\\n\\\\n[Session ended. Press any key to close pane.]' ; read -n1 -s"\`;`);
      continue;
    }

    out.push(line.replace(/\bplaceholderCmd\b/g, "attachCmd"));
  }

  return out.join("\n");
}

export const TmuxPatchKeeperPlugin: Plugin = async () => {
  return {
    event: async (input: { event: { type: string; properties?: any } }) => {
      try {
        if (input.event.type !== "session.created") return;
        if (patchAppliedThisProcess) return;
        if (!existsSync(PATCH_TARGET)) return;

        const content = readFileSync(PATCH_TARGET, "utf-8");
        if (!isUnpatched(content)) {
          patchAppliedThisProcess = true;
          return;
        }

        const fingerprint = sha1hex(content);
        if (fingerprint !== FINGERPRINT_UPSTREAM_V4_9_1) {
          console.warn(
            `[tmux-patch-keeper] dist/index.js is unpatched but fingerprint is unknown (${fingerprint}). Skipping — refusing to patch a drifted upstream.`,
          );
          patchAppliedThisProcess = true;
          return;
        }

        console.warn("[tmux-patch-keeper] Upstream detected — re-applying tmux attach patch.");
        const patched = applyPatch(content);
        writeFileSync(PATCH_TARGET, patched);

        const newContent = readFileSync(PATCH_TARGET, "utf-8");
        if (isUnpatched(newContent)) {
          console.error("[tmux-patch-keeper] Patch FAILED — unpatched signature still present.");
          return;
        }
        console.warn("[tmux-patch-keeper] Patch confirmed applied.");
        patchAppliedThisProcess = true;
      } catch (err) {
        console.error("[tmux-patch-keeper] error:", err);
      }
    },
  };
};