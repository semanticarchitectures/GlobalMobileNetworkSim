# +agent package

LLM agent registry, role loader, behavior tracer, and fidelity evaluator.

## Contents

- `AgentRegistry.m` — Manages agents and their node bindings
- `LLMClient.m` — OpenAI-compatible REST API client
- `RoleLoader.m` — Markdown role definition loader and validator
- `BehaviorTracer.m` — Time-ordered agent action recorder
- `FidelityEvaluator.m` — Behavior trace vs. reference behavior comparator
