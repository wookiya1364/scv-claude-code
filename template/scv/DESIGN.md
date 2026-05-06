---
name: design
version: 1.0.0
status: draft
last_updated: 2026-04-17
applies_to: []
owners: ["@team-fe", "@team-design"]
tags: [standard, core, ui-ux]
standard_version: 1.0.0
merge_policy: preserve
optional_when: "no user-facing UI"
---

# DESIGN — UI/UX spec

> **This document is only needed for projects with a user-facing UI (web/app).** CLI/backend-only projects mark `status: N/A` and skip it.
> Claude follows `INTAKE.md` Step 3 plus the `How to elicit` section below to fill this through dialogue with the user.

## How to elicit (order of questions)

1. **Applicability**: "Does this have a UI? If not we'll skip this document." (If no, record `status: N/A`.)
2. **Personas**: "Who are the primary user personas? (1–3 people; goals, constraints, usage frequency.)"
3. **Core flows**: "What is the **most important journey** the personas perform here? (observable steps between a clear start and end.)"
4. **Screen list**: "Which screens does each flow pass through? (path, title, purpose.)"
5. **State machines**: "Are there **complex screens with multiple states**? What are the transitions between them?"
6. **Design tokens**: "Do you have color/spacing/typography tokens already? If not, will you define them in this project?"
7. **Accessibility**: "Are there accessibility standards? (WCAG level, keyboard-only, screen reader.)"
8. **Error / empty states**: "What's the UX principle for errors, permission denials, empty data?"

## Completion criteria

- [ ] Applicability decided (`status: active` or `N/A`)
- [ ] (if applicable) At least 1 persona
- [ ] (if applicable) At least 1 core flow
- [ ] (if applicable) At least 1 screen + each screen's purpose
- [ ] (if applicable) Design token source declared
- [ ] (if applicable) Accessibility standards agreed
- [ ] User confirms "this design is good to proceed with"

## Structure

### 1. Personas

<TODO: 1–3 personas, coded as P1, P2, …>

### 2. Core flows

<TODO: F1, F2, … Mermaid sequenceDiagram recommended.>

### 3. Screen list

| ID | Path | Title | Purpose | Primary persona |
|---|---|---|---|---|
| <TODO> | ... | ... | ... | ... |

### 4. Screen state machines

<TODO: Only for screens with complex state. Mermaid stateDiagram.>

### 5. Design tokens

<TODO: Figma URL / token package path. Just the primary categories.>

### 6. Accessibility

<TODO: WCAG level, keyboard, screen reader, alternative flows for mic/camera permission denials (if applicable).>

### 7. Error / empty state UX

| Situation | Display | Call to action |
|---|---|---|
| <TODO> | ... | ... |

## Related modules

<!-- MODULES:AUTO START applies_to=design -->
<!-- MODULES:AUTO END -->
