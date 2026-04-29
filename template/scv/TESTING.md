---
name: testing
version: 1.0.0
status: draft
last_updated: 2026-04-17
applies_to: []
owners: ["@team-qa"]
tags: [standard, core, testing]
standard_version: 1.0.0
merge_policy: merge-on-markers
---

# TESTING — Quality verification convention

> Claude follows `INTAKE.md` Step 5 plus the `How to elicit` section below to fill this through user dialogue.
> Some sections (artifact-path rules) are template-fixed defaults.

## How to elicit (order of questions)

1. **Test pyramid balance**: "Do you have a target ratio for unit / integration / e2e?"
2. **Mock policy**: "In integration tests, do you **mock DB / external dependencies, or hit them for real**?" (recommended: real)
3. **E2E tooling**: "If there's a UI, what E2E tool is set? (default: Playwright + Chrome DevTools MCP)"
4. **E2E scenario targets**: "Which use cases from DOMAIN.md will you cover with E2E?" (at least 1)
5. **Probabilistic verification**: "If there are AI agents, how do you handle probabilistic responses in E2E?" (reuse AGENTS.md distribution tests)
6. **CI integration**: "When should tests run? (PR / main merge / nightly)"
7. **Failure policy**: "What kind of failure is a merge blocker? (pass-rate threshold, p95, etc.)"

## Completion criteria

- [ ] Test pyramid balance decided
- [ ] Mock policy stated
- [ ] E2E tool fixed (or "no UI" marked)
- [ ] At least 1 E2E scenario (with UC code reference)
- [ ] CI trigger points agreed
- [ ] Failure policy stated
- [ ] User confirmation

## Artifact path rules (template-fixed)

> This section is the **contract** that `/scv:report`'s `collect-artifacts.sh` depends on. If you change it, also change the script.

| Type | Path pattern | Notes |
|---|---|---|
| Screenshot | `test-results/**/*.png` | by recent mtime |
| Video | `test-results/**/*.{webm,mp4}` | failed tests |
| Trace | `test-results/**/trace.zip` | optional |
| MCP artifact | `test-results/mcp/**` | manual scenarios |
| Log | `test-results/logs/*.log` | tail 20KB on failure |
| JSON result | `test-results/results.json` | summary extraction |

**If no artifact exists**: `/scv:report` summary explicitly notes `[no artifact: <reason>]`.

## Recommended Playwright config (for UI projects)

```ts
export default defineConfig({
  outputDir: 'test-results/',
  reporter: [
    ['list'],
    ['html', { outputFolder: 'test-results/report', open: 'never' }],
    ['json', { outputFile: 'test-results/results.json' }],
  ],
  use: {
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },
});
```

## Chrome DevTools MCP convention

- Screenshot: `test-results/mcp/<YYYYMMDD>-<slug>.png`
- Performance trace: `test-results/mcp/trace-<slug>.json`
- Console log: `test-results/mcp/console-<slug>.log`

## Structure

### 1. Test pyramid

| Layer | Target ratio | Tooling |
|---|---|---|
| unit | <TODO> | ... |
| integration | <TODO> | ... |
| e2e | <TODO> | ... |

### 2. Mock policy

<TODO: how far you mock, where you switch to real dependencies, with reasoning.>

### 3. CI integration + regression strategy

SCV separates two axes of test execution.

| Axis | Command | Timing | Scope |
|---|---|---|---|
| Per-plan verification | `/scv:work <slug>` | Right after implementation | A single `scv/promote/<slug>/TESTS.md` |
| Accumulated regression | `/scv:regression` | Before archive · nightly · pre-release | `scv/archive/**/TESTS.md` (+ promote with `--include-promote`) |

#### 3.1 Local workflow

- During plan implementation: `/scv:work` runs only that TESTS (fast).
- Just before archive: `/scv:work` Step 9a fires AskUserQuestion "run archived regression too?" → on Yes, `/scv:regression` runs as pre-flight; slugs declared in `supersedes` are auto-skipped.
- Weekly or pre-release: user runs `/scv:regression` manually (or `/scv:regression --tag core` to narrow scope).

#### 3.2 CI integration example

In CI, `regression.sh` **auto-detects `CI=true`** and switches to non-interactive mode (GitHub Actions / GitLab CI / CircleCI / Jenkins all set this automatically). No need to pass `--ci`. On failure: exit 2, with `test-results/regression-summary.json` auto-generated.

**GitHub Actions example** (`.github/workflows/scv-regression.yml`):

```yaml
name: SCV regression

on:
  pull_request:
  schedule:
    - cron: '0 18 * * *'   # 03:00 KST nightly

jobs:
  regression:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4    # or setup-python, setup-go, etc.
        with:
          node-version: 20
      - run: npm ci
      # If you bundle the SCV plugin alongside CI: git submodule or cached path
      - name: Run SCV accumulated regression
        env:
          # GitHub Actions auto-sets CI=true → --ci mode kicks in automatically
          # Just point SCV at the plugin path
          CLAUDE_PLUGIN_ROOT: ${{ github.workspace }}/.scv-plugin
        run: |
          bash "$CLAUDE_PLUGIN_ROOT/scripts/regression.sh"
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: regression-summary
          path: test-results/regression-summary.json
```

To make this a PR merge gate, add the workflow's `regression` job to GitHub branch protection rules' "Required status checks". Failed regressions block the merge.

**Tip — what `supersedes` does**: when a new feature intentionally changes an old one, the old feature's archived TESTS will fail — and that's fine. A single `supersedes: [<old-slug>]` line in the new PLAN.md auto-skips it in the regression runner — that's how SCV avoids **time-pressure merges** while still treating **deprecation** explicitly.

#### 3.3 Auto PR video attachment (v0.3+)

`/scv:work` Step 9d auto-embeds **test execution videos** into the PR body when creating a PR — so reviewers can confirm "does this actually work" via video without reading code.

**What's automated**:
- For Playwright projects, SCV auto-detects `playwright.config.{ts,js,mjs,cjs}` and recommends adding `video: 'on'` automatically (Step 5b's AskUserQuestion). One Yes makes it permanent.
- During tests, .webm is auto-generated under `test-results/` (Playwright's standard behavior).
- At Step 9d's PR creation, those videos are pushed to the **`scv-attachments` orphan branch** (zero impact on the working branch's git history). If `ffmpeg` is on the system, .webm is co-converted to .gif (default 480px / 10fps / 60s cap) and pushed alongside.
- The PR body becomes a hybrid markdown: **inline GIF (auto-plays silently) + clickable .webm link (new tab native player with audio)**. Since GitHub strips `<video>` tags from PR body, GIF gives inline preview while .webm covers audio + full quality.
- If `ffmpeg` is absent, graceful degrade — only the .webm link is attached + an "install ffmpeg for inline GIF previews" notice. No SCV behavior is broken.
- Local video / GIF files are deleted right after push (disk hygiene).
- N days after PR merge (default 3, configurable), they're auto-deleted from the orphan branch (manifest-driven, `gh pr view`-based self-amortizing cleanup).

**.env settings** (optional — defaults are fine):
```
SCV_ATTACHMENTS_BACKEND=git-orphan         # default. v0.5+ adds s3 / r2
SCV_ATTACHMENTS_RETENTION_DAYS=3           # post-merge retention days. 'never' allowed
SCV_GIF_WIDTH=480                          # GIF horizontal pixels. default 480
SCV_GIF_FPS=10                             # GIF frame rate. default 10
SCV_GIF_MAX_SECONDS=60                     # GIF length cap (sec). default 60
```

Non-Playwright projects (Cypress / backend-only tests) proceed without video — only screenshots are attached to the PR.

#### 3.4 Test deprecation (vs. true regression)

3 paths when a new feature **intentionally** changes existing behavior (full detail in `scv/PROMOTE.md §8b`):

1. **Pre-declaration** — In the new PLAN.md, `supersedes: [<old-slug>]` or `supersedes_scenarios: ["<slug>:T<n>"]`.
2. **Auto-propagation** — When such a declaration exists, `/scv:work` Step 9c asks (default Yes) whether to mark the old slug as obsolete at archive time, and on user approval modifies only the old PLAN.md frontmatter.
3. **Runtime triage** — On `/scv:regression` failure, fire a per-slug 3-way AskUserQuestion: regression (fix code) / obsolete (mark now) / flaky (retry).

A slug marked `status: obsolete` is auto-excluded from subsequent regression runs (only included via `--include-obsolete`), and archived TESTS.md **is never modified** (immutable archive principle).

### 4. Failure policy

<TODO: which failures are merge blockers.>

### 5. E2E scenario catalog

<!-- PROJECT:LOCAL START -->
<!-- This block is preserved on sync. Put project-specific E2E scenarios here. -->

<TODO: E2E-001, E2E-002 form. For each scenario: preconditions, steps, success criteria, artifact storage location.>

<!-- PROJECT:LOCAL END -->

## Related modules

<!-- MODULES:AUTO START applies_to=testing -->
<!-- MODULES:AUTO END -->
