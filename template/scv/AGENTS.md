---
name: agents
version: 1.0.0
status: draft
last_updated: 2026-04-17
applies_to: []
owners: ["@team-ai"]
tags: [standard, optional, ai, agents]
standard_version: 1.0.0
merge_policy: preserve
optional_when: "no probabilistic AI components (LLM/STT/TTS/classifier)"
---

# AGENTS — AI agent spec (optional document)

> **Fill this only if the project has probabilistic components (LLM / STT / TTS / classifier, etc.).** Otherwise mark `status: N/A` and skip.
> Claude follows `INTAKE.md` Step 4 plus the `How to elicit` section below.

## How to elicit (order of questions)

1. **Applicability**: "Does this system have probabilistic (non-deterministic) AI components?" — if no, set `status: N/A` and stop.
2. **Agent list**: "How many agents and what roles? (one line per agent: name + role.)"
3. **I/O contract**: "What is each agent's input / output data shape?"
4. **Model / provider**: "Are the model/provider already chosen, or do we need to pick?"
5. **SLA**: "What are the latency / cost / accuracy targets?"
6. **Prompt management**: "Will we version prompts as files? What's the path convention?"
7. **Verifiability**: "How is each agent's output **verifiable**? Deterministic snapshot? Or distribution-based?"
8. **Guardrails**: "Need toxicity / PII / disallowed-topic filters?"
9. **Rollback procedure**: "On model / prompt change, what triggers a rollback?"

## Completion criteria

- [ ] Applicability decided (`status: active` or `N/A`)
- [ ] (if applicable) At least 1 agent + I/O contract + SLA
- [ ] (if applicable) Prompt storage path convention agreed
- [ ] (if applicable) Verification approach (deterministic / distribution) decided per agent
- [ ] (if applicable) Guardrail need decided
- [ ] (if applicable) Rollback criteria recorded
- [ ] User confirms "this agent spec is good to proceed with"

## Structure

### 1. Agent list

| Agent | Model/Provider | Role | Input | Output | SLA |
|---|---|---|---|---|---|
| <TODO> | ... | ... | ... | ... | ... |

### 2. Prompt storage and versioning

<TODO: Path convention (e.g., `prompts/<agent>/<version>.md`), major/minor/patch criteria, active symlink policy.>

### 3. Verifiability of probabilistic behavior

> For each agent, pick **at least one** of the below.

- **Deterministic test** (when possible): temperature=0 + fixed seed + snapshot compare
- **Distribution test**: run the same input N times, judge by an assertion's `min_ratio`

Assertion type reference:

| Type | Use |
|---|---|
| `contains_any` / `contains_all` | Keyword inclusion |
| `not_contains` | Forbidden phrases |
| `regex_match` | Regex |
| `semantic_similarity` | Embedding-based semantic similarity |
| `latency_p95` | Latency distribution |
| `tool_called` | Function-call invocation |
| `schema_valid` | Structured-output schema |

Scenario template:

```yaml
- id: <TODO>
  agent: <TODO>
  scenario: "<TODO: user input / situation>"
  input: {}
  runs: 20
  assertions:
    - type: <TODO>
      ...
      min_ratio: 0.9
```

### 4. Golden-set regression

<TODO: Path, pass-rate threshold, execution cadence.>

### 5. Toxicity / PII guard

<TODO: Need? rule-set path? testing method?>

### 6. Model / prompt swap & rollback procedure

<TODO: Canary stages, rollback triggers (pass rate / latency / complaints).>

### 7. Orchestration

<TODO: Inter-agent call order, timeouts, fallback. Omit for single-agent.>

## Related modules

<!-- MODULES:AUTO START applies_to=agents -->
<!-- MODULES:AUTO END -->
