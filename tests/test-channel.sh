#!/usr/bin/env bash
# test-channel.sh — 채널(개발 · 스테이징 · 운영)의 순수부 (0.71.0).
#
# 채널 → 브랜치, 브랜치 → 채널, 바꿔 끼우기 단계, 채널 버전 표시를 확인한다. 호스트 명령으로 실제로 바꾸는 일은 래퍼의 시험이 본다.
set -uo pipefail

HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=../scripts/lib/channel.sh
source "$HERE/../scripts/lib/channel.sh"

pass=0; fail=0
ok()  { pass=$((pass+1)); }
bad() { echo "  ✗ $1"; fail=$((fail+1)); }
eq()  { [[ "$2" == "$3" ]] && ok || bad "$1: '$2' != '$3'"; }

# T1. 채널 이름이 브랜치로 바뀐다 — 모르는 이름은 종료 코드 2
eq 'T1 dev' "$(scv_channel_ref dev)" 'channel/dev'
eq 'T1 stage' "$(scv_channel_ref stage)" 'channel/stage'
eq 'T1 prod' "$(scv_channel_ref prod)" ''
scv_channel_ref nightly >/dev/null; eq 'T1 unknown rc' "$?" 2

# T1b. 브랜치에서 채널을 읽는다 — 지금 상태를 사람 말로 보이기
eq 'T1b none' "$(scv_channel_of_ref '')" 'prod'
eq 'T1b main' "$(scv_channel_of_ref main)" 'prod'
eq 'T1b dev' "$(scv_channel_of_ref channel/dev)" 'dev'
eq 'T1b stage' "$(scv_channel_of_ref channel/stage)" 'stage'
eq 'T1b other' "$(scv_channel_of_ref develop)" 'other:develop'

# T3. 바꿔 끼우기 단계 — 운영 → 개발은 지우고 브랜치 붙여 다시 넣고 설치, 같은 채널은 할 일 없음
eq 'T3 prod→dev' "$(scv_channel_plan 1 '' channel/dev | tr '\n' '|')" 'remove|add channel/dev|install|'
eq 'T3 dev→prod' "$(scv_channel_plan 1 channel/dev '' | tr '\n' '|')" 'remove|add -|install|'
eq 'T3 none→stage' "$(scv_channel_plan 0 '' channel/stage | tr '\n' '|')" 'add channel/stage|install|'
eq 'T3 same' "$(scv_channel_plan 1 channel/dev channel/dev)" ''
eq 'T3 same prod' "$(scv_channel_plan 1 '' '')" ''

# T4. 채널 버전 표시 — 운영은 그대로, 개발 · 스테이징은 다음 패치 + 채널 + 커밋 7자리
eq 'T4 prod' "$(scv_channel_version 0.70.4 prod abc1234def)" '0.70.4'
eq 'T4 dev' "$(scv_channel_version 0.70.4 dev abc1234def)" '0.70.5-dev.abc1234'
eq 'T4 stage' "$(scv_channel_version 0.70.4 stage abc1234def)" '0.70.5-stage.abc1234'
eq 'T4 codex base' "$(scv_channel_version 0.70.4-codex.1 dev abc1234)" '0.70.5-dev.abc1234'
scv_channel_version bad dev abc >/dev/null; eq 'T4 bad base rc' "$?" 2
scv_channel_version 0.70.4 nightly abc >/dev/null; eq 'T4 bad channel rc' "$?" 2

# T4b. 개발 버전은 지금 운영과 버전 폴더가 달라 바꿔 끼우면 새로 받아지고, 지금 운영보다 앞선다
eq 'T4b differs' "$([[ "$(scv_channel_version 0.70.4 dev abc1234)" != 0.70.4 ]] && echo y)" 'y'
eq 'T4b dev > prod' "$(printf '%s\n' 0.70.5-dev.abc1234 0.70.4 | sort -V | head -1)" '0.70.4'

echo "test-channel: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
