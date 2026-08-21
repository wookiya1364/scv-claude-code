# /scv:workspace

Interactive setup for nested multi-repo SCV. Ask a couple of simple questions and
this runs the right thing under the hood — no need to remember
`sync --join --id --role …` or `hydrate --root`.

## Language preference

Resolve the user's preferred language from `.env` `SCV_LANG`, then the latest
user message, then English. Keep technical identifiers (`repo_id`, `root`,
skill invocations, paths) as-is.

## Plain language first

Skip this section only when the project `.env` sets `SCV_PLAIN_LANGUAGE=off`
(absent or any other value = on).

Answer shape — every time you explain something to the user:

1. First, 1–2 sentences. Lead with what the user gets.
   The cap is 2 unless the project `.env` sets `SCV_PLAIN_MAX_SENTENCES=<n>`
   (a positive integer) — then up to n.
2. Then one example — from the user's situation, or an everyday comparison.
3. No code values before the user asks: file paths, variable names, version
   numbers, setting values. Use the plain name instead ("the settings file",
   "last week's plan").
4. Detail comes after, and only when wanted. Offer it in one line.

Identifiers the user needs to act on — the next command to run, a file that
was created — stay exact, after the plain summary.

Bad: "The block landed in `.env.example.scv:154-161` and the stamp advanced
2.1.0 → 2.2.0."
Good: "Your settings example file is up to date. For example, the new 'effort'
setting now shows there. Want the exact lines?"

This governs everything the user reads: answers, questions, plans, progress
reports, summaries, and explanations of what went wrong.

## Protocol

### Step 1 — detect current state

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workspace-helper.sh" info
```

Parse `MODE:` → one of `NOT_HYDRATED | SINGLE | ROOT | CHILD`.
- `NOT_HYDRATED` → tell the user to run `/scv:help` first to hydrate, then stop.

### Step 2 — branch by MODE

#### MODE = SINGLE → offer to set up
Ask the user for confirmation "이 레포를 워크스페이스에서 어떻게 둘까요?":
- **합류 (자식)** — 이 레포가 FE/BE/AI 중 하나로 기존 우산에 들어감
- **우산 만들기 (루트)** — 이 레포가 모두를 아우르는 최상위
- **그냥 단일로 둔다** — 변경 없음

**합류 선택 시:**
1. Ask (plain questions, one at a time):
   - 우산(root) scv repo의 **git URL 또는 로컬 경로**.
   - 이 레포의 **id** (기본값 = 폴더 이름) 와 **role** (예: frontend / backend / ai-agent).
   - (선택) workspace 이름.
2. Run:
   ```!
   "${CLAUDE_PLUGIN_ROOT}/scripts/workspace-helper.sh" join --root "<URL>" --id "<id>" --role "<role>" --workspace "<ws>"
   ```
3. Confirm: 이제 CHILD. `git pull` 후 `/scv:status`에 들어온 handoff가 보입니다.

**우산 만들기 선택 시:**
1. Run:
   ```!
   "${CLAUDE_PLUGIN_ROOT}/scripts/workspace-helper.sh" init-root
   ```
2. Open `scv/WORKSPACE.yaml` (Read/Edit) and help the user fill `members:` (id / role / url per repo).

**그냥 단일 선택 시:** do nothing.

#### MODE = CHILD → show + offer detach
Show repo_id / role / root / reachable (from `info`). Then ask:
- **그대로 둔다**
- **분리(detach) — 단일로 되돌림** → run:
  ```!
  "${CLAUDE_PLUGIN_ROOT}/scripts/workspace-helper.sh" detach
  ```
  (Reversible and lossless — re-join later with `/scv:workspace`.)

#### MODE = ROOT → show members
Read `scv/WORKSPACE.yaml` and list members. Offer to add/edit a member (Edit the file).

## Notes

- Join / detach are reversible and lossless — mode is recomputed from local files on every command, so there is no migration either way.
- This is just a friendly wrapper. The underlying mechanics are the same as the manual `sync --join` / `hydrate --root`; power users can still use those directly.
- **Monorepo (one repo, nested scv/)** — the umbrella `scv/` and each module's `scv/` live in the SAME git repo (`repo-root/scv` + `repo-root/fe/scv` + `repo-root/be/scv`). Join a module from inside it with a portable relative root:
  ```
  cd fe && /scv:sync --project-dir . --join .. --id fe --role frontend
  ```
  `..` is the module dir's parent = the repo root that holds the umbrella `scv/`. No URL, no clone — handoffs commit straight into the in-repo umbrella. Address a module without cd-ing via the leading arg: `/scv:status fe`, `/scv:handoff fe write …`. Running a command from the repo root targets the umbrella `scv/` (macro); from a module dir targets that module (micro).
