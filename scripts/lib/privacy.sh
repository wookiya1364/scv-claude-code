#!/usr/bin/env bash
# lib/privacy.sh — 개인정보 검사의 순수부. 본문: scripts/check-privacy.sh.
#
# 공개 저장소에 다시 쌓이면 안 되는 것: 개인 메일 주소, 내 컴퓨터 경로, 세션 id, 세션 링크 줄, 그리고 저장소 밖
# 비밀 목록(실명 · 회사 이름 등)의 낱말. 개인 값 자체는 이 파일에 적지 않는다 — 목록은 SCV_PRIVACY_TERMS(줄마다
# 하나, CI 는 Actions 비밀값)로만 들어온다. 여기 함수는 모두 순수하다(인자만 읽고 stdout 으로만 돌려준다).
#
#   scv_privacy_email_ok <메일>            → 종료 코드 0 이면 공개해도 되는 주소(GitHub noreply · 봇)
#   scv_privacy_text_rule <줄>             → 걸린 규칙 이름 하나(personal-email | local-path | session-id | session-line) 또는 빈 값
#   scv_privacy_term_hit <줄> <목록 원문>  → 걸린 목록 줄 번호(1부터) 또는 빈 값 — 낱말 경계, 대소문자 무시
#   scv_privacy_path_skipped <경로>        → 종료 코드 0 이면 검사하지 않는 경로(가짜 시험 자료 · 래퍼 안 Core 사본)
# @pure

scv_privacy_email_ok() {
  case "${1:-}" in
    *@users.noreply.github.com|noreply@github.com|noreply@anthropic.com) return 0 ;;
    *) return 1 ;;
  esac
}

scv_privacy_text_rule() {
  local l="${1:-}"
  if printf '%s' "$l" | grep -qE '(^|[^A-Za-z])[A-Z][A-Za-z]*-Session:[[:space:]]|/code/session_[A-Za-z0-9]'; then echo session-line; return; fi
  if printf '%s' "$l" | grep -qE 'session_01[A-Za-z0-9]{10,}'; then echo session-id; return; fi
  if printf '%s' "$l" | grep -qE '/Users/[A-Za-z0-9._-]+/|/home/[A-Za-z0-9._-]+/|/private/tmp/claude-[0-9]+'; then echo local-path; return; fi
  if printf '%s' "$l" | grep -qiE '[A-Za-z0-9._%+-]+@(gmail|googlemail|naver|daum|hanmail|kakao|nate|hotmail|outlook|live|yahoo|icloud|me|proton|protonmail)\.[a-z.]+'; then echo personal-email; return; fi
  echo ''
}

scv_privacy_term_hit() {
  local l="${1:-}" terms="${2:-}" t n=0
  while IFS= read -r t; do
    n=$((n + 1))
    [[ -z "$t" || "$t" == \#* ]] && continue
    if printf '%s' "$l" | grep -qiF -- "$t"; then
      # 낱말 경계: 앞뒤가 영숫자가 아니어야 한다(짧은 낱말이 다른 낱말 속에서 걸리지 않게).
      if printf '%s' "$l" | LC_ALL=C awk -v t="$t" 'BEGIN{IGNORECASE=1} { s=tolower($0); w=tolower(t); i=index(s,w); while(i>0){ a=substr(s,i-1,1); b=substr(s,i+length(w),1); if((i==1||a!~/[a-z0-9]/)&&(b==""||b!~/[a-z0-9]/)){f=1;exit} s=substr(s,i+1); i=index(s,w) } } END{exit !f}'; then
        echo "$n"; return
      fi
    fi
  done <<< "$terms"
  echo ''
}

scv_privacy_path_skipped() {
  case "${1:-}" in
    */tests/fixtures/*|tests/fixtures/*|vendor/*|*/vendor/*) return 0 ;;
    *.gif|*.png|*.jpg|*.jpeg|*.webp|*.ico|*.mp4|*.webm|*.woff|*.woff2|*.ttf|*.pdf) return 0 ;;
    *) return 1 ;;
  esac
}
