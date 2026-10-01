#!/usr/bin/env bash
# check-readme.sh — README 가 지금 저장소와 맞는지 본다.
#
#   bash tools/check-readme.sh --profile core|claude|codex [<repo root>]
#
# 보는 것: (1) 적힌 명령 · 설정 키 · 상대 링크가 저장소에 실제로 있다 (2) 필수 주제의 표식이 언어판마다 있다
# (3) 영 · 한 · 일 판의 절 구조와 명령 · 설정 · 링크 목록이 같다 (4) 버전 번호(0.x.y 꼴)가 없다 — 최신 버전은 배지와
# VERSION 파일이 읽는다 (5) 다른 호스트의 명령 문법이 없다.
# 통과하면 "OK readme (<profile>): …" 한 줄과 exit 0, 어긋나면 "✖ …" 줄들과 exit 1, 인자 오류는 exit 2.
# README_OVERRIDE_DIR 가 있으면 README 본문만 그 폴더(같은 상대 경로)에서 읽는다 — 붉은 검사용. 목록 · 링크 대상은
# 늘 <repo root> 에서 찾는다. 맥(bash 3.2) · 리눅스 공통.
set -uo pipefail

# ---------------------------------------------------------------- 프로필 데이터 (순수)
profile_sets() {  # <profile> → README 묶음 이름들
  case "$1" in
    core|claude) echo "root" ;;
    codex) echo "root plugin" ;;
  esac
}
set_files() {  # <profile> <set> → 영 · 한 · 일 README 상대 경로, 한 줄에 하나
  case "$1:$2" in
    codex:plugin) printf '%s\n' plugins/scv/README.md plugins/scv/README.ko.md plugins/scv/README.ja.md ;;
    *) printf '%s\n' README.md README.ko.md README.ja.md ;;
  esac
}
cmd_regex() {  # <profile> → 그 호스트의 명령 표기
  case "$1" in
    core) echo 'action:[a-z][a-z-]*' ;;
    claude) echo '/scv:[a-z][a-z-]*' ;;
    codex) echo '[$]scv:[a-z][a-z-]*' ;;
  esac
}
cmd_path() {  # <profile> <name> → 그 명령이 있으면 존재할 파일
  case "$1" in
    core) echo "core/protocols/$2.md" ;;
    claude) echo "skills/$2/SKILL.md" ;;
    codex) echo "plugins/scv/skills/$2/SKILL.md" ;;
  esac
}
code_roots() {  # <profile> → 설정 키가 실제로 쓰이는지 찾을 폴더들
  case "$1" in
    core) echo "core tools .github" ;;
    claude) echo "vendor/scv-core/core scripts adapter hooks skills agents .claude-plugin" ;;
    codex) echo "plugins/scv/vendor/scv-core/core plugins/scv/adapter plugins/scv/hooks plugins/scv/skills tools .github" ;;
  esac
}
foreign_syntax() {  # <profile> → 다른 호스트 문법 (없으면 빈 값)
  case "$1" in
    claude) echo '[$]scv:|[.]codex-plugin|CODEX_PLUGIN_ROOT|allow_implicit_invocation' ;;
    codex) echo '/scv:[a-z]' ;;
    *) echo '' ;;
  esac
}
topics() {  # <profile> <set> → 필수 주제 표식, 한 줄에 하나 (계획 20260930-…-readme-refresh-core-wrappers 의 표)
  local common='SCV_ALWAYS_ON
SCV_PLAIN_LANGUAGE
SCV_MODEL_PROMPTING
SCV_GRAPH
SCV_GRAFT
FEATURE_ARCHITECTURE.md
archive-search
metrics.sh'
  case "$1:$2" in
    core:root) printf '%s\nSCV_RESUME_RECAP\nSCV_DELEGATE_EFFORT\n' "$common" ;;
    claude:root) printf '%s\nSCV_RESUME_RECAP\nSCV_DELEGATE_EFFORT\n/plugin marketplace update scv-claude-code\n/reload-plugins\n' "$common" ;;
    codex:root) printf '%s\ncodex plugin marketplace upgrade scv-codex\ncodex plugin add scv@scv-codex\n' "$common" ;;
    codex:plugin) printf 'SCV_ALWAYS_ON\nSCV_MODEL_PROMPTING\ncodex plugin marketplace upgrade scv-codex\ncodex plugin add scv@scv-codex\n' ;;
  esac
}

# ---------------------------------------------------------------- 뽑기 (순수: 본문 → 줄)
prose_of() { awk '/^[[:space:]]*```/ { fence = !fence; next } !fence'; }         # 코드 블록 밖 글
heading_levels() { prose_of | grep -E '^#{1,6} ' | sed -E 's/^(#+) .*/\1/'; }   # 절 제목 수준, 순서대로
commands_of() { grep -oE "$1" | sed 's/^.*://' | sort -u; }                       # <regex> → 명령 이름
settings_of() { grep -oE 'SCV_[A-Z0-9_]*[A-Z0-9]' | sort -u; }                    # 설정 키
links_of() {  # 코드 블록 밖의 상대 링크 · 그림 경로 (조각 · 질의 제거)
  prose_of | { grep -oE '\]\([^)]+\)|(src|href)="[^"]+"' || true; } \
    | sed -E 's/^\]\(//; s/\)$//; s/^(src|href)="//; s/"$//; s/^<//; s/>$//; s/[#?].*$//' \
    | grep -vE '^(https?:|mailto:|$)' | sort -u
}
lang_links_dropped() { grep -vE '(^|/)README(\.[a-z]{2})?\.md$' || true; }        # 언어 전환 링크는 판마다 다르다
versions_of() { grep -oE '(^|[^0-9A-Za-z_.])v?[0-9]+\.[0-9]+\.[0-9]+' | sed -E 's/^[^0-9v]//' | sort -u; }

# ---------------------------------------------------------------- 판정 (순수: 값 → ✖ 줄)
missing_markers() {  # <text> <markers> → 본문에 없는 표식
  local text="$1" m
  while IFS= read -r m; do
    [[ -z "$m" ]] && continue
    case "$text" in *"$m"*) : ;; *) printf '%s\n' "$m" ;; esac
  done <<< "$2"
}
diff_lines() {  # <label> <base name> <base> <other name> <other> → 차이 요약 (같으면 빈 값)
  [[ "$3" == "$5" ]] && return 0
  local only_base only_other
  only_base="$(comm -23 <(printf '%s\n' "$3" | sort) <(printf '%s\n' "$5" | sort) | grep -v '^$' | tr '\n' ' ')"
  only_other="$(comm -13 <(printf '%s\n' "$3" | sort) <(printf '%s\n' "$5" | sort) | grep -v '^$' | tr '\n' ' ')"
  printf '%s: %s 와 %s 가 다르다 — %s 에만: [%s] %s 에만: [%s]\n' "$1" "$2" "$4" "$2" "${only_base% }" "$4" "${only_other% }"
}

# ---------------------------------------------------------------- 입구
PROFILE=""; ROOT="."
while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="${2:-}"; shift 2 || shift ;;
    --profile=*) PROFILE="${1#--profile=}"; shift ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) ROOT="$1"; shift ;;
  esac
done
case "$PROFILE" in core|claude|codex) : ;; *) echo "usage: check-readme.sh --profile core|claude|codex [<repo root>]" >&2; exit 2 ;; esac
ROOT="$(cd "$ROOT" 2>/dev/null && pwd)" || { echo "✖ repo root not found" >&2; exit 2; }
SRC="${README_OVERRIDE_DIR:-$ROOT}"

fail=0; nfile=0; ncmd=0; nset=0; nlink=0; ntopic=0
err() { echo "✖ $*"; fail=1; }
exists_in_code() {  # <token> → 코드 폴더 어딘가에 있으면 0
  local d
  for d in $(code_roots "$PROFILE"); do
    [[ -d "$ROOT/$d" ]] || continue
    grep -rqF --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=.cache -- "$1" "$ROOT/$d" 2>/dev/null && return 0
  done
  return 1
}

for set in $(profile_sets "$PROFILE"); do
  base_name=""; base_levels=""; base_cmds=""; base_sets=""; base_links=""
  markers="$(topics "$PROFILE" "$set")"
  while IFS= read -r rel; do
    f="$SRC/$rel"
    [[ -f "$f" ]] || { err "$rel: file missing"; continue; }
    nfile=$((nfile + 1))
    text="$(cat "$f")"
    # (1) 실재 — 명령 · 설정 · 링크
    cmds="$(printf '%s\n' "$text" | commands_of "$(cmd_regex "$PROFILE")")"
    while IFS= read -r c; do
      [[ -z "$c" ]] && continue
      ncmd=$((ncmd + 1))
      [[ -f "$ROOT/$(cmd_path "$PROFILE" "$c")" ]] || err "$rel: command '$c' has no $(cmd_path "$PROFILE" "$c")"
    done <<< "$cmds"
    keys="$(printf '%s\n' "$text" | settings_of)"
    while IFS= read -r k; do
      [[ -z "$k" ]] && continue
      nset=$((nset + 1))
      exists_in_code "$k" || err "$rel: setting '$k' appears nowhere in $(code_roots "$PROFILE")"
    done <<< "$keys"
    links="$(printf '%s\n' "$text" | links_of)"
    while IFS= read -r l; do
      [[ -z "$l" ]] && continue
      nlink=$((nlink + 1))
      [[ -e "$ROOT/$(dirname "$rel")/$l" ]] || err "$rel: link target '$l' does not exist"
    done <<< "$links"
    # (2) 필수 주제
    while IFS= read -r m; do
      [[ -n "$m" ]] && err "$rel: required topic marker missing: $m"
    done <<< "$(missing_markers "$text" "$markers")"
    ntopic=$((ntopic + $(printf '%s\n' "$markers" | grep -c .)))
    # (4) 버전 번호 · (5) 다른 호스트 문법
    v="$(printf '%s\n' "$text" | versions_of | tr '\n' ' ')"
    [[ -n "${v// /}" ]] && err "$rel: version numbers present (badge and VERSION carry them): ${v% }"
    fx="$(foreign_syntax "$PROFILE")"
    if [[ -n "$fx" ]] && printf '%s\n' "$text" | grep -qE -- "$fx"; then
      err "$rel: another host's syntax present: $(printf '%s\n' "$text" | grep -oE -- "$fx" | sort -u | tr '\n' ' ')"
    fi
    # (3) 언어판 일치 — 첫 판(영어)을 기준으로
    levels="$(printf '%s\n' "$text" | heading_levels)"
    lk="$(printf '%s\n' "$links" | lang_links_dropped)"
    if [[ -z "$base_name" ]]; then
      base_name="$rel"; base_levels="$levels"; base_cmds="$cmds"; base_sets="$keys"; base_links="$lk"
    else
      [[ "$levels" == "$base_levels" ]] || err "parity: $rel heading structure differs from $base_name ($(printf '%s\n' "$levels" | tr '\n' ' ') vs $(printf '%s\n' "$base_levels" | tr '\n' ' '))"
      d="$(diff_lines commands "$base_name" "$base_cmds" "$rel" "$cmds")"; [[ -n "$d" ]] && err "parity: $d"
      d="$(diff_lines settings "$base_name" "$base_sets" "$rel" "$keys")"; [[ -n "$d" ]] && err "parity: $d"
      d="$(diff_lines links "$base_name" "$base_links" "$rel" "$lk")"; [[ -n "$d" ]] && err "parity: $d"
    fi
  done <<< "$(set_files "$PROFILE" "$set")"
done

# ---------------------------------------------------------------- 출구
(( fail )) && exit 1
echo "OK readme ($PROFILE): $nfile file(s), $ncmd command mention(s), $nset setting mention(s), $nlink link(s), $ntopic topic check(s)"
