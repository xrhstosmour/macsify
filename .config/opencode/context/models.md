# Model Routing

Default to FREE models. Switch to PREMIUM only when user approves.

## Model Selection

Ask at session start: "Use free models or switch to premium models?"

| Task | Premium | Free |
| --- | --- | --- |
| Planning/Analysis | claude-haiku-4.5 | big-pickle |
| Code/Implementation | gpt-5.3-codex | minimax-m2.5-free |
| Design/UX | big-pickle | big-pickle |
| Testing | claude-haiku-4.5 | gpt-5-nano |

To switch: `/model <model-name>`

## Complexity Escalation

If using premium and hitting complexity issues, escalate:

1. `big-pickle` → `minimax-m2.5-free` → `claude-haiku-4.5` → `gpt-5.3-codex`

**Rule:** Start free, upgrade only when needed.
