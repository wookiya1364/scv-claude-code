---
name: domain
version: 1.0.0
status: draft
last_updated: 2026-04-17
applies_to: []
owners: ["@team-be", "@team-pm"]
tags: [standard, core, domain]
standard_version: 1.0.0
merge_policy: preserve
---

# DOMAIN — Business domain

> This document **starts empty**. Claude follows `INTAKE.md` Step 1 plus the `How to elicit` section below to fill it through dialogue with the user. Don't speculate without the user's explicit answer.

## How to elicit (order of questions)

1. **Mission & scope**: "In one sentence, what business problem does this system solve?" — re-ask until clear.
2. **Ubiquitous language**: "What are the core nouns and verbs your team always uses? If English/native are mixed, do you want to unify into one?"
3. **Entities**: "Does each term **exist as state** inside the system? What's its identifier?" (no upper bound, confirm one at a time)
4. **Invariants**: "What rules must each entity always satisfy?" (only those whose violation we'd treat as a bug)
5. **Use cases**: "List the 3–7 most important user actions in this system as **observable sequences**." (UC codes assigned by Claude)
6. **Business rules**: "Are there any reject / block / detour branches in the use cases?" (BR codes assigned)
7. **External policy / regulation**: "Any regulatory / legal / compliance constraints?"
8. **Bounded contexts**: "What are the boundaries with other domains (payments / logs / analytics, etc.)?" (omit if not applicable)

After each answer, Claude must confirm with **"Shall I record it like this?"** before moving to the next question.

## Completion criteria

- [ ] Mission written as one sentence
- [ ] Glossary has at least 5 core terms
- [ ] At least 1 entity + at least 1 invariant for it
- [ ] At least 1 use case (with UC code)
- [ ] External policy / regulation either listed or explicitly marked "n/a"
- [ ] User confirms "this domain doc is good to proceed with"

When met, with user approval, change frontmatter `status: draft` → `active`.

## Structure

### 1. Mission & scope

<TODO: Output of "How to elicit" Q1, in 1–2 paragraphs.>

### 2. Ubiquitous language

<TODO: Use a table. Also list disallowed synonyms.>

| Term | Definition | Disallowed synonyms |
|---|---|---|
| ... | ... | ... |

### 3. Entities

<TODO: Mermaid classDiagram or a table. Identifier, fields, relationships.>

### 4. Invariants

<TODO: INV-01, INV-02 form. State the behavior on violation.>

### 5. Use cases

<TODO: UC-xxx code, actor, preconditions, success/failure scenarios.>

### 6. Business rules

<TODO: BR-xxx code with behavior on violation.>

### 7. External policy / regulation

<TODO: Applicable laws / internal compliance. Mark "n/a" if none.>

### 8. Bounded contexts

<TODO: Boundaries with other domains. Omit for a single-context system.>

## Related modules

<!-- MODULES:AUTO START applies_to=domain -->
<!-- MODULES:AUTO END -->
