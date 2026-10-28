#!/usr/bin/env bash
# check-readme.sh — README 가 지금 저장소와 맞는지 본다.
#
#   bash tools/check-readme.sh --profile core|claude|codex|mods [<repo root>]
#
# 보는 것: (1) 적힌 명령 · 설정 키 · 상대 링크가 저장소에 실제로 있다 (2) 필수 주제의 표식이 언어판마다 있다
# (3) 영 · 한 · 일 판의 절 구조와 명령 · 설정 · 링크 · 그림 목록이 같다 (4) 버전 번호(0.x.y 꼴)가 없다 — 최신 버전은 배지와
# VERSION 파일이 읽는다 (5) 다른 호스트의 명령 문법이 없다 (6) Core 명령 목록(actions.json)의 명령이 모두 적혀 있다
# (7) 필수 그림 — 머메이드 블록 수와 GIF — 이 있다 (8) Core 는 구조 문서(docs/architecture.md)의 주제 · 그림도 본다.
# mods 프로필은 scv-mods 저장소의 영어 README 하나만 본다(명령 · 설정 실재 검사 없음, 모드 간 최소 버전은 적을 수 있다).
# 통과하면 "OK readme (<profile>): …" 한 줄과 exit 0, 어긋나면 "✖ …" 줄들과 exit 1, 인자 오류는 exit 2.
# README_OVERRIDE_DIR 가 있으면 README 본문만 그 폴더(같은 상대 경로)에서 읽는다 — 붉은 검사용. 목록 · 링크 대상은
# 늘 <repo root> 에서 찾는다. 맥(bash 3.2) · 리눅스 공통.
set -uo pipefail

# ---------------------------------------------------------------- 프로필 데이터 (순수)
profile_sets() {  # <profile> → README 묶음 이름들
  case "$1" in
    core|claude|mods) echo "root" ;;
    codex) echo "root plugin" ;;
  esac
}
set_files() {  # <profile> <set> → 영 · 한 · 일 README 상대 경로, 한 줄에 하나
  case "$1:$2" in
    codex:plugin) printf '%s\n' plugins/scv/README.md plugins/scv/README.ko.md plugins/scv/README.ja.md ;;
    mods:root) echo README.md ;;
    *) printf '%s\n' README.md README.ko.md README.ja.md ;;
  esac
}
cmd_regex() {  # <profile> → 그 호스트의 명령 표기
  case "$1" in
    core) echo 'action:[a-z][a-z-]*' ;;
    claude) echo '/scv:[a-z][a-z-]*' ;;
    codex) echo '[$]scv:[a-z][a-z-]*' ;;
    *) echo '' ;;
  esac
}
cmd_prefix() {  # <profile> → 명령 이름 앞에 붙는 그 호스트의 표기 (actions.json 대조용)
  case "$1" in
    core) echo 'action:' ;;
    claude) echo '/scv:' ;;
    codex) echo '$scv:' ;;
    *) echo '' ;;
  esac
}
actions_file() {  # <profile> → 그 저장소 안 Core 명령 목록 (없으면 빈 값)
  case "$1" in
    core) echo core/actions.json ;;
    claude) echo vendor/scv-core/core/actions.json ;;
    codex) echo plugins/scv/vendor/scv-core/core/actions.json ;;
    *) echo '' ;;
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
    *) echo '' ;;
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
SCV_SHOW_REAL
FEATURE_ARCHITECTURE.md
archive-search
metrics.sh'
  case "$1:$2" in
    core:root) printf '%s\nSCV_RESUME_RECAP\nSCV_DELEGATE_EFFORT\n' "$common" ;;
    claude:root) printf '%s\nSCV_RESUME_RECAP\nSCV_DELEGATE_EFFORT\n/plugin marketplace update scv-claude-code\n/reload-plugins\n' "$common" ;;
    codex:root) printf '%s\nSCV_RESUME_RECAP\ncodex plugin marketplace upgrade scv-codex\ncodex plugin add scv@scv-codex\n' "$common" ;;
    codex:plugin) printf 'SCV_ALWAYS_ON\nSCV_MODEL_PROMPTING\ncodex plugin marketplace upgrade scv-codex\ncodex plugin add scv@scv-codex\n' ;;
    mods:root) printf '/scv-dashboard\n/scv-mirror\n/scv-mirror stop\n' ;;
  esac
}
diagrams() {  # <profile> <set> → 필수 그림: "mermaid <최소 수>" · "seq <표식>"(그 표식이 든 sequenceDiagram) · "gif <경로>"
  case "$1:$2" in
    core:root) printf 'mermaid 2\n' ;;
    claude:root) printf 'mermaid 2\ngif assets/scv-demo.gif\ngif assets/the-loop.gif\ngif assets/architecture.gif\n' ;;
    codex:root) printf 'mermaid 2\n' ;;
    mods:root) printf 'mermaid 1\nseq /scv-mirror\ngif assets/mirror.gif\n' ;;
  esac
}
extra_docs() {  # <profile> → 그 밖에 볼 문서 "<경로>|<표식,표식…>|<머메이드 최소 수>" — 영어 한 판
  case "$1" in
    core) echo 'docs/architecture.md|SCV_ALWAYS_ON,SCV_RESUME_RECAP,SCV_SHOW_REAL,SCV_MODEL_PROMPTING,SCV_DREAMS,SCV_JUDGE_COMMAND,action:mods,action:channel|2' ;;
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
mermaid_count() { grep -cE '^[[:space:]]*```mermaid' || true; }                    # 머메이드 블록 수
seq_blocks() {  # sequenceDiagram 이 든 머메이드 블록 본문만
  awk '/^[[:space:]]*```mermaid/{m=1; b=""; next} m&&/^[[:space:]]*```/{if(b~/sequenceDiagram/) printf "%s", b; m=0; next} m{b=b $0 "\n"}'
}
gifs_of() { grep -oE '[A-Za-z0-9_./-]+\.gif' | sort -u; }                          # GIF 참조
versions_of() { grep -oE '(^|[^0-9A-Za-z_.])v?[0-9]+\.[0-9]+\.[0-9]+' | sed -E 's/^[^0-9v]//' | sort -u; }

# ---------------------------------------------------------------- 판정 (순수: 값 → ✖ 줄)
missing_actions() {  # <text> <prefix> <ids> → 본문에 그 표기로 없는 명령
  local text="$1" id
  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    printf '%s\n' "$text" | grep -qE -- "$(printf '%s' "$2$id" | sed 's/[$]/[$]/g')([^a-z-]|\$)" || printf '%s\n' "$id"
  done <<< "$3"
}
missing_diagrams() {  # <text> <needs> → 모자란 그림 설명
  local text="$1" kind arg n
  while read -r kind arg; do
    case "$kind" in
      mermaid) n="$(printf '%s\n' "$text" | mermaid_count)"; (( n >= arg )) || printf 'mermaid blocks: %s < %s\n' "$n" "$arg" ;;
      seq) printf '%s\n' "$text" | seq_blocks | grep -qF -- "$arg" || printf 'sequenceDiagram with %s\n' "$arg" ;;
      gif) case "$text" in *"$arg"*) : ;; *) printf 'gif %s\n' "$arg" ;; esac ;;
    esac
  done <<< "$2"
}
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
case "$PROFILE" in core|claude|codex|mods) : ;; *) echo "usage: check-readme.sh --profile core|claude|codex|mods [<repo root>]" >&2; exit 2 ;; esac
ROOT="$(cd "$ROOT" 2>/dev/null && pwd)" || { echo "✖ repo root not found" >&2; exit 2; }
SRC="${README_OVERRIDE_DIR:-$ROOT}"

fail=0; nfile=0; ncmd=0; nset=0; nlink=0; ntopic=0; npic=0
ACTION_IDS=""
af="$(actions_file "$PROFILE")"
if [[ -n "$af" ]]; then
  [[ -f "$ROOT/$af" ]] || { echo "✖ $af not found" >&2; exit 2; }
  ACTION_IDS="$(jq -r '.actions[].id' "$ROOT/$af")"
fi
err() { echo "✖ $*"; fail=1; }
SEEN_IN_CODE=$'\n'; SEEN_NOT_IN_CODE=$'\n'
exists_in_code() {  # <token> → 코드 폴더 어딘가에 있으면 0 (코드 폴더가 없는 프로필은 늘 0)
  # 같은 설정 이름이 언어판마다 되풀이된다 — 한 번 찾은 답은 기억한다(트리 전체 grep 이 이 검사의
  # 거의 모든 시간이었다: 맥 CI 에서 시험 하나 62초, 우분투 6초).
  local d
  [[ "$SEEN_IN_CODE" == *$'\n'"$1"$'\n'* ]] && return 0
  [[ "$SEEN_NOT_IN_CODE" == *$'\n'"$1"$'\n'* ]] && return 1
  [[ -z "$(code_roots "$PROFILE")" ]] && return 0
  for d in $(code_roots "$PROFILE"); do
    [[ -d "$ROOT/$d" ]] || continue
    if grep -rqF --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=.cache -- "$1" "$ROOT/$d" 2>/dev/null; then
      SEEN_IN_CODE="$SEEN_IN_CODE$1"$'\n'
      return 0
    fi
  done
  SEEN_NOT_IN_CODE="$SEEN_NOT_IN_CODE$1"$'\n'
  return 1
}

for set in $(profile_sets "$PROFILE"); do
  base_name=""; base_levels=""; base_cmds=""; base_sets=""; base_links=""; base_pics=""
  markers="$(topics "$PROFILE" "$set")"
  needs="$(diagrams "$PROFILE" "$set")"
  while IFS= read -r rel; do
    f="$SRC/$rel"
    [[ -f "$f" ]] || { err "$rel: file missing"; continue; }
    nfile=$((nfile + 1))
    text="$(cat "$f")"
    # (1) 실재 — 명령 · 설정 · 링크
    cmds=""; rx="$(cmd_regex "$PROFILE")"
    [[ -n "$rx" ]] && cmds="$(printf '%s\n' "$text" | commands_of "$rx")"
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
    # (6) 명령 목록 — 루트 README 묶음만 (codex 의 플러그인 README 는 짧은 안내라 뺀다)
    if [[ "$set" == root && -n "$ACTION_IDS" ]]; then
      while IFS= read -r a; do
        [[ -n "$a" ]] && err "$rel: command missing from the README: $(cmd_prefix "$PROFILE")$a"
      done <<< "$(missing_actions "$text" "$(cmd_prefix "$PROFILE")" "$ACTION_IDS")"
    fi
    # (7) 필수 그림
    while IFS= read -r m; do
      [[ -n "$m" ]] && err "$rel: required diagram missing: $m"
    done <<< "$(missing_diagrams "$text" "$needs")"
    pics="$(printf 'mermaid %s\n' "$(printf '%s\n' "$text" | mermaid_count)"; printf '%s\n' "$text" | gifs_of)"
    npic=$((npic + $(printf '%s\n' "$needs" | grep -c .)))
    # (4) 버전 번호 · (5) 다른 호스트 문법
    v="$(printf '%s\n' "$text" | versions_of | tr '\n' ' ')"
    [[ -n "${v// /}" && "$PROFILE" != mods ]] && err "$rel: version numbers present (badge and VERSION carry them): ${v% }"
    fx="$(foreign_syntax "$PROFILE")"
    if [[ -n "$fx" ]] && printf '%s\n' "$text" | grep -qE -- "$fx"; then
      err "$rel: another host's syntax present: $(printf '%s\n' "$text" | grep -oE -- "$fx" | sort -u | tr '\n' ' ')"
    fi
    # (3) 언어판 일치 — 첫 판(영어)을 기준으로
    levels="$(printf '%s\n' "$text" | heading_levels)"
    lk="$(printf '%s\n' "$links" | lang_links_dropped)"
    if [[ -z "$base_name" ]]; then
      base_name="$rel"; base_levels="$levels"; base_cmds="$cmds"; base_sets="$keys"; base_links="$lk"; base_pics="$pics"
    else
      [[ "$levels" == "$base_levels" ]] || err "parity: $rel heading structure differs from $base_name ($(printf '%s\n' "$levels" | tr '\n' ' ') vs $(printf '%s\n' "$base_levels" | tr '\n' ' '))"
      d="$(diff_lines commands "$base_name" "$base_cmds" "$rel" "$cmds")"; [[ -n "$d" ]] && err "parity: $d"
      d="$(diff_lines settings "$base_name" "$base_sets" "$rel" "$keys")"; [[ -n "$d" ]] && err "parity: $d"
      d="$(diff_lines links "$base_name" "$base_links" "$rel" "$lk")"; [[ -n "$d" ]] && err "parity: $d"
      d="$(diff_lines diagrams "$base_name" "$base_pics" "$rel" "$pics")"; [[ -n "$d" ]] && err "parity: $d"
    fi
  done <<< "$(set_files "$PROFILE" "$set")"
done

# (8) 그 밖의 문서 — 구조 문서 등
while IFS='|' read -r rel mk mn; do
  [[ -z "$rel" ]] && continue
  f="$SRC/$rel"; [[ -f "$f" ]] || f="$ROOT/$rel"
  [[ -f "$f" ]] || { err "$rel: file missing"; continue; }
  nfile=$((nfile + 1)); text="$(cat "$f")"
  while IFS= read -r m; do
    [[ -n "$m" ]] && err "$rel: required topic marker missing: $m"
  done <<< "$(missing_markers "$text" "$(printf '%s\n' "$mk" | tr ',' '\n')")"
  ntopic=$((ntopic + $(printf '%s\n' "$mk" | tr ',' '\n' | grep -c .)))
  while IFS= read -r m; do
    [[ -n "$m" ]] && err "$rel: required diagram missing: $m"
  done <<< "$(missing_diagrams "$text" "mermaid $mn")"
  npic=$((npic + 1))
done <<< "$(extra_docs "$PROFILE")"

# ---------------------------------------------------------------- 출구
(( fail )) && exit 1
echo "OK readme ($PROFILE): $nfile file(s), $ncmd command mention(s), $nset setting mention(s), $nlink link(s), $ntopic topic check(s), $npic diagram check(s)"
