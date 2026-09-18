---
name: finding-triage
description: Fast structured triage for no-mistakes findings using TypeSafe Jev. Classifies severity, auto-fixability, and human-review requirements with calibrated confidence.
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
- Model: `typesafe-ai/jev` via Vercel AI Gateway

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

// High confidence → auto-route
if (triage.answers.severity.confidence > 0.9 && triage.answers.auto_fixable.noul > 0.95) {
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
    decision.answers.genuinely_ambiguous.noul > 0.8) {
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
| `auto_fixable.noul` | > 0.95 | Queue auto-fix |
| `needs_human.noul` | > 0.8 | Escalate |
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
