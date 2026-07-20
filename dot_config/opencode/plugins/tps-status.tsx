/**
 * tps-status — TUI plugin that shows TPS, cumulative token usage, and the
 * project workspace directory in the session prompt-right slot.
 *
 * Data source: session.next.step.started / session.next.step.ended events.
 * TPS is computed client-side from per-step timestamps (acceptable drift).
 * No upstream patching required — pure plugin via the slot system.
 */
/** @jsxImportSource @opentui/solid */
import type { TuiPlugin } from "@opencode-ai/plugin/tui"
import { createSignal, Show } from "solid-js"

// ── helpers ──────────────────────────────────────────────────────────
function abbreviateHome(dir: string, home?: string): string {
  if (home && dir.startsWith(home)) return "~" + dir.slice(home.length)
  return dir
}

function fmtTokens(n: number): string {
  if (n >= 1_000_000) return (n / 1_000_000).toFixed(1) + "m"
  if (n >= 10_000) return Math.round(n / 1_000) + "k"
  if (n >= 1_000) return (n / 1_000).toFixed(1) + "k"
  return String(n)
}

// ── plugin ───────────────────────────────────────────────────────────
const tui: TuiPlugin = async (api) => {
  // Per-step bookkeeping (not reactive — transient between started→ended)
  const stepStarts = new Map<string, { timestamp: number; agent: string }>()

  // Session-scoped cumulative totals + most-recent TPS
  const [stats, setStats] = createSignal({
    tps: null as number | null,
    input: 0,
    output: 0,
    lastAgent: "" as string,
  })

  const unsub1 = api.event.on("session.next.step.started", (e) => {
    if (e.type !== "session.next.step.started") return
    stepStarts.set(e.properties.sessionID, {
      timestamp: e.properties.timestamp,
      agent: e.properties.agent,
    })
  })

  const unsub2 = api.event.on("session.next.step.ended", (e) => {
    if (e.type !== "session.next.step.ended") return
    const start = stepStarts.get(e.properties.sessionID)
    if (!start) return

    const elapsedSec = (e.properties.timestamp - start.timestamp) / 1000
    const tps = elapsedSec > 0 ? Math.round(e.properties.tokens.output / elapsedSec) : null

    setStats((prev) => ({
      tps,
      input: prev.input + e.properties.tokens.input,
      output: prev.output + e.properties.tokens.output,
      lastAgent: start.agent,
    }))

    stepStarts.delete(e.properties.sessionID)
  })

  // ── slot renderer ──────────────────────────────────────────────────
  api.slots.register({
    order: 50,
    slots: {
      session_prompt_right(_ctx, _props) {
        const theme = () => api.theme.current
        const dir = api.state.path?.directory ?? ""
        const home = api.state.path?.home
        const s = stats()

        return (
          <box flexDirection="row" gap={1} flexShrink={0}>
            {/* workspace directory */}
            <Show when={dir}>
              <text fg={theme().textMuted}>{abbreviateHome(dir, home)}</text>
            </Show>

            {/* cumulative tokens */}
            <Show when={s.input > 0 || s.output > 0}>
              <text fg={theme().textMuted}>
                {fmtTokens(s.input)}→{fmtTokens(s.output)}
              </text>
            </Show>

            {/* live TPS */}
            <Show when={s.tps !== null}>
              <text fg={theme().text}>{s.tps} tok/s</text>
            </Show>
          </box>
        )
      },
    },
  })

  // Cleanup on plugin unload
  return () => {
    unsub1()
    unsub2()
  }
}

export default {
  id: "tps-status",
  tui,
}
