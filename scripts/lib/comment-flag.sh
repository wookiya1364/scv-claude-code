#!/usr/bin/env bash
# lib/comment-flag.sh — 이번 일이 새로 넣은 임시방편 주석을 파일:줄로 알린다(0.95.0+).
#
# 왜: 손쉬운 해결을 괜찮다고 보증하는 주석은 그 해결을 정당화한다. 다음 에이전트는 그것을 저장소의 관례로
# 읽고 베낀다. 주석에는 강제력이 없다 — 그래서 계획 끝에 새로 들어간 그런 주석을 보여 주고, 검사로 옮기거나 마무리 보고의
# 남은 빚으로 적게 한다. 막지는 않는다(알림). 원래 있던 주석과 순수 함수 표식 주석 덩어리는 알리지 않는다.
# 예시 글 안의 표식은 \x40 으로 적는다 — 그대로 적으면 선언 판정이 그 글을 표식으로 읽는다.
# 계획 20261117-wookiya1364-checks-not-comments 3단계.

_SCV_CF_AWK_ADDED='
    function flush(   i) { if (n > 0 && !marked) for (i = 1; i <= n; i++) print buf[i]; n = 0; marked = 0 }
    /^\+\+\+ / { flush(); f = substr($0, 5); sub(/^b\//, "", f); next }
    /^@@ / { flush(); h = $0; sub(/^@@ -[0-9,]+ \+/, "", h); sub(/[ ,].*$/, "", h); ln = h + 0; next }
    /^-/ { next }
    /^\+/ {
      t = substr($0, 2); s = t; sub(/^[ \t]+/, "", s)
      if (s ~ /^(#|\/\/|\/\*|\*|--|;|<!--)/ && s !~ /^#!/) {
        n++; buf[n] = f "\t" ln "\t" s
        if (s ~ /@(pure|deterministic|effect)([^A-Za-z]|$)/) marked = 1
      } else flush()
      ln++; next
    }
    { flush() }
    END { flush() }'

# @deterministic
# 역할: 통합 diff 글에서 새로 들어간 주석 줄만 "파일<탭>줄 번호<탭>주석 글"로 뽑는다 — 표식 주석 덩어리는 뺀다
# 종류: 꺼내기
# 예: $'+++ b/a.sh\n@@ -1,0 +2,2 @@\n+# TODO: 나중에 제거\n+echo hi' → $'a.sh\t2\t# TODO: 나중에 제거'
# 예: $'+++ b/a.sh\n@@ -0,0 +1,3 @@\n+# \x40pure foo\n+# 역할: 나중에 쓸 값\n+foo() { :; }' → ""
# 예: $'+++ b/x.ts\n@@ -3,1 +3,1 @@\n-// old\n+// 일반 설명' → $'x.ts\t3\t// 일반 설명'
# <통합 diff 글(git diff -U0)> → 줄들 | 빈 값. 주석 앞머리: # // /* * -- ; <!--. 셸의 첫 줄 #! 은 주석으로 보지 않는다.
scv_added_comment_lines() {
  printf '%s\n' "${1:-}" | LC_ALL=C awk "$_SCV_CF_AWK_ADDED"
}

# @pure
# 역할: 새 주석 줄들 가운데 임시방편을 뜻하는 낱말 · 구절(한 · 영 · 일)이 든 줄만 고른다 — 개념을 설명하는 낱말(임시 저장소)은 빼려고 구절로 본다
# 종류: 판정
# 예: $'a.sh\t2\t# TODO: 나중에 제거\nx.ts\t3\t// 일반 설명' → $'a.sh\t2\t# TODO: 나중에 제거'
# 예: $'b.py\t9\t# workaround — 큰 변경이라 미룸' → $'b.py\t9\t# workaround — 큰 변경이라 미룸'
# 예: $'c.go\t1\t// 一時的な回避' → $'c.go\t1\t// 一時的な回避'
# 예: $'e.sh\t5\t# 임시 저장소를 만든다' → ""
# 예: $'d.sh\t4\t# 입력을 정리한다' → ""
# <파일<탭>줄<탭>주석 줄들> → 고른 줄들 | 빈 값.
scv_flag_workaround() {
  local line text out="" nc=0
  shopt -q nocasematch && nc=1
  shopt -s nocasematch
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    text="${line#*$'\t'}"; text="${text#*$'\t'}"
    if [[ "$text" =~ (^|[^a-z])(todo|fixme|hack|xxx|workaround|work-around|temporary|temporarily|for now|stopgap|kludge)([^a-z]|$) ]] \
       || [[ "$text" =~ (fix|remove|clean[[:space:]]?up|do[[:space:]](this|it))[[:space:]]later ]] \
       || [[ "$text" =~ 임시로|임시[[:space:]]?(조치|처리|해결)|땜질|나중에[[:space:]]?(제거|지우|지운|고치|고칠|고친|정리|바꾸|바꿀|처리)|미룸|미뤄|미룬다|一時的|暫定|後で(直|消|対応)|回避策 ]]; then
      out+="$line"$'\n'
    fi
  done <<< "${1:-}"
  (( nc )) || shopt -u nocasematch
  printf '%s' "${out%$'\n'}"
}

# @pure
# 역할: 고른 임시방편 주석 줄들을 계획 끝 알림 글로 만든다 — 막지 않는다는 것과 할 일을 함께 적는다
# 종류: 조립/notice
# 예: $'a.sh\t2\t# TODO: 나중에 제거' → $'새 임시방편 주석 1개 (막지 않음 — 검사로 옮기거나 WRAPUP 의 남은 빚으로 적어라):\n  a.sh:2  # TODO: 나중에 제거'
# 예: "" → ""
# <고른 줄들> → 알림 글 | 빈 값.
scv_workaround_note() {
  local lines="${1:-}" f l t out="" n=0
  [[ -n "$lines" ]] || return 0
  while IFS=$'\t' read -r f l t; do
    [[ -n "$f" ]] || continue
    n=$(( n + 1 )); out+=$'\n'"  $f:$l  $t"
  done <<< "$lines"
  printf '%s%s' "새 임시방편 주석 ${n}개 (막지 않음 — 검사로 옮기거나 WRAPUP 의 남은 빚으로 적어라):" "$out"
}
