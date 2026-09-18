---
name: escalation-check
description: Fast structured escalation decision helper using TypeSafe Jev. Evaluates if findings or decisions require captain escalation per ask-user-authority criteria with calibrated confidence.
---

# Escalation Check

Uses TypeSafe's Jev evaluation model to make fast, cheap structured decisions about whether to escalate to the captain, complementing Firstmate's `ask-user-authority` skill.

## When to Use

- **Before escalating ask-user findings** — determine if genuinely ambiguous per criteria
- **Captain-hold decisions** — decide if finding needs captain judgment
- **Blast-radius assessment** — evaluate impact scope for routing
- **Destructive action approval** — gate high-risk operations

## Prerequisites

- `AI_GATEWAY_API_KEY` environment variable (Vercel AI Gateway, immediate access)
- Model: `typesafe-ai/jev` via Vercel AI Gateway

## Question Schemas

### Ambiguity Assessment

```javascript
{
  genuinely_ambiguous: {
    type: 'boolean',
    instructions: 'Is this genuinely ambiguous per ask-user-authority criteria (multiple valid interpretations, no clear right answer)?'
  },
  has_clear_intent: {
    type: 'boolean',
    instructions: 'Is there a clear, unambiguous intent that matches existing patterns?'
  },
  needs_clarification: {
    type: 'boolean',
    instructions: 'Would additional context resolve the ambiguity?'
  }
}
```

### Blast Radius Evaluation

```javascript
{
  blast_radius: {
    type: 'choice',
    instructions: 'What is the impact scope of this decision?',
    criteria: {
      single_file: 'Change isolated to one file',
      multiple_files: 'Change affects multiple files in same repo',
      cross_repo: 'Change affects multiple repositories or shared infrastructure',
      fleet_wide: 'Change affects fleet configuration or all servers'
    }
  },
  reversible: {
    type: 'boolean',
    instructions: 'Can this change be easily rolled back if wrong?'
  },
  affects_production: {
    type: 'boolean',
    instructions: 'Does this change touch production systems or live data?'
  }
}
```

### Security Sensitivity

```javascript
{
  security_sensitive: {
    type: 'boolean',
    instructions: 'Does this touch security-sensitive code (auth, crypto, secrets, permissions)?'
  },
  handles_secrets: {
    type: 'boolean',
    instructions: 'Does this decision involve handling or storing secrets/credentials?'
  },
  is_destructive: {
    type: 'boolean',
    instructions: 'Is this action destructive (deleting data, removing access, force-pushing)?'
  },
  is_irreversible: {
    type: 'boolean',
    instructions: 'Is this action irreversible without manual intervention?'
  }
}
```

### Scope Expansion

```javascript
{
  expanding_scope: {
    type: 'boolean',
    instructions: 'Does this decision expand beyond the original task scope?'
  },
  scope_drift: {
    type: 'boolean',
    instructions: 'Is this a case of scope creep that should be captured as follow-up work?'
  },
  needs_new_task: {
    type: 'boolean',
    instructions: 'Should this be filed as a separate backlog task instead of inline?'
  }
}
```

## Integration Pattern

### Ask-User Authority Pre-Check

```javascript
const decision = await evaluate({
  model: 'typesafe-ai/jev',
  state: {
    finding,
    task_context,
    recent_history
  },
  questions: {
    genuinely_ambiguous: { /* boolean schema */ },
    blast_radius: { /* choice schema */ },
    expanding_scope: { /* boolean schema */ },
    security_sensitive: { /* boolean schema */ }
  }
});

// Escalate if genuinely ambiguous, high blast radius, or security-sensitive
const shouldEscalate =
  decision.answers.genuinely_ambiguous.noul > 0.8 ||
  decision.answers.blast_radius.choice === 'cross_repo' ||
  decision.answers.blast_radius.choice === 'fleet_wide' ||
  decision.answers.security_sensitive.noul > 0.7;

if (shouldEscalate) {
  escalateToCaptain(finding, decision.answers);
} else {
  // Proceed with autonomous decision
  proceedWithFix(finding);
}
```

### Destructive Action Gate

```javascript
const safetyCheck = await evaluate({
  model: 'typesafe-ai/jev',
  state: { action_description, target, context },
  questions: {
    is_destructive: { type: 'boolean', instructions: 'Is this destructive?' },
    is_irreversible: { type: 'boolean', instructions: 'Is this irreversible?' },
    reversible: { type: 'boolean', instructions: 'Can this be rolled back?' },
    affects_production: { type: 'boolean', instructions: 'Touches production?' }
  }
});

// Always escalate destructive + irreversible + production
if (safetyCheck.answers.is_destructive.noul > 0.8 &&
    !safetyCheck.answers.reversible.noul > 0.7 &&
    safetyCheck.answers.affects_production.noul > 0.7) {
  requireCaptainApproval(action, safetyCheck.answers);
  return;
}
```

### Blast Radius Routing

```javascript
const impactCheck = await evaluate({
  model: 'typesafe-ai/jev',
  state: { decision, repo_context, fleet_state },
  questions: {
    blast_radius: { /* choice schema */ },
    affects_production: { type: 'boolean', instructions: 'Touches production?' }
  }
});

switch (impactCheck.answers.blast_radius.choice) {
  case 'single_file':
    // Autonomous
    proceedWithChange();
    break;
  case 'multiple_files':
    // Route to fixer agent
    routeToFixer(decision);
    break;
  case 'cross_repo':
    // Escalate to captain
    escalateToCaptain(decision, { reason: 'cross_repo_impact' });
    break;
  case 'fleet_wide':
    // Captain + log to fleet state
    escalateToCaptain(decision, { reason: 'fleet_wide_impact' });
    logFleetChange(decision);
    break;
}
```

## Confidence Thresholds

Default thresholds (tune against labeled escalation history):

| Metric | Threshold | Action |
|--------|-----------|--------|
| `genuinely_ambiguous.noul` | > 0.8 | Escalate |
| `blast_radius.choice` | === 'cross_repo' | Escalate |
| `blast_radius.choice` | === 'fleet_wide' | Escalate + log |
| `security_sensitive.noul` | > 0.7 | Escalate |
| `is_destructive.noul` | > 0.8 AND `is_irreversible.noul` > 0.7 | Escalate |
| `expanding_scope.noul` | > 0.8 | File follow-up task |

## Relationship to ask-user-authority

This skill **complements** Firstmate's `ask-user-authority`:

- **ask-user-authority** — authoritative policy for escalation criteria
- **escalation-check** — fast decision helper using Jev
- **Pattern**: Use escalation-check as first pass, escalate only if criteria met

You call this skill directly; Firstmate does not modify it.

## Cost

At $0.042/MTok input, typical check (~400 tokens) costs ~$0.00002 (2 hundredths of a cent). 500 escalation checks/day → ~$0.01/day.

## References

- `references/SCHEMA.md` — Complete question schema definitions
- `references/ESCALATION_CRITERIA.md` — Mapping to ask-user-authority policy
- `../ask-user-authority/SKILL.md` — Authoritative escalation policy
