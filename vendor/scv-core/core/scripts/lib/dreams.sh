#!/usr/bin/env bash
# lib/dreams.sh — 드림(프롬프트 코치)의 순수부 (v0.69.0+). 규칙 전문은 protocols/dreams.md 한 곳 — 여기는 계산만.
# 효과는 둘: scripts/dreams.sh(세션 기록 · 보관 기록 읽기, 판정자, 보고서 쓰기)와 훅(배경 띄우기 · 요약 한 줄).
#
# flow(효과: 기록 읽기 → scv_dreams_entries → scv_dreams_human_turns · scv_dreams_register_features,
#      효과: 보관 읽기 → scv_dreams_archive_dates,
#      scv_dreams_periods → scv_dreams_distribution → scv_dreams_tips → scv_dreams_evidence
#      → [판정자 — 효과] scv_dreams_judge_prompt · scv_dreams_judge_parse
#      → scv_dreams_render_html · scv_dreams_render_summary → 효과: 쓰기)
#
# 이 파일의 함수는 lib/show-real.sh(scv_show_real_local_date · scv_show_real_valid_day · scv_show_real_is_correction)와
# lib/model-prompting.sh(scv_mp_prompt_kind)를 함께 불러 둔 셸에서 부른다 — 사람 턴 가르기 · 날짜 · 정정 판별은 실사용 보고와 같은 기준이다.
#
# 줄 모양(모두 탭으로 나눔, 글 안의 탭 · 줄바꿈은 공백):
#   사람 턴  "<세션><탭><번호><탭><시각><탭><사람 메시지 앞 1000자>"      — 세션은 효과부가 붙인 순번(f1, f2 …), 세션 id 가 아니다
#   등록     "<세션><탭><번호><탭><시각><탭><goal><탭><depth><탭><finish>" — 값은 msg | ctx | asked | na | -(없음)
#   보관     "<YYYYMMDD><탭><계획 이름>"                                  — 날짜 순
#   기간     "<시작 YYYYMMDD><탭><끝 YYYYMMDD><탭><질의><탭><보관><탭><비율 n.n | ->"
#   분포     "<계획 이름><탭><보관 날짜><탭><질의><탭><근거 턴 id | ->" 과 마지막 "#open<탭><보관 뒤 질의>"
#   개선점   "<종류 finish|depth|correction|plan><탭><a><탭><b><탭><덧붙임><탭><근거 턴 id 들(공백)>"
#   근거     "<개선점 번호(1부터)><탭><가린 발췌>"
#   조언     "<개선점 번호><탭>ok<탭><규칙 이름><탭><조언><탭><예시>" | "<개선점 번호><탭>none<탭><이유>"
#
# 꺾쇠 글자는 순수 함수 안에 그대로 쓰지 않는다 — 순수성 검사가 리다이렉션으로 본다(lib/choices.sh 와 같은 이유). HTML 조각은
# « » 로 적고 scv_dreams_tag 가 짧은 조각마다 바꾼다(긴 글에 글자 단위 치환을 쓰지 않는다 — bash 3.2 에서 느리다).

# @pure
# <설정 값 원문> → on | off. off 만 끈다(대소문자 · 공백 · 따옴표 무관) — 다른 SCV 스위치와 같은 규칙.
scv_dreams_switch() {
  local v="${1:-}"
  v="${v//[[:space:]]/}"; v="${v//\"/}"; v="${v//\'/}"
  case "$v" in
    [Oo][Ff][Ff]) printf 'off' ;;
    *)            printf 'on'  ;;
  esac
}

# @pure
# <훅 입력의 source 값> → 1(드림을 띄움: clear · compact) | 0(resume · startup · 그 밖).
scv_dreams_start_trigger() {
  case "${1:-}" in
    clear|compact) printf '1' ;;
    *)             printf '0' ;;
  esac
}

# @pure
# <지난 드림 날짜 YYYYMMDD — 빈 값 가능> <오늘 YYYYMMDD> → 1(날짜가 바뀜 — 띄움) | 0.
scv_dreams_day_trigger() {
  local last="${1:-}" today="${2:-}"
  last="${last//[[:space:]]/}"
  [[ "$today" =~ ^[0-9]{8}$ ]] || { printf '0'; return 0; }
  if [[ "$last" == "$today" ]]; then printf '0'; else printf '1'; fi
}

# @deterministic
# 표준입력: 세션 기록 JSONL(한 세션, NUL 은 효과부가 미리 지운다) → 기록 순서대로
#   "U<탭><시각><탭><앞 1000자><탭><판별용 글>"(사람이 쓴 것으로 보이는 메시지 · 프롬프트가 든 첨부 — 실사용 보고와 같은 모양)
#   "A"(모델이 무언가 함 — 글 · 도구 호출이 든 모델 줄)
#   "G<탭><시각><탭><goal><탭><depth><탭><finish>"(등록 명령 — 모델별 프롬프팅 명령의 register 호출 입력 속 "id | 상태 | 값" 줄)
# 깨진 줄 · 객체가 아닌 줄 · 메타 · 기록에만 보이는 줄(압축 요약 등) · 하위 에이전트 줄 · 도구 결과만 든 줄은 건너뛴다.
# 원문 그대로 읽기(-R)를 쓰지 않는다 — jq 1.6 이 4,096바이트 경계의 여러 바이트 글자를 깨뜨린다(show-real 과 같은 이유).
scv_dreams_entries() {
  jq -nr --rawfile in /dev/stdin '
    def sp: split("\t") | join(" ") | split("\r") | join(" ") | split("\n") | join(" ");
    def obj: type == "object";
    def head_tail: if (.[8000:] | length) != 0 then .[0:6000] + " " + .[-2000:] else . end;
    def st: if . == "msg" or . == "ctx" or . == "asked" or . == "na" then . else "-" end;
    def regmap: [split("\n")[] | sub("^\\s+"; "")
                 | (if index("\t") != null then split("\t") else split(" | ") end)
                 | map(sub("^\\s+"; "") | sub("\\s+$"; "")) | select(.[1] != null)
                 | {(.[0]): (.[1] | st)}] | add // {};
    def is_reg: type == "string" and test("model-prompting\\.sh[\"\u0027]?\\s+register(\\s|$)") and (test("--keep") | not);
    def events($o):
      if $o.type == "user" and (($o.isMeta // false) != true) and (($o.isVisibleInTranscriptOnly // false) != true)
         and (($o.isCompactSummary // false) != true) then
        ($o.message.content // null) as $c
        | if ($c | type) == "array" and ([$c[] | select(obj and .type == "tool_result")] | length) != 0 then empty
          else
            (if ($c | type) == "string" then $c
             elif ($c | type) == "array" and ([$c[] | select(obj and .type == "text")] | length) != 0
             then [$c[] | select(obj and .type == "text") | (.text // "")] | join("\n")
             else empty end) as $m
            | "U\t\($o.timestamp // "" | sp)\t\($m | .[0:1000] | sp)\t\($m | head_tail | sp)"
          end
      elif $o.type == "attachment" and (($o.attachment.prompt // null) | type) == "string" then
        $o.attachment.prompt as $m
        | "U\t\($o.timestamp // $o.attachment.timestamp // "" | sp)\t\($m | .[0:1000] | sp)\t\($m | head_tail | sp)"
      elif $o.type == "assistant" then
        [($o.message.content // null) | if type == "array" then .[] else empty end | select(obj)] as $b
        | (if ([$b[] | select(.type == "text" or .type == "tool_use")] | length) != 0 then "A" else empty end),
          ($b[] | select(.type == "tool_use") | (.input.command? // null) | select(is_reg) | regmap as $r
           | "G\t\($o.timestamp // "" | sp)\t\($r.goal // "-")\t\($r.depth // "-")\t\($r.finish // "-")")
      else empty end;
    $in | split("\n")[] | (fromjson? // null) | select(obj) | select((.isSidechain // false) != true) | events(.)' 2>/dev/null
}

# @pure
# <세션> <기록 항목 줄들(scv_dreams_entries)> <자동 입력 태그> <앞말> <뒷말> → 사람 턴 줄들(기록 순서).
# 사람 턴: 자동 입력이 아닌(scv_mp_prompt_kind 가 human) 메시지 하나부터 다음 사람 메시지 전까지. 번호는 사람 메시지마다 1부터 —
# 모델이 아무것도 하지 않은 턴(중단 표시 · 명령 출력 줄 등)은 번호만 먹고 줄을 내지 않는다(실사용 보고와 같은 기준).
scv_dreams_human_turns() {
  local sess="${1:-}" entries="${2:-}" tags="${3:-}" pfx="${4:-}" sfx="${5:-}" tab=$'\t' line k rest ts head txt
  local n=0 cur=0 did=0 c_ts="" c_head=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    k="${line%%"$tab"*}"
    case "$k" in
      U)
        rest="${line#U"$tab"}"; ts="${rest%%"$tab"*}"; rest="${rest#*"$tab"}"
        head="${rest%%"$tab"*}"; txt="${rest#*"$tab"}"
        [[ "$(scv_mp_prompt_kind "$txt" "$tags" "$pfx" "$sfx")" == "human" ]] || continue
        (( cur && did )) && printf '%s\n' "$sess$tab$n$tab$c_ts$tab$c_head"
        n=$(( n + 1 )); cur=1; did=0; c_ts="$ts"; c_head="$head" ;;
      A|G)
        (( cur )) && did=1 ;;
    esac
  done <<< "$entries"
  (( cur && did )) && printf '%s\n' "$sess$tab$n$tab$c_ts$tab$c_head"
  return 0
}

# @pure
# <세션> <기록 항목 줄들> <자동 입력 태그> <앞말> <뒷말> → 등록 줄들. 사람 턴마다 그 턴의 마지막 등록 하나(첫 사람 메시지 앞의
# 등록은 버린다). 번호는 scv_dreams_human_turns 와 같다.
scv_dreams_register_features() {
  local sess="${1:-}" entries="${2:-}" tags="${3:-}" pfx="${4:-}" sfx="${5:-}" tab=$'\t' line k rest txt
  local n=0 cur=0 reg=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    k="${line%%"$tab"*}"
    case "$k" in
      U)
        rest="${line#U"$tab"}"; rest="${rest#*"$tab"}"; txt="${rest#*"$tab"}"
        [[ "$(scv_mp_prompt_kind "$txt" "$tags" "$pfx" "$sfx")" == "human" ]] || continue
        [[ -n "$reg" ]] && printf '%s\n' "$sess$tab$n$tab$reg"
        n=$(( n + 1 )); cur=1; reg="" ;;
      G)
        (( cur )) && reg="${line#G"$tab"}" ;;
    esac
  done <<< "$entries"
  [[ -n "$reg" ]] && printf '%s\n' "$sess$tab$n$tab$reg"
  return 0
}

# @deterministic
# <"<계획 이름><탭><archived_at 값>" 줄들> → 보관 줄들 "<YYYYMMDD><탭><계획 이름>"(날짜 · 이름 순). 값은 앞의 YYYY-MM-DD 만 본다
# (따옴표 · 뒤의 시각 무관). 날짜가 없거나 없는 날이면 그 계획은 뺀다.
scv_dreams_archive_dates() {
  local tab=$'\t' line slug v
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == *"$tab"* ]] || continue
    slug="${line%%"$tab"*}"; v="${line#*"$tab"}"; v="${v//\"/}"; v="${v//\'/}"; v="${v#"${v%%[![:space:]]*}"}"
    [[ "$v" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2}) ]] || continue
    [[ "$(scv_show_real_valid_day "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}")" == "1" ]] || continue
    printf '%s\t%s\n' "${BASH_REMATCH[1]}${BASH_REMATCH[2]}${BASH_REMATCH[3]}" "$slug"
  done <<< "${1:-}" | LC_ALL=C sort
}

# @pure
# <사람 턴 수> → 기간 단위 dekad(열흘 — 1~10 · 11~20 · 21~말일) | month. 100턴 이상이면 dekad — 표본이 작으면 한 달로 묶는다.
scv_dreams_unit() {
  local n="${1:-0}"
  [[ "$n" =~ ^[0-9]+$ ]] || n=0
  if (( n >= 100 )); then printf 'dekad'; else printf 'month'; fi
}

# @pure
# <YYYYMMDD> <dekad|month> → 기간 순번(정수). 다음 기간은 순번 + 1.
scv_dreams_period_ord() {
  local d="${1:-}" unit="${2:-month}" y m dd k
  [[ "$d" =~ ^([0-9]{4})([0-9]{2})([0-9]{2})$ ]] || { printf '0'; return 0; }
  y=$(( 10#${BASH_REMATCH[1]} )); m=$(( 10#${BASH_REMATCH[2]} )); dd=$(( 10#${BASH_REMATCH[3]} ))
  if [[ "$unit" == "dekad" ]]; then
    k=2; (( dd <= 20 )) && k=1; (( dd <= 10 )) && k=0
    printf '%s' "$(( (y * 12 + m - 1) * 3 + k ))"
  else
    printf '%s' "$(( y * 12 + m - 1 ))"
  fi
}

# @pure
# <기간 순번> <dekad|month> → "<시작 YYYYMMDD> <끝 YYYYMMDD>".
scv_dreams_period_range() {
  local o="${1:-0}" unit="${2:-month}" mo k y m from to last=31
  if [[ "$unit" == "dekad" ]]; then mo=$(( o / 3 )); k=$(( o % 3 )); else mo=$o; k=-1; fi
  y=$(( mo / 12 )); m=$(( mo % 12 + 1 ))
  while (( last > 28 )) && [[ "$(scv_show_real_valid_day "$y" "$m" "$last")" != "1" ]]; do last=$(( last - 1 )); done
  case "$k" in
    0) from=1; to=10 ;;
    1) from=11; to=20 ;;
    2) from=21; to=$last ;;
    *) from=1; to=$last ;;
  esac
  printf '%04d%02d%02d %04d%02d%02d' "$y" "$m" "$from" "$y" "$m" "$to"
}

# @pure
# <q> <a> → 비율 "n.n"(반올림, 소수 한 자리) | "-"(a 가 0).
scv_dreams_ratio() {
  local q="${1:-0}" a="${2:-0}" r
  (( a > 0 )) || { printf -- '-'; return 0; }
  r=$(( (q * 10 * 2 + a) / (a * 2) ))
  printf '%s.%s' "$(( r / 10 ))" "$(( r % 10 ))"
}

# @pure
# <사람 턴 줄들> <보관 줄들> <지역 오프셋(분)> <dekad|month> → 기간 줄들(첫 사람 턴의 기간부터 마지막 턴 · 보관의 기간까지, 빈 기간 포함).
# 턴은 사람 메시지의 지역 날짜로 기간에 든다. 보관은 첫 사람 턴 날 이후(그날 포함)의 것만 센다 — 기록이 없던 때의 보관은 질의와
# 짝지을 수 없다. 사람 턴이 없으면 빈 값.
scv_dreams_periods() {
  local turns="${1:-}" arch="${2:-}" off="${3:-0}" unit="${4:-month}" tab=$'\t' line ts rest d o lo="" hi="" first="" i r
  local -a q=() a=() tds=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    rest="${line#*"$tab"}"; rest="${rest#*"$tab"}"; ts="${rest%%"$tab"*}"
    d="$(scv_show_real_local_date "$ts" "$off")"; [[ -n "$d" ]] || continue
    tds+=("$d")
    if [[ -z "$first" ]] || (( 10#$d < 10#$first )); then first="$d"; fi
  done <<< "$turns"
  [[ -n "$first" ]] || return 0
  for d in "${tds[@]}"; do
    o="$(scv_dreams_period_ord "$d" "$unit")"
    q[o]=$(( ${q[o]:-0} + 1 ))
    if [[ -z "$lo" ]] || (( o < lo )); then lo=$o; fi
    if [[ -z "$hi" ]] || (( o > hi )); then hi=$o; fi
  done
  while IFS= read -r line || [[ -n "$line" ]]; do
    d="${line%%"$tab"*}"; [[ "$d" =~ ^[0-9]{8}$ ]] || continue
    (( 10#$d < 10#$first )) && continue
    o="$(scv_dreams_period_ord "$d" "$unit")"
    a[o]=$(( ${a[o]:-0} + 1 ))
    (( o > hi )) && hi=$o
  done <<< "$arch"
  for (( i = lo; i <= hi; i++ )); do
    r="$(scv_dreams_period_range "$i" "$unit")"
    printf '%s\t%s\t%s\t%s\t%s\n' "${r%% *}" "${r##* }" "${q[i]:-0}" "${a[i]:-0}" "$(scv_dreams_ratio "${q[i]:-0}" "${a[i]:-0}")"
  done
}

# @pure
# <사람 메시지 글> → 종료 0(붙여 넣은 글로 보임) | 1(사람이 쓴 요청). 근거는 사람이 쓴 요청에서만 고른다 — 붙여 넣은 글(답변 · 메일 ·
# 로그)을 근거로 고르면 판정자 조언이 엇나간다(2026-10-21 첫 실실행: 붙여 넣은 이전 답변이 근거로 뽑힘). 표시: 코드 울타리(```),
# pasted_content 태그, 이미지 표시([Image), 굵은 글씨 표시(**) 세 쌍 이상.
scv_dreams_pasted() {
  local s="${1:-}" t
  case "$s" in *'```'*|*'pasted_content'*|*'[Image'*) return 0 ;; esac
  t="${s//\*\*/}"
  (( ${#s} - ${#t} >= 12 ))
}

# @pure
# <사람 턴 줄들> <보관 줄들> <지역 오프셋(분)> → 분포 줄들. 계획마다 '보관까지 질의 수' = 바로 앞 보관 날 다음 날부터 그 보관 날까지의
# 사람 턴 수(첫 계획은 첫 사람 턴부터). 같은 날 보관된 계획 k 개는 그 구간을 나눠 갖는다(몫, 나머지는 이름 순으로 앞 계획부터 하나씩).
# 근거 턴은 구간에서 붙여 넣은 글이 아닌 가장 이른 턴(scv_dreams_pasted, 같은 날 묶음의 첫 계획에만, 모두 붙여 넣은 글이면 -). 첫 사람 턴 날보다 이른 보관은 뺀다. 마지막 줄 "#open<탭><n>" 은 마지막
# 보관 뒤의 사람 턴 수(진행 중).
scv_dreams_distribution() {
  local turns="${1:-}" arch="${2:-}" off="${3:-0}" tab=$'\t' line ts rest d id first="" g ng=0 nopen=0 i j k=0 base=0 rem=0 qn
  local -a tdate=() tid=() tts=() tpaste=() gdate=() gq=() gfirst=() gfts=() slugs=() sdate=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    id="${line%%"$tab"*}"; rest="${line#*"$tab"}"; id="$id/${rest%%"$tab"*}"
    rest="${rest#*"$tab"}"; ts="${rest%%"$tab"*}"
    d="$(scv_show_real_local_date "$ts" "$off")"; [[ -n "$d" ]] || continue
    if scv_dreams_pasted "${rest#*"$tab"}"; then tpaste+=(1); else tpaste+=(0); fi
    ts="${ts:0:19}"; ts="${ts//[!0-9]/}"            # 견주기용 숫자(YYYYMMDDHHMMSS)
    [[ "$ts" =~ ^[0-9]+$ ]] || ts=0
    tdate+=("$d"); tid+=("$id"); tts+=("$ts")
    if [[ -z "$first" ]] || (( 10#$d < 10#$first )); then first="$d"; fi
  done <<< "$turns"
  while IFS= read -r line || [[ -n "$line" ]]; do
    d="${line%%"$tab"*}"; [[ "$d" =~ ^[0-9]{8}$ && -n "$first" ]] || continue
    (( 10#$d < 10#$first )) && continue
    slugs+=("${line#*"$tab"}"); sdate+=("$d")
    if (( ng == 0 )) || [[ "${gdate[ng-1]}" != "$d" ]]; then gdate[ng]="$d"; gq[ng]=0; gfirst[ng]="-"; gfts[ng]=""; ng=$(( ng + 1 )); fi
  done <<< "$arch"
  for (( i = 0; i < ${#tdate[@]}; i++ )); do
    g=-1
    for (( j = 0; j < ng; j++ )); do
      if (( 10#${tdate[i]} <= 10#${gdate[j]} )); then g=$j; break; fi
    done
    if (( g < 0 )); then nopen=$(( nopen + 1 )); continue; fi
    gq[g]=$(( gq[g] + 1 ))
    (( tpaste[i] )) && continue
    if [[ -z "${gfts[g]}" ]] || (( 10#${tts[i]} < 10#${gfts[g]} )); then gfts[g]="${tts[i]}"; gfirst[g]="${tid[i]}"; fi
  done
  g=-1
  for (( i = 0; i < ${#slugs[@]}; i++ )); do
    if (( g < 0 )) || [[ "${gdate[g]}" != "${sdate[i]}" ]]; then
      g=$(( g + 1 )); k=0; j=0
      for d in "${sdate[@]}"; do [[ "$d" == "${gdate[g]}" ]] && j=$(( j + 1 )); done
      base=$(( gq[g] / j )); rem=$(( gq[g] % j ))
    fi
    qn=$base; (( k < rem )) && qn=$(( qn + 1 ))
    if (( k == 0 )); then id="${gfirst[g]}"; else id="-"; fi
    printf '%s\t%s\t%s\t%s\n' "${slugs[i]}" "${sdate[i]}" "$qn" "$id"
    k=$(( k + 1 ))
  done
  printf '#open\t%s\n' "$nopen"
}

# @pure
# <등록 줄들> <사람 턴 줄들> <분포 줄들> → 개선점 줄들(문턱은 protocols/dreams.md 의 '개선점 규칙'):
#   finish · depth — 등록 3건 이상에서 그 항목을 사람이 직접 말한(msg) 비율이 절반 미만. a=msg 수, b=등록 수, 근거=msg 가 아닌 마지막 3턴
#   correction    — 사람 턴 5개 이상에서 고쳐 달라는 턴(세션의 첫 턴 제외, scv_show_real_is_correction)이 20% 이상. a=정정 턴, b=사람 턴,
#                   근거=마지막 정정 3개의 바로 앞 턴(고치게 된 원래 요청)
#   plan          — 계획 3개 이상에서 보관까지 질의가 가장 많은 계획이 중앙값의 2배 이상이고 10번 이상. a=그 질의 수, b=중앙값,
#                   덧붙임=계획 이름, 근거=그 구간의 첫 턴
scv_dreams_tips() {
  local regs="${1:-}" turns="${2:-}" dist="${3:-}" tab=$'\t' line rest st sess n prev_sess="" prev_id="" key col
  local nr=0 t=0 c=0 i np=0 max=-1 maxslug="" maxid="" med q tmp
  local -a ids=() cids=() qs=()
  for key in finish depth; do
    col=3; [[ "$key" == "finish" ]] && col=4
    nr=0; n=0; ids=()
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -n "$line" ]] || continue
      sess="${line%%"$tab"*}"; rest="${line#*"$tab"}"; i="${rest%%"$tab"*}"; rest="${rest#*"$tab"}"
      rest="${rest#*"$tab"}"                       # 시각 다음
      rest="${rest#*"$tab"}"                       # goal 다음
      st="${rest%%"$tab"*}"; rest="${rest#*"$tab"}" # depth
      (( col == 4 )) && st="${rest%%"$tab"*}"       # finish
      nr=$(( nr + 1 ))
      if [[ "$st" == "msg" ]]; then n=$(( n + 1 )); else ids+=("$sess/$i"); fi
    done <<< "$regs"
    if (( nr >= 3 && n * 2 < nr )); then
      tmp="${ids[*]:$(( ${#ids[@]} > 3 ? ${#ids[@]} - 3 : 0 ))}"
      printf '%s\t%s\t%s\t\t%s\n' "$key" "$n" "$nr" "$tmp"
    fi
  done
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    sess="${line%%"$tab"*}"; rest="${line#*"$tab"}"; i="${rest%%"$tab"*}"; rest="${rest#*"$tab"}"; rest="${rest#*"$tab"}"
    t=$(( t + 1 ))
    if [[ "$sess" == "$prev_sess" && "$(scv_show_real_is_correction "$rest")" == "1" ]]; then
      c=$(( c + 1 )); cids+=("$prev_id")
    fi
    prev_sess="$sess"; prev_id="$sess/$i"
  done <<< "$turns"
  if (( t >= 5 && c > 0 && c * 5 >= t )); then
    tmp="${cids[*]:$(( ${#cids[@]} > 3 ? ${#cids[@]} - 3 : 0 ))}"
    printf 'correction\t%s\t%s\t\t%s\n' "$c" "$t" "$tmp"
  fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" && "$line" != "#"* ]] || continue
    rest="${line#*"$tab"}"; rest="${rest#*"$tab"}"; q="${rest%%"$tab"*}"
    [[ "$q" =~ ^[0-9]+$ ]] || continue
    qs[np]=$q; np=$(( np + 1 ))
    if (( q > max )); then max=$q; maxslug="${line%%"$tab"*}"; maxid="${rest#*"$tab"}"; fi
  done <<< "$dist"
  if (( np >= 3 )); then
    for (( i = 1; i < np; i++ )); do        # 삽입 정렬 — 계획 수는 많아야 수백
      tmp=${qs[i]}; n=$(( i - 1 ))
      while (( n >= 0 )) && (( qs[n] > tmp )); do qs[n+1]=${qs[n]}; n=$(( n - 1 )); done
      qs[n+1]=$tmp
    done
    if (( np % 2 )); then med=${qs[np/2]}; else med=$(( (qs[np/2-1] + qs[np/2]) / 2 )); fi
    if (( max >= 10 && max >= med * 2 )); then
      [[ "$maxid" == "-" ]] && maxid=""
      printf 'plan\t%s\t%s\t%s\t%s\n' "$max" "$med" "$maxslug" "$maxid"
    fi
  fi
  return 0
}

# @deterministic
# <글> [<최대 글자 수, 기본 160>] → 가린 한 줄 발췌. 경로(/… · ~/… · C:\…) → [경로], 메일 → [메일], 세션 id · UUID → [id],
# 열쇠 모양 값(password · token · secret · api key 뒤의 값, Bearer, 알려진 접두 토큰, 32자 이상 무작위 문자열) → [REDACTED].
# 글자 단위로 자른다(jq). 효과부는 이 뒤에 저널 가림 필터(journal-append.sh --redact-only)를 한 번 더 거친다.
scv_dreams_mask() {
  jq -nr --arg s "${1:-}" --argjson n "${2:-160}" '
    $s | split("\t") | join(" ") | split("\r") | join(" ") | split("\n") | join(" ")
    | gsub("[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)*\\.[A-Za-z]{2,}"; "[메일]")
    | gsub("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"; "[id]")
    | gsub("session_[A-Za-z0-9]+"; "[id]")
    | gsub("(?\u003ck\u003e(?i:password|passwd|pwd|secret|token|api[_-]?key|access[_-]?token)[\"\u0027]?\\s*[:=]\\s*)[^\\s]+"; "\(.k)[REDACTED]")
    | gsub("(?i:bearer)\\s+[A-Za-z0-9._~+/=-]+"; "Bearer [REDACTED]")
    | gsub("(sk|pk|ghp|gho|ghs|github_pat|xox[abprs]|AKIA)[-_A-Za-z0-9]{8,}"; "[REDACTED]")
    | gsub("[A-Za-z0-9_+=-]{32,}"; "[REDACTED]")
    | gsub("[A-Za-z]:\\\\[^\\s]+"; "[경로]")
    | gsub("(?\u003cp\u003e^|[^A-Za-z0-9._-])~?/[A-Za-z0-9._@~-][^\\s\"\u0027`)]*"; "\(.p)[경로]")
    | if (.[$n:] | length) != 0 then .[0:$n] + "…" else . end' 2>/dev/null
}

# @deterministic
# <개선점 줄들> <사람 턴 줄들> → 근거 줄들 "<개선점 번호><탭><가린 발췌>"(개선점마다 근거 턴 id 순서대로, 많아야 3개,
# 붙여 넣은 글로 보이는 턴은 뺀다 — scv_dreams_pasted).
scv_dreams_evidence() {
  local tips="${1:-}" turns="${2:-}" tab=$'\t' line rest ids id k=0 tl head x
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    k=$(( k + 1 ))
    ids="${line##*"$tab"}"
    for id in $ids; do
      head=""
      while IFS= read -r tl || [[ -n "$tl" ]]; do
        [[ "$tl" == "${id%%/*}$tab${id#*/}$tab"* ]] || continue
        rest="${tl#*"$tab"}"; rest="${rest#*"$tab"}"; head="${rest#*"$tab"}"; break
      done <<< "$turns"
      [[ -n "$head" ]] || continue
      scv_dreams_pasted "$head" && continue
      x="$(scv_dreams_mask "$head" 160)"
      [[ -n "$x" ]] && printf '%s\t%s\n' "$k" "$x"
    done
  done <<< "$tips"
  return 0
}

# @pure
# <개선점 줄 하나> → 사람이 읽는 한 문장(보고서 · 요약 · 판정자 질문이 같은 문장을 쓴다).
scv_dreams_tip_text() {
  local tab=$'\t' kind a b x rest pct=0
  kind="${1%%"$tab"*}"; rest="${1#*"$tab"}"; a="${rest%%"$tab"*}"; rest="${rest#*"$tab"}"; b="${rest%%"$tab"*}"
  rest="${rest#*"$tab"}"; x="${rest%%"$tab"*}"
  [[ "$a" =~ ^[0-9]+$ && "$b" =~ ^[0-9]+$ ]] || { a=0; b=0; }
  (( b > 0 )) && pct=$(( (a * 100 + b / 2) / b ))
  case "$kind" in
    finish)     printf '요청에 완료 기준(무엇이 되면 끝인지)을 직접 말한 비율 %s/%s(%s%%)' "$a" "$b" "$pct" ;;
    depth)      printf '요청에 깊이(어디까지 할지)를 직접 말한 비율 %s/%s(%s%%)' "$a" "$b" "$pct" ;;
    correction) printf '고쳐 달라는 턴 %s/%s(%s%%) — 첫 요청에 빠진 것이 뒤에 정정으로 왔다' "$a" "$b" "$pct" ;;
    plan)       printf '보관까지 질의가 많았던 계획 %s — %s번(중앙값 %s번)' "$x" "$a" "$b" ;;
    *)          printf '%s' "$kind" ;;
  esac
}

# @pure
# <개선점 줄 하나> → 판정자에게 권할 가이드 규칙 이름(요구 항목 id).
scv_dreams_tip_rule() {
  case "${1%%$'\t'*}" in
    finish|plan) printf 'finish' ;;
    depth)       printf 'depth' ;;
    *)           printf 'goal' ;;
  esac
}

# @pure
# <개선점 줄 하나> <그 개선점의 가린 발췌들(줄마다 하나)> → 판정자에게 보낼 글. 판정자는 발췌 · 숫자만 본다(경로 · 세션 id 없음).
# 답은 JSON 객체 하나 {"rule": …, "advice": …, "example": …}.
scv_dreams_judge_prompt() {
  local tip="${1:-}" ex="${2:-}" line i=0
  [[ -n "$tip" ]] || return 0
  printf '%s\n\n' "You coach a person on writing better prompts for an AI coding assistant. Answer with one JSON object only."
  printf '%s\n\n' "Finding from their recent sessions: $(scv_dreams_tip_text "$tip")."
  printf '%s\n\n' "Suggested prompting-guide rule: $(scv_dreams_tip_rule "$tip") (name the rule from the model's official prompting guide that fits best)."
  printf '%s\n' "Excerpts of the person's own requests (redacted):"
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    i=$(( i + 1 )); printf '%s. %s\n' "$i" "$line"
  done <<< "$ex"
  (( i )) || printf '%s\n' "(none)"
  printf '\n%s\n' "Reply with exactly one JSON object: {\"rule\": \"GUIDE RULE NAME\", \"advice\": \"ONE OR TWO SENTENCES: WHAT TO ADD NEXT TIME\", \"example\": \"ONE REWRITTEN REQUEST\"}. Write advice and example in the same language as the excerpts. Do not include paths, emails, names, or ids."
}

# @deterministic
# <판정자 답 글> → "<규칙><탭><조언><탭><예시>" | 빈 값(깨진 답). 답 글에서 rule · advice 가 빈 글이 아닌 첫 JSON 객체를 쓴다.
scv_dreams_judge_parse() {
  [[ -n "${1:-}" ]] || return 0
  jq -nr --arg s "$1" '
    def sp: tostring | split("\t") | join(" ") | split("\r") | join(" ") | split("\n") | join(" ");
    [$s | scan("\\{[^{}]*\\}") | (fromjson? // empty) | select(type == "object")
     | select((.rule | type) == "string" and (.advice | type) == "string")
     | select((.rule | test("\\S")) and (.advice | test("\\S")))] | first // empty
    | "\(.rule | sp)\t\(.advice | sp)\t\(.example // "" | sp)"' 2>/dev/null
  return 0
}

# @pure
# <짧은 HTML 조각 — « » 로 꺾쇠를 적음> → 꺾쇠로 바꾼 조각.
scv_dreams_tag() {
  local s="${1:-}" lt=$'\x3c' gt=$'\x3e'
  s="${s//«/$lt}"; s="${s//»/$gt}"
  printf '%s' "$s"
}

# @pure
# <글> → HTML 에 넣을 수 있게 & · 꺾쇠 · 따옴표 · « » 를 바꾼 글(짧은 글에만 쓴다). « » 도 바꾸는 것은 scv_dreams_tag 가 사람 글 속의
# « » 를 꺾쇠로 만들지 않게 하려는 것이다.
scv_dreams_esc() {
  local s="${1:-}" lt=$'\x3c' gt=$'\x3e' ps=0
  # bash 5.2 의 patsub_replacement 는 바꿀 글 속 & 를 찾은 글로 바꾼다 — 잠시 끄고 되돌린다(3.2 에는 없는 옵션).
  shopt -q patsub_replacement 2>/dev/null && { ps=1; shopt -u patsub_replacement; }
  s="${s//&/&amp;}"; s="${s//$lt/&lt;}"; s="${s//$gt/&gt;}"; s="${s//\"/&quot;}"; s="${s//«/&laquo;}"; s="${s//»/&raquo;}"
  (( ps )) && shopt -s patsub_replacement
  printf '%s' "$s"
}

# @pure
# <YYYYMMDD> → "YYYY-MM-DD".
scv_dreams_day() {
  local d="${1:-}"
  [[ "$d" =~ ^[0-9]{8}$ ]] || { printf '%s' "$d"; return 0; }
  printf '%s-%s-%s' "${d:0:4}" "${d:4:2}" "${d:6:2}"
}

# @pure
# <기간 줄들> → "<질의 합><탭><보관 합>"(마지막 보관이 있는 기간까지의 질의 — 비율의 분자 · 분모).
scv_dreams_totals() {
  local tab=$'\t' line rest q a sq=0 sa=0 pend=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    rest="${line#*"$tab"}"; rest="${rest#*"$tab"}"; q="${rest%%"$tab"*}"; rest="${rest#*"$tab"}"; a="${rest%%"$tab"*}"
    pend=$(( pend + q ))
    if (( a > 0 )); then sq=$(( sq + pend )); sa=$(( sa + a )); pend=0; fi
  done <<< "${1:-}"
  printf '%s\t%s' "$sq" "$sa"
}

# @pure
# <기간 줄들> <개선점 줄들> <보고서 경로(저장소 기준)> <사람 턴 수> → 다음 턴에 싣는 한 줄 요약.
scv_dreams_render_summary() {
  local periods="${1:-}" tips="${2:-}" rel="${3:-}" nt="${4:-0}" tot sq sa first tip=""
  tot="$(scv_dreams_totals "$periods")"; sq="${tot%%$'\t'*}"; sa="${tot#*$'\t'}"
  first="${tips%%$'\n'*}"; [[ -n "$first" ]] && tip=" · 개선점: $(scv_dreams_tip_text "$first")"
  if (( sa > 0 )); then
    printf '[SCV 드림] 계획 하나에 사람 질의 %s번(보관 %s개 · 질의 %s번)%s · 보고서 %s' "$(scv_dreams_ratio "$sq" "$sa")" "$sa" "$sq" "$tip" "$rel"
  else
    printf '[SCV 드림] 아직 셀 것이 없음(보관된 계획 0개 · 사람 질의 %s번)%s · 보고서 %s' "$nt" "$tip" "$rel"
  fi
}

# @pure
# <제목> <"<라벨><탭><값>" 줄들> <막대 색> → 막대 차트 SVG 한 덩이(값 0 은 높이 0, 막대가 16개를 넘으면 아래 라벨은 생략).
scv_dreams_svg_bars() {
  local title="${1:-}" rows="${2:-}" color="${3:-#7aa2f7}" tab=$'\t' line lbl v n=0 max=0 i w=640 h=220 bw x y bh
  local -a ls=() vs=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    lbl="${line%%"$tab"*}"; v="${line#*"$tab"}"; [[ "$v" =~ ^[0-9]+$ ]] || v=0
    ls+=("$lbl"); vs+=("$v"); n=$(( n + 1 )); (( v > max )) && max=$v
  done <<< "$rows"
  (( n )) || return 0
  (( max )) || max=1
  bw=$(( (w - 40) / n )); (( bw > 80 )) && bw=80; (( bw < 6 )) && bw=6
  scv_dreams_tag "«svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 $w $h\" role=\"img\" aria-label=\"$(scv_dreams_esc "$title")\"»"
  for (( i = 0; i < n; i++ )); do
    bh=$(( vs[i] * 150 / max )); x=$(( 30 + i * bw )); y=$(( 180 - bh ))
    scv_dreams_tag "«rect x=\"$x\" y=\"$y\" width=\"$(( bw - 4 ))\" height=\"$bh\" rx=\"3\" fill=\"$color\"»«title»$(scv_dreams_esc "${ls[i]}"): ${vs[i]}«/title»«/rect»"
    scv_dreams_tag "«text x=\"$(( x + (bw - 4) / 2 ))\" y=\"$(( y - 4 ))\" text-anchor=\"middle\" class=\"v\"»${vs[i]}«/text»"
    (( n <= 16 )) && scv_dreams_tag "«text x=\"$(( x + (bw - 4) / 2 ))\" y=\"198\" text-anchor=\"middle\" class=\"l\"»$(scv_dreams_esc "${ls[i]:0:12}")«/text»"
  done
  scv_dreams_tag "«line x1=\"26\" y1=\"180\" x2=\"$(( w - 10 ))\" y2=\"180\" class=\"axis\"/»«/svg»"
  printf '\n'
}

# @pure
# <기간 줄들> <분포 줄들> <개선점 줄들> <근거 줄들> <조언 줄들> <만든 시각 글> <기간 단위> <사람 턴 수> <세션 수> <등록 수>
# → 한 파일로 된 HTML(내장 SVG · 외부 자원 없음, scv 어두운 화면).
scv_dreams_render_html() {
  local periods="${1:-}" dist="${2:-}" tips="${3:-}" evid="${4:-}" adv="${5:-}" stamp="${6:-}" unit="${7:-month}"
  local nt="${8:-0}" ns="${9:-0}" nr="${10:-0}" tab=$'\t' line rest f t q a r k=0 e ad st rule tx ex tot sq sa bars="" dbars="" open=0 ul
  ul="달"; [[ "$unit" == "dekad" ]] && ul="열흘"
  tot="$(scv_dreams_totals "$periods")"; sq="${tot%%"$tab"*}"; sa="${tot#*"$tab"}"
  scv_dreams_tag '«!doctype html»«html lang="ko"»«head»«meta charset="utf-8"»«meta name="viewport" content="width=device-width, initial-scale=1"»'
  printf '\n'
  scv_dreams_tag "«title»SCV 드림«/title»«style»"
  printf '%s\n' ':root{--bg:#171922;--panel:#1e1e1e;--line:#3a3d4a;--text:#e7e9f0;--muted:#9096a8;--accent:#7aa2f7;--warn:#e0af68}' \
    'body{margin:0;background:var(--bg);color:var(--text);font:15px/1.6 -apple-system,"Segoe UI",sans-serif}' \
    'main{max-width:880px;margin:0 auto;padding:24px 16px}h1{font-size:22px;margin:0 0 4px}h2{font-size:17px;margin:28px 0 8px}' \
    '.muted{color:var(--muted)}.card{background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:12px 16px;margin:10px 0}' \
    'table{border-collapse:collapse;width:100%}th,td{border-bottom:1px solid var(--line);padding:6px 8px;text-align:left}td.n{text-align:right}' \
    'svg{width:100%;height:auto;margin:8px 0}svg .v{fill:var(--text);font-size:11px}svg .l{fill:var(--muted);font-size:10px}svg .axis{stroke:var(--line)}' \
    '.ex{border-left:3px solid var(--line);padding-left:10px;margin:6px 0;color:var(--muted)}.adv{border-left:3px solid var(--accent);padding-left:10px;margin:8px 0}' \
    '.none{color:var(--warn)}'
  scv_dreams_tag "«/style»«/head»«body»«main»"
  printf '\n'
  scv_dreams_tag "«h1»SCV 드림 — 프롬프트 코치«/h1»«p class=\"muted\"»$(scv_dreams_esc "$stamp") · 세션 ${ns}개 · 사람 질의 ${nt}번 · 등록 ${nr}건 · 기간 단위: ${ul}«/p»"
  printf '\n'
  if (( sa > 0 )); then
    scv_dreams_tag "«div class=\"card\"»계획 하나에 사람 질의 «b»$(scv_dreams_ratio "$sq" "$sa")번«/b»(보관 ${sa}개 · 그때까지 질의 ${sq}번)«/div»"
  else
    scv_dreams_tag "«div class=\"card\"»아직 셀 것이 없음 — 기록이 있는 동안 보관된 계획이 0개다. 지금까지 사람 질의 ${nt}번.«/div»"
  fi
  printf '\n'
  scv_dreams_tag "«h2»기간별 질의 ÷ 보관«/h2»"
  printf '\n'
  if [[ -n "$periods" ]]; then
    scv_dreams_tag "«table»«tr»«th»기간«/th»«th»사람 질의«/th»«th»보관«/th»«th»비율«/th»«/tr»"
    printf '\n'
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -n "$line" ]] || continue
      f="${line%%"$tab"*}"; rest="${line#*"$tab"}"; t="${rest%%"$tab"*}"; rest="${rest#*"$tab"}"
      q="${rest%%"$tab"*}"; rest="${rest#*"$tab"}"; a="${rest%%"$tab"*}"; r="${rest#*"$tab"}"
      scv_dreams_tag "«tr»«td»$(scv_dreams_day "$f")..$(scv_dreams_day "$t")«/td»«td class=\"n\"»${q}«/td»«td class=\"n\"»${a}«/td»«td class=\"n\"»${r}«/td»«/tr»"
      printf '\n'
      bars+="${f:4:2}/${f:6:2}$tab$q"$'\n'
    done <<< "$periods"
    scv_dreams_tag "«/table»"
    printf '\n'
    scv_dreams_svg_bars "기간별 사람 질의" "$bars" "#7aa2f7"
  else
    scv_dreams_tag "«p class=\"muted\"»아직 셀 것이 없음 — 세션 기록에서 사람 질의를 찾지 못했다.«/p»"
    printf '\n'
  fi
  scv_dreams_tag "«h2»계획마다 보관까지 걸린 질의«/h2»"
  printf '\n'
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    if [[ "$line" == "#open$tab"* ]]; then open="${line#*"$tab"}"; continue; fi
    rest="${line#*"$tab"}"; rest="${rest#*"$tab"}"
    dbars+="${line%%"$tab"*}$tab${rest%%"$tab"*}"$'\n'
  done <<< "$dist"
  if [[ -n "$dbars" ]]; then
    scv_dreams_svg_bars "계획마다 보관까지 질의" "$dbars" "#9ece6a"
    scv_dreams_tag "«table»«tr»«th»계획«/th»«th»질의«/th»«/tr»"
    printf '\n'
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -n "$line" ]] || continue
      scv_dreams_tag "«tr»«td»$(scv_dreams_esc "${line%%"$tab"*}")«/td»«td class=\"n\"»${line#*"$tab"}«/td»«/tr»"
      printf '\n'
    done <<< "$dbars"
    scv_dreams_tag "«/table»«p class=\"muted\"»마지막 보관 뒤(진행 중) 질의 ${open}번«/p»"
  else
    scv_dreams_tag "«p class=\"muted\"»아직 셀 것이 없음 — 기록이 있는 동안 보관된 계획이 없다.«/p»"
  fi
  printf '\n'
  scv_dreams_tag "«h2»개선점«/h2»"
  printf '\n'
  [[ -n "$tips" ]] || { scv_dreams_tag "«p class=\"muted\"»규칙에 걸린 개선점이 없다.«/p»"; printf '\n'; }
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    k=$(( k + 1 ))
    scv_dreams_tag "«div class=\"card\"»«b»$k. $(scv_dreams_esc "$(scv_dreams_tip_text "$line")")«/b»"
    printf '\n'
    while IFS= read -r e || [[ -n "$e" ]]; do
      [[ "$e" == "$k$tab"* ]] || continue
      scv_dreams_tag "«div class=\"ex\"»근거: $(scv_dreams_esc "${e#*"$tab"}")«/div»"
      printf '\n'
    done <<< "$evid"
    ad="none${tab}판정자 결과 없음"
    while IFS= read -r e || [[ -n "$e" ]]; do
      [[ "$e" == "$k$tab"* ]] && { ad="${e#*"$tab"}"; break; }
    done <<< "$adv"
    st="${ad%%"$tab"*}"; rest="${ad#*"$tab"}"
    if [[ "$st" == "ok" ]]; then
      rule="${rest%%"$tab"*}"; rest="${rest#*"$tab"}"; tx="${rest%%"$tab"*}"; ex=""; [[ "$rest" == *"$tab"* ]] && ex="${rest#*"$tab"}"
      scv_dreams_tag "«div class=\"adv\"»조언(가이드 규칙: $(scv_dreams_esc "$rule")): $(scv_dreams_esc "$tx")"
      [[ -n "$ex" ]] && scv_dreams_tag "«br»다음에 이렇게 쓰면: «i»$(scv_dreams_esc "$ex")«/i»"
      scv_dreams_tag "«/div»"
    else
      scv_dreams_tag "«div class=\"adv none\"»조언 없음($(scv_dreams_esc "$rest"))«/div»"
    fi
    scv_dreams_tag "«/div»"
    printf '\n'
  done <<< "$tips"
  scv_dreams_tag "«p class=\"muted\"»드림은 입력(세션 기록 · 보관 기록)을 바꾸지 않는다. 발췌는 경로 · 메일 · 비밀값 · id 를 가린 짧은 글이다. 규칙: protocols/dreams.md«/p»«/main»«/body»«/html»"
  printf '\n'
}
