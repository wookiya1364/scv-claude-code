#!/usr/bin/env bash
# lib/obsolete.sh — 보관된 계획을 폐기로 표시하는 순수부. 읽기 · 쓰기 · 보관 목록 다시 만들기는 scripts/obsolete-mark.sh.
#
# work 9c(대체 선언)와 regression(분류)의 폐기 표시가 같은 것을 부른다 — 한쪽만 보관 목록을 새로 만들던 어긋남을
# 없앤다(계획 20261102-wookiya1364-obsolete-refresh-index).

# @pure
# 역할: PLAN.md 글의 앞머리에서 세 칸(status · obsoleted_at · obsoleted_by)만 폐기로 바꾼다 — 이미 obsolete 면 글을 그대로 돌려준다
# 종류: 변환
# 예: $'---\ntitle: a\nstatus: done\n---\n# a' "2026-11-02" "new-x" → $'---\ntitle: a\nstatus: obsolete\nobsoleted_at: 2026-11-02\nobsoleted_by: new-x\n---\n# a'
# 예: $'---\nstatus: obsolete\nobsoleted_at: 2026-10-01\n---' "2026-11-02" "new-x" → $'---\nstatus: obsolete\nobsoleted_at: 2026-10-01\n---'
# 예: "" "2026-11-02" "new-x" → ""
# 앞머리가 없으면(첫 줄이 --- 가 아니면) 글을 그대로 돌려준다. 칸이 이미 있으면 그 줄의 값만 바꾸고, 없으면 status 줄 바로 뒤에 둔다.
scv_obsolete_frontmatter() {
  local text="${1:-}" day="${2:-}" by="${3:-}" line out="" n=0 fm=0 done_fm=0 has_at=0 has_by=0 st=""
  [[ "$text" == ---* ]] || { printf '%s' "$text"; return 0; }
  # 1회차: 앞머리의 status 값과 두 칸이 있는지 본다.
  while IFS= read -r line; do
    n=$((n + 1))
    if (( n == 1 )); then continue; fi
    [[ "$line" == "---" ]] && break
    case "$line" in
      status:*) st="${line#status:}"; st="${st# }" ;;
      obsoleted_at:*) has_at=1 ;;
      obsoleted_by:*) has_by=1 ;;
    esac
  done <<< "$text"
  [[ "$st" == "obsolete" ]] && { printf '%s' "$text"; return 0; }
  # 2회차: 세 칸만 바꿔 다시 쓴다.
  n=0
  while IFS= read -r line; do
    n=$((n + 1))
    if (( n == 1 )); then out="$line"; fm=1; continue; fi
    if (( fm && ! done_fm )); then
      case "$line" in
        ---) done_fm=1 ;;
        status:*)
          line="status: obsolete"
          (( has_at )) || line="$line"$'\n'"obsoleted_at: $day"
          (( has_by )) || line="$line"$'\n'"obsoleted_by: $by" ;;
        obsoleted_at:*) line="obsoleted_at: $day" ;;
        obsoleted_by:*) line="obsoleted_by: $by" ;;
      esac
    fi
    out="$out"$'\n'"$line"
  done <<< "$text"
  [[ "$text" == *$'\n' ]] && out="$out"$'\n'
  printf '%s' "$out"
}
