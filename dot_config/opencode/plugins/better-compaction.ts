import type { Plugin } from "@opencode-ai/plugin";
import { tool } from "@opencode-ai/plugin";
import { z } from "zod";
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
  startedAt?: number;      // when the todo entered in_progress
  toolCount?: number;       // unique tools used while this todo was active
  userBoosted?: boolean;    // true if user said "remember that" etc.
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

/** Tracks a single file's read history within a session */
interface FileReadInfo {
  path: string;
  shortPath: string;
  readCount: number;
  firstTurn: number;
  lastTurn: number;
}

/** Arguments shape for Read tool calls */
interface ReadArgs {
  filePath?: string;
  path?: string;
  file_path?: string;
  /** Some integrations nest args under an `input` key */
  input?: { filePath?: string; path?: string; file_path?: string };
}

/** Arguments shape for task() / delegate-task calls */
interface TaskArgs {
  prompt?: string;
  description?: string;
  [key: string]: unknown;
}

/** Arguments shape for chat.message events */
interface ChatMessageArgs {
  message?: string;
  content?: string;
  text?: string;
  [key: string]: unknown;
}

export const BetterCompactionPlugin: Plugin = async (input) => {
  const projectName = input.directory.split("/").pop() || "default";
  const shell = input.$;
  const prevTodos = new Map<string, Todo[]>();          // sessionID → previous todo state
  const completedTodos = new Map<string, CompletedItem[]>(); // sessionID → completed items
  const sessionContexts = new Map<string, string[]>();
  const sessionReads = new Map<string, Map<string, FileReadInfo>>();
  const injectedSessions = new Set<string>();            // sessionID → already got auto-context injection
let turnCounter = 0;
  const activeTodo = new Map<string, string>();          // sessionID → current in_progress todo content
  const activeTodoTools = new Map<string, Set<string>>();
  const activeTodoStart = new Map<string, number>();
  const todoMeta = new Map<string, { startedAt: number; tools: Set<string>; boosted: boolean }>();

/**
   * Assess a completed item against 5 base criteria (0-10 each) plus 3 bonus signals.
   * Base threshold ≥ 30. User boost (+15) forces inclusion regardless of score.
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

    // Bonus 1: tool diversity (0-10) — more tools = more complex task
    const toolDiversityScore = Math.min(item.toolCount ?? 0, 10);
    score += toolDiversityScore;
    reasons.push(`tools:${toolDiversityScore}`);

    // Bonus 2: time investment (0-10) — tasks that took longer are more significant
    const elapsedMinutes = item.startedAt ? (item.completedAt - item.startedAt) / 60000 : 0;
    const timeScore = Math.min(Math.floor(elapsedMinutes / 5), 10);
    score += timeScore;
    reasons.push(`time:${timeScore}`);

    // Bonus 3: user boost (+15) — explicit "remember that" request
    const userBoostScore = item.userBoosted ? 15 : 0;
    score += userBoostScore;
    if (item.userBoosted) reasons.push("user_boost:15");

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
Completed todo with priority: ${item.priority} | Score: ${analysis.score} | Reasoning: ${analysis.reasoning}

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

  function inferMemoryKind(content: string): string {
    const c = content.toLowerCase();
    if (c.includes("debug") || c.includes("investigate") || c.includes("root cause") || c.includes("analyze") || c.includes("trace")) return "discovery";
    if (c.includes("fix") || c.includes("bug") || c.includes("patch") || c.includes("hotfix")) return "bugfix";
    if (c.includes("implement") || c.includes("create") || c.includes("build") || c.includes("design") || c.includes("add ") || c.includes("new ")) return "feature";
    if (c.includes("refactor") || c.includes("optimize") || c.includes("clean") || c.includes("restructure") || c.includes("simplify")) return "refactor";
    if (c.includes("config") || c.includes("setup") || c.includes("configure") || c.includes("migrate") || c.includes("deploy")) return "decision";
    return "exploration";
  }

  function inferTags(content: string): string[] {
    const tags: string[] = [];
    const c = content.toLowerCase();
    if (c.includes("godoxy") || c.includes("proxy") || c.includes("reverse")) tags.push("godoxy");
    if (c.includes("crowdsec") || c.includes("waf") || c.includes("appsec")) tags.push("crowdsec");
    if (c.includes("pocket") || c.includes("oidc")) tags.push("pocketid");
    if (c.includes("tinyauth") || c.includes("forward-auth")) tags.push("tinyauth");
    if (c.includes("docker") || c.includes("compose") || c.includes("container")) tags.push("docker");
    if (c.includes("cert") || c.includes("tls") || c.includes("ssl") || c.includes("https") || c.includes("cloudflare")) tags.push("networking");
    if (c.includes("kali") || c.includes("sync") || c.includes("codemem") || c.includes("dotfiles")) tags.push("sync");
    if (c.includes("ci") || c.includes("cd") || c.includes("github") || c.includes("action")) tags.push("ci");
    if (c.includes("db") || c.includes("database") || c.includes("postgres") || c.includes("mysql") || c.includes("sqlite") || c.includes("mariadb")) tags.push("database");
    if (c.includes("infra") || c.includes("vm") || c.includes("server") || c.includes("deploy") || c.includes("provision")) tags.push("infrastructure");
    if (c.includes("secret") || c.includes("vault") || c.includes("token") || c.includes("key") || c.includes("credential")) tags.push("security");
    if (c.includes("restic") || c.includes("backup") || c.includes("restore")) tags.push("backup");
    if (c.includes("monitor") || c.includes("alert") || c.includes("metric") || c.includes("netdata")) tags.push("monitoring");
    return tags.length > 0 ? tags : ["general"];
  }

  function inferProject(content: string, defaultProject: string): string {
    const c = content.toLowerCase();
    if (c.includes("godoxy") || c.includes("proxy")) return "godoxy";
    if (c.includes("crowdsec") || c.includes("waf") || c.includes("appsec")) return "crowdsec";
    if (c.includes("pocket") || c.includes("oidc")) return "pocketid";
    if (c.includes("tinyauth") || c.includes("forward-auth")) return "tinyauth";
    if (c.includes("pirate") || c.includes("stremio") || c.includes("prowlarr") || c.includes("jackett") || c.includes("shelfmark") || c.includes("decypharr")) return "pirate";
    if (c.includes("kali") || c.includes("sync") || c.includes("codemem") || c.includes("dotfiles")) return "dotfiles";
    return defaultProject;
  }

  async function rememberInCodemem(item: CompletedItem, sessionID: string, score: number, skillName?: string): Promise<void> {
    try {
      const kind = inferMemoryKind(item.content);
      const tags = inferTags(item.content);
      const effectiveProject = inferProject(item.content, projectName);

      // Dedup: skip if memory with similar title already exists for this project
      const existing = await shell`codemem search "${item.content}" --project ${effectiveProject} --limit 1`.quiet().nothrow().text();
      if (existing.trim().length > 0) {
        console.log(`[better-compaction] ∼ Skipped duplicate codemem: "${item.content}"`);
        return;
      }

      // Body: link to full SKILL.md if one was generated, otherwise just the content
      const body = skillName
        ? `See: ~/.config/opencode/skills/${skillName}/SKILL.md` +
          `\n${item.content}`
        : item.content;

      // Metadata goes into tags, not body (keeps vector embeddings clean)
      const allTags = [...tags, `priority:${item.priority}`, `score:${score}`];

      await shell`codemem memory remember -k ${kind} -t ${item.content} -b ${body} --tags ${allTags} --project ${effectiveProject}`.quiet().nothrow();
      console.log(`[better-compaction] ✓ Remembered in codemem: "${item.content}" (kind: ${kind}, project: ${effectiveProject}, tags: ${allTags.join(",")})`);
    } catch (err) {
      console.error(`[better-compaction] ✗ Failed to remember in codemem: "${item.content}"`, err);
    }
  }

  function captureToolContext(sessionID: string, toolName: string): void {
    const ctx = sessionContexts.get(sessionID) ?? [];
    if (!["read", "glob", "lsp_diagnostics"].includes(toolName)) {
      ctx.push(`[${toolName}]`);
      if (ctx.length > 50) ctx.shift();
    }
    sessionContexts.set(sessionID, ctx);
  }

  const estimatedTokensPerRead = 5000;

  function generateReadOptimizationReport(sessionID: string): string {
    const reads = sessionReads.get(sessionID);
    if (!reads || reads.size === 0) return "";

    const entries = Array.from(reads.values())
      .filter(r => r.readCount > 1)
      .sort((a, b) => b.readCount - a.readCount);

    if (entries.length === 0) return "";

    const totalReads = Array.from(reads.values()).reduce((s, r) => s + r.readCount, 0);
    const totalFiles = reads.size;
    const redundantReads = entries.reduce((s, r) => s + (r.readCount - 1), 0);
    const estWastedTokens = redundantReads * estimatedTokensPerRead;

    const top = entries.slice(0, 10).map(r =>
      `  ${r.readCount}x  ${r.shortPath}  (${r.readCount - 1} redundant)`
    ).join("\n");

    const report = [
      "## ⚡ Context Optimization Notes",
      "",
      "The following files were read multiple times without modification between reads.",
      "Consider caching content or reading once for efficiency in the next session.",
      "",
      "```",
      `  Reads  File`,
      `  ${"─".repeat(50)}`,
      top,
      "```",
      "",
      `**Summary**: ${totalReads} total reads of ${totalFiles} files, ~${redundantReads} redundant reads`,
      `(~${(estWastedTokens / 1000).toFixed(0)}K wasted tokens).`,
      "",
    ].join("\n");

    console.log(`[better-compaction] Optimization report for ${sessionID}:`);
    console.log(`  ${totalReads} reads, ${totalFiles} files, ${redundantReads} redundant, ~${(estWastedTokens / 1000).toFixed(0)}K wasted tokens`);
    for (const r of entries.slice(0, 5)) {
      console.log(`  - ${r.readCount}x ${r.shortPath}`);
    }

    return report;
  }

  return {
    event: async (input: EventInput) => {
      const ev = input.event;

      if (ev.type === "todo.updated") {
        const props = ev.properties as TodoUpdatedProperties | undefined;
        if (!props?.sessionID || !props?.todos) return;

        const { sessionID, todos } = props;
        const prev = prevTodos.get(sessionID) ?? [];

        // Track current in_progress todo for tool attribution
        const currentActive = todos.find(t => t.status === "in_progress");
        if (currentActive) {
          activeTodo.set(sessionID, currentActive.content);
          const key = `${sessionID}::${currentActive.content}`;
          if (!todoMeta.has(key)) {
            todoMeta.set(key, { startedAt: Date.now(), tools: new Set(), boosted: false });
          }
        }

        const freshCompleted: CompletedItem[] = [];
        for (const todo of todos) {
          if (todo.status === "completed") {
            const wasCompleted = prev.some(
              (p) => p.content === todo.content && p.status === "completed"
            );
            if (!wasCompleted) {
              const key = `${sessionID}::${todo.content}`;
              const meta = todoMeta.get(key);
              freshCompleted.push({
                content: todo.content,
                priority: todo.priority,
                completedAt: Date.now(),
                startedAt: meta?.startedAt,
                toolCount: meta?.tools.size ?? 0,
                userBoosted: meta?.boosted ?? false,
                skillEvaluated: false,
              });
              todoMeta.delete(key);
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

    tool: {
      "codemem-search": tool({
        description: "Search project memories and skills via codemem. Returns relevant context from past sessions. Use this when you need to recall past decisions, patterns, or solutions for the current project.",
        args: {
          query: z.string().describe("The search query to find relevant memories"),
          project: z.string().optional().describe("Project scope (defaults to current project)"),
        },
        execute: async (args, ctx) => {
          const project = args.project ?? projectName;
          const result = await shell`codemem pack "${args.query}" --project ${project} --budget 500 --compact --compact-detail 2 --limit 5`.quiet().nothrow().text();
          if (result.trim().length === 0) {
            return { output: `No memories found for "${args.query}" in project "${project}".` };
          }
          return { output: `Previous context for "${args.query}" (${project}):\n${result}` };
        },
      }),
    },

    "chat.message": async (input: { sessionID: string }, output: { parts: Array<{ text?: string }> }) => {
      const text = output.parts.map(p => p.text ?? "").join(" ");
      const boostPhrases = ["remember that", "keep that one", "save that", "remember this", "keep this", "worth remembering", "note that", "remember", "worked", "perfect", "that's it", "fixed"];
      if (boostPhrases.some(p => text.toLowerCase().includes(p))) {
        const currentTodo = activeTodo.get(input.sessionID);
        if (currentTodo) {
          const key = `${input.sessionID}::${currentTodo}`;
          const meta = todoMeta.get(key) ?? { startedAt: Date.now(), tools: new Set(), boosted: false };
          meta.boosted = true;
          todoMeta.set(key, meta);
          console.log(`[better-compaction] 🔖 User boost for: "${currentTodo}"`);
        }
      }
    },

    "tool.execute.after": async (input: { tool: string; sessionID: string; callID: string; args: any }) => {
      captureToolContext(input.sessionID, input.tool);
turnCounter++;
      captureToolContext(input.sessionID, input.tool);

      // Attribute tool usage to the active todo
      const currentTodo = activeTodo.get(input.sessionID);
      if (currentTodo) {
        const key = `${input.sessionID}::${currentTodo}`;
        const meta = todoMeta.get(key);
        if (meta) {
          meta.tools.add(input.tool);
        }
      }

      if (input.tool.toLowerCase() === "read") {
        const args: ReadArgs = input.args || {};
        const filePath = args.filePath || args.path || args.file_path || args.input?.filePath || args.input?.path || args.input?.file_path || "";
        if (filePath) {
          const reads = sessionReads.get(input.sessionID) ?? new Map();
          const existing = reads.get(filePath);
          if (existing) {
            existing.readCount++;
            existing.lastTurn = turnCounter;
          } else {
            const home = homedir();
            const shortPath = filePath.startsWith(home) ? "~" + filePath.slice(home.length) : filePath;
            reads.set(filePath, { path: filePath, shortPath, readCount: 1, firstTurn: turnCounter, lastTurn: turnCounter });
          }
          sessionReads.set(input.sessionID, reads);
        }
      }
    },

    "experimental.chat.system.transform": async (input: { sessionID?: string }, output: { system: string[] }) => {
      if (!input.sessionID || injectedSessions.has(input.sessionID)) return;
      injectedSessions.add(input.sessionID);

      const result = await shell`codemem pack "active context" --project ${projectName} --budget 600 --compact --compact-detail 2 --limit 5`.quiet().nothrow().text();
      if (result.trim().length > 50) {
        output.system.push(`\n## Previous Context (${projectName})\n${result}`);
      }
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
        if (score >= 30 || item.userBoosted) {
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

      // Persist skill-worthy completions to codemem for searchable cross-session memory
      await Promise.all(skillWorthyItems.map(({ item, score }) => {
        const skillName = generateSkillName(item.content);
        return rememberInCodemem(item, sessionID, score, skillName);
      }));

      const taskTree = buildTaskTree(currentTodos);

      const completedSummary = completed.length > 0
        ? completed
            .map((c, i) => `${i + 1}. ✅ ${c.content} (${c.priority}${c.skillScore ? `, score: ${c.skillScore}` : ""}${c.userBoosted ? ", 🔖 boosted" : ""})`)
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
              `- "${item.content}" → generated as skill (score: ${score}, reasoning: ${reasoning})`
          ).join("\n")}`
        : "";

      const optimizationReport = generateReadOptimizationReport(sessionID);

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
${optimizationReport ? `\n${optimizationReport}` : ""}
---`;
    },
  };
};
