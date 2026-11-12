#!/usr/bin/env bash
# lib/wrapup.sh — 마무리 보고(계획 폴더의 WRAPUP.md)가 다 채워졌는지 보는 순수부 (계획 20261113-wookiya1364-wrapup-report-plan-required).
# 파일 읽기 · 출력 · 종료 코드는 scripts/wrapup.sh, 보관을 막는 일은 scripts/work.sh --archive 가 맡는다.
#
# 마무리 보고는 일곱 묶음이다: 1 문제 · 2 관찰 · 3 가설 · 4 실험 · 5 원인 · 6 해결과 검증 · 7 배운 것.
# 묶음은 "## 1. 제목" 머리로, 칸은 "- 이름: 값" 줄로 읽는다 — 칸 이름의 말(한국어 · 영어)에 기대지 않는다.
# 2 ~ 5번 묶음은 "해당 없음 — 이유"(영어 "N/A — reason") 한 줄로 건너뛸 수 있다. 1 · 6 · 7번은 건너뛸 수 없다.
#
#   scv_wu_fields <보고 글>        → "묶음<TAB>이름<TAB>값" 줄들 (이름 "#" = 묶음 제목, "-" = 건너뜀 줄)
#   scv_wu_empty <칸 줄들>         → 빈 칸 · 모자란 칸 줄들 "묶음<TAB>이름<TAB>이유"
#   scv_wu_skip_bad <칸 줄들>      → 잘못 건너뛴 묶음 줄들 "묶음<TAB>-<TAB>이유"
#   scv_wu_points <계획 글>        → yes | no (계획 문서가 마무리 보고 파일을 가리키는가)
#   scv_wu_verdict <빈 칸 줄들> <건너뜀 줄들> <파일 있음 yes|no> <가리킴 yes|no> → 첫 줄 pass | legacy | block, 그 아래 막는 이유
#   scv_wu_digest <칸 줄들>        → 끝 답에 실을 글 (틀의 안내 글을 뺀 묶음 제목과 칸)
#   scv_wu_names <언어>           → 묶음마다 "번호<TAB>제목<TAB>칸 이름;칸 이름…" 일곱 줄 (korean 이면 한국어, 그 밖은 영어)
#   scv_wu_head <언어> <제목>      → 새 마무리 보고 파일의 머리(제목 줄과 안내 주석)
#   scv_wu_skeleton <이름 줄들>    → 새 마무리 보고 파일의 몸(묶음 머리와 채울 자리만 있는 칸 줄)
#
# 꺾쇠 글자는 변수에 담아 쓴다 — 순수성 검사가 리다이렉션으로 본다.

# @pure
# 역할: 마무리 보고 글에서 묶음 제목 · 칸 · 건너뜀 줄을 꺼내 "묶음<TAB>이름<TAB>값" 줄로 낸다 — 이름 "#" 은 묶음 제목, "-" 는 건너뜀 줄. 주석이 든 줄과 1 ~ 7번 밖의 묶음은 읽지 않는다
# 종류: 꺼내기/wrapup
# 예: $'## 1. 문제\n- 상황: 느리다\n- 기대:' → $'1\t#\t문제\n1\t상황\t느리다\n1\t기대\t'
# 예: $'## 2. 관찰\n해당 없음 — 새 기능' → $'2\t#\t관찰\n2\t-\t해당 없음 — 새 기능'
# 예: $'## 3. 가설\n- H1:\n  - 캐시가 낡았다' → $'3\t#\t가설\n3\tH1\t캐시가 낡았다'
# 예: $'## Links\n- a: b' → ""
# 예: "" → ""
scv_wu_fields() {
  local text="${1:-}" line cur="" out="" pn="" pv="" in_c="" s
  local lt=$'\x3c' gt=$'\x3e' tab=$'\t' nl=$'\n'
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ -n "$in_c" ]]; then
      [[ "$line" == *"--${gt}"* ]] && in_c=""
      continue
    fi
    if [[ "$line" == *"${lt}!--"* ]]; then
      [[ "$line" == *"--${gt}"* ]] || in_c=1
      continue
    fi
    if [[ "$line" == "## "* ]]; then
      if [[ -n "$pn" ]]; then out+="${cur}${tab}${pn}${tab}${pv}${nl}"; pn=""; pv=""; fi
      s="${line#"## "}"
      case "$s" in
        [1-7].*) cur="${s%%.*}"; s="${s#*.}"
                 while [[ "$s" == " "* ]]; do s="${s# }"; done
                 out+="${cur}${tab}#${tab}${s//$tab/ }${nl}" ;;
        *) cur="" ;;
      esac
      continue
    fi
    [[ -n "$cur" ]] || continue
    case "$line" in
      "- "*|"해당 없음"*|"N/A"*|"n/a"*)
        if [[ -n "$pn" ]]; then out+="${cur}${tab}${pn}${tab}${pv}${nl}"; pn=""; pv=""; fi
        s="${line#- }"
        case "$s" in
          "해당 없음"*|"N/A"*|"n/a"*) out+="${cur}${tab}-${tab}${s//$tab/ }${nl}" ;;
          *:*) pn="${s%%:*}"; pv="${s#*:}"
               while [[ "$pn" == *" " ]]; do pn="${pn% }"; done
               while [[ "$pv" == " "* || "$pv" == "$tab"* ]]; do pv="${pv#?}"; done
               while [[ "$pv" == *" " ]]; do pv="${pv% }"; done
               pn="${pn//$tab/ }"; pv="${pv//$tab/ }" ;;
        esac ;;
      " "*|"$tab"*)
        if [[ -n "$pn" ]]; then
          s="$line"
          while [[ "$s" == " "* || "$s" == "$tab"* ]]; do s="${s#?}"; done
          s="${s#- }"
          while [[ "$s" == *" " ]]; do s="${s% }"; done
          [[ -n "$s" ]] && pv="${pv:+$pv }${s//$tab/ }"
        fi ;;
    esac
  done <<< "$text"
  if [[ -n "$pn" ]]; then out+="${cur}${tab}${pn}${tab}${pv}${nl}"; fi
  printf '%s' "${out%"$nl"}"
}

# @pure
# 역할: 칸 줄들에서 값이 비었거나 채울 자리 표시(TODO)가 남은 칸, 칸 수가 모자란 묶음, 아예 없는 묶음을 고른다 — 건너뛴 묶음은 보지 않는다. 묶음마다 필요한 칸 수는 4 · 2 · 1 · 2 · 2 · 3 · 2
# 종류: 고르기/wrapup
# 예: $'1\t#\t문제\n1\t상황\t느리다\n1\t기대\t' → $'1\t기대\t빈 칸\n1\t-\t칸 2개 · 필요 4개\n2\t-\t묶음 없음\n3\t-\t묶음 없음\n4\t-\t묶음 없음\n5\t-\t묶음 없음\n6\t-\t묶음 없음\n7\t-\t묶음 없음'
# 예: $'1\t#\tP\n1\ta\tx\n1\tb\tx\n1\tc\tx\n1\td\tx\n2\t-\tN/A — r\n3\t-\tN/A — r\n4\t-\tN/A — r\n5\t-\tN/A — r\n6\t#\tS\n6\ta\tx\n6\tb\tx\n6\tc\tx\n7\t#\tL\n7\ta\tx\n7\tb\tx' → ""
# 예: "" → $'1\t-\t묶음 없음\n2\t-\t묶음 없음\n3\t-\t묶음 없음\n4\t-\t묶음 없음\n5\t-\t묶음 없음\n6\t-\t묶음 없음\n7\t-\t묶음 없음'
scv_wu_empty() {
  local fields="${1:-}" line n rest name val skipped=" " seen=" " out="" i have need
  local lt=$'\x3c' tab=$'\t' nl=$'\n'
  local c1=0 c2=0 c3=0 c4=0 c5=0 c6=0 c7=0
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    n="${line%%$tab*}"; rest="${line#*$tab}"; name="${rest%%$tab*}"
    [[ "$name" == "-" ]] && skipped+="$n "
  done <<< "$fields"
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    n="${line%%$tab*}"; rest="${line#*$tab}"; name="${rest%%$tab*}"; val="${rest#*$tab}"
    case "$n" in [1-7]) ;; *) continue ;; esac
    seen+="$n "
    [[ "$skipped" == *" $n "* ]] && continue
    [[ "$name" == "#" || "$name" == "-" ]] && continue
    case "$n" in
      1) c1=$((c1 + 1)) ;; 2) c2=$((c2 + 1)) ;; 3) c3=$((c3 + 1)) ;; 4) c4=$((c4 + 1)) ;;
      5) c5=$((c5 + 1)) ;; 6) c6=$((c6 + 1)) ;; 7) c7=$((c7 + 1)) ;;
    esac
    if [[ -z "$val" || "$val" == *"${lt}TODO"* ]]; then out+="${n}${tab}${name}${tab}빈 칸${nl}"; fi
  done <<< "$fields"
  for i in 1 2 3 4 5 6 7; do
    [[ "$skipped" == *" $i "* ]] && continue
    case "$i" in
      1) have=$c1; need=4 ;; 2) have=$c2; need=2 ;; 3) have=$c3; need=1 ;; 4) have=$c4; need=2 ;;
      5) have=$c5; need=2 ;; 6) have=$c6; need=3 ;; 7) have=$c7; need=2 ;;
    esac
    if [[ "$seen" != *" $i "* ]]; then out+="${i}${tab}-${tab}묶음 없음${nl}"
    elif [[ "$have" -lt "$need" ]]; then out+="${i}${tab}-${tab}칸 ${have}개 · 필요 ${need}개${nl}"
    fi
  done
  printf '%s' "${out%"$nl"}"
}

# @pure
# 역할: 칸 줄들의 건너뜀 줄 가운데 건너뛸 수 없는 묶음(1 · 6 · 7번)의 것과 이유가 없는 것을 고른다
# 종류: 고르기/wrapup
# 예: $'2\t-\t해당 없음 — 새 기능이라 고장이 없다' → ""
# 예: $'3\t-\t해당 없음' → $'3\t-\t이유 없음'
# 예: $'4\t-\tN/A —  ' → $'4\t-\t이유 없음'
# 예: $'1\t-\t해당 없음 — 문제 없음\n5\t-\tN/A: new feature' → $'1\t-\t건너뛸 수 없는 묶음'
# 예: "" → ""
scv_wu_skip_bad() {
  local fields="${1:-}" line n rest name val out=""
  local tab=$'\t' nl=$'\n'
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    n="${line%%$tab*}"; rest="${line#*$tab}"; name="${rest%%$tab*}"; val="${rest#*$tab}"
    [[ "$name" == "-" ]] || continue
    case "$n" in
      1|6|7) out+="${n}${tab}-${tab}건너뛸 수 없는 묶음${nl}"; continue ;;
    esac
    case "$val" in
      "해당 없음"*) val="${val#"해당 없음"}" ;;
      "N/A"*) val="${val#"N/A"}" ;;
      "n/a"*) val="${val#"n/a"}" ;;
    esac
    while :; do
      case "$val" in
        " "*) val="${val# }" ;;
        "—"*) val="${val#"—"}" ;;
        "–"*) val="${val#"–"}" ;;
        "·"*) val="${val#"·"}" ;;
        "-"*|":"*|"."*|","*) val="${val#?}" ;;
        *) break ;;
      esac
    done
    [[ -n "$val" ]] || out+="${n}${tab}-${tab}이유 없음${nl}"
  done <<< "$fields"
  printf '%s' "${out%"$nl"}"
}

# @pure
# 역할: 계획 문서 글이 마무리 보고 파일(WRAPUP.md)을 가리키는지 가린다 — 가리키지 않으면 이 기능 전에 세운 옛 계획이다
# 종류: 판정/wrapup
# 예: $'## Links\n- 마무리 보고: [`WRAPUP.md`](./WRAPUP.md)' → "yes"
# 예: $'## Links\n- Related PRs:' → "no"
# 예: "" → "no"
scv_wu_points() {
  case "${1:-}" in
    *WRAPUP.md*) printf 'yes' ;;
    *) printf 'no' ;;
  esac
}

# @pure
# 역할: 보관해도 되는지 가린다 — 첫 줄은 pass(다 채움) · legacy(보고 파일도 가리킴도 없는 옛 계획) · block(막음), block 이면 그 아래에 이유를 한 줄씩 붙인다
# 종류: 판정/wrapup
# 예: "" "" yes yes → "pass"
# 예: "" "" no no → "legacy"
# 예: "" "" no yes → $'block\n마무리 보고 파일 없음 — 계획 문서가 WRAPUP.md 를 가리킨다'
# 예: $'7\t다른 곳에도 쓸 수 있는 것\t빈 칸' $'3\t-\t이유 없음' yes yes → $'block\n묶음 7 · 다른 곳에도 쓸 수 있는 것 — 빈 칸\n묶음 3 — 이유 없음'
# 예: $'6\t-\t칸 2개 · 필요 3개' "" yes no → $'block\n묶음 6 — 칸 2개 · 필요 3개'
scv_wu_verdict() {
  local empty="${1:-}" bad="${2:-}" has="${3:-no}" points="${4:-no}" line n rest name why out=""
  local tab=$'\t' nl=$'\n'
  if [[ "$has" != "yes" ]]; then
    if [[ "$points" == "yes" ]]; then
      printf 'block\n마무리 보고 파일 없음 — 계획 문서가 WRAPUP.md 를 가리킨다'
    else
      printf 'legacy'
    fi
    return 0
  fi
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    n="${line%%$tab*}"; rest="${line#*$tab}"; name="${rest%%$tab*}"; why="${rest#*$tab}"
    if [[ "$name" == "-" ]]; then out+="${nl}묶음 ${n} — ${why}"
    else out+="${nl}묶음 ${n} · ${name} — ${why}"
    fi
  done <<< "${empty}${nl}${bad}"
  if [[ -z "$out" ]]; then printf 'pass'; else printf 'block%s' "$out"; fi
}

# @pure
# 역할: 칸 줄들로 끝 답에 실을 마무리 보고 글을 만든다 — 묶음 제목 한 줄, 그 아래 칸은 "   - 이름: 값", 건너뛴 묶음은 건너뜀 줄 그대로
# 종류: 조립/wrapup
# 예: $'1\t#\t문제\n1\t상황\t느리다\n2\t#\t관찰\n2\t-\t해당 없음 — 새 기능' → $'1. 문제\n   - 상황: 느리다\n2. 관찰\n   해당 없음 — 새 기능'
# 예: "" → ""
scv_wu_digest() {
  local fields="${1:-}" line n rest name val out=""
  local tab=$'\t' nl=$'\n'
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    n="${line%%$tab*}"; rest="${line#*$tab}"; name="${rest%%$tab*}"; val="${rest#*$tab}"
    case "$name" in
      "#") out+="${n}. ${val}${nl}" ;;
      "-") out+="   ${val}${nl}" ;;
      *) out+="   - ${name}: ${val}${nl}" ;;
    esac
  done <<< "$fields"
  printf '%s' "${out%"$nl"}"
}

# @pure
# 역할: 마무리 보고의 묶음 제목과 칸 이름 표를 언어로 고른다 — 묶음마다 "번호<TAB>제목<TAB>칸 이름;칸 이름…" 한 줄, 일곱 묶음 16칸. korean 이면 한국어, 그 밖은 영어
# 종류: 고르기/wrapup
# 예: korean → $'1\t문제\t상황;기대;실제;재현 조건\n2\t관찰\t관찰한 사실과 측정값;정상일 때와 차이\n3\t가설\tH1\n4\t실험\t방법과 같게 둔 것;결과와 가설별 판정\n5\t원인\t직접 원인과 일어난 길;근본 원인\n6\t해결과 검증\t해결책과 고른 이유;고치기 전후 값;부작용과 회귀 시험\n7\t배운 것\t다음에 같은 문제를 만나면 진단하는 법;다른 곳에도 쓸 수 있는 것'
# 예: english → $'1\tProblem\tSituation;Expected;Actual;How to reproduce\n2\tObservation\tFacts and measurements;Difference from the normal case\n3\tHypothesis\tH1\n4\tExperiment\tMethod and what was held equal;Result and verdict per hypothesis\n5\tRoot cause\tDirect cause and how it happens;Underlying cause\n6\tSolution and validation\tSolution and why it was chosen;Before and after values;Side effects and regression tests\n7\tLearning\tHow to diagnose it next time;What applies elsewhere'
scv_wu_names() {
  local tab=$'\t' nl=$'\n' o=""
  if [[ "${1:-}" == "korean" ]]; then
    o+="1${tab}문제${tab}상황;기대;실제;재현 조건${nl}"
    o+="2${tab}관찰${tab}관찰한 사실과 측정값;정상일 때와 차이${nl}"
    o+="3${tab}가설${tab}H1${nl}"
    o+="4${tab}실험${tab}방법과 같게 둔 것;결과와 가설별 판정${nl}"
    o+="5${tab}원인${tab}직접 원인과 일어난 길;근본 원인${nl}"
    o+="6${tab}해결과 검증${tab}해결책과 고른 이유;고치기 전후 값;부작용과 회귀 시험${nl}"
    o+="7${tab}배운 것${tab}다음에 같은 문제를 만나면 진단하는 법;다른 곳에도 쓸 수 있는 것"
  else
    o+="1${tab}Problem${tab}Situation;Expected;Actual;How to reproduce${nl}"
    o+="2${tab}Observation${tab}Facts and measurements;Difference from the normal case${nl}"
    o+="3${tab}Hypothesis${tab}H1${nl}"
    o+="4${tab}Experiment${tab}Method and what was held equal;Result and verdict per hypothesis${nl}"
    o+="5${tab}Root cause${tab}Direct cause and how it happens;Underlying cause${nl}"
    o+="6${tab}Solution and validation${tab}Solution and why it was chosen;Before and after values;Side effects and regression tests${nl}"
    o+="7${tab}Learning${tab}How to diagnose it next time;What applies elsewhere"
  fi
  printf '%s' "$o"
}

# @pure
# 역할: 새 마무리 보고 파일의 머리를 만든다 — 제목 줄과, 언제 무엇을 채우는지 적은 안내 주석. korean 이면 한국어, 그 밖은 영어
# 종류: 조립/wrapup
# 예: korean "로그인 고침" → $'# 마무리 보고 — 로그인 고침\n\n<!-- 계획을 세울 때 아는 만큼(적어도 1번) 채우고, 일이 끝난 뒤 모든 칸을 채운다.\n     고장을 고치는 계획이 아니면 2 ~ 5번은 묶음마다 "해당 없음 — 이유" 한 줄로 건너뛴다.\n     1 · 6 · 7번은 모든 계획이 채운다. 빈 칸이 있으면 보관되지 않는다. -->'
# 예: english "Login fix" → $'# Wrap-up — Login fix\n\n<!-- Fill what is known when the plan is written (at least group 1), and every field once the work is done.\n     A plan that does not fix something that went wrong skips groups 2-5 with one line each: "N/A — reason".\n     Groups 1, 6 and 7 are filled by every plan. The archive is refused while a field is empty. -->'
scv_wu_head() {
  local lang="${1:-}" title="${2:-}"
  local lt=$'\x3c' gt=$'\x3e' nl=$'\n' o=""
  if [[ "$lang" == "korean" ]]; then
    o+="# 마무리 보고 — ${title}${nl}${nl}"
    o+="${lt}!-- 계획을 세울 때 아는 만큼(적어도 1번) 채우고, 일이 끝난 뒤 모든 칸을 채운다.${nl}"
    o+="     고장을 고치는 계획이 아니면 2 ~ 5번은 묶음마다 \"해당 없음 — 이유\" 한 줄로 건너뛴다.${nl}"
    o+="     1 · 6 · 7번은 모든 계획이 채운다. 빈 칸이 있으면 보관되지 않는다. --${gt}"
  else
    o+="# Wrap-up — ${title}${nl}${nl}"
    o+="${lt}!-- Fill what is known when the plan is written (at least group 1), and every field once the work is done.${nl}"
    o+="     A plan that does not fix something that went wrong skips groups 2-5 with one line each: \"N/A — reason\".${nl}"
    o+="     Groups 1, 6 and 7 are filled by every plan. The archive is refused while a field is empty. --${gt}"
  fi
  printf '%s' "$o"
}

# @pure
# 역할: 묶음 제목과 칸 이름 줄들로 새 마무리 보고 파일의 몸을 만든다 — 묶음마다 "## 번호. 제목" 머리와 채울 자리(TODO)만 있는 칸 줄
# 종류: 조립/wrapup
# 예: $'1\t문제\t상황;기대\n3\t가설\tH1' → $'## 1. 문제\n\n- 상황: <TODO>\n- 기대: <TODO>\n\n## 3. 가설\n\n- H1: <TODO>'
# 예: "" → ""
scv_wu_skeleton() {
  local names="${1:-}" line n rest title list name o=""
  local lt=$'\x3c' gt=$'\x3e' tab=$'\t' nl=$'\n'
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    n="${line%%$tab*}"; rest="${line#*$tab}"; title="${rest%%$tab*}"; list="${rest#*$tab}"
    o+="${o:+$nl}## ${n}. ${title}${nl}${nl}"
    while [[ -n "$list" ]]; do
      name="${list%%;*}"
      if [[ "$list" == *";"* ]]; then list="${list#*;}"; else list=""; fi
      o+="- ${name}: ${lt}TODO${gt}${nl}"
    done
  done <<< "$names"
  printf '%s' "${o%"$nl"}"
}
