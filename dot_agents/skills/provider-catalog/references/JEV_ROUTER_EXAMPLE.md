# Jev Router Example

Example crew-dispatch profile using TypeSafe Jev for fast task classification.

## Profile Definition

```json
{
  "profiles": {
    "jev-router": {
      "description": "Jev-based task router — classifies shape/complexity and routes to appropriate lane",
      "model": "typesafe-ai/jev",
      "questions": {
        "task_type": {
          "type": "choice",
          "instructions": "Classify the task type",
          "criteria": {
            "ship": "Implementation work requiring code changes",
            "scout": "Investigation, research, or planning work",
            "review": "Code review or quality assessment",
            "maintenance": "Repo hygiene, refactoring, or cleanup"
          }
        },
        "complexity": {
          "type": "score",
          "instructions": "Task complexity level",
          "criteria": [
            "Trivial single-file fix",
            "Moderate multi-file change",
            "Complex architectural work"
          ]
        },
        "needs_reasoning": {
          "type": "boolean",
          "instructions": "Does this require extended reasoning chain?"
        },
        "repo_context": {
          "type": "choice",
          "instructions": "Repository context",
          "criteria": {
            "application": "Product-facing application code",
            "infrastructure": "Infrastructure or deployment code",
            "dotfiles": "Configuration or dotfiles",
            "documentation": "Documentation-only changes"
          }
        }
      },
      "routing": {
        "high_confidence": {
          "condition": "confidence > 0.9",
          "action": "use_classification_directly"
        },
        "medium_confidence": {
          "condition": "confidence > 0.7",
          "action": "route_to_frontier_model_for_validation"
        },
        "low_confidence": {
          "condition": "confidence <= 0.7",
          "action": "route_to_frontier_model_for_decision"
        }
      },
      "fallback": {
        "model": "cf-aig-dynamic/dynamic/TUI",
        "reason": "Jev unavailable or ambiguous classification"
      }
    }
  },
  "rules": [
    {
      "condition": "task_description matches 'implement|fix|add|update'",
      "profile": "jev-router",
      "priority": 10
    },
    {
      "condition": "task_description matches 'investigate|research|explore|plan'",
      "profile": "jev-router",
      "priority": 10
    }
  ],
  "default": {
    "profile": "jev-router",
    "priority": 5
  }
}
```

## Usage in Firstmate

Save to `config/crew-dispatch.json` (local, gitignored).

When dispatch receives a task:
1. Jev evaluates all questions in single call (~100ms)
2. High confidence → use classification directly
3. Medium confidence → validate with frontier model
4. Low confidence → let frontier model decide

Example routing:

| Jev Classification | Confidence | Route |
|--------------------|------------|-------|
| `task_type: ship`, `complexity: 0` | 0.95 | Use directly → spawn ship task |
| `task_type: scout`, `complexity: 2` | 0.82 | Validate → then spawn |
| `task_type: ambiguous` | 0.65 | Frontier model decides |

## Cost Savings

At ~500 tokens per classification call:
- Jev: $0.00002 per call
- Frontier model (GPT-5.6): $0.003 per call
- **Savings: 150x cheaper** for classification step

For 100 classifications/day:
- Jev: $0.002/day
- Frontier: $0.30/day
- **Monthly savings: ~$9**

## Combining with Existing Profiles

Jev-router can cascade to existing profiles:

```json
{
  "routing": {
    "high_confidence": {
      "condition": "confidence > 0.9 AND task_type == 'ship'",
      "action": "spawn_with_profile: opencode-go/deepseek-v4-flash"
    },
    "needs_reasoning": {
      "condition": "needs_reasoning.noul > 0.8",
      "action": "spawn_with_profile: opencode-zen/glm-5.2"
    }
  }
}
```

This allows cheapest-lane dispatch to use Jev's classification to pick the right lane.
