import { Plugin } from "@opencode-ai/plugin";

const exhaustedSessions = new Set<string>();

function isExhaustionError(message: string): boolean {
  const m = message.toLowerCase();
  return m.includes("gousagelimiterror") ||
    m.includes("go usage limit") ||
    m.includes("go limit reached") ||
    m.includes("freeusagelimiterror") ||
    m.includes("free usage limit") ||
    m.includes("free usage exceeded");
}

export const GoPoolFallbackPlugin: Plugin = async () => {
  return {
    event: async ({ event }: { event: any }) => {
      if (event.type === "session.next.retried" &&
          event.error?.message &&
          isExhaustionError(event.error.message)) {
        exhaustedSessions.add(event.sessionID);
      }
    },

    "experimental.session.compacting": async (
      { sessionID }: { sessionID: string },
      output: { context: string[]; prompt?: string }
    ) => {
      if (exhaustedSessions.has(sessionID)) {
        output.context = output.context || [];
        output.context.push(
          "System: Go pool subscription exhausted. Free OpenRouter models in use."
        );
      }
    },
  };
};
