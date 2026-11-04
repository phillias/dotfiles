---
name: finding-triage
description: Fast structured triage for no-mistakes findings using TypeSafe Jev. Classifies severity, auto-fixability, and human-review requirements with calibrated confidence. Use when triaging findings reported by a no-mistakes gate.
---

# Finding Triage

Uses TypeSafe's Jev evaluation model to make fast, cheap structured decisions about no-mistakes pipeline findings before routing them to fixes, human review, or auto-resolution.

## When to Use

- **Before routing no-mistakes findings** — classify severity and fixability
- **Ask-user finding decisions** — determine if genuinely ambiguous per `ask-user-authority` criteria
- **Finding prioritization** — score blast radius and urgency for queue ordering
- **Guardrail verification** — detect policy violations or jailbreak attempts in LLM output

## Prerequisites

- `AI_GATEWAY_API_KEY` environment variable (Vercel AI Gateway, immediate access)
- Model: `typesafe-ai/jev` via Vercel AI Gateway (decision endpoint `https://ai-gateway.vercel.sh/v1/decisions`)

## API Invocation (verified 2026-11-04)

Call the decision endpoint directly with curl or any HTTP client; there is no Jev CLI.
The gateway host `ai.gateway.vercel.dev` is unreachable from some hosts (the TLS
handshake is killed at the SNI level). Use `https://ai-gateway.vercel.sh/v1` with the
same `AI_GATEWAY_API_KEY`. Jev is a decision model: the chat completions path returns
`ModelTypeMismatchError`, so use `POST /v1/decisions`.

```sh
curl -sS --max-time 30 https://ai-gateway.vercel.sh/v1/decisions \
  -H "Authorization: Bearer $AI_GATEWAY_API_KEY" \
  -H 'Content-Type: application/json' \
  -d @request.json
```

Request body: `model`, `input` (the text to classify, as a string; JSON-stringify a
structured state object), and `questions[]`. Each question carries `name`, `type`
(`predicate` | `choice` | `score`), `prompt`, and `instructions`, plus
`choices[]` (`label`/`value`[/`description`] objects) for choice questions or
`levels[]` (`label`/`value`[/`description`] objects) for score questions.
Plain string arrays are rejected with a structured 400.

Response `answers[]`:

- predicate -> `{"type","name","probability"}`
- choice -> `{"type","name","choice","confidence","probabilities":[{"value","probability"}]}`
- score -> `{"type","name","score","confidence","probabilities":[{"value","label","probability"}]}`

Do not call `ai.gateway.vercel.dev` (dead from some networks) and do not use
`/v1/chat/completions` (wrong model type for Jev).

## Question Schemas

### Severity Classification

```javascript
{
  severity: {
    type: 'choice',
    instructions: 'What is the finding severity?',
    criteria: {
      critical: 'Blocks build, tests, or CI — must fix immediately',
      warning: 'Style, best-practice, or maintainability issue — fix in normal flow',
      info: 'Nitpick or suggestion — optional fix',
      false_positive: 'Not a real issue — should be skipped'
    }
  }
}
```

### Auto-Fixability

```javascript
{
  auto_fixable: {
    type: 'boolean',
    instructions: 'Can this finding be fixed automatically without human judgment?'
  },
  needs_context: {
    type: 'boolean',
    instructions: 'Does fixing this require additional context beyond the finding location?'
  }
}
```

### Human Review Required

```javascript
{
  needs_human: {
    type: 'boolean',
    instructions: 'Does this finding require human judgment per ask-user-authority criteria?'
  },
  genuinely_ambiguous: {
    type: 'boolean',
    instructions: 'Is this genuinely ambiguous (multiple valid interpretations, no clear right answer)?'
  },
  blast_radius: {
    type: 'choice',
    instructions: 'What is the impact scope of fixing this?',
    criteria: {
      single_file: 'Change isolated to one file',
      multiple_files: 'Change affects multiple files',
      cross_repo: 'Change affects multiple repositories or shared infrastructure'
    }
  }
}
```

## Integration Pattern

### Cascade Decision Flow

```javascript
const triage = await evaluate({
  model: 'typesafe-ai/jev',
  state: { finding, code_context, repo_metadata },
  questions: {
    severity: { /* choice schema */ },
    auto_fixable: { /* boolean schema */ },
    needs_human: { /* boolean schema */ },
    blast_radius: { /* choice schema */ }
  }
});

// High needs_human → route to human review first
if (triage.answers.needs_human.probability > 0.8) {
  queueHumanReview(finding, triage.answers);
}
// High confidence → auto-route
else if (triage.answers.severity.confidence > 0.9 && triage.answers.auto_fixable.probability > 0.95) {
  queueAutoFix(finding, triage.answers.severity.choice);
}
// Medium confidence → escalate to frontier model
else if (triage.answers.severity.confidence > 0.7) {
  routeToFixer(finding, triage.answers);
}
// Low confidence → human review
else {
  queueHumanReview(finding, triage.answers);
}
```

### Ask-User Authority Check

```javascript
const decision = await evaluate({
  model: 'typesafe-ai/jev',
  state: { finding, task_context, recent_history },
  questions: {
    genuinely_ambiguous: {
      type: 'boolean',
      instructions: 'Is this truly ambiguous per ask-user-authority criteria?'
    },
    blast_radius: {
      type: 'choice',
      instructions: 'Impact scope',
      criteria: {
        single_file: 'Single file',
        multiple_files: 'Multiple files',
        cross_repo: 'Cross-repo or infrastructure'
      }
    },
    expanding_scope: {
      type: 'boolean',
      instructions: 'Does fixing this expand beyond the original task scope?'
    }
  }
});

// Escalate to captain if high-blast-radius or genuinely ambiguous
if (decision.answers.blast_radius.choice === 'cross_repo' ||
    decision.answers.genuinely_ambiguous.probability > 0.8) {
  escalateToCaptain(finding, decision.answers);
}
```

## Confidence Thresholds

Default thresholds (tune against labeled data):

| Metric | Threshold | Action |
|--------|-----------|--------|
| `severity.confidence` | > 0.9 | Auto-route |
| `severity.confidence` | > 0.7 | Route to fixer |
| `severity.confidence` | < 0.7 | Human review |
| `auto_fixable.probability` | > 0.95 | Queue auto-fix |
| `needs_human.probability` | > 0.8 | Escalate |
| `blast_radius.choice` | === 'cross_repo' | Always escalate |

## Calibration

Before production use:

1. **Collect labeled test set** — 50-100 historical findings with human triage decisions
2. **Run evaluation** — Jev on same set, compare confidence vs accuracy
3. **Tune thresholds** — adjust per calibration curve
4. **Monitor drift** — log all decisions, re-calibrate monthly

See `references/CALIBRATION.md` for methodology.

## Cost

At $0.042/MTok input, typical triage call (~500 tokens) costs ~$0.00002 (2 hundredths of a cent). 10,000 findings/day → ~$0.20/day.

## References

- `references/SCHEMA.md` — Complete question schema definitions
- `references/CALIBRATION.md` — Threshold tuning methodology
- `references/EXAMPLES.md` — Real triage examples with Jev responses
