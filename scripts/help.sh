#!/usr/bin/env bash
# Self-onboarding output for the SCV plugin.
# Prints: overview, command list, current project diagnosis, next action.
set -uo pipefail

VERBOSE=0
for a in "$@"; do
  case "$a" in
    --verbose|-v) VERBOSE=1 ;;
  esac
done

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# Plugin root (contains scripts/, template/, commands/, ...). When run as a
# slash command, $CLAUDE_PLUGIN_ROOT is set; fall back to ../ of SCRIPT_DIR.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

# --- Fixed overview (always shown) -------------------------------------------
cat <<'EOF'
╔══════════════════════════════════════════════════════════════════════╗
║  SCV — Standard · Cowork · Verify                                     ║
╚══════════════════════════════════════════════════════════════════════╝

핵심 아이디어 (S·C·V)
  S  Standard — 사람이 설계 문서를 대화로 채운다 (scv/INTAKE.md)
  C  Cowork   — scv/raw 자유 투입 → scv/promote/ 승격으로 팀 협업
  V  Verify   — 구현 → E2E → Slack/Discord 보고로 매 Phase 검증

워크플로 (기본 = adoption / --new = greenfield)
  ① hydrate         → 빈 템플릿을 프로젝트에 복제
  ② .env 설정       → NOTIFIER_PROVIDER=slack|discord, 토큰/채널
  ③ scv/raw/        → 기존 자료(회의록·스케치·PDF) 자유 투입 (선택)
  ④ /scv:promote    → raw → scv/promote/<YYYYMMDD>-<author>-<slug>/ (PLAN + TESTS)
  ⑤ /scv:work       → 구현 · 테스트 · 통과 시 archive 이동
  (선택) INTAKE.md   → 신규 프로젝트(--new)일 때 표준 문서를 대화로 채움
  (선택) /ralph-loop → 외부 템플릿 (ralph-template-scv.md 를 ~/.claude/ralph-template.md 로 복사 필요)
  (선택) /scv:regression → 주기적 · 릴리즈 전 누적 회귀 (archive 전체). ⑤ 의 archive 직전에도 선택적 pre-flight 가능

커맨드
  /scv:help       이 화면 (현재 상태 + 다음 할 일)
  /scv:status     scv/raw/ 변경 감지 + 활성 promote 계획 + 그래프 상태
  /scv:promote    scv/raw/ → scv/promote/<YYYYMMDD>-<author>-<slug>/ 승격 + 그래프 갱신
  /scv:work       promote 계획 구현 → 테스트 → 필요 시 archive 이동
  /scv:regression archived 누적 회귀 실행 + supersedes/obsolete 자동 skip + 실패 triage
  /scv:report     Slack/Discord로 Phase 보고 (아티팩트 포함)
  /scv:sync       템플릿 버전 업 시 안전 병합

EOF

# --- Raw change banner (quick read of scv/readpath.json) ---------------------
# Only show when there are changes and readpath.sh is present.
READPATH_SH="$PLUGIN_ROOT/scripts/readpath.sh"
if [[ -x "$READPATH_SH" ]] && [[ -d "scv/raw" ]]; then
  COUNTS=$(bash "$READPATH_SH" status-counts 2>/dev/null || true)
  # parses "added=N modified=N removed=N total=N"
  TOTAL=$(printf '%s' "$COUNTS" | sed -n 's/.*total=\([0-9]*\).*/\1/p')
  TOTAL=${TOTAL:-0}
  if [[ "$TOTAL" -gt 0 ]]; then
    ADDED=$(printf '%s' "$COUNTS" | sed -n 's/.*added=\([0-9]*\).*/\1/p')
    MODIFIED=$(printf '%s' "$COUNTS" | sed -n 's/.*modified=\([0-9]*\).*/\1/p')
    REMOVED=$(printf '%s' "$COUNTS" | sed -n 's/.*removed=\([0-9]*\).*/\1/p')
    echo ""
    echo "[scv/raw] ${ADDED:-0} added · ${MODIFIED:-0} modified · ${REMOVED:-0} removed → /scv:status or /scv:promote"
  fi
fi

# --- Dynamic diagnosis of current project ------------------------------------
PROJECT_PWD="$(pwd)"
echo "──────────────────────────────────────────────────────────────────────"
echo " 현재 프로젝트 진단 ($PROJECT_PWD)"
echo "──────────────────────────────────────────────────────────────────────"

HYDRATED=0
ENV_SET=0
RAW_COUNT=0
DRAFT_DOCS=()
ACTIVE_DOCS=()
NA_DOCS=()

# Hydration check (SCV owns scv/ only — root CLAUDE.md is user-owned)
if [[ -f "scv/CLAUDE.md" && -f "scv/INTAKE.md" ]]; then
  HYDRATED=1
  echo "  [✓] hydrate 완료 (scv/CLAUDE.md + scv/INTAKE.md 존재)"
else
  echo "  [✗] hydrate 안됨 (scv/CLAUDE.md / scv/INTAKE.md 누락)"
fi

# .env check
if [[ -f ".env" ]]; then
  if grep -q "^NOTIFIER_PROVIDER=" .env 2>/dev/null; then
    prov=$(grep "^NOTIFIER_PROVIDER=" .env | head -1 | cut -d= -f2)
    token_ok=0
    case "$prov" in
      slack)   grep -q "^SLACK_BOT_TOKEN=xoxb-" .env 2>/dev/null && token_ok=1 ;;
      discord) grep -q "^DISCORD_BOT_TOKEN=.\+" .env 2>/dev/null && ! grep -q "^DISCORD_BOT_TOKEN=REPLACE" .env && token_ok=1 ;;
    esac
    if [[ $token_ok -eq 1 ]]; then
      ENV_SET=1
      echo "  [✓] .env 설정 (NOTIFIER_PROVIDER=$prov, 토큰 있음)"
    else
      echo "  [△] .env 있지만 토큰 미설정 (NOTIFIER_PROVIDER=$prov)"
    fi
  else
    echo "  [△] .env 있지만 NOTIFIER_PROVIDER 없음"
  fi
elif [[ -f ".env.example.scv" ]]; then
  echo "  [✗] .env 없음 — 'cp .env.example.scv .env' (또는 기존 .env 에 cat >> 로 append) 후 값 채우기"
else
  echo "  [✗] .env.example.scv 도 없음 (hydrate 필요)"
fi

# Document status
if [[ $HYDRATED -eq 1 ]]; then
  for doc in INTAKE PROMOTE DOMAIN ARCHITECTURE DESIGN AGENTS TESTING REPORTING RALPH_PROMPT; do
    f="scv/$doc.md"
    [[ ! -f "$f" ]] && continue
    st=$(awk '/^---[[:space:]]*$/{c++; next} c==1 && /^status:/{print $2; exit}' "$f" | tr -d '[:space:]')
    case "$st" in
      draft)   DRAFT_DOCS+=("$doc") ;;
      active)  ACTIVE_DOCS+=("$doc") ;;
      N/A|na)  NA_DOCS+=("$doc") ;;
      *)       DRAFT_DOCS+=("$doc") ;;
    esac
  done

  echo "  문서 상태:"
  if [[ ${#ACTIVE_DOCS[@]} -gt 0 ]]; then
    printf '    active  : %s\n' "${ACTIVE_DOCS[*]}"
  fi
  if [[ ${#DRAFT_DOCS[@]} -gt 0 ]]; then
    printf '    draft   : %s  ← 채워야 함\n' "${DRAFT_DOCS[*]}"
  fi
  if [[ ${#NA_DOCS[@]} -gt 0 ]]; then
    printf '    N/A     : %s\n' "${NA_DOCS[*]}"
  fi
fi

# Raw inventory
if [[ -d "scv/raw" ]]; then
  RAW_COUNT=$(find scv/raw -type f ! -name 'README.md' 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$RAW_COUNT" -gt 0 ]]; then
    echo "  [i] scv/raw 에 $RAW_COUNT 개 자료 있음 — /scv:promote 로 정제 검토 가능"
  fi
fi

# Raw changes since last index (reuses readpath.sh earlier banner logic)
RAW_CHANGES_TOTAL=0
if [[ -x "$READPATH_SH" && -d "scv/raw" ]]; then
  COUNTS2=$(bash "$READPATH_SH" status-counts 2>/dev/null || true)
  RAW_CHANGES_TOTAL=$(printf '%s' "$COUNTS2" | sed -n 's/.*total=\([0-9]*\).*/\1/p')
  RAW_CHANGES_TOTAL=${RAW_CHANGES_TOTAL:-0}
fi

# Active promote plans (dir-based with PLAN.md)
ACTIVE_PLANS=()
if [[ -d "scv/promote" ]]; then
  for d in scv/promote/*/; do
    [[ -d "$d" && -f "${d}PLAN.md" ]] || continue
    ACTIVE_PLANS+=("$(basename "$d")")
  done
fi
if [[ ${#ACTIVE_PLANS[@]} -gt 0 ]]; then
  echo "  [i] scv/promote 에 ${#ACTIVE_PLANS[@]} 개 활성 계획: ${ACTIVE_PLANS[0]}${ACTIVE_PLANS[1]+ …}"
fi

# Archive count (info-only)
ARCHIVED_COUNT=0
if [[ -d "scv/archive" ]]; then
  for d in scv/archive/*/; do
    [[ -d "$d" ]] && ARCHIVED_COUNT=$((ARCHIVED_COUNT+1))
  done
  if [[ "$ARCHIVED_COUNT" -gt 0 ]]; then
    echo "  [i] scv/archive 에 $ARCHIVED_COUNT 개 완료 계획 보관됨"
  fi
fi

echo ""
echo "──────────────────────────────────────────────────────────────────────"
echo " 추천 다음 액션"
echo "──────────────────────────────────────────────────────────────────────"

# --- Recommend next step based on state --------------------------------------
if [[ $HYDRATED -eq 0 ]]; then
  cat <<EOF
  이 디렉토리는 아직 hydrate 되지 않았습니다. 두 가지 모드 중 선택하세요.

  ── 기본 · adoption mode (권장) — 기존 프로젝트에 SCV 얹기 ──
  표준 문서는 status: N/A 로 시드되고 /scv:promote, /scv:work 를
  바로 쓸 수 있습니다. 필요한 범위만 scope 좁혀 문서화 가능.

    bash "$PLUGIN_ROOT/scripts/hydrate.sh" init .

  ── --new · greenfield mode — 신규 프로젝트에서 INTAKE 로 전체 표준 문서 채우기 ──
  표준 문서가 status: draft 로 시드되고, /scv:help 가 INTAKE
  프로토콜로 DOMAIN / ARCHITECTURE / ... 를 하나씩 채우도록
  안내합니다. 이건 정말 "zero 부터 시작" 할 때만.

    bash "$PLUGIN_ROOT/scripts/hydrate.sh" init . --new

  완료 후 다시 /scv:help 를 호출하면 다음 단계를 알려드립니다.
EOF
elif [[ $ENV_SET -eq 0 ]]; then
  cat <<'EOF'
  .env 를 설정하세요. SCV Notifier 변수는 `.env.example.scv` 에 있습니다.

  1. 기존 .env 없으면:   cp .env.example.scv .env
     기존 .env 있으면:   cat .env.example.scv >> .env   (SCV 변수만 append)
  2. NOTIFIER_PROVIDER (slack 또는 discord) 결정
  3. 해당 Bot 토큰과 SLACK_CHANNEL_ID_* (또는 DISCORD_*) 채우기
  4. 다시 /scv:help
EOF
elif [[ ${#DRAFT_DOCS[@]} -gt 0 ]]; then
  active_list="${ACTIVE_DOCS[*]:-(없음)}"
  cat <<EOF
  표준 문서 상태:
    active : $active_list
    draft  : ${DRAFT_DOCS[*]}

  INTAKE 를 진행하세요. Claude 가 먼저 이어서/처음부터 선택을 물어봅니다.

  - Claude 에게 요청하는 문장 (복사용):

    "scv/INTAKE.md 를 읽고, §1 의 'resume check' 절차에 따라
     현재 status 를 먼저 확인한 뒤, [A] 이어서 / [B] 처음부터
     어느 쪽으로 진행할지 먼저 물어봐줘. 바로 단계 0 부터 시작하지 말 것."

  - 기존 raw 자료가 있으면 scv/raw/ 에 넣어두면 Claude 가 참고합니다.
EOF
elif [[ "$RAW_CHANGES_TOTAL" -gt 0 ]]; then
  cat <<EOF
  scv/raw/ 에 감지된 변경이 있습니다 (총 $RAW_CHANGES_TOTAL 건).

  다음 커맨드로 정제해서 promote 계획을 생성하세요:

      /scv:promote

  또는 먼저 상세 diff 를 보려면:

      /scv:status

  (변경만 확인하고 계획은 나중에 만들 거면 /scv:status --ack 로 baseline 만 갱신)
EOF
elif [[ ${#ACTIVE_PLANS[@]} -gt 0 ]]; then
  FIRST_SLUG="${ACTIVE_PLANS[0]}"
  if [[ ${#ACTIVE_PLANS[@]} -eq 1 ]]; then
    PLAN_HINT="다음 커맨드로 구현·테스트를 시작하세요:

      /scv:work $FIRST_SLUG"
  else
    PLAN_HINT="다음 커맨드로 가장 오래된 계획부터 시작하거나, /scv:status 로 전체 목록 확인:

      /scv:work $FIRST_SLUG       # 가장 오래된 계획부터
      /scv:status               # 전체 계획 + 그래프 상태"
  fi
  cat <<EOF
  활성 promote 계획이 ${#ACTIVE_PLANS[@]} 개 있습니다.

  $PLAN_HINT

  구현·테스트 통과 후 /scv:work 가 archive 이동 여부를 대화로 확인합니다.
EOF
else
  cat <<'EOF'
  준비 완료 — 지금 당장 필요한 액션 없음.

  다음 중 하나로 새 루프를 시작하세요:

  - 새 자료 던지기        : scv/raw/ 에 파일 투입 → 다시 /scv:help
  - Ralph Loop 자동 반복  : /ralph-loop  (외부 커맨드 · ralph-template-scv.md 설정 필요)
  - 수동 Phase 보고       : /scv:report "Phase 1 — ..." passed --summary "..."
EOF
fi

echo ""
echo "──────────────────────────────────────────────────────────────────────"
echo " 더 알고 싶다면"
echo "──────────────────────────────────────────────────────────────────────"
cat <<EOF
  각 커맨드에 --help 또는 -h 지원:
    /scv:report -h
    /scv:promote --help

  플러그인 루트:
    $PLUGIN_ROOT

  주요 문서 (hydrate 후 scv/ 하위에 생성됨 — 루트 CLAUDE.md 는 SCV 가 건드리지 않음):
    scv/CLAUDE.md     — SCV 워크플로 인덱스 · 규칙
    scv/INTAKE.md     — 대화 프로토콜 (프로젝트 시작 순서)
    scv/PROMOTE.md    — raw → promote → archive 승격 규약

EOF
