# Relay Triage Question Schemas

## Complete Schema Definitions

### Mention Type Classification

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
      support: 'User needing account/billing/technical assistance',
      complaint: 'User expressing dissatisfaction or negative feedback',
      partnership: 'Business inquiry or collaboration request'
    }
  }
}
```

**Returns:**
- `choice`: Selected mention type
- `confidence`: Calibrated probability
- `probabilities`: Full distribution

### Spam Detection

```javascript
{
  is_spam: {
    type: 'boolean',
    instructions: 'Is this spam, low-quality, or irrelevant promotional content?'
  },
  is_automated: {
    type: 'boolean',
    instructions: 'Does this appear to be bot-generated or mass-posted?'
  },
  has_value: {
    type: 'boolean',
    instructions: 'Does this contain actionable feedback or legitimate engagement?'
  },
  is_marketing: {
    type: 'boolean',
    instructions: 'Is this primarily promotional/marketing content?'
  }
}
```

**Returns:**
- `noul`: Probability `true`

### Safety Assessment

```javascript
{
  safe_to_reply: {
    type: 'boolean',
    instructions: 'Is it safe to auto-reply without human review?'
  },
  contains_pii: {
    type: 'boolean',
    instructions: 'Does this contain personal identifiable information?'
  },
  is_sensitive: {
    type: 'boolean',
    instructions: 'Does this touch sensitive topics (security, legal, ethics, finance)?'
  },
  needs_verification: {
    type: 'boolean',
    instructions: 'Should a human verify this before responding?'
  },
  contains_secrets: {
    type: 'boolean',
    instructions: 'Does this contain API keys, passwords, or secrets?'
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
      'Detailed feedback with specific examples'
    ]
  },
  urgency: {
    type: 'choice',
    instructions: 'What urgency level?',
    criteria: {
      low: 'General feedback or casual mention',
      medium: 'Timely question or actionable request',
      high: 'Critical issue, outage, or urgent need'
    }
  }
}
```

## State Input Schema

### Minimal State

```javascript
{
  mention_text: 'string',
  user_handle: 'string',
  thread_id: 'string'
}
```

### Extended State

```javascript
{
  mention_text: 'string',
  user_handle: 'string',
  user_history: {
    total_mentions: 'number',
    avg_quality: 'number',
    is_verified: 'boolean'
  },
  thread_context: 'string',
  recent_posts: ['string']
}
```

## Response Structure

Same format as finding-triage schemas.

## Batching

```javascript
const result = await evaluate({
  model: 'typesafe-ai/jev',
  state: { mention_text, user_handle },
  questions: {
    mention_type: { /* choice schema */ },
    is_spam: { /* boolean schema */ },
    safe_to_reply: { /* boolean schema */ },
    message_quality: { /* score schema */ }
  }
});
```

All questions evaluated in parallel with same latency.
