#!/usr/bin/env bash
# lib/words.sh — 프로젝트 낱말 사전의 순수부(계획 20261125-wookiya1364-words).
#
# 사용자가 정한 말이 있다 — "재다" 대신 "측정하다". 사전(scv/words/WORDS.tsv)에 "피할 말 → 쓸 말"을 넣어 두면 대화 첫머리에
# 안내 묶음이 한 번 실리고, 답이 나간 뒤 스크립트가 직전 답에서 피할 말을 찾아 다음 턴에 한 줄로 알린다(답은 다시 쓰게 하지 않는다).
# 항목 한 줄은 탭으로 나눈 네 칸이다: 피할 말(으뜸꼴 — 항목의 이름) · 쓸 말 · 다른 꼴들(", " 로 나눔) · 메모.
# 여기 함수들은 받은 글만 본다 — 파일 읽기 · 쓰기는 scripts/words.sh 한 곳이 한다.
# 찾기는 바이트 단위다(LC_ALL=C): 글자 단위는 글자 설정마다 달라져 맥과 리눅스에서 다른 값이 나온다.
# awk 안에서도 부등호를 쓰지 않는다(크기 비교는 나눗셈의 몫으로): 순수성 검사가 부등호를 파일 읽기 · 쓰기와 가르지 못한다.

# @pure
# 역할: 낱말 사전의 칸 하나에 넣을 글을 다듬는다 — 탭 · 줄바꿈을 빈칸으로 바꾸고 앞뒤 빈칸을 뗀다
# 종류: 다듬기/words
# 예: $' 재다\t측정 \n' → "재다 측정"
# 예: "  utilize  " → "utilize"
# 예: "" → ""
scv_words_field() {
  local s="${1:-}"
  s="${s//$'\t'/ }"; s="${s//$'\r'/ }"; s="${s//$'\n'/ }"
  s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# @pure
# 역할: 꼴 목록을 다듬는다 — 쉼표로 나눠 앞뒤 빈칸을 떼고, 빈 것과 겹친 것을 빼고 ", " 로 잇는다
# 종류: 다듬기/words
# 예: "잰,재서 ,  재 본,, 잰" → "잰, 재서, 재 본"
# 예: $'잰\t재서' → "잰 재서"
# 예: " , " → ""
# 예: "" → ""
scv_words_forms() {
  local s="${1:-}" piece out="" seen=$'\n' had_f=""
  s="${s//$'\t'/ }"; s="${s//$'\r'/ }"; s="${s//$'\n'/ }"
  # 글을 쉼표에서 한 번만 나눈다 — 조각마다 남은 글을 다시 복사하면 조각 수 × 글 길이만큼 느려진다(2026-11-25 실측, 입력 4배에 9.0배).
  [[ $- == *f* ]] && had_f=1
  local IFS=,
  set -f; set -- $s; [[ -n "$had_f" ]] || set +f
  for piece in "$@"; do
    piece="${piece#"${piece%%[![:space:]]*}"}"; piece="${piece%"${piece##*[![:space:]]}"}"
    [[ -n "$piece" ]] || continue
    case "$seen" in *$'\n'"$piece"$'\n'*) continue ;; esac
    seen+="$piece"$'\n'
    out+="${out:+, }$piece"
  done
  printf '%s' "$out"
}

# @pure
# 역할: 낱말 사전 파일의 글을 항목 줄들로 읽는다 — 주석 줄 · 빈 줄 · 피할 말이나 쓸 말이 없는 줄을 빼고, 줄마다 탭으로 나눈 네 칸으로 맞춘다
# 종류: 꺼내기/words
# 예: $'# 낱말 사전\n\n재다\t측정하다\t잰, 재서\t수치 얘기\n유저\t사용자' → $'재다\t측정하다\t잰, 재서\t수치 얘기\n유저\t사용자\t\t'
# 예: $'재다\t측정하다\t\t\n재다\t계측하다\t\t' → $'재다\t측정하다\t\t'
# 예: $'쓸 말 없음\n\t측정하다' → ""
# 예: "" → ""
# <파일 글> → 항목 줄들. 같은 피할 말이 두 번 나오면 앞의 것만 남긴다. 다섯째 칸부터는 메모에 빈칸으로 이어 붙인다.
scv_words_parse() {
  local text="${1:-}" T=$'\t' line a u f n rest out="" seen=$'\n'
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ "$line" == *[![:space:]]* ]] || continue
    rest="${line#"${line%%[![:space:]]*}"}"
    [[ "$rest" == '#'* ]] && continue
    a="$line"; u=""; f=""; n=""
    if [[ "$line" == *"$T"* ]]; then
      a="${line%%"$T"*}"; rest="${line#*"$T"}"; u="$rest"
      if [[ "$rest" == *"$T"* ]]; then
        u="${rest%%"$T"*}"; rest="${rest#*"$T"}"; f="$rest"
        if [[ "$rest" == *"$T"* ]]; then f="${rest%%"$T"*}"; n="${rest#*"$T"}"; n="${n//"$T"/ }"; fi
      fi
    fi
    a="${a#"${a%%[![:space:]]*}"}"; a="${a%"${a##*[![:space:]]}"}"
    u="${u#"${u%%[![:space:]]*}"}"; u="${u%"${u##*[![:space:]]}"}"
    f="${f#"${f%%[![:space:]]*}"}"; f="${f%"${f##*[![:space:]]}"}"
    n="${n#"${n%%[![:space:]]*}"}"; n="${n%"${n##*[![:space:]]}"}"
    [[ -n "$a" && -n "$u" ]] || continue
    case "$seen" in *$'\n'"$a"$'\n'*) continue ;; esac
    seen+="$a"$'\n'
    out+="${out:+$'\n'}$a$T$u$T$f$T$n"
  done <<< "$text"
  printf '%s' "$out"
}

# @pure
# 역할: 낱말 사전에 넣을 수 없는 항목이면 그 까닭을 낸다 — 피할 말이나 쓸 말이 비었거나, 둘이 같거나, 피할 말이 # 로 시작할 때. 넣을 수 있으면 빈 값
# 종류: 판정/words
# 예: 재다 측정하다 → ""
# 예: "" 측정하다 → "피할 말이 비었다(--avoid)"
# 예: 재다 "" → "쓸 말이 비었다(--use)"
# 예: 재다 재다 → "피할 말과 쓸 말이 같다: 재다"
# 예: "#재다" 측정하다 → "피할 말은 # 로 시작할 수 없다(그 줄이 주석으로 읽힌다)"
scv_words_add_error() {
  local a="${1:-}" u="${2:-}"
  if [[ -z "$a" ]]; then printf '%s' "피할 말이 비었다(--avoid)"
  elif [[ -z "$u" ]]; then printf '%s' "쓸 말이 비었다(--use)"
  elif [[ "$a" == "$u" ]]; then printf '%s' "피할 말과 쓸 말이 같다: $a"
  elif [[ "$a" == '#'* ]]; then printf '%s' "피할 말은 # 로 시작할 수 없다(그 줄이 주석으로 읽힌다)"
  fi
}

# @pure
# 역할: 항목 줄들에 항목 하나를 넣는다 — 같은 피할 말이 있으면 그 자리에서 갈아 끼우고, 꼴 · 메모를 주지 않았으면 있던 것을 지킨다
# 종류: 조립/words
# 예: "" 재다 측정하다 "잰, 재서" 1 "" 0 → $'재다\t측정하다\t잰, 재서\t'
# 예: $'재다\t측정하다\t잰, 재서\t수치 얘기\n유저\t사용자\t\t' 재다 계측하다 "" 0 "" 0 → $'재다\t계측하다\t잰, 재서\t수치 얘기\n유저\t사용자\t\t'
# 예: $'재다\t측정하다\t잰, 재서\t수치 얘기' 재다 측정하다 "쟀다" 1 "" 1 → $'재다\t측정하다\t쟀다\t'
# 예: $'재다\t측정하다\t\t' 유저 사용자 "" 0 "" 0 → $'재다\t측정하다\t\t\n유저\t사용자\t\t'
# <항목 줄들> <피할 말> <쓸 말> <꼴들> <꼴을 줬는가 1|0> <메모> <메모를 줬는가 1|0> → 항목 줄들. 새 항목은 맨 뒤에 붙는다.
scv_words_upsert() {
  local entries="${1:-}" a="${2:-}" u="${3:-}" f="${4:-}" fg="${5:-0}" n="${6:-}" ng="${7:-0}"
  local T=$'\t' line rest lf ln out="" hit=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    if [[ "${line%%"$T"*}" == "$a" ]]; then
      rest="${line#*"$T"}"; rest="${rest#*"$T"}"; lf="${rest%%"$T"*}"; ln=""
      [[ "$rest" == *"$T"* ]] && ln="${rest#*"$T"}"
      [[ "$fg" == 1 ]] || f="$lf"
      [[ "$ng" == 1 ]] || n="$ln"
      line="$a$T$u$T$f$T$n"; hit=1
    fi
    out+="${out:+$'\n'}$line"
  done <<< "$entries"
  (( hit )) || out+="${out:+$'\n'}$a$T$u$T$f$T$n"
  printf '%s' "$out"
}

# @pure
# 역할: 항목 줄들에서 피할 말이 같은 항목을 뺀다 — 그런 항목이 없으면 줄들을 그대로 내고 실패한다
# 종류: 고르기/words
# 예: $'재다\t측정하다\t\t\n유저\t사용자\t\t' 재다 → $'유저\t사용자\t\t'
# 예: $'재다\t측정하다\t\t' 재다 → ""
# 예: $'재다\t측정하다\t\t' 유저 → $'재다\t측정하다\t\t' [1]
# 예: "" 재다 → "" [1]
scv_words_remove() {
  local entries="${1:-}" a="${2:-}" T=$'\t' line out="" hit=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    if [[ "${line%%"$T"*}" == "$a" ]]; then hit=1; continue; fi
    out+="${out:+$'\n'}$line"
  done <<< "$entries"
  printf '%s' "$out"
  (( hit ))
}

# @deterministic
# 역할: 답 글에서 사전의 피할 말을 찾는다 — 낱말 첫머리에서만 세고, 코드(울타리 블록 · 백틱 안)와 인용 줄은 건너뛴다. 항목마다 "찾은 꼴 → 쓸 말" 한 줄
# 종류: 판정/words
# 예: "잰 값은 3초다" $'재다\t측정하다\t잰, 재서, 재 본, 재 봤\t' → "잰 → 측정하다"
# 예: "값을 (재 봤을 때) 유저가 늘었다" $'재다\t측정하다\t잰, 재 봤\t\n유저\t사용자\t\t' → $'재 봤 → 측정하다\n유저 → 사용자'
# 예: "현재다. 어제잰 것" $'재다\t측정하다\t잰\t' → ""
# 예: $'값은 `잰` 것\n```\n잰 값\n```\n  \x3e 잰 값을 알려 줘' $'재다\t측정하다\t잰\t' → ""
# 예: "사용하는 값 · 재는 값" $'사용하다\t쓰다\t\t\n재다\t측정하다\t\t' → "사용하 → 쓰다"
# 예: "We Utilized it" $'utilize\tuse\t\t' → "Utilize → use"
# 예: "사용자 수" $'사용\t사용자\t\t' → ""
# 예: "" $'재다\t측정하다\t잰\t' → ""
# <답 글> <항목 줄들> → 찾은 항목마다 한 줄(사전의 차례대로). 꼴은 낱말의 첫머리에 올 때만 센다 — 글의 처음, 또는 빈칸 · 줄바꿈 ·
# ( [ { " ' “ ‘ · — - / , . : ; ! ? 뒤. 꼴이 빈 항목은 피할 말 그대로와, "다"로 끝나고 어간이 두 글자 이상이면 그 어간만 찾는다.
# 영문은 대소문자를 가리지 않는다. 찾은 자리가 쓸 말로 시작하면(쓸 말이 피할 말로 시작하는 사전) 세지 않는다.
# 한 항목은 처음 찾은 줄에서 끝난다 — 그 줄의 가장 앞, 같은 자리면 가장 긴 꼴. 답 글은 한 번만 훑는다.
scv_words_hits() {
  local ans="${1:-}" entries="${2:-}"
  [[ -n "$ans" && -n "$entries" ]] || return 0
  printf '%s\n' "$ans" | SCV_WORDS_E="$entries" SCV_WORDS_Q=$'\x3e' LC_ALL=C awk '
    function wstart(s, p,   c) {
      if (p == 1) return 1
      c = substr(s, p - 1, 1)
      if (index(" \t\r([{\"\047-/,.:;!?", c) != 0) return 1
      if (substr(s, p - 2, 2) == "\302\267") return 1
      c = substr(s, p - 3, 3)
      if (c == "\342\200\234" || c == "\342\200\230" || c == "\342\200\224") return 1
      return 0
    }
    BEGIN {
      q = ENVIRON["SCV_WORDS_Q"]; ne = split(ENVIRON["SCV_WORDS_E"], el, "\n"); n = 0
      for (i = 1; i != ne + 1; i++) {
        nc = split(el[i], col, "\t")
        if (int(nc / 2) == 0 || col[1] == "" || col[2] == "") continue
        n++; use[n] = col[2]; usel[n] = tolower(col[2]); nf[n] = 1; form[n, 1] = tolower(col[1])
        fs = (int(nc / 3) != 0) ? col[3] : ""
        if (fs != "") {
          m = split(fs, part, ",")
          for (k = 1; k != m + 1; k++) {
            w = part[k]; sub(/^[ \t]+/, "", w); sub(/[ \t]+$/, "", w)
            if (w != "") { nf[n]++; form[n, nf[n]] = tolower(w) }
          }
        } else {
          w = col[1]; lw = length(w)
          if (int(lw / 4) != 0 && substr(w, lw - 2) == "\353\213\244") {
            stem = substr(w, 1, lw - 3); tmp = stem; chars = length(stem) - gsub(/[\200-\277]/, "", tmp)
            if (int(chars / 2) != 0) { nf[n]++; form[n, nf[n]] = tolower(stem) }
          }
        }
      }
    }
    {
      line = $0; t = line; sub(/^[ \t]+/, "", t)
      if (substr(t, 1, 3) == "```" || substr(t, 1, 3) == "~~~") { fence = 1 - fence; next }
      if (fence || substr(t, 1, 1) == q) next
      gsub(/`[^`]*`/, "\001", line)
      low = tolower(line)
      for (e = 1; e != n + 1; e++) {
        if (e in found) continue
        bp = 0; bl = 0
        for (k = 1; k != nf[e] + 1; k++) {
          w = form[e, k]; lw = length(w); off = 0; rest = low
          while ((i = index(rest, w)) != 0) {
            p = off + i
            if (wstart(low, p) && substr(low, p, length(usel[e])) != usel[e]) {
              if (bp == 0 || (p != bp && int(p / bp) == 0) || (p == bp && int(lw / (bl + 1)) != 0)) { bp = p; bl = lw }
              break
            }
            off = p; rest = substr(low, p + 1)
          }
        }
        if (bp != 0) found[e] = substr(line, bp, bl)
      }
    }
    END {
      first = 1
      for (e = 1; e != n + 1; e++) if (e in found) { printf "%s%s → %s", (first ? "" : "\n"), found[e], use[e]; first = 0 }
    }'
}

# @pure
# 역할: 대화 첫머리에 실을 낱말 안내 묶음을 만든다 — 머리 한 줄과 항목마다 한 줄("피할 말(꼴들) → 쓸 말"). 항목이 없으면 빈 값
# 종류: 조립/words
# 예: $'재다\t측정하다\t잰, 재서\t수치 얘기' korean → $'[SCV 낱말] 아래 왼쪽 말은 쓰지 않는다 — 그 활용 · 같은 계열의 말도 쓰지 않는다(괄호 안의 꼴은 예일 뿐 전부가 아니다). 오른쪽 말을 문장에 맞게 활용해 쓴다. 사용자가 읽는 모든 글(답 · 중간 보고 · 요약)에 적용하고, 코드 · 파일 이름 · 인용한 사용자 글 · 명령에는 적용하지 않는다.\n- 재다(잰, 재서) → 측정하다 — 수치 얘기'
# 예: $'utilize\tuse\t\t' english → $'[SCV words] Do not use a word on the left, or any inflection or same-family form of it (the forms in brackets are examples, not the whole list) — say the word on the right instead, conjugated to fit the sentence. This applies to everything the user reads (answers, progress notes, summaries), not to code, file names, quoted user text or commands.\n- utilize → use'
# 예: "" korean → ""
# <항목 줄들> <설정 언어> → 안내 묶음. 언어가 korean · ko 면 한국어, 그 밖은 영어 글이다.
scv_words_text() {
  local entries="${1:-}" lang="${2:-}" T=$'\t' line a u f n rest out=""
  [[ -n "$entries" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == *"$T"* ]] || continue
    a="${line%%"$T"*}"; rest="${line#*"$T"}"; u="${rest%%"$T"*}"; f=""; n=""
    if [[ "$rest" == *"$T"* ]]; then
      rest="${rest#*"$T"}"; f="${rest%%"$T"*}"
      [[ "$rest" == *"$T"* ]] && n="${rest#*"$T"}"
    fi
    [[ -n "$a" && -n "$u" ]] || continue
    out+=$'\n'"- $a${f:+($f)} → $u${n:+ — $n}"
  done <<< "$entries"
  [[ -n "$out" ]] || return 0
  case "$lang" in
    korean|ko)
      printf '%s%s' "[SCV 낱말] 아래 왼쪽 말은 쓰지 않는다 — 그 활용 · 같은 계열의 말도 쓰지 않는다(괄호 안의 꼴은 예일 뿐 전부가 아니다). 오른쪽 말을 문장에 맞게 활용해 쓴다. 사용자가 읽는 모든 글(답 · 중간 보고 · 요약)에 적용하고, 코드 · 파일 이름 · 인용한 사용자 글 · 명령에는 적용하지 않는다." "$out" ;;
    *)
      printf '%s%s' "[SCV words] Do not use a word on the left, or any inflection or same-family form of it (the forms in brackets are examples, not the whole list) — say the word on the right instead, conjugated to fit the sentence. This applies to everything the user reads (answers, progress notes, summaries), not to code, file names, quoted user text or commands." "$out" ;;
  esac
}

# @pure
# 역할: 이 턴에 낱말 안내 묶음을 실을지 가른다 — 사전이 없으면 none, 한 번만 싣기가 꺼졌거나 이 맥락에 실은 적이 없거나 사전이 바뀌었으면 full
# 종류: 판정/words
# 예: "" "123 45" on → "full"
# 예: "123 45" "123 45" on → "none"
# 예: "123 45" "999 50" on → "full"
# 예: "123 45" "123 45" off → "full"
# 예: "123 45" "" on → "none"
# <이 맥락에 실은 사전의 지문(없으면 빈 값)> <지금 사전의 지문(사전이 없으면 빈 값)> <한 번만 싣기 on|off> → full | none.
# 표시는 세션 자리에 있고, 대화가 요약 · 비움 · 재개되면 초기화가 지운다(규칙 글의 한 번만 싣기와 같은 길).
scv_words_due() {
  local seen="${1:-}" cur="${2:-}" once="${3:-on}"
  [[ -n "$cur" ]] || { printf 'none'; return 0; }
  [[ "$once" == off ]] && { printf 'full'; return 0; }
  if [[ "$seen" == "$cur" ]]; then printf 'none'; else printf 'full'; fi
}

# @pure
# 역할: 다음 턴 안내 글에서 낱말 알림 줄("[SCV 낱말] 직전 답에 …")을 뺀 나머지를 낸다
# 종류: 고르기/words
# 예: $'[SCV 낱말] 직전 답에 피할 말이 있었다: 잰 → 측정하다 — 같은 뜻으로 쓴 것이면 이번 답부터 바꿔 말하라(직전 답은 다시 쓰지 않는다).\n[SCV 그림] 직전 답이 순서를 글로만 적었다' → "[SCV 그림] 직전 답이 순서를 글로만 적었다"
# 예: "[SCV 낱말] 직전 답에 피할 말이 있었다: 잰 → 측정하다" → ""
# 예: "[SCV 낱말] 아래 왼쪽 말은 쓰지 않는다" → "[SCV 낱말] 아래 왼쪽 말은 쓰지 않는다"
# 예: "" → ""
# <안내 글> → 낱말 알림 줄이 없는 안내 글. 규칙 글 전문을 다시 실을지 가를 때 쓴다 — 낱말 알림은 그 한 줄로 충분하고,
# 글자만 같은 말(틀린 알림)에 규칙 전문이 다시 실리면 매 턴 글이 불어난다.
scv_words_note_drop() {
  local text="${1:-}" line out=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == "[SCV 낱말] 직전 답에 "* ]] && continue
    out+="${out:+$'\n'}$line"
  done <<< "$text"
  printf '%s' "$out"
}

# @pure
# 역할: 직전 답에서 찾은 피할 말들로 다음 턴에 실을 한 줄을 만든다 — 찾은 것이 없으면 빈 값
# 종류: 조립/words
# 예: "잰 → 측정하다" → "[SCV 낱말] 직전 답에 피할 말이 있었다: 잰 → 측정하다 — 같은 뜻으로 쓴 것이면 이번 답부터 바꿔 말하라(직전 답은 다시 쓰지 않는다)."
# 예: $'잰 → 측정하다\n유저 → 사용자' → "[SCV 낱말] 직전 답에 피할 말이 있었다: 잰 → 측정하다, 유저 → 사용자 — 같은 뜻으로 쓴 것이면 이번 답부터 바꿔 말하라(직전 답은 다시 쓰지 않는다)."
# 예: $'a → 1\nb → 2\nc → 3' 2 → "[SCV 낱말] 직전 답에 피할 말이 있었다: a → 1, b → 2 외 1개 — 같은 뜻으로 쓴 것이면 이번 답부터 바꿔 말하라(직전 답은 다시 쓰지 않는다)."
# 예: "" → ""
# <찾은 줄들("찾은 꼴 → 쓸 말")> [<한 줄에 적을 개수 — 기본 6>] → 한 줄. 스크립트는 글자만 본다 — 같은 뜻인지는 모델이 본다.
scv_words_note() {
  local hits="${1:-}" max="${2:-6}" line list="" n=0 more=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    n=$(( n + 1 ))
    if (( n > max )); then more=$(( more + 1 )); continue; fi
    list+="${list:+, }$line"
  done <<< "$hits"
  [[ -n "$list" ]] || return 0
  (( more == 0 )) || list+=" 외 ${more}개"
  printf '%s' "[SCV 낱말] 직전 답에 피할 말이 있었다: $list — 같은 뜻으로 쓴 것이면 이번 답부터 바꿔 말하라(직전 답은 다시 쓰지 않는다)."
}
