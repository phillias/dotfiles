import { describe, expect, test } from "bun:test";
import {
  DEFAULT_BUDGET_TOKENS,
  TURN_CLOSE,
  TURN_OPEN,
  appendTurn,
  buildCompactionPrompt,
  computeBudget,
  enforceBudget,
  estimateTokens,
  evaluateEdit,
  liveContextFileName,
  parseConfig,
  parseLiveContext,
  resolveEnabled,
  sanitizeSessionID,
  serializeLiveContext,
} from "./clm-context-core";

describe("estimateTokens", () => {
  test("empty is zero", () => {
    expect(estimateTokens("")).toBe(0);
  });
  test("rounds up at 4 chars per token", () => {
    expect(estimateTokens("abcd")).toBe(1);
    expect(estimateTokens("abcde")).toBe(2);
    expect(estimateTokens("a".repeat(400))).toBe(100);
  });
});

describe("serialize / parse round trip", () => {
  test("round trips roles and content", () => {
    const messages = [
      { role: "user" as const, content: "hello\nworld" },
      { role: "assistant" as const, content: "hi there" },
    ];
    const text = serializeLiveContext(messages);
    expect(text).toContain(`${TURN_OPEN} user 1`);
    expect(text).toContain(`${TURN_OPEN} assistant 2`);
    const parsed = parseLiveContext(text);
    expect(parsed.ok).toBe(true);
    if (parsed.ok) expect(parsed.messages).toEqual(messages);
  });

  test("round trips content containing the end marker", () => {
    const messages = [
      { role: "user" as const, content: "before\n@@END\nafter" },
      { role: "assistant" as const, content: "  @@END" },
      { role: "system" as const, content: "\\@@END" },
      { role: "user" as const, content: "backslash \\ then text" },
      { role: "assistant" as const, content: "@@TURN user 99\nstill content" },
    ];
    const parsed = parseLiveContext(serializeLiveContext(messages));
    expect(parsed.ok).toBe(true);
    if (parsed.ok) expect(parsed.messages).toEqual(messages);
  });

  test("empty input parses to an empty context", () => {
    const parsed = parseLiveContext("");
    expect(parsed.ok).toBe(true);
    if (parsed.ok) expect(parsed.messages).toEqual([]);
  });

  test("tolerates comments and blank lines outside blocks", () => {
    const text = `# my notes\n\n${TURN_OPEN} user 1\nhi\n${TURN_CLOSE}\n\n# trailing\n`;
    const parsed = parseLiveContext(text);
    expect(parsed.ok).toBe(true);
    if (parsed.ok) expect(parsed.messages).toEqual([{ role: "user", content: "hi" }]);
  });
});

describe("parseLiveContext rejects malformed input", () => {
  test("invalid role", () => {
    const parsed = parseLiveContext(`${TURN_OPEN} robot 1\nhi\n${TURN_CLOSE}`);
    expect(parsed.ok).toBe(false);
    if (!parsed.ok) expect(parsed.line).toBe(1);
  });
  test("missing role", () => {
    const parsed = parseLiveContext(`${TURN_OPEN}\nhi\n${TURN_CLOSE}`);
    expect(parsed.ok).toBe(false);
  });
  test("missing close marker", () => {
    const parsed = parseLiveContext(`${TURN_OPEN} user 1\nhi`);
    expect(parsed.ok).toBe(false);
  });
  test("content outside a block", () => {
    const parsed = parseLiveContext(`stray line`);
    expect(parsed.ok).toBe(false);
    if (!parsed.ok) expect(parsed.line).toBe(1);
  });
});

describe("computeBudget", () => {
  test("counts blocks, chars and tokens", () => {
    const budget = computeBudget([
      { role: "user", content: "abcd" },
      { role: "assistant", content: "efgh" },
    ]);
    expect(budget.blocks).toBe(2);
    expect(budget.chars).toBe(8);
    expect(budget.tokens).toBe(estimateTokens("abcd\nefgh"));
  });
});

describe("evaluateEdit (the edit gate)", () => {
  const small = `${TURN_OPEN} user 1\nhi\n${TURN_CLOSE}`;

  test("accepts an edit that fits the budget", () => {
    const decision = evaluateEdit("", small, 100);
    expect(decision.accepted).toBe(true);
    expect(decision.receipt).toContain("accepted (fits)");
    expect(decision.receipt.split("\n")).toHaveLength(1);
  });

  test("accepts a strict shrink when over budget", () => {
    const before = `${TURN_OPEN} user 1\n${"x".repeat(400)}\n${TURN_CLOSE}`;
    const after = `${TURN_OPEN} user 1\n${"x".repeat(240)}\n${TURN_CLOSE}`;
    const decision = evaluateEdit(before, after, 50);
    expect(decision.after.tokens).toBeGreaterThan(50);
    expect(decision.accepted).toBe(true);
    expect(decision.receipt).toContain("accepted (shrink)");
  });

  test("rejects growth when over budget", () => {
    const before = `${TURN_OPEN} user 1\n${"x".repeat(40)}\n${TURN_CLOSE}`;
    const after = `${TURN_OPEN} user 1\n${"x".repeat(400)}\n${TURN_CLOSE}`;
    const decision = evaluateEdit(before, after, 50);
    expect(decision.accepted).toBe(false);
    expect(decision.reason).toContain("over budget");
    expect(decision.receipt).toContain("rejected");
  });

  test("rejects an equal-size edit when already over budget", () => {
    const text = `${TURN_OPEN} user 1\n${"x".repeat(400)}\n${TURN_CLOSE}`;
    const decision = evaluateEdit(text, text, 50);
    expect(decision.accepted).toBe(false);
  });

  test("rejects a parse error", () => {
    const decision = evaluateEdit(small, "not a valid file", 100);
    expect(decision.accepted).toBe(false);
    expect(decision.reason).toContain("parse error");
    expect(decision.receipt).toContain("rejected");
  });

  test("default budget is applied when omitted", () => {
    const decision = evaluateEdit("", small);
    expect(decision.budget).toBe(DEFAULT_BUDGET_TOKENS);
  });
});

describe("appendTurn", () => {
  test("appends a block and preserves prior blocks", () => {
    const first = appendTurn("", "user", "hi");
    const second = appendTurn(first, "assistant", "hello");
    const parsed = parseLiveContext(second);
    expect(parsed.ok).toBe(true);
    if (parsed.ok) {
      expect(parsed.messages).toEqual([
        { role: "user", content: "hi" },
        { role: "assistant", content: "hello" },
      ]);
    }
  });

  test("preserves prior turns when new content contains the end marker", () => {
    const first = appendTurn("", "user", "line1\n@@END\nline2");
    const second = appendTurn(first, "assistant", "done");
    const parsed = parseLiveContext(second);
    expect(parsed.ok).toBe(true);
    if (parsed.ok) {
      expect(parsed.messages).toEqual([
        { role: "user", content: "line1\n@@END\nline2" },
        { role: "assistant", content: "done" },
      ]);
    }
  });

  test("recovers from invalid prior content", () => {
    const text = appendTurn("garbage", "user", "hi");
    const parsed = parseLiveContext(text);
    expect(parsed.ok).toBe(true);
    if (parsed.ok) expect(parsed.messages).toEqual([{ role: "user", content: "hi" }]);
  });
});

describe("resolveEnabled", () => {
  test("defaults to disabled", () => {
    expect(resolveEnabled({}, undefined)).toBe(false);
    expect(resolveEnabled(undefined, undefined)).toBe(false);
  });
  test("config enables", () => {
    expect(resolveEnabled({ enabled: true }, undefined)).toBe(true);
  });
  test("env overrides config", () => {
    expect(resolveEnabled({ enabled: false }, "1")).toBe(true);
    expect(resolveEnabled({ enabled: true }, "0")).toBe(false);
    expect(resolveEnabled({}, "true")).toBe(true);
    expect(resolveEnabled({}, "false")).toBe(false);
  });
});

describe("parseConfig", () => {
  test("parses plain json", () => {
    expect(parseConfig('{"enabled":true,"budget_tokens":123}')).toEqual({
      enabled: true,
      budget_tokens: 123,
    });
  });
  test("parses jsonc with comments and trailing commas", () => {
    const raw = `{\n  // gate\n  "enabled": true,\n  /* budget */\n  "budget_tokens": 42,\n}`;
    expect(parseConfig(raw)).toEqual({ enabled: true, budget_tokens: 42 });
  });
  test("returns empty config on garbage", () => {
    expect(parseConfig("not json")).toEqual({});
    expect(parseConfig("")).toEqual({});
    expect(parseConfig(undefined)).toEqual({});
  });
});

describe("session file naming", () => {
  test("sanitizes unsafe characters", () => {
    expect(sanitizeSessionID("ses_ab/../c d")).toBe("ses_ab_.._c_d");
    expect(liveContextFileName("ses_abc")).toBe("LIVE_CTX_ses_abc.txt");
  });
});

describe("buildCompactionPrompt", () => {
  test("embeds the authored context verbatim and instructs replay", () => {
    const live = `${TURN_OPEN} user 1\nhi\n${TURN_CLOSE}`;
    const prompt = buildCompactionPrompt(live, 100);
    expect(prompt).toContain(live);
    expect(prompt).toContain("verbatim");
    expect(prompt).toContain("100-token budget");
    expect(prompt).toContain("Do NOT read or use the conversation history");
  });

  test("re-seed mode instructs condensation without embedding the file", () => {
    const prompt = buildCompactionPrompt(undefined, 500);
    expect(prompt).not.toContain("verbatim");
    expect(prompt).toContain("@@TURN");
    expect(prompt).toContain("@@END");
    expect(prompt).toContain("500-token budget");
    expect(prompt).toContain("Condense");
  });
});

describe("enforceBudget", () => {
  test("returns content unchanged when within budget", () => {
    const text = `${TURN_OPEN} user 1\nhi\n${TURN_CLOSE}`;
    const result = enforceBudget(text, 1000);
    expect(result.trimmed).toBe(false);
    expect(result.removed).toBe(0);
    expect(result.nudge).toBe("");
    const parsed = parseLiveContext(result.content);
    expect(parsed.ok).toBe(true);
    if (parsed.ok) expect(parsed.messages).toEqual([{ role: "user", content: "hi" }]);
  });

  test("rolls back newest turns when over budget", () => {
    const big = "x".repeat(4000);
    let text = "";
    for (let i = 0; i < 5; i++) {
      text = appendTurn(text, "user", `${big} turn ${i}`);
    }
    const result = enforceBudget(text, 1000, 2048);
    expect(result.trimmed).toBe(true);
    expect(result.removed).toBeGreaterThan(0);
    expect(result.nudge).toContain("budget");
    expect(result.tokens).toBeLessThanOrEqual(1000 - 2048 + 4000);
    const parsed = parseLiveContext(result.content);
    expect(parsed.ok).toBe(true);
    if (parsed.ok) {
      expect(parsed.messages.length).toBeLessThan(5);
      expect(parsed.messages.length).toBeGreaterThanOrEqual(1);
    }
  });

  test("never removes the last remaining turn", () => {
    const huge = "x".repeat(10000);
    const text = `${TURN_OPEN} user 1\n${huge}\n${TURN_CLOSE}`;
    const result = enforceBudget(text, 100, 2048);
    expect(result.removed).toBe(0);
    const parsed = parseLiveContext(result.content);
    expect(parsed.ok).toBe(true);
    if (parsed.ok) expect(parsed.messages.length).toBe(1);
  });

  test("empty input returns empty result", () => {
    const result = enforceBudget("", 1000);
    expect(result.trimmed).toBe(false);
    expect(result.removed).toBe(0);
    expect(result.tokens).toBe(0);
  });
});
