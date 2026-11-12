#!/usr/bin/env bash
# reference.sh — 느린 순수함수 17개의 고치기 전 본문 (계획 20261111-wookiya1364-slow-pure-functions).
# 고친 본문의 답이 고치기 전과 같은지 맞대는 견줄 판이다. 이름 앞에 ref_ 만 붙였고 본문은 손대지 않았다.
# 이 파일은 고치지 않는다 — 여기 본문이 바뀌면 시험이 지키는 "고치기 전의 답"이 사라진다.
# 쓰는 곳: core/tests/test-slow-pure-functions.sh (부르기 전에 core/scripts/lib 의 해당 파일들을 먼저 읽어 둔다)

# 원래 자리: scripts/lib/plan-link.sh
ref_scv_plan_conflict_after() {
  local a="${1:-}" files="${2:-}" row num r mark rest f out=""
  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    num="${row%%$'\t'*}"; r="${row#*$'\t'}"; mark="${r%%$'\t'*}"; rest="${r#*$'\t'}"
    [[ "$mark" == done ]] && continue
    while IFS= read -r f; do
      [[ -n "$f" ]] || continue
      if [[ "$rest" == *"$f"* ]]; then
        [[ -n "$out" ]] && out="$out"$'\n'
        out="${out}겹침 · A ${num}단계 · $f"
      fi
    done <<< "$files"
  done <<< "$(scv_plan_steps "$a")"
  printf '%s' "$out"
}

# 원래 자리: scripts/lib/plan-link.sh
ref_scv_plan_conflict_before() {
  local a="${1:-}" b="${2:-}" goal ng g n out="" row num mark rest r
  local goals nongoals steps
  goals="$(scv_plan_goal_items "$b" Goals)"
  nongoals="$(scv_plan_goal_items "$a" Non-Goals)"
  steps="$(scv_plan_steps "$a")"
  while IFS= read -r goal; do
    g="$(scv_plan_norm_req "$goal")"
    (( ${#g} >= 2 )) || continue
    while IFS= read -r ng; do
      n="$(scv_plan_norm_req "$ng")"
      (( ${#n} >= 2 )) || continue
      if [[ "$g" == *"$n"* || "$n" == *"$g"* ]]; then
        [[ -n "$out" ]] && out="$out"$'\n'
        out="${out}충돌 · A 가 하지 않기로 함: $ng ↔ B 목표: $goal"
      fi
    done <<< "$nongoals"
    while IFS= read -r row; do
      [[ -n "$row" ]] || continue
      num="${row%%$'\t'*}"; r="${row#*$'\t'}"; mark="${r%%$'\t'*}"; rest="${r#*$'\t'}"
      [[ "$mark" == done ]] && continue
      n="$(scv_plan_norm_req "$rest")"
      (( ${#n} >= 2 )) || continue
      if [[ "$g" == *"$n"* || "$n" == *"$g"* ]]; then
        [[ -n "$out" ]] && out="$out"$'\n'
        out="${out}겹침 · A ${num}단계: $rest ↔ B 목표: $goal"
      fi
    done <<< "$steps"
  done <<< "$goals"
  printf '%s' "$out"
}

# 원래 자리: scripts/lib/help-state.sh
ref_scv_lint_lang_turn() {
  local last="${1:-}" turn="${2:-}" lang="${3:-}" line t pl infence=0 n=0 letters
  local re_link='^(.*)\[[^]]*\]\([^)]*\)(.*)$' re_url='^(.*)https?://[^[:space:]]*(.*)$'
  [[ "$lang" == korean || "$lang" == ko ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    t="${line#"${line%%[![:space:]]*}"}"
    if [[ "$t" == '```'* ]]; then infence=$(( 1 - infence )); continue; fi
    (( infence )) && continue
    [[ "$t" == $'\x3e'* || "$t" == \|* ]] && continue
    pl="$t"; while [[ "$pl" =~ ^(.*)\`[^\`]*\`(.*)$ ]]; do pl="${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"; done
    # 0.79.0+ — 링크([글](주소))와 맨 주소는 이름이다 — 세지 않는다(15자로 낮추자 'PR을 열었음: [저장소#420](https://…)' 가 걸렸다).
    while [[ "$pl" =~ $re_link ]]; do pl="${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"; done
    while [[ "$pl" =~ $re_url ]]; do pl="${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"; done
    letters="$(LC_ALL=C; printf '%s' "${pl//[^A-Za-z$'\xea'-$'\xed']/}")"
    (( ${#letters} >= 15 )) || continue
    [[ "$(ref_scv_lint_hangul_ratio "$pl")" -lt 20 ]] && n=$((n + 1))
  done <<< "$turn"$'\n'"$last"
  (( n > 0 )) && printf 'lang-mismatch-lines=%s\n' "$n"
  return 0
}

# 원래 자리: scripts/lib/help-state.sh
ref_scv_lint_hangul_ratio() {
  local LC_ALL=C t="${1:-}" h l
  t="${t:0:4000}"
  h="${t//[^$'\xea'-$'\xed']/}"; l="${t//[^A-Za-z]/}"
  if (( ${#h} + ${#l} == 0 )); then printf '0'; return 0; fi
  printf '%s' "$(( ${#h} * 100 / (${#h} + ${#l}) ))"
}

# 원래 자리: scripts/lib/help-state.sh
ref_scv_lint_strip_quoted() {
  local s="${1:-}"
  while [[ "$s" =~ ^(.*)\"[^\"]*\"(.*)$ ]]; do s="${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"; done
  while [[ "$s" =~ ^(.*)“.*”(.*)$ ]]; do s="${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"; done
  while [[ "$s" =~ ^(.*)‘.*’(.*)$ ]]; do s="${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"; done
  while [[ "$s" =~ ^(.*)\([^()]*\)(.*)$ ]]; do s="${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"; done
  while [[ "$s" =~ ^(.*)（.*）(.*)$ ]]; do s="${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"; done
  printf '%s' "$s"
}

# 원래 자리: scripts/lib/text.sh
ref_scv_is_rewrite_quote() {
  local t="${1:-}" q=$'\x3e'
  t="${t#"${t%%[![:space:]]*}"}"
  [[ "${t:0:1}" == "$q" ]] || { printf '0'; return 0; }
  t="${t:1}"; t="${t//\*/}"; t="${t//_/}"; t="${t#"${t%%[![:space:]]*}"}"
  case "$t" in
    "다시 쓴 요청"*|"Rewritten request"*|"rewritten request"*|"書き直した依頼"*) printf '1' ;;
    *) printf '0' ;;
  esac
}

# 원래 자리: scripts/lib/model-prompting.sh
ref_scv_mp_answer_shows_rewrite() {
  local text="${1:-}" rw="${2:-}" line t fence=0 q=$'\x3e' key="" flat
  key="${rw//[[:space:]]/}"; key="${key:0:16}"
  while IFS= read -r line || [[ -n "$line" ]]; do
    t="${line#"${line%%[![:space:]]*}"}"
    if [[ "$t" == '```'* ]]; then fence=$(( 1 - fence )); continue; fi
    (( fence )) && continue
    [[ "${t:0:1}" == "$q" ]] || continue
    case "$t" in *"다시 쓴 요청"*|*"Rewritten request"*) printf '1'; return 0 ;; esac
    flat="${t//[[:space:]]/}"
    [[ -n "$key" && "$flat" == *"$key"* ]] && { printf '1'; return 0; }
  done <<< "$text"
  printf '0'
}

# 원래 자리: scripts/lib/model-prompting.sh
ref_scv_mp_scope_forbid() {
  local v="${1:-}" p low rest up="ABCDEFGHIJKLMNOPQRSTUVWXYZ" lo="abcdefghijklmnopqrstuvwxyz" c i out="" e
  v="${v//\*/}"; v="${v//\`/}"
  v="${v#"${v%%[![:space:]_]*}"}"
  case "$v" in "범위:"*|"범위 :"*|"scope:"*|"Scope:"*|"SCOPE:"*) v="${v#*:}" ;; esac
  v="${v#"${v%%[![:space:]_]*}"}"
  for (( i = 0; i < ${#v}; i++ )); do
    c="${v:i:1}"
    case "$up" in *"$c"*) p="${up%%"$c"*}"; out+="${lo:${#p}:1}" ;; *) out+="$c" ;; esac
  done
  low="$out"
  for e in "except" "other than" "outside of" "besides" "말고" "외에" "빼고" "제외" "以外" "を除"; do
    [[ "$low" == *"$e"* ]] && return 0
  done
  for p in "변경 없음" "변경없음" "읽기 전용" "읽기만 한다" "읽기만" "보고만 한다" "보고만" "조회만 한다" "조회만" \
           "제안만 한다" "제안만" "설명만 한다" "설명만" \
           "아무것도 바꾸지 않는다" "아무것도 바꾸지 않음" "아무것도 바꾸지 않습니다" \
           "파일 · 코드는 바꾸지 않는다" "파일 · 코드는 바꾸지 않음" "파일·코드는 바꾸지 않는다" "파일 · 코드를 바꾸지 않는다" \
           "파일과 코드는 바꾸지 않는다" "파일은 바꾸지 않는다" "파일은 바꾸지 않음" "파일을 바꾸지 않는다" \
           "파일은 수정하지 않는다" "파일을 수정하지 않는다" \
           "no changes" "no file changes" "no edits" "make no changes" "change nothing" "read-only" "report only" "suggest only" \
           "do not change any file" "do not change any files" "don't change any file" "don't change any files" \
           "do not modify any file" "do not modify any files" "don't modify any file" "don't modify any files" \
           "変更なし" "読み取り専用" "報告のみ" "提案のみ" "読むだけ" "ファイルは変更しない" "何も変更しない"; do
    [[ "$low" == "$p"* ]] || continue
    rest="${low#"$p"}"; rest="${rest#"${rest%%[![:space:]]*}"}"
    case "$rest" in ""|"—"*|"–"*|"-"*|":"*|"："*|","*|"，"*|"、"*|"."*|"。"*|";"*|"("*|"（"*|"/"*|")"*)
      printf '%s' "$p"; return 0 ;;
    esac
  done
  return 0
}

# 원래 자리: scripts/lib/lang-enforce.sh
ref_scv_lang_drop_machine() {
  local p="${1:-}" lt=$'\x3c' gt=$'\x3e' t pre rest
  for t in task-notification system-reminder local-command-caveat local-command-stdout local-command-stderr \
           command-name command-message command-args side-sessions-event ci-monitor-event artifact-view-context; do
    while [[ "$p" == *"$lt$t"* ]]; do
      pre="${p%%"$lt$t"*}"; rest="${p#*"$lt$t"}"
      if [[ "$rest" == *"$lt/$t$gt"* ]]; then p="$pre${rest#*"$lt/$t$gt"}"; else p="$pre"; fi
    done
  done
  printf '%s' "$p"
}

# 원래 자리: scripts/lib/turn-check.sh
ref_scv_tc_words() {
  local t="${1:-}" w out=""
  t="${t//[^[:alnum:]가-힣%]/ }"
  for w in $t; do
    case "$w" in
      *으로|*에서|*에게|*부터|*까지) w="${w%??}" ;;
      *은|*는|*이|*가|*을|*를|*의|*에|*로|*도|*만|*와|*과) w="${w%?}" ;;
    esac
    (( ${#w} >= 2 )) || continue
    case "$w" in 기능|추가|수정|변경|화면|단계|계획|사용자|하기|한다|있음|없음) continue ;; esac
    out="$out${out:+ }$w"
  done
  printf '%s' "$out"
}

# 원래 자리: scripts/lib/turn-check.sh
ref_scv_tc_receipt() {
  local cmd="${1:-}" re
  cmd="${cmd%%$'\n'*}"
  re='^[[:space:]]*(cd[[:space:]]+[^;&|]+(&&|;)[[:space:]]*)?([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*bash[[:space:]]+"?/[^"[:space:]]*/plan-link\.sh"?[[:space:]]+(append|pause|resume|progress|exempt)([[:space:]]|$)'
  if [[ "$cmd" =~ $re ]]; then
    printf 'plan-link %s' "${BASH_REMATCH[4]}"
  fi
}

# 원래 자리: scripts/turn-check.sh
ref_key_of() {
  local k="${1//\//_}"
  printf '%s' "${k// /_}"
}

# 원래 자리: scripts/lib/pure-catalog.sh
ref_pc_duplicate_pairs() {
  local lines="${1:-}" key name i j n=0 a b
  local -a keys=() names=()
  while IFS=$'\t' read -r key name; do
    [[ -n "$name" ]] || continue
    keys[n]="$key"; names[n]="$name"; n=$((n + 1))
  done <<< "$lines"
  for (( i = 0; i != n; i++ )); do
    for (( j = i + 1; j != n; j++ )); do
      [[ "${keys[i]}" == "${keys[j]}" ]] || continue
      a="${names[i]}"; b="${names[j]}"
      printf '%s\t%s\n' "$a" "$b"
    done
  done
}

# 원래 자리: scripts/lib/pure-catalog.sh
ref_pc_mutual_pairs() {
  local lines="${1:-}" x y i j n=0
  local -a xs=() ys=()
  while IFS=$'\t' read -r x y; do
    [[ -n "$y" ]] || continue
    xs[n]="$x"; ys[n]="$y"; n=$((n + 1))
  done <<< "$lines"
  for (( i = 0; i != n; i++ )); do
    for (( j = i + 1; j != n; j++ )); do
      [[ "${xs[j]}" == "${ys[i]}" && "${ys[j]}" == "${xs[i]}" ]] && printf '%s\t%s\n' "${xs[i]}" "${ys[i]}"
    done
  done
}

# 원래 자리: scripts/lib/metrics.sh
ref_scv_mx_aggregate() {
  local lines="${1:-}" slug v n=0 m=0 sum=0 i j tmp avg10="" med10=""
  local vals=()
  while IFS=$'\t' read -r slug v || [[ -n "$slug" ]]; do
    [[ -z "$slug" ]] && continue
    m=$(( m + 1 ))
    [[ "$v" =~ ^[0-9]+$ ]] || continue
    n=$(( n + 1 )); sum=$(( sum + v )); vals+=("$v")
  done <<< "$lines"
  if (( n > 0 )); then
    # 삽입 정렬 — sort 를 부르지 않는다 (n 은 계획 수, 수백을 넘지 않는다)
    for (( i = 1; i < n; i++ )); do
      tmp=${vals[$i]}; j=$(( i - 1 ))
      # bash 3.2 는 단락 평가 뒤에도 vals[-1] 첨자를 오류로 본다 — 조건을 둘로 나눈다
      while (( j >= 0 )); do
        (( vals[j] > tmp )) || break
        vals[$(( j + 1 ))]=${vals[$j]}; j=$(( j - 1 ))
      done
      vals[$(( j + 1 ))]=$tmp
    done
    avg10=$(( (sum * 10 + n / 2) / n ))
    if (( n % 2 )); then med10=$(( vals[n / 2] * 10 )); else med10=$(( (vals[n / 2 - 1] + vals[n / 2]) * 5 )); fi
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$n" "$m" "$sum" "$avg10" "$med10"
}

# 원래 자리: scripts/lib/regression-memo.sh
ref_scv_reg_split_chain() {
  local line="${1:-}" seg="" i=0 n c2
  if [[ "$line" == *"'"* || "$line" == *'"'* ]]; then printf '%s\x1f\n' "$line"; return 0; fi
  n=${#line}
  while [[ $i -lt $n ]]; do
    c2="${line:i:2}"
    if [[ "$c2" == "&&" || "$c2" == "||" ]]; then
      printf '%s\x1f%s\n' "$seg" "$c2"; seg=""; i=$((i + 2)); continue
    elif [[ "${line:i:1}" == ";" ]]; then
      printf '%s\x1f;\n' "$seg"; seg=""; i=$((i + 1)); continue
    fi
    seg+="${line:i:1}"; i=$((i + 1))
  done
  printf '%s\x1f\n' "$seg"
}

# 원래 자리: scripts/lib/archive-search.sh
ref_scv_as_count_terms() {
  local line="${1:-}" terms="${2:-}" t n=0
  local lower; lower="$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]')"
  local tl
  while IFS= read -r t; do
    [[ -n "$t" ]] || continue
    # 있는 그대로 먼저 — 문자 변환이 여러 바이트 글자를 깨뜨리는 환경이 있다.
    case "$line" in *"$t"*) n=$((n+1)); continue ;; esac
    tl="$(printf '%s' "$t" | tr '[:upper:]' '[:lower:]')"
    case "$lower" in *"$tl"*) n=$((n+1)) ;; esac
  done <<< "$terms"
  printf '%s' "$n"
}
