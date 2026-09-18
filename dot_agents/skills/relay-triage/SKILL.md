---
name: relay-triage
description: Fast structured classification of public mentions (Relay/X-mode) using TypeSafe Jev. Classifies mention type, spam probability, and auto-reply safety with calibrated confidence.
---

# Relay Triage

Uses TypeSafe's Jev evaluation model to classify public mentions and decide auto-reply safety before responding through the Relay integration.

## When to Use

- **Before auto-replying to mentions** — classify mention type and safety
- **Spam filtering** — detect low-quality or promotional mentions
- **Routing decisions** — direct mentions to appropriate handler (auto-reply, manual review, dismiss)
- **Safety gates** — prevent auto-reply on ambiguous or sensitive content

## Prerequisites

- `TYPESAFE_API_KEY` environment variable (direct) OR `AI_GATEWAY_API_KEY` (Vercel path)
- Jev available through CF AI Gateway custom provider OR Vercel AI Gateway
- Relay enabled (`FMX_PAIRING_TOKEN` present in `.env`)

## Question Schemas

### Mention Classification

```javascript
{
  mention_type: {
    type: 'choice',
    instructions: 'What type of mention is this?',
    criteria: {
      feature_request: 'User requesting new functionality or enhancement',
      bug_report: 'User reporting unexpected behavior or error',
      question: 'User asking for help, clarification, or how-to',
      praise: 'User expressing satisfaction or positive feedback',
      spam: 'Low-quality, irrelevant, or promotional content',
      support: 'User needing account/billing/technical assistance'
    }
  }
}
```

### Spam Detection

```javascript
{
  is_spam: {
    type: 'boolean',
    instructions: 'Is this spam, low-quality, or irrelevant promotional content?'
  },
  is_automated: {
    type: 'boolean',
    instructions: 'Does this appear to be bot-generated or mass-posted content?'
  },
  has_value: {
    type: 'boolean',
    instructions: 'Does this mention contain actionable feedback or legitimate engagement?'
  }
}
```

### Auto-Reply Safety

```javascript
{
  safe_to_reply: {
    type: 'boolean',
    instructions: 'Is it safe to auto-reply to this mention without human review?'
  },
  needs_clarification: {
    type: 'boolean',
    instructions: 'Does this mention require clarification before responding?'
  },
  contains_pii: {
    type: 'boolean',
    instructions: 'Does this mention contain personal identifiable information?'
  },
  is_sensitive: {
    type: 'boolean',
    instructions: 'Does this touch sensitive topics (security, legal, ethics, finance)?'
  }
}
```

### Engagement Quality

```javascript
{
  message_quality: {
    type: 'score',
    instructions: 'How substantive is this mention?',
    criteria: [
      'One-word or emoji-only response',
      'Brief comment with minimal context',
      'Detailed feedback with specific examples or context'
    ]
  },
  urgency: {
    type: 'choice',
    instructions: 'What urgency level does this mention convey?',
    criteria: {
      low: 'General feedback or casual mention',
      medium: 'Timely question or actionable request',
      high: 'Critical issue, outage report, or urgent need'
    }
  }
}
```

## Integration Pattern

### Triage Flow

```javascript
const classification = await evaluate({
  model: 'typesafe-ai/jev',
  state: {
    mention_text,
    user_handle,
    user_history,
    thread_context
  },
  questions: {
    mention_type: { /* choice schema */ },
    is_spam: { /* boolean schema */ },
    safe_to_reply: { /* boolean schema */ },
    message_quality: { /* score schema */ }
  }
});

// High-quality, safe mentions → auto-reply
if (classification.answers.safe_to_reply.noul > 0.9 &&
    !classification.answers.is_spam.noul > 0.8 &&
    classification.answers.message_quality.score > 1) {
  autoReply(mention, classification.answers.mention_type.choice);
}
// Spam → dismiss
else if (classification.answers.is_spam.noul > 0.8) {
  dismissMention(mention);
}
// Everything else → manual review
else {
  queueManualReview(mention, classification.answers);
}
```

### Spam Filter

```javascript
const spamCheck = await evaluate({
  model: 'typesafe-ai/jev',
  state: { mention_text, user_handle, recent_posts },
  questions: {
    is_spam: { type: 'boolean', instructions: 'Is this spam?' },
    is_automated: { type: 'boolean', instructions: 'Bot-generated?' },
    has_value: { type: 'boolean', instructions: 'Contains value?' }
  }
});

if (spamCheck.answers.is_spam.noul > 0.85 ||
    (spamCheck.answers.is_automated.noul > 0.9 && !spamCheck.answers.has_value.noul > 0.7)) {
  dismissMention(mention);
}
```

### Safety Gate

```javascript
const safetyCheck = await evaluate({
  model: 'typesafe-ai/jev',
  state: { mention_text, user_history, thread_context },
  questions: {
    safe_to_reply: { type: 'boolean', instructions: 'Safe to auto-reply?' },
    contains_pii: { type: 'boolean', instructions: 'Contains PII?' },
    is_sensitive: { type: 'boolean', instructions: 'Sensitive topic?' }
  }
});

// Block auto-reply on PII or sensitive content
if (safetyCheck.answers.contains_pii.noul > 0.7 ||
    safetyCheck.answers.is_sensitive.noul > 0.8) {
  queueManualReview(mention, { reason: 'safety', ...safetyCheck.answers });
  return;
}
```

## Confidence Thresholds

Default thresholds (tune against labeled mention history):

| Metric | Threshold | Action |
|--------|-----------|--------|
| `safe_to_reply.noul` | > 0.9 | Auto-reply |
| `is_spam.noul` | > 0.85 | Dismiss |
| `is_automated.noul` | > 0.9 | Require `has_value` check |
| `message_quality.score` | > 1.5 | Prioritize response |
| `is_sensitive.noul` | > 0.8 | Manual review |
| `contains_pii.noul` | > 0.7 | Manual review |

## Integration with fmx-respond

This skill complements Firstmate's `fmx-respond`:

1. **Before fmx-respond triage step** — use this skill to pre-classify
2. **Pass classification to fmx-respond** — via task context
3. **fmx-respond respects thresholds** — auto-reply only if safe

You call this skill directly; Firstmate does not modify it.

## Cost

At $0.042/MTok input, typical triage call (~300 tokens) costs ~$0.00001 (1 hundredth of a cent). 1,000 mentions/day → ~$0.01/day.

## References

- `references/SCHEMA.md` — Complete question schema definitions
- `references/EXAMPLES.md` — Real triage examples with Jev responses
- `../fmx-respond/SKILL.md` — Firstmate's Relay response skill
