# Model Routing

Use this model preference by task complexity:

- `opencode/big-pickle` as default baseline for simple tasks and Q&A.
- `haiku` for quick lightweight clarifications.
- `codex-5.3` only for hard tasks and deep coding work.

Agent defaults:

- `leader`: `codex-5.3`
- `architect`: `codex-5.3`
- `implementor`: `codex-5.3`
- `clarifier`: `haiku`
- `tester`: `haiku`
- `designer`: `opencode/big-pickle`

Escalation rule:

- Start cheap; escalate to `codex-5.3` only when complexity, risk, or repeated failure justifies it.
