import type { Plugin } from "@opencode-ai/plugin";
import { mkdirSync, writeFileSync, existsSync } from "fs";
import { join } from "path";
import { homedir } from "os";

interface Todo {
  content: string;
  status: "pending" | "in_progress" | "completed" | "cancelled";
  priority: "high" | "medium" | "low";
}

interface TodoUpdatedProperties {
  sessionID: string;
  todos: Todo[];
}

interface CompletedItem {
  content: string;
  priority: string;
  completedAt: number;
  skillEvaluated: boolean;
  skillScore?: number;
}

interface EventInput {
  event: {
    type: string;
    properties?: unknown;
  };
}

interface CompactingInput {
  sessionID: string;
}

interface CompactingOutput {
  prompt?: string;
}

export const BetterCompactionPlugin: Plugin = async () => {
  const prevTodos = new Map<string, Todo[]>();          // sessionID → previous todo state
  const completedTodos = new Map<string, CompletedItem[]>(); // sessionID → completed items
  const sessionContexts = new Map<string, string[]>();

/**
   * Assess a completed item against 5 criteria (0-10 each, threshold ≥ 30).
   * Uses todo content keyword analysis and priority as heuristics.
   */
  function evaluateSkillWorthiness(item: CompletedItem): { score: number; reasoning: string } {
    const content = item.content.toLowerCase();
    let score = 0;
    const reasons: string[] = [];

    const noveltyKeywords = ["implement", "create", "build", "design", "architect", "setup", "configure", "migrate", "new"];
    const noveltyScore = noveltyKeywords.some(k => content.includes(k)) ? 7 : 3;
    score += noveltyScore;
    reasons.push(`novelty:${noveltyScore}`);

    const applicabilityKeywords = ["pattern", "workflow", "pipeline", "integration", "service", "api", "config", "template", "skill", "deploy"];
    const applicabilityScore = applicabilityKeywords.some(k => content.includes(k)) ? 8 :
      item.priority === "high" ? 6 : 4;
    score += applicabilityScore;
    reasons.push(`applicability:${applicabilityScore}`);

    const depthKeywords = ["debug", "investigate", "research", "refactor", "optimize", "migrate", "complex", "analyze", "root cause"];
    const depthScore = depthKeywords.some(k => content.includes(k)) ? 8 :
      item.priority === "high" ? 6 : 3;
    score += depthScore;
    reasons.push(`depth:${depthScore}`);

    const riskKeywords = ["config", "setup", "integration", "workflow", "pattern", "pipeline", "deploy", "infra", "auth", "permission"];
    const riskScore = riskKeywords.some(k => content.includes(k)) ? 8 :
      item.priority === "high" ? 6 : 3;
    score += riskScore;
    reasons.push(`contextRisk:${riskScore}`);

    const effortScore = item.priority === "high" ? 8 : item.priority === "medium" ? 5 : 2;
    score += effortScore;
    reasons.push(`effort:${effortScore}`);

    return { score, reasoning: reasons.join(", ") };
  }

  function generateSkillName(content: string): string {
    return content
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "")
      .slice(0, 50);
  }

  function generateSkillMd(item: CompletedItem, sessionID: string, analysis: { score: number; reasoning: string }): string {
    const name = generateSkillName(item.content);
    return `# ${item.content}

## Description
Auto-generated skill from completed task in session \`${sessionID}\`.

## Trigger
Completed todo with priority: ${item.priority} | Score: ${analysis.score}/50 | Reasoning: ${analysis.reasoning}

## Summary
This skill captures the context and approach used to complete: "${item.content}"

## Usage
When encountering similar tasks, reference this skill for established patterns and workflows.

## Skills
- \`${name}\`
`;
  }

  /**
   * Parse hierarchical task names using dot-notation.
   * Example: "auth.login.setup" → parent "auth.login", leaf "setup"
   */
  function parseSubtask(content: string): { parent: string | null; leaf: string } {
    const parts = content.split(".");
    if (parts.length >= 2) {
      return { parent: parts.slice(0, -1).join("."), leaf: parts[parts.length - 1] };
    }
    return { parent: null, leaf: content };
  }

  function buildTaskTree(todos: Todo[]): string {
    const groups = new Map<string, Todo[]>();
    const roots: Todo[] = [];

    for (const todo of todos) {
      const { parent, leaf } = parseSubtask(todo.content);
      if (parent) {
        const group = groups.get(parent) ?? [];
        group.push({ ...todo, content: leaf });
        groups.set(parent, group);
      } else {
        roots.push(todo);
      }
    }

    const lines: string[] = [];
    for (const root of roots) {
      const statusChar = root.status === "in_progress" ? ">" : root.status === "completed" ? "x" : " ";
      const group = groups.get(root.content);
      if (group) {
        lines.push(`- [${statusChar}] ${root.content} (${root.priority})`);
        for (const sub of group) {
          const subStatus = sub.status === "in_progress" ? ">" : sub.status === "completed" ? "x" : " ";
          lines.push(`  - [${subStatus}] ${sub.content} (${sub.priority})`);
        }
      } else {
        lines.push(`- [${statusChar}] ${root.content} (${root.priority})`);
      }
    }
    return lines.join("\n");
  }

  function captureToolContext(sessionID: string, toolName: string): void {
    const ctx = sessionContexts.get(sessionID) ?? [];
    if (!["read", "glob", "lsp_diagnostics"].includes(toolName)) {
      ctx.push(`[${toolName}]`);
      if (ctx.length > 50) ctx.shift();
    }
    sessionContexts.set(sessionID, ctx);
  }

  return {
    event: async (input: EventInput) => {
      const ev = input.event;

      if (ev.type === "todo.updated") {
        const props = ev.properties as TodoUpdatedProperties | undefined;
        if (!props?.sessionID || !props?.todos) return;

        const { sessionID, todos } = props;
        const prev = prevTodos.get(sessionID) ?? [];

        const freshCompleted: CompletedItem[] = [];
        for (const todo of todos) {
          if (todo.status === "completed") {
            const wasCompleted = prev.some(
              (p) => p.content === todo.content && p.status === "completed"
            );
            if (!wasCompleted) {
              freshCompleted.push({
                content: todo.content,
                priority: todo.priority,
                completedAt: Date.now(),
                skillEvaluated: false,
              });
            }
          }
        }

        if (freshCompleted.length > 0) {
          const existing = completedTodos.get(sessionID) ?? [];
          completedTodos.set(sessionID, [...existing, ...freshCompleted]);
        }

        prevTodos.set(sessionID, todos);
      }
    },

    "tool.execute.after": async (input: { tool: string; sessionID: string; callID: string; args: any }) => {
      captureToolContext(input.sessionID, input.tool);
    },

    "experimental.session.compacting": async (input: CompactingInput, output: CompactingOutput) => {
      const sessionID = input.sessionID;
      const completed = completedTodos.get(sessionID) ?? [];
      const currentTodos = prevTodos.get(sessionID) ?? [];

      const skillWorthyItems: Array<{ item: CompletedItem; score: number; reasoning: string }> = [];
      for (const item of completed) {
        if (item.skillEvaluated) continue;
        const { score, reasoning } = evaluateSkillWorthiness(item);
        item.skillEvaluated = true;
        item.skillScore = score;
        if (score >= 30) {
          skillWorthyItems.push({ item, score, reasoning });
        }
      }

      const skillsDir = join(homedir(), ".config", "opencode", "skills");
      for (const { item, score, reasoning } of skillWorthyItems) {
        const skillName = generateSkillName(item.content);
        const skillPath = join(skillsDir, skillName, "SKILL.md");
        if (!existsSync(skillPath)) {
          try {
            mkdirSync(join(skillsDir, skillName), { recursive: true });
            writeFileSync(skillPath, generateSkillMd(item, sessionID, { score, reasoning }));
            console.log(`[better-compaction] ✓ Auto-generated skill: ${skillName} (score: ${score}/50)`);
          } catch (err) {
            console.error(`[better-compaction] ✗ Failed to create skill ${skillName}:`, err);
          }
        }
      }

      const taskTree = buildTaskTree(currentTodos);

      const completedSummary = completed.length > 0
        ? completed
            .map((c, i) => `${i + 1}. ✅ ${c.content} (${c.priority}${c.skillScore ? `, skill score: ${c.skillScore}/50` : ""})`)
            .join("\n")
        : "No completed items yet.";

      const activeTodos = currentTodos.filter(
        (t) => t.status !== "completed" && t.status !== "cancelled"
      );
      const todoSection = activeTodos.length > 0
        ? taskTree
        : "No active todos.";

      const toolCtx = sessionContexts.get(sessionID) ?? [];
      const toolSummary = toolCtx.length > 0
        ? `Recent tools used: ${[...new Set(toolCtx)].join(", ")}`
        : "";

      const skillSummary = skillWorthyItems.length > 0
        ? `\n### 🧠 Auto-Generated Skills\n${skillWorthyItems.map(
            ({ item, score, reasoning }) =>
              `- "${item.content}" → generated as skill (score: ${score}/50, reasoning: ${reasoning})`
          ).join("\n")}`
        : "";

      output.prompt = `You are compacting a conversation so it can continue in a new context window. Your job is to produce a continuation prompt that preserves ALL information needed to seamlessly resume work without losing anything important.

## CRITICAL RULES

1. NEVER generalize or summarize away specific details. Keep exact names, paths, values, error messages, flag names, config keys, URLs, version numbers, and file locations.
2. If the user pasted external content (conversation logs, error output, code snippets, config files), reproduce the KEY PARTS verbatim — do not summarize them.
3. Preserve ALL user-stated constraints, preferences, behavioral instructions, and communication style preferences.
4. Preserve the full investigation/debugging state: what hypotheses were tested, what was ruled out and with what evidence, what remains unexplored.
5. Preserve the agent/category model configuration and any fallback chain details that are relevant to ongoing work.

## OUTPUT TEMPLATE

Use this exact structure for the continuation prompt:

---
## Goal
[The specific goal(s) of the current task]

## Active Constraints & Preferences
- [User instructions, behavioral constraints, communication preferences, rules the agent must follow]
- [Model/provider constraints if relevant]

## Discoveries & Technical Details
[Exact technical details discovered so far: config values, file paths, flag names, CLI commands used, error messages, version numbers, API endpoints. Include what was tried and what happened — never generalize these.]

## User-Pasted Content (Key Parts)
[Verbatim reproduction of critical user-pasted content — error logs, config snippets, conversation output. If the content was large, reproduce the most important sections exactly.]

## Progress
### ✅ Completed Tasks
${completedSummary}

### 📋 Active Tasks
${todoSection}

### ❌ Not Solved / Blocked
[Unsolved items with the current investigation state — what was tried, what was ruled out, what evidence supports each conclusion]

### ⏭️ Next Steps
[Planned next actions in priority order]

## Relevant Files & Resources
[Files read, modified, or created during this session. Key external references, documentation links, or API endpoints used.]
${toolSummary ? `\n${toolSummary}` : ""}
${skillSummary}
---`;
    },
  };
};
