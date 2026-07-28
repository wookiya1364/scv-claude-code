---
description: "Set up or change this repo's place in a multi-repo SCV workspace: join an umbrella as a child, create an umbrella (root), check status, or detach. Friendly — no long flags to remember."
argument-hint: ""
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/workspace-helper.sh:*)", "AskUserQuestion", "Read", "Edit"]
model: haiku
---

# /scv:workspace

Interactive setup for nested multi-repo SCV. Ask a couple of simple questions and
this runs the right thing under the hood — no need to remember
`sync --join --id --role …` or `hydrate --root`.

## Language preference

Resolve the user's preferred language from `.env` `SCV_LANG`, then the latest
user message, then English. Keep technical identifiers (`repo_id`, `root`,
skill invocations, paths) as-is.

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
