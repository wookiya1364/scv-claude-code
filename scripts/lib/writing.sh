#!/usr/bin/env bash
# lib/writing.sh — 글을 읽는 사람이 덜 헤매게 하는 판정. 규칙 본문은 core/contracts/writing.md 하나다.
#
# 숫자(칸 · 문단 길이)는 여기 한 곳에만 둔다 — 문서는 이 함수 이름을 가리킨다. 글자 수는 바이트가 아니라
# 글자로 센다(한글 한 자 = 1). 맥 기본 bash 3.2 와 리눅스 bash 가 같은 값을 내게 UTF-8 지역 설정을 골라 쓴다.

# awk 를 쓰는 함수는 @deterministic 이다(순수성 검사의 엄격 층은 awk 를 막는다). 프로그램은 함수 밖 상수로 둔다 —
# 비교 연산자를 검사기가 리다이렉션으로 읽지 않게(lib/rule-constitution.sh 와 같다).
SCV_WRITING_AWK_CRITERIA='
    /^## / { sec = ($0 ~ /^## (Pass criteria|통과 판정)[ \t]*$/); next }
    /\*\*Pass criterion\*\*:/ { s = $0; sub(/.*\*\*Pass criterion\*\*:[ \t]*/, "", s); if (s != "") print s; next }
    sec && /^[ \t]*[-*][ \t]/ { s = $0; sub(/^[ \t]*[-*][ \t]+/, "", s); if (s != "") print s }
'
SCV_WRITING_AWK_CELLS='
    /^[ \t]*```/ { f = !f; next }
    f { next }
    /^[ \t]*\|/ {
      if ($0 ~ /^[ \t]*\|[ \t:|-]+\|[ \t]*$/) next
      line = $0; sub(/^[ \t]*\|/, "", line); sub(/\|[ \t]*$/, "", line)
      n = split(line, c, "|")
      for (i = 1; i <= n; i++) {
        s = c[i]; gsub(/^[ \t]+|[ \t]+$/, "", s)
        code = s; gsub(/`[^`]*`/, "", code); gsub(/[ \t·,\/]/, "", code)
        if (s == "" || code == "") continue
        while (match(s, /\[[^]]*\]\([^)]*\)/)) { t = substr(s, RSTART + 1, RLENGTH); sub(/\]\(.*/, "", t); s = substr(s, 1, RSTART - 1) t substr(s, RSTART + RLENGTH) }
        gsub(/`/, "", s)
        print s
      }
    }
'
SCV_WRITING_AWK_PARAS='
    function flush() { if (p != "") print p; p = "" }
    /^[ \t]*```/ { flush(); f = !f; next }
    f { next }
    /^[ \t]*$/ || /^#/ || /^[ \t]*\|/ || /^[ \t]*</ { flush(); next }
    /^[ \t]*([-*+]|[0-9]+\.)[ \t]/ { flush(); s = $0; sub(/^[ \t]+/, "", s); p = s; next }
    { s = $0; sub(/^[ \t]+/, "", s); p = (p == "") ? s : p " " s }
    END { flush() }
'

# @pure
# 역할: 쓸 수 있는 UTF-8 지역 설정 이름 하나를 고른다 — 글자 수를 바이트가 아닌 글자로 세려고
# 종류: 판정
# 예: "C.UTF-8 en_US.UTF-8" "en_US.UTF-8" → "en_US.UTF-8"
# 예: "C.UTF-8" "C.UTF-8" → "C.UTF-8"
# 예: "" "" → "C.UTF-8"
# <있는 지역 설정 목록(공백 구분)> <원하는 순서(공백 구분)> → 첫 일치, 없으면 C.UTF-8.
scv_writing_pick_locale() {
  local have=" ${1:-} " want="${2:-}" w
  for w in $want; do
    [[ "$have" == *" $w "* ]] && { printf '%s' "$w"; return 0; }
  done
  printf 'C.UTF-8'
}

# @pure
# 역할: README 파일 이름으로 칸 · 문단 길이 한도(글자)를 정한다 — 한글 · 일본어 판은 영어 판의 절반
# 종류: 판정
# 예: "README.md" → "60 600"
# 예: "README.ko.md" → "40 300"
# 예: "docs/README.ja.md" → "40 300"
# 휴대폰 한 줄(칸) · 한 화면(문단)에 맞춘 값. 한 · 중 · 일 글자는 영문 두 자 폭이라 절반으로 둔다.
scv_writing_limits() {
  case "${1:-}" in
    *.ko.md|*.ja.md|*.zh.md) printf '40 300' ;;
    *) printf '60 600' ;;
  esac
}

# @deterministic
# 역할: 시험서에서 통과 기준 줄('Pass criterion:' 줄과 '## Pass criteria' 절의 목록)만 꺼낸다
# 종류: 꺼내기
# 예: $'- **Pass criterion**: 잘 된다\n- **Run**: x' → "잘 된다"
# 예: $'## Pass criteria\n\n- 종료 코드 0\n## Next' → "종료 코드 0"
# 예: "" → ""
scv_writing_pass_criteria() {
  printf '%s\n' "${1:-}" | awk "$SCV_WRITING_AWK_CRITERIA"
}

# @pure
# 역할: 통과 기준 줄 중 값 · 정확한 문구가 하나도 없는 줄(숫자 · 백틱 · 따옴표가 없음)을 고른다
# 종류: 고르기
# 예: $'잘 동작한다\n종료 코드 0' → "잘 동작한다"
# 예: $'`OK readme` 출력\n"완료" 문구' → ""
# 예: "" → ""
# 값이 있으면 읽는 사람이 직접 맞춰 볼 수 있다 — "4초"처럼. 숫자 · `코드` · "문구" · '문구' · 「문구」 중 하나면 값이 있다고 본다.
scv_writing_vague_criteria() {
  local line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    case "$line" in
      *[0-9]*|*'`'*|*'"'*|*"'"*|*'“'*|*'「'*) : ;;
      *) printf '%s\n' "$line" ;;
    esac
  done <<< "${1:-}"
}

# @deterministic
# 역할: 마크다운에서 코드 블록 밖 표 칸을 꺼낸다 — 링크는 글자만, 백틱은 벗기고, 코드만 든 칸 · 구분 줄은 뺀다
# 종류: 꺼내기
# 예: $'| a | `x` |\n|---|---|\n| [링크](u) 글 | b |' → $'a\n링크 글\nb'
# 예: $'```\n| 코드 | 안 |\n```' → ""
# 예: "" → ""
# 코드만 든 칸(`action:a` · `action:b`)은 명령 목록이라 길이를 보지 않는다.
scv_writing_table_cells() {
  printf '%s\n' "${1:-}" | awk "$SCV_WRITING_AWK_CELLS"
}

# @pure
# 역할: 줄들 중 글자 수가 한도를 넘는 줄을 "글자수<탭>줄" 로 고른다
# 종류: 고르기
# 예: $'ab\nabcdefgh' 5 → $'8\tabcdefgh'
# 예: "abc" 3 → ""
# 예: "" 10 → ""
# 지역 설정은 부르는 쪽이 UTF-8 로 맞춰 둔다(LC_ALL) — 그래야 ${#s} 가 글자를 센다.
scv_writing_over_limit() {
  local lim="${2:-0}" line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    (( ${#line} > lim )) && printf '%s\t%s\n' "${#line}" "$line"
  done <<< "${1:-}"
  return 0
}

# @deterministic
# 역할: 마크다운에서 코드 블록 · 제목 · 표 · HTML 밖 문단을 한 줄씩(줄바꿈은 공백으로) 꺼낸다 — 목록 항목은 따로
# 종류: 꺼내기
# 예: $'첫 줄\n둘째 줄\n\n# 제목\n- 항목 하나\n  이어짐' → $'첫 줄 둘째 줄\n- 항목 하나 이어짐'
# 예: $'```\n코드\n```' → ""
# 예: "" → ""
scv_writing_paragraphs() {
  printf '%s\n' "${1:-}" | awk "$SCV_WRITING_AWK_PARAS"
}
