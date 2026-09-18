# Finding Triage Question Schemas

## Complete Schema Definitions

### Severity Classification

```javascript
{
  severity: {
    type: 'choice',
    instructions: 'What is the finding severity level?',
    criteria: {
      critical: 'Blocks build, tests, or CI pipeline — must fix immediately',
      warning: 'Style, best-practice, or maintainability issue — fix in normal flow',
      info: 'Nitpick, suggestion, or documentation note — optional fix',
      false_positive: 'Not a real issue — should be skipped'
    }
  }
}
```

**Returns:**
- `choice`: One of `['critical', 'warning', 'info', 'false_positive']`
- `confidence`: Calibrated probability the choice is correct
- `probabilities`: Full distribution over all choices

### Auto-Fixability Assessment

```javascript
{
  auto_fixable: {
    type: 'boolean',
    instructions: 'Can this finding be fixed automatically without human judgment?'
  },
  needs_context: {
    type: 'boolean',
    instructions: 'Does fixing this require additional context beyond the finding location?'
  },
  fix_complexity: {
    type: 'choice',
    instructions: 'How complex is the fix?',
    criteria: {
      trivial: 'Single-line change, obvious fix',
      moderate: 'Multi-line change, requires understanding context',
      complex: 'Architectural change or multi-file refactoring'
    }
  }
}
```

**Returns:**
- `probability`: Probability `true` (range 0-1)
- For `auto_fixable`: `probability > 0.95` suggests auto-fix safe

### Human Review Decision

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
      multiple_files: 'Change affects multiple files in same repo',
      cross_repo: 'Change affects multiple repositories or shared infrastructure'
    }
  },
  expanding_scope: {
    type: 'boolean',
    instructions: 'Does fixing this expand beyond the original task scope?'
  },
  security_sensitive: {
    type: 'boolean',
    instructions: 'Does this touch security-sensitive code (auth, crypto, secrets)?'
  }
}
```

**Returns:**
- `probability`: Probability `true`
- For `needs_human`: `probability > 0.8` suggests escalation
- For `blast_radius`: Always escalate if `choice === 'cross_repo'`

### Quality Gate Verification

```javascript
{
  policy_violation: {
    type: 'boolean',
    instructions: 'Does this finding violate repository policy?'
  },
  jailbreak_attempt: {
    type: 'boolean',
    instructions: 'Does this look like a prompt injection or jailbreak attempt?'
  },
  needs_verification: {
    type: 'boolean',
    instructions: 'Should a human verify this before merging?'
  }
}
```

## State Input Schema

### Minimal State (for single finding)

```javascript
{
  finding: {
    id: 'string',
    type: 'string', // e.g., 'lint', 'typecheck', 'test'
    message: 'string',
    file: 'string',
    line: 'number',
    severity: 'string' // upstream severity if available
  },
  code_context: 'string', // snippet around finding
  repo_metadata: {
    language: 'string',
    framework: 'string'
  }
}
```

### Extended State (for ask-user decision)

```javascript
{
  finding: { /* as above */ },
  task_context: {
    description: 'string',
    scope: 'string',
    constraints: ['string']
  },
  recent_history: [
    { action: 'string', outcome: 'string' }
  ],
  repo_metadata: { /* as above */ }
}
```

## Response Structure

### Choice Question

```javascript
{
  type: 'choice',
  choice: 'warning', // selected option
  probabilities: {
    critical: 0.02,
    warning: 0.95,
    info: 0.02,
    false_positive: 0.01
  },
  confidence: 0.95 // calibrated confidence in choice
}
```

### Boolean Question

```javascript
{
  type: 'boolean',
  probability: 0.97 // probability true
}
```

Note: Boolean questions return `probability` (probability true), not separate confidence.

### Score Question (rubric)

```javascript
{
  type: 'score',
  score: 1.8,
  legend: {
    '0': 'Trivial fix',
    '1': 'Moderate complexity',
    '2': 'Complex refactoring'
  },
  probabilities: {
    '0': 0.1,
    '1': 0.8,
    '2': 0.1
  },
  confidence: 0.85
}
```

## Batching Multiple Questions

All questions can be evaluated in single call:

```javascript
const result = await evaluate({
  model: 'typesafe-ai/jev',
  state: { finding, code_context },
  questions: {
    severity: { /* choice schema */ },
    auto_fixable: { /* boolean schema */ },
    needs_human: { /* boolean schema */ },
    blast_radius: { /* choice schema */ }
  }
});

// All evaluated in parallel, ~same latency as single question
```
