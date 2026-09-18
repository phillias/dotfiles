# Escalation Check Question Schemas

## Complete Schema Definitions

### Ambiguity Assessment

```javascript
{
  genuinely_ambiguous: {
    type: 'boolean',
    instructions: 'Is this genuinely ambiguous per ask-user-authority criteria?'
  },
  has_clear_intent: {
    type: 'boolean',
    instructions: 'Is there a clear, unambiguous intent matching existing patterns?'
  },
  needs_clarification: {
    type: 'boolean',
    instructions: 'Would additional context resolve the ambiguity?'
  },
  multiple_valid_interpretations: {
    type: 'boolean',
    instructions: 'Are there multiple valid ways to interpret this?'
  }
}
```

**Returns:**
- `probability`: Probability `true`

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
    instructions: 'Can this be easily rolled back if wrong?'
  },
  affects_production: {
    type: 'boolean',
    instructions: 'Does this touch production systems or live data?'
  },
  requires_coordination: {
    type: 'boolean',
    instructions: 'Does this require coordination across teams or services?'
  }
}
```

**Returns:**
- `choice`: Selected blast radius level
- `confidence`: Calibrated probability

### Security & Risk

```javascript
{
  security_sensitive: {
    type: 'boolean',
    instructions: 'Does this touch security-sensitive code (auth, crypto, secrets)?'
  },
  handles_secrets: {
    type: 'boolean',
    instructions: 'Does this involve handling or storing secrets/credentials?'
  },
  is_destructive: {
    type: 'boolean',
    instructions: 'Is this action destructive (deleting data, removing access)?'
  },
  is_irreversible: {
    type: 'boolean',
    instructions: 'Is this action irreversible without manual intervention?'
  },
  introduces_vulnerability: {
    type: 'boolean',
    instructions: 'Could this introduce a security vulnerability?'
  }
}
```

### Scope Management

```javascript
{
  expanding_scope: {
    type: 'boolean',
    instructions: 'Does this expand beyond the original task scope?'
  },
  scope_drift: {
    type: 'boolean',
    instructions: 'Is this scope creep that should be captured separately?'
  },
  needs_new_task: {
    type: 'boolean',
    instructions: 'Should this be filed as a separate backlog task?'
  },
  blocking_work: {
    type: 'boolean',
    instructions: 'Is this blocking other work that should proceed?'
  }
}
```

### Decision Authority

```javascript
{
  needs_captain_approval: {
    type: 'boolean',
    instructions: 'Does this require captain approval per policy?'
  },
  can_auto_proceed: {
    type: 'boolean',
    instructions: 'Is this safe to proceed autonomously?'
  },
  needs_documentation: {
    type: 'boolean',
    instructions: 'Should this decision be documented for future reference?'
  }
}
```

## State Input Schema

### Finding State

```javascript
{
  finding: {
    id: 'string',
    type: 'string',
    message: 'string',
    file: 'string',
    line: 'number'
  },
  task_context: {
    description: 'string',
    scope: 'string',
    constraints: ['string']
  },
  repo_context: {
    name: 'string',
    is_shared: 'boolean',
    has_tests: 'boolean'
  }
}
```

### Action State

```javascript
{
  action_description: 'string',
  target: {
    type: 'string', // 'file', 'branch', 'repo', 'service'
    name: 'string'
  },
  context: {
    is_production: 'boolean',
    has_backup: 'boolean',
    affects_users: 'boolean'
  }
}
```

## Response Structure

Same format as finding-triage schemas.

## Batching Example

```javascript
const decision = await evaluate({
  model: 'typesafe-ai/jev',
  state: { finding, task_context, repo_context },
  questions: {
    genuinely_ambiguous: { /* boolean schema */ },
    blast_radius: { /* choice schema */ },
    security_sensitive: { /* boolean schema */ },
    expanding_scope: { /* boolean schema */ },
    needs_captain_approval: { /* boolean schema */ }
  }
});

// All questions evaluated in parallel
// Check decision.answers.genuinely_ambiguous.probability for escalation
```
