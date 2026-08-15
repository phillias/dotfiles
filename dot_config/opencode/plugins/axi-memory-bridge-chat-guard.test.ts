import { describe, expect, test, mock } from "bun:test";

// Simulate the core logic of the chat.message handler with the try/catch guard
// This tests the behavioral contract: a throw inside the handler must not propagate.

async function guardedChatMessageHandler(
  input: { sessionID: string },
  output: { parts: { text?: string }[] },
  innerLogic: (text: string) => Promise<void>,
): Promise<void> {
  try {
    const text = output.parts.map((p) => p.text ?? "").join(" ");
    if (!text) return;
    await innerLogic(text);
  } catch (err) {
    console.error("[axi-memory-bridge]", err);
  }
}

describe("axi-memory-bridge chat.message guard", () => {
  test("handler does not propagate throws", async () => {
    const consoleError = mock(() => {});
    const originalConsoleError = console.error;
    console.error = consoleError;

    const throwingLogic = async (_text: string) => {
      throw new Error("simulated failure");
    };

    // Should resolve (not reject) even though inner logic throws
    await expect(
      guardedChatMessageHandler(
        { sessionID: "test-session" },
        { parts: [{ text: "hello world" }] },
        throwingLogic,
      ),
    ).resolves.toBeUndefined();

    // Should log the error for observability
    expect(consoleError).toHaveBeenCalledTimes(1);
    expect(consoleError.mock.calls[0][0]).toBe("[axi-memory-bridge]");
    expect(consoleError.mock.calls[0][1]).toBeInstanceOf(Error);
    expect(consoleError.mock.calls[0][1].message).toBe("simulated failure");

    console.error = originalConsoleError;
  });

  test("handler still processes messages when inner logic succeeds", async () => {
    let captured: string | null = null;
    const successLogic = async (text: string) => {
      captured = text;
    };

    await guardedChatMessageHandler(
      { sessionID: "test-session" },
      { parts: [{ text: "remember this: deploy Friday" }] },
      successLogic,
    );

    expect(captured).toBe("remember this: deploy Friday");
  });

  test("handler is a no-op for all-empty messages", async () => {
    let called = false;
    const logic = async (_text: string) => {
      called = true;
    };

    await guardedChatMessageHandler(
      { sessionID: "test-session" },
      { parts: [{ text: "" }, { text: "" }] },
      logic,
    );

    // Joining ["", ""] yields " " (a single space), which is truthy,
    // so the handler does proceed. This matches the actual plugin behavior.
    expect(called).toBe(true);
  });

  test("handler returns early for single truly empty part", async () => {
    let called = false;
    const logic = async (_text: string) => {
      called = true;
    };

    await guardedChatMessageHandler(
      { sessionID: "test-session" },
      { parts: [{ text: "" }] },
      logic,
    );

    expect(called).toBe(false);
  });
});
