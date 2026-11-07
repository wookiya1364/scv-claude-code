#!/usr/bin/env bash
# lib/finish-report.sh — 끝 보고 확인 범위 · 근거 목록의 순수부 (0.82.0+, 계획 finish-report-evidence).
# 본문: core/contracts/finish-report.md. 효과(원본 읽기 · 막기 출력 · 근거 목록 파일 쓰기)는 template/hooks/on-stop.sh,
# 매 턴 안내 한 줄은 template/hooks/on-user-prompt.sh.
#
#   scv_turn_group <원본 줄들>                       → 이번 턴 사건 줄들(T 도구 호출+결과 · N 알림 끝 코드)
#   scv_evidence_build <사건 줄들>                   → 근거 목록 줄들 "종류\x1f쉬운 이름\x1f결과\x1f대상"
#   scv_evidence_test_first <근거 목록>              → 바꾼 뒤 실패를 못 본 시험 파일 이름들(줄마다)
#   scv_finish_needed <근거 목록>                    → none | short | full
#   scv_finish_scan <끝 답> <언어>                   → "칸\x1f내용" 줄들(verified · unverified · decided · scope)
#   scv_finish_check <칸 줄들> <근거 목록> <못 본 시험> <필요> → "문제\x1f칸 · 이름" 줄들(missing · noreason · unbacked · undisclosed)
#   scv_finish_note <문제 줄들> <언어>               → 교정 문구 한 줄 | 빈 값
#   scv_finish_rule_line <언어>                      → 매 턴 안내 한 줄
#   scv_evidence_render <근거 목록> <언어>           → 근거 목록 기록용 불릿 줄들
#
# 종류: read · edit · run · test · fetch · ask · scv · other. 결과: ok · fail · none.
# 도구 이름이 아니라 입력 모양으로 종류를 가린다(command → run, file_path + 고칠 글 → edit …) — 코어에 호스트 이름 · 도구 이름을
# 박지 않는다. 원본에서 도구 호출을 못 찾으면(다른 모양의 원본) 근거 목록이 비고, 이 검사는 꺼진다.
# 꺾쇠 글자는 쓰지 않는다 — 순수성 검사가 리다이렉션으로 본다(jq 안에서는 < · > 로 쓴다).

# @deterministic
# 역할: 원본 줄들에서 마지막 사람 글 뒤의 이번 턴 사건(도구 호출과 그 결과 · 알림 끝 코드)을 꺼낸다 — 알림 · 안내로 열린 턴은 앞 사람 턴에 묶는다
# 종류: 꺼내기
# 예: $'{"type":"user","message":{"content":"고쳐 줘"}}\n{"type":"assistant","message":{"content":[{"type":"tool_use","id":"a","name":"X","input":{"command":"ls","description":"목록 보기"}}]}}\n{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"a","content":"ok"}]}}' → $'T\x1frun\x1f목록 보기\x1fls\x1f0\x1f0\x1f'
# 예: "" → ""
# 예: "not json" → ""
# <원본 줄들(JSON 한 줄씩)> → 도구 호출마다 "T\x1f종류\x1f이름\x1f대상\x1f실패 0|1\x1f실패 표시 0|1\x1f결과 없음이면 none".
# 실패 표시: 결과 글에 ✖ · FAIL · not ok · N failed 가 있음. 뒤에서 돌린 명령은 나중 알림의 끝 코드가 0 이 아니거나, 그 출력 파일을
# 나중에 읽은 명령의 결과에 실패 표시가 있으면 실패 표시를 단다. 사람 글이 창 안에 없으면(긴 턴) 창 전체가 이번 턴이다.
scv_turn_group() {
  local raw="${1:-}"
  [[ -n "$raw" ]] || return 0
  printf '%s\n' "$raw" | jq -Rrn '
    def txt: if (.message.content|type) == "string" then .message.content
             elif (.message.content|type) == "array" then ([.message.content[]? | select(.type? == "text") | .text] | join("\n"))
             else "" end;
    def isresult: (.message.content|type) == "array" and any(.message.content[]?; .type? == "tool_result");
    def human: .type? == "user" and (.isMeta? != true) and (.sourceToolUseID? == null) and (isresult | not)
               and (txt != "") and ((txt | test("^\\s*\u003c(task-notification|system-reminder)")) | not);
    def kind($i): if ($i.command? != null) then "run"
      elif (($i.file_path? // $i.notebook_path?) != null) and (($i.old_string? // $i.new_string? // $i.content? // $i.edits? // $i.new_source?) != null) then "edit"
      elif (($i.file_path? // $i.path? // $i.pattern?) != null) then "read"
      elif (($i.url? // $i.query?) != null) then "fetch"
      elif ($i.questions? != null) then "ask"
      elif ($i.skill? != null) then "scv"
      elif (($i.items? // $i.advance? // $i.done? // $i.recap?) != null) then "app"
      else "other" end;
    def flat: tostring | gsub("[\u0000-\u001f]"; " ");
    [inputs | fromjson? | select(type == "object")] as $all
    | ([range(0; $all | length) | select($all[.] | human)] | last) as $h
    | (if $h == null then $all else $all[($h + 1):] end) as $t
    | ([$t[] | select(isresult) | .message.content[]? | select(.type? == "tool_result")
        | (.content | if type == "array" then (map(.text? // "") | join(" ")) else (. // "" | tostring) end) as $c
        | {key: (.tool_use_id // ""), value: {
            err: (if (.is_error == true) or ($c | test("^\\s*(Exit code|\u003cerror\u003e)")) then 1 else 0 end),
            mark: (if ($c | test("(^|\n)\\s*(✖|✗|not ok\\b|FAILED\\b|FAIL\\b(?!=0))|\\b[1-9][0-9]* (failed|failing)\\b")) then 1 else 0 end),
            bg: (($c | capture("running in background with ID: (?\u003cid\u003e[A-Za-z0-9_-]+)\\. Output is being written to: (?\u003cp\u003e\\S+)")) // {id: "", p: ""})
          }}]
       | from_entries) as $res
    | [$t[]
       | if .type? == "assistant" then
           (.message.content[]? | select(.type? == "tool_use")
            | (.input // {}) as $i | kind($i) as $k | select($k != "app")
            | ($res[.id // ""] // {err: 0, mark: 0, bg: {id: "", p: ""}, none: 1}) as $r
            | (if $k == "run" then ($i.command | flat) elif $k == "edit" or $k == "read" then (($i.file_path // $i.notebook_path // $i.path // $i.pattern) | flat)
               elif $k == "fetch" then (($i.url // $i.query) | flat) elif $k == "scv" then ($i.skill | flat) else "" end) as $tg
            | (if $k == "run" then (($i.description // "") | flat) else "" end) as $d
            | (if $d != "" then $d elif $k == "edit" or $k == "read" then ($tg | split("/") | last)
               elif $k == "ask" then "ask" elif $k == "other" then (.name // "" | flat) else $tg end) as $nm
            | {e: "T", k: $k, nm: ($nm | .[0:80]), tg: ($tg | .[0:400]), err: $r.err, mark: $r.mark,
               bg: $r.bg.id, bp: $r.bg.p, none: (if $r.none == 1 then "none" else "" end)})
         elif (.type? == "user") and (isresult | not) then
           (txt | gsub("\n"; " ") | [scan("\u003ctask-id\u003e(?\u003cid\u003e[A-Za-z0-9_-]+)\u003c/task-id\u003e.*?exit code (?\u003cc\u003e[0-9]+)")]
            | .[] | {e: "N", id: .[0], c: .[1]})
         else empty end] as $ev
    # 뒤에서 돌린 명령: 나중 알림의 끝 코드가 0 이 아니거나, 그 출력 파일을 나중에 읽은 명령의 출력에 실패 표시가 있으면 실패 표시를 단다.
    | [range(0; $ev | length) as $j | $ev[$j]
       | if .e == "T" and .bg != "" then
           .bg as $b | .bp as $p
           | (any($ev[($j + 1):][]; (.e == "N" and .id == $b and .c != "0")
                 or (.e == "T" and .k == "run" and $p != "" and (.tg | contains($p)) and .mark == 1))) as $lf
           | .mark = (if $lf then 1 else .mark end)
         else . end]
    | .[] | select(.e == "T")
    | ["T", .k, .nm, .tg, (.err | tostring), (.mark | tostring), .none] | join("\u001f")' 2>/dev/null || true
}

# @pure
# 역할: 사건 줄들을 근거 목록으로 바꾼다 — 실행을 시험 · SCV 기록 · 실행으로 가르고, 실패는 끝 코드 · 출력 표시 · 뒤 실행 알림으로 정한다
# 종류: 변환
# 예: $'T\x1frun\x1f시험 실행\x1fbash tests/test-a.sh | tail\x1f0\x1f1\x1f\x1f' → $'test\x1f시험 실행\x1ffail\x1fbash tests/test-a.sh | tail'
# 예: $'T\x1frun\x1f읽기\x1fgrep -n x tests/test-a.sh\x1f0\x1f0\x1f\x1f' → $'run\x1f읽기\x1fok\x1fgrep -n x tests/test-a.sh'
# 예: "" → ""
# <사건 줄들> → 근거 목록 줄들 "종류\x1f쉬운 이름\x1f결과\x1f대상". 시험 = 실행기(bash · pytest · npm …)로 시작하는 토막이 시험 대상을
# 가리킬 때만(grep · sed 로 시험 파일을 읽는 것은 실행). 시험이 아닌 실행의 '실패 표시'는 보지 않는다.
scv_evidence_build() {
  local ev="${1:-}" us=$'\x1f' nl=$'\n' line tag k nm tg err mark none res seg segs out=""
  local re_scv='(journal-append\.sh|model-prompting\.sh|help-state\.sh|scripts/help\.sh|scripts/work\.sh|scripts/promote-helper\.sh)'
  local re_run='^(bash|sh|zsh|python3?|pytest|npx|pnpm|npm|yarn|go|cargo|node|vitest|jest|playwright|time|env)([[:space:]]|$)|^\./'
  local re_tgt='(test-[A-Za-z0-9_-]+\.sh|tests?/[A-Za-z0-9_./-]+|pytest|vitest|jest|playwright test|go test|cargo test|(npm|pnpm|yarn)( run)? test)'
  [[ -n "$ev" ]] || return 0
  while IFS= read -r line; do
    [[ "$line" == T"$us"* ]] || continue
    IFS="$us" read -r tag k nm tg err mark none <<< "$line"
    if [[ "$k" == run ]]; then
      if [[ "$tg" =~ $re_scv ]]; then k=scv
      else
        segs="${tg//&&/$nl}"; segs="${segs//||/$nl}"; segs="${segs//;/$nl}"; segs="${segs//|/$nl}"
        while IFS= read -r seg; do
          seg="${seg#"${seg%%[![:space:]]*}"}"
          if [[ "$seg" =~ $re_run && "$seg" =~ $re_tgt ]]; then k=test; break; fi
        done <<< "$segs"
      fi
    fi
    res=ok; [[ "$none" == none ]] && res=none
    [[ "$err" == 1 ]] && res=fail
    [[ "$k" == test && "$mark" == 1 ]] && res=fail
    [[ -n "$nm" ]] || nm="${tg:0:60}"
    out+="$k$us$nm$us$res$us$tg$nl"
  done <<< "$ev"
  printf '%s' "${out%"$nl"}"
}

# @pure
# 역할: 근거 목록에서 시험 파일을 바꾼 뒤 실패하는 시험 실행을 한 번도 보지 못한 시험 파일 이름을 꺼낸다
# 종류: 꺼내기
# 예: $'edit\x1ftest-a.sh\x1fok\x1fcore/tests/test-a.sh\ntest\x1f시험\x1fok\x1fbash core/tests/test-a.sh' → "test-a.sh"
# 예: $'edit\x1ftest-a.sh\x1fok\x1fcore/tests/test-a.sh\ntest\x1f시험\x1ffail\x1fbash core/tests/test-a.sh' → ""
# 예: "" → ""
# <근거 목록> → 이름들(줄마다, 처음 나온 순서). 시험 파일: tests/ · __tests__/ · e2e/ 아래, 이름 끝 .test.* · .spec.* · test-*.sh.
scv_evidence_test_first() {
  local led="${1:-}" us=$'\x1f' nl=$'\n' line k nm r tg base pending="" seen=""
  local re_tf='(^|/)(tests?|__tests__|e2e)/|[._-](test|spec)\.[A-Za-z]+$|(^|/)test-[A-Za-z0-9_-]+\.sh$'
  [[ -n "$led" ]] || return 0
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    IFS="$us" read -r k nm r tg <<< "$line"
    if [[ "$k" == edit && "$tg" =~ $re_tf ]]; then
      base="${tg##*/}"
      # 한 번 실패를 본 시험은 그 뒤에 다시 고쳐도 다시 요구하지 않는다.
      [[ "$nl$pending" == *"$nl$base$nl"* || "$nl$seen" == *"$nl$base$nl"* ]] || pending+="$base$nl"
    elif [[ "$k" == test && "$r" == fail ]]; then
      seen+="$pending"; pending=""
    fi
  done <<< "$led"
  printf '%s' "${pending%"$nl"}"
}

# @pure
# 역할: 근거 목록으로 이번 턴 끝 보고에 무엇이 필요한지 판정한다 — 없음 · 한 줄 · 세 줄
# 종류: 판정/gate
# 예: "" → "none"
# 예: $'scv\x1fhelp\x1fok\x1fhelp\nask\x1fask\x1fok\x1f' → "short"
# 예: $'scv\x1fhelp\x1fok\x1fhelp\nread\x1fa.sh\x1fok\x1fa.sh' → "full"
# <근거 목록> → none(도구 안 씀) | short(SCV 기록 · 질문만) | full(그 밖의 도구를 씀).
scv_finish_needed() {
  local led="${1:-}" us=$'\x1f' line k any=0
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    any=1; k="${line%%"$us"*}"
    case "$k" in scv|ask) ;; *) printf 'full'; return 0 ;; esac
  done <<< "$led"
  if (( any )); then printf 'short'; else printf 'none'; fi
}

# @pure
# 역할: 끝 답에서 확인 범위 줄(확인한 것 · 확인 못 한 것 · 제가 대신 정한 것 · 확인 범위 한 줄)을 찾아 칸과 내용으로 꺼낸다
# 종류: 꺼내기
# 예: $'**결과**\n- 확인한 것: 시험 실행 → 3개 통과\n- 확인 못 한 것: 없음 — 바꾼 갈래 모두 돌림\n- 제가 대신 정한 것: 이름' korean → $'verified\x1f시험 실행 → 3개 통과\nunverified\x1f없음 — 바꾼 갈래 모두 돌림\ndecided\x1f이름'
# 예: $'- Verification scope: records only' english → $'scope\x1frecords only'
# 예: "**이 답의 확인 범위**" korean → ""
# 예: $'**확인한 것**\n- 시험 실행 → 통과\n- 화면 확인\n\n**확인 못 한 것**\n- 폰' korean → $'verified\x1f시험 실행 → 통과 / 화면 확인\nunverified\x1f폰'
# <끝 답> <언어> → "칸\x1f내용" 줄들. 줄 머리의 불릿 · 굵게는 무시하고, 이름 뒤 쌍점이 있어야 칸이다. 바로 아래 들여 쓴 줄은 그 칸의
# 내용에 ' / ' 로 잇는다. 코드 블록 안은 보지 않는다. korean 이 아닌 언어는 english 이름으로 찾는다.
scv_finish_scan() {
  local ans="${1:-}" lang="${2:-}" us=$'\x1f' nl=$'\n' line t slot="" cur="" out="" infence=0 lv lu ld ls body a b hd=0 h
  case "$lang" in
    korean|ko) lv="확인한 것"; lu="확인 못 한 것"; ld="제가 대신 정한 것"; ls="확인 범위" ;;
    *) lv="Verified"; lu="Not verified"; ld="Decided for you"; ls="Verification scope" ;;
  esac
  [[ -n "$ans" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    t="${line#"${line%%[![:space:]]*}"}"
    if [[ "$t" == '```'* ]]; then infence=$(( 1 - infence )); continue; fi
    (( infence )) && continue
    if [[ -n "$slot" && "$line" == [[:space:]]* && -n "$t" ]]; then
      t="${t#- }"; t="${t#\* }"; cur+=" / ${t//\*\*/}"; continue
    fi
    # 0.83.0+ — 제목형(쌍점 없는 '**확인한 것**' · '### 확인한 것' 한 줄) 아래 목록은 그 칸의 내용이다. 실제 세션에서 막힘 45번 중
    # 31번이 이 모양을 '빠진 줄'로 본 오탐이었다. 제목 바로 뒤 빈 줄은 건너뛰고, 목록이 끝나면(빈 줄 · 다른 줄) 칸을 닫는다.
    if (( hd )); then
      if [[ -z "$t" && -z "$cur" ]]; then continue; fi
      if [[ "$t" == "- "* || "$t" == "* "* ]]; then
        h="${t#- }"; h="${h#\* }"; h="${h//\*\*/}"
        # 목록 줄이 그 자체로 칸('확인한 것: …')이면 제목 아래 목록이 아니다 — 아래 일반 판정으로 넘긴다
        case "$h" in
          "${lv}:"*|"${lv}："*|"${lu}:"*|"${lu}："*|"${ld}:"*|"${ld}："*|"${ls}:"*|"${ls}："*|"확인하지 못한 것:"*|"대신 정한 것:"*) hd=0; [[ -n "$cur" ]] || slot="" ;;
          *) if [[ -z "$cur" ]]; then cur="$h"; else cur+=" / $h"; fi; continue ;;
        esac
      fi
      hd=0
    fi
    if [[ -n "$slot" ]]; then out+="$slot$us$cur$nl"; slot=""; cur=""; fi
    t="${t#- }"; t="${t#\* }"; t="${t//\*\*/}"
    # 제목형: 머리 '#' 를 떼고 이름만 남으면(쌍점 없음) 제목으로 본다
    h="$t"; while [[ "$h" == "#"* ]]; do h="${h#\#}"; done; h="${h#"${h%%[![:space:]]*}"}"; h="${h%"${h##*[![:space:]]}"}"
    case "$h" in
      "$lu"|"확인하지 못한 것") slot=unverified; hd=1; cur=""; continue ;;
      "$lv") slot=verified; hd=1; cur=""; continue ;;
      "$ld"|"대신 정한 것") slot=decided; hd=1; cur=""; continue ;;
    esac
    body=""
    # 변수 이름은 중괄호로 감싼다 — 바로 뒤의 전각 쌍점(：)을 이름의 일부로 읽는 셸이 있다.
    case "$t" in
      "${lu}:"*|"${lu}："*|"확인하지 못한 것:"*) slot=unverified ;;
      "${lv}:"*|"${lv}："*) slot=verified ;;
      "${ld}:"*|"${ld}："*|"대신 정한 것:"*) slot=decided ;;
      "${ls}:"*|"${ls}："*) slot=scope ;;
    esac
    if [[ -n "$slot" ]]; then
      # 쌍점 둘(: · ：) 중 앞에 있는 것에서 자른다. 괄호 식 [:：] 은 bash 3.2 가 문자 부류 이름의 시작으로 읽어 엉뚱한 글자에서 자른다.
      a="${t#*:}"; b="${t#*：}"
      if [[ "$a" == "$t" ]]; then body="$b"; elif [[ "$b" == "$t" ]]; then body="$a"
      elif (( ${#a} > ${#b} )); then body="$a"; else body="$b"; fi
    fi
    if [[ -n "$slot" ]]; then body="${body#"${body%%[![:space:]]*}"}"; cur="$body"; fi
  done <<< "$ans"
  [[ -n "$slot" ]] && out+="$slot$us$cur$nl"
  printf '%s' "${out%"$nl"}"
}

# @pure
# 역할: 찾은 칸 · 근거 목록 · 실패를 못 본 시험으로 끝 보고의 문제(빠진 줄 · 이유 없는 없음 · 근거 없는 확인 · 안 밝힌 시험)를 낸다
# 종류: 판정/answer
# 예: "" $'read\x1fa.sh\x1fok\x1fa.sh' "" full → $'missing\x1fverified\nmissing\x1funverified\nmissing\x1fdecided'
# 예: $'scope\x1f기록만 함' $'scv\x1fhelp\x1fok\x1fhelp' "" short → ""
# 예: $'verified\x1f언어 시험 실행 → 14개 통과\nunverified\x1f없음\ndecided\x1f이름' $'read\x1fa.sh\x1fok\x1fa.sh' "" full → $'noreason\x1funverified\nunbacked\x1fpass'
# <칸 줄들> <근거 목록> <못 본 시험 이름들> <none|short|full> → 문제 줄들 | 빈 값. '확인한 것'이 통과 · pass 를 말하면 이번 턴에
# 시험 실행이 있어야 하고, 파일 이름(x.sh · x.md …)을 말하면 근거 목록 대상에 그 이름이 있어야 한다. 근거 목록에 실제로 한 일
# (읽기 · 바꾸기 · 실행 · 시험 · 찾아보기 · 그 밖)이 없는데 무엇을 확인했다고 하면 근거 없음.
scv_finish_check() {
  local scan="${1:-}" led="${2:-}" untested="${3:-}" need="${4:-none}" us=$'\x1f' nl=$'\n' out=""
  local v="" u="" d="" s="" hv=0 hu=0 hd=0 hs=0 line slot c low tok base work=0 hastest=0 alltg="" rest
  local re_file='[A-Za-z0-9_./-]+\.(sh|md|py|ts|tsx|js|jsx|json|ya?ml|go|rs|rb|java|kt|swift|toml)'
  [[ "$need" == short || "$need" == full ]] || return 0
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    slot="${line%%"$us"*}"; c="${line#*"$us"}"
    case "$slot" in verified) v="$c"; hv=1 ;; unverified) u="$c"; hu=1 ;; decided) d="$c"; hd=1 ;; scope) s="$c"; hs=1 ;; esac
  done <<< "$scan"
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    case "${line%%"$us"*}" in scv|ask) ;; test) work=1; hastest=1 ;; *) work=1 ;; esac
    alltg+="${line#*"$us"}$nl"
  done <<< "$led"
  if [[ "$need" == short ]]; then
    (( hv || hu || hd || hs )) || out+="missing${us}scope$nl"
  else
    (( hv )) || out+="missing${us}verified$nl"
    (( hu )) || out+="missing${us}unverified$nl"
    (( hd )) || out+="missing${us}decided$nl"
  fi
  for slot in verified unverified decided; do
    case "$slot" in verified) c="$v"; (( hv )) || continue ;; unverified) c="$u"; (( hu )) || continue ;; decided) c="$d"; (( hd )) || continue ;; esac
    c="${c%"${c##*[![:space:]]}"}"; c="${c%.}"; c="${c%。}"
    case "$c" in 없음|none|None|NONE|N/A|n/a|"") out+="noreason$us$slot$nl" ;; esac
  done
  if (( hv )); then
    case "$v" in 없음*|none*|None*) ;; *)
      if (( ! hastest )) && [[ "$v" == *통과* || "$v" == *[Pp][Aa][Ss][Ss]* || "$v" == *[Gg][Rr][Ee][Ee][Nn]* ]]; then out+="unbacked${us}pass$nl"; fi
      rest="$v"
      while [[ "$rest" =~ $re_file ]]; do
        tok="${BASH_REMATCH[0]}"; base="${tok##*/}"
        [[ "$alltg" == *"$base"* ]] || out+="unbacked$us$base$nl"
        rest="${rest#*"$tok"}"
      done
      if (( ! work )); then out+="unbacked${us}none$nl"; fi
    ;; esac
  fi
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    [[ "$u" == *"$line"* || "$u" == *"${line%.*}"* ]] || out+="undisclosed$us$line$nl"
  done <<< "$untested"
  printf '%s' "${out%"$nl"}"
}

# @pure
# 역할: 끝 보고 문제 줄들을 설정 언어로 된 교정 문구 한 줄로 만든다
# 종류: 조립
# 예: $'missing\x1funverified\nmissing\x1fdecided' korean → "[SCV 확인 범위] 끝 보고에 고칠 것 — 빠진 줄: 확인 못 한 것 · 제가 대신 정한 것. 고친 줄만 끝에 덧붙여라(본문: contracts/finish-report.md)."
# 예: $'undisclosed\x1ftest-a.sh' korean → "[SCV 확인 범위] 끝 보고에 고칠 것 — 고치기 전 실패를 못 본 시험('확인 못 한 것'에 적어라): test-a.sh. 고친 줄만 끝에 덧붙여라(본문: contracts/finish-report.md)."
# 예: "" korean → ""
# <문제 줄들> <언어> → 한 줄 | 빈 값.
scv_finish_note() {
  local chk="${1:-}" lang="${2:-}" us=$'\x1f' line kind what nm miss="" nor="" unb="" und="" parts="" sep
  local tag nv nu nd ns lmiss lnor lunb lund tail npass nnone
  [[ -n "$chk" ]] || return 0
  case "$lang" in
    korean|ko) tag="[SCV 확인 범위] 끝 보고에 고칠 것 —"; nv="확인한 것"; nu="확인 못 한 것"; nd="제가 대신 정한 것"; ns="확인 범위 한 줄"
      lmiss="빠진 줄"; lnor="'없음'에 이유 없음"; lunb="이번 턴 근거 목록에 없는 확인"; lund="고치기 전 실패를 못 본 시험('확인 못 한 것'에 적어라)"
      npass="통과(이번 턴에 시험 실행 없음)"; nnone="이번 턴에 한 일이 없음"; tail="고친 줄만 끝에 덧붙여라(본문: contracts/finish-report.md)."; sep=" · " ;;
    *) tag="[SCV verification scope] Fix the final report —"; nv="Verified"; nu="Not verified"; nd="Decided for you"; ns="the one-line Verification scope"
      lmiss="missing"; lnor="'none' without a reason"; lunb="checks not in this turn's evidence list"; lund="tests never seen failing (name them under Not verified)"
      npass="pass (no test run this turn)"; nnone="no work done this turn"; tail="Append only the fixed lines (body: contracts/finish-report.md)."; sep=", " ;;
  esac
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    kind="${line%%"$us"*}"; what="${line#*"$us"}"
    case "$what" in verified) nm="$nv" ;; unverified) nm="$nu" ;; decided) nm="$nd" ;; scope) nm="$ns" ;; pass) nm="$npass" ;; none) nm="$nnone" ;; *) nm="$what" ;; esac
    case "$kind" in
      missing) miss="${miss:+$miss$sep}$nm" ;; noreason) nor="${nor:+$nor$sep}$nm" ;;
      unbacked) unb="${unb:+$unb$sep}$nm" ;; undisclosed) und="${und:+$und$sep}$nm" ;;
    esac
  done <<< "$chk"
  [[ -n "$miss" ]] && parts+=" $lmiss: $miss."
  [[ -n "$nor" ]] && parts+=" $lnor: $nor."
  [[ -n "$unb" ]] && parts+=" $lunb: $unb."
  [[ -n "$und" ]] && parts+=" $lund: $und."
  [[ -n "$parts" ]] || return 0
  printf '%s%s %s\n' "$tag" "$parts" "$tail"
}

# @pure
# 역할: 매 턴 맨 앞에 실을 확인 범위 안내 한 줄을 설정 언어로 만든다
# 종류: 조립
# 예: korean → "[SCV 확인 범위] 도구를 쓴 턴은 끝 보고 끝에 '확인한 것 · 확인 못 한 것 · 제가 대신 정한 것'(기록 · 질문만 쓴 턴은 '확인 범위:' 한 줄). '없음'엔 이유, 실패를 못 본 시험은 '확인 못 한 것'에. 본문: contracts/finish-report.md"
# 예: english → "[SCV verification scope] A turn that used tools ends its final report with Verified · Not verified · Decided for you (only SCV records or questions: one 'Verification scope:' line). 'none' needs a reason; a test never seen failing goes under Not verified. Body: contracts/finish-report.md"
# 예: "" → "[SCV verification scope] A turn that used tools ends its final report with Verified · Not verified · Decided for you (only SCV records or questions: one 'Verification scope:' line). 'none' needs a reason; a test never seen failing goes under Not verified. Body: contracts/finish-report.md"
# <언어> → 한 줄. korean 이 아니면 english 문구.
scv_finish_rule_line() {
  case "${1:-}" in
    korean|ko) printf '%s\n' "[SCV 확인 범위] 도구를 쓴 턴은 끝 보고 끝에 '확인한 것 · 확인 못 한 것 · 제가 대신 정한 것'(기록 · 질문만 쓴 턴은 '확인 범위:' 한 줄). '없음'엔 이유, 실패를 못 본 시험은 '확인 못 한 것'에. 본문: contracts/finish-report.md" ;;
    *) printf '%s\n' "[SCV verification scope] A turn that used tools ends its final report with Verified · Not verified · Decided for you (only SCV records or questions: one 'Verification scope:' line). 'none' needs a reason; a test never seen failing goes under Not verified. Body: contracts/finish-report.md" ;;
  esac
}

# @pure
# 역할: 근거 목록을 사람이 읽을 기록용 불릿 줄들로 만든다
# 종류: 조립
# 예: $'test\x1f언어 시험 실행\x1ffail\x1fbash t.sh' korean → "- 시험 · 실패 · 언어 시험 실행"
# 예: $'read\x1fa.md\x1fok\x1fdocs/a.md' english → "- read · ok · a.md"
# 예: "" korean → ""
# <근거 목록> <언어> → 줄마다 "- 종류 · 결과 · 이름". SCV 기록은 뺀다.
scv_evidence_render() {
  local led="${1:-}" lang="${2:-}" us=$'\x1f' nl=$'\n' line k nm r tg out="" kk rr
  [[ -n "$led" ]] || return 0
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    IFS="$us" read -r k nm r tg <<< "$line"
    [[ "$k" == scv ]] && continue
    kk="$k"; rr="$r"
    case "$lang" in korean|ko)
      case "$k" in read) kk="읽음" ;; edit) kk="바꿈" ;; run) kk="실행" ;; test) kk="시험" ;; fetch) kk="찾아봄" ;; ask) kk="물음" ;; other) kk="기타" ;; esac
      case "$r" in ok) rr="성공" ;; fail) rr="실패" ;; none) rr="결과 없음" ;; esac ;;
    esac
    out+="- $kk · $rr · $nm$nl"
  done <<< "$led"
  printf '%s' "${out%"$nl"}"
}
