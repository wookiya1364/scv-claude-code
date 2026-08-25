#!/usr/bin/env bash
# test-journal.sh — team journal unit/integration tests (v0.22.0+).
#
# Covers TESTS.md scenarios 3–6 of 20260804-wookiya1364-team-journal:
#   3. author resolution (git config user.name → GIT_AUTHOR_NAME → USER) +
#      filename-safe slugging incl. spaces and Korean names
#   4. journal append + attribution — per-day PER-AUTHOR file split
#   5. redaction — password= / Bearer / api_key: / AKIA… are [REDACTED] and
#      the originals survive NOWHERE (masking failure = test failure)
#   6. UserPromptSubmit hook contract — stdin JSON {"prompt": ...} lands in
#      the journal; invalid JSON → exit 0 (non-blocking) + no record
# Plus (additions allowed): on-stop.sh non-blocking + transcript extraction.
#
# Run: bash core/tests/test-journal.sh

set -uo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
AUTHOR_LIB="$REPO_ROOT/scripts/lib/author.sh"
JOURNAL="$REPO_ROOT/scripts/journal-append.sh"
HOOK_PROMPT="$REPO_ROOT/template/hooks/on-user-prompt.sh"
HOOK_STOP="$REPO_ROOT/template/hooks/on-stop.sh"

PASS=0; FAIL=0
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
eq()   { if [[ "$2" == "$3" ]]; then ok "$1"; else fail "$1 — expected [$2], got [$3]"; fi; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Env isolation: no user/global git config, controlled fallback vars.
GIT_ISOLATE=(GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null HOME="$WORK/fakehome")
mkdir -p "$WORK/fakehome"

echo "── [3] author resolution + slugging ──"

# 3a. git config user.name wins (repo-local config)
GITREPO="$WORK/gitrepo"
mkdir -p "$GITREPO"
git -C "$GITREPO" init -q
git -C "$GITREPO" config user.name "Hong Gil Dong"
OUT="$(cd "$GITREPO" && env "${GIT_ISOLATE[@]}" GIT_AUTHOR_NAME="Should Not Win" USER=nobody \
  bash -c "source '$AUTHOR_LIB'; scv_author")"
eq "git config user.name wins and is slugged" "hong-gil-dong" "$OUT"

# 3b. no git config → GIT_AUTHOR_NAME fallback
NOGIT="$WORK/nogit"; mkdir -p "$NOGIT"
OUT="$(cd "$NOGIT" && env "${GIT_ISOLATE[@]}" GIT_AUTHOR_NAME="Test Author" USER=nobody \
  bash -c "source '$AUTHOR_LIB'; scv_author")"
eq "GIT_AUTHOR_NAME fallback" "test-author" "$OUT"

# 3c. no git config, no GIT_AUTHOR_NAME → USER fallback
OUT="$(cd "$NOGIT" && env -u GIT_AUTHOR_NAME "${GIT_ISOLATE[@]}" USER="Fallback User" \
  bash -c "source '$AUTHOR_LIB'; scv_author")"
eq "USER fallback (slugged)" "fallback-user" "$OUT"

# 3d. Korean name: spaces → dash, hangul preserved, filename-safe, non-empty
OUT="$(bash -c "source '$AUTHOR_LIB'; scv_author_slug '홍 길동'")"
eq "Korean name slug keeps hangul (space → dash)" "홍-길동" "$OUT"
case "$OUT" in
  *' '*|*'/'*|*':'*|'') fail "Korean slug not filename-safe: [$OUT]" ;;
  *) ok "Korean slug is filename-safe (no space//:/, non-empty)" ;;
esac

# 3e. punctuation/quotes collapse, dashes squeezed+trimmed; empty → unknown
OUT="$(bash -c "source '$AUTHOR_LIB'; scv_author_slug '  Anne O'\''Brien / QA  '")"
eq "punctuation squeezed to single dashes" "anne-o-brien-qa" "$OUT"
OUT="$(bash -c "source '$AUTHOR_LIB'; scv_author_slug ''")"
eq "empty name → unknown (never anonymous)" "unknown" "$OUT"

echo "── [4] journal append + attribution + per-author split ──"

PROJ="$WORK/proj"; mkdir -p "$PROJ/scv"
DAY="$(date +%Y%m%d)"

OUT="$(cd "$PROJ" && printf 'first turn from alice' | bash "$JOURNAL" --author alice --speaker user)"
AF="$PROJ/scv/journal/${DAY}-alice.md"
[[ -f "$AF" ]] && ok "journal file created: scv/journal/${DAY}-alice.md" || fail "alice journal file missing"
grep -qF "JOURNAL_FILE: scv/journal/${DAY}-alice.md" <<< "$OUT" && ok "JOURNAL_FILE line emitted" || fail "JOURNAL_FILE line missing"
grep -qE '^### \[[0-9]{2}:[0-9]{2}:[0-9]{2}\] user$' "$AF" && ok "block header ### [HH:MM:SS] user" || fail "block header format wrong"
grep -qF "first turn from alice" "$AF" && ok "turn content appended" || fail "turn content missing"

# append-only: a second turn adds a second block, first survives
(cd "$PROJ" && printf 'second turn' | bash "$JOURNAL" --author alice --speaker assistant >/dev/null)
N_BLOCKS="$(grep -cE '^### \[' "$AF")"
eq "two blocks after two appends (append-only)" "2" "$N_BLOCKS"
grep -qF "first turn from alice" "$AF" && ok "earlier block preserved" || fail "earlier block lost"
grep -qE '^### \[[0-9:]+\] assistant$' "$AF" && ok "speaker attribution per block" || fail "assistant speaker block missing"

# different author, same day → DIFFERENT file
(cd "$PROJ" && printf 'turn from bob' | bash "$JOURNAL" --author bob >/dev/null)
BF="$PROJ/scv/journal/${DAY}-bob.md"
[[ -f "$BF" ]] && ok "second author writes a separate file" || fail "bob journal file missing"
[[ "$AF" != "$BF" ]] && ok "per-author file split (no shared file → no git conflict)" || fail "authors shared one file"
grep -qF "turn from bob" "$BF" && ok "bob's content in bob's file" || fail "bob content missing"
grep -qF "turn from bob" "$AF" && fail "bob content leaked into alice file" || ok "no cross-author leakage"

# default author resolution path (no --author): via lib/author.sh
(cd "$PROJ" && env "${GIT_ISOLATE[@]}" GIT_AUTHOR_NAME="Carol Kim" \
  bash -c "printf 'env-resolved author' | bash '$JOURNAL'" >/dev/null)
[[ -f "$PROJ/scv/journal/${DAY}-carol-kim.md" ]] \
  && ok "author auto-resolved via lib/author.sh when --author absent" \
  || fail "auto-resolved author file missing"

echo "── [5] redaction (masking failure = test failure) ──"

RED="$WORK/red"; mkdir -p "$RED/scv"
SECRET_INPUT='login password=hunter2 auth Bearer eyJhbGciOiJIUzI1NiJ9.payload.sig conf api_key: sk-live-abc123 aws AKIAIOSFODNN7EXAMPLE done'
(cd "$RED" && printf '%s' "$SECRET_INPUT" | bash "$JOURNAL" --author redtest >/dev/null)
RF="$RED/scv/journal/${DAY}-redtest.md"
[[ -f "$RF" ]] || fail "redaction journal file missing"

N_RED="$(grep -o '\[REDACTED\]' "$RF" | wc -l | tr -d ' ')"
[[ "$N_RED" -ge 4 ]] && ok "all 4 secret patterns masked ([REDACTED] x$N_RED)" || fail "expected >=4 [REDACTED], got $N_RED"

for secret in "hunter2" "eyJhbGciOiJIUzI1NiJ9" "sk-live-abc123" "AKIAIOSFODNN7EXAMPLE"; do
  if grep -rqF "$secret" "$RED"; then
    fail "SECRET LEAKED to disk: $secret"
  else
    ok "original nowhere on disk: $secret"
  fi
done

# --redact-only: filter mode writes NOTHING, prints redacted text
BEFORE_FILES="$(find "$RED" -type f | sort)"
OUT="$(cd "$RED" && printf 'x password=hunter2 Bearer abc.def y' | bash "$JOURNAL" --redact-only)"
AFTER_FILES="$(find "$RED" -type f | sort)"
grep -qF 'password=[REDACTED]' <<< "$OUT" && ok "--redact-only masks password" || fail "--redact-only did not mask password"
grep -qF 'Bearer [REDACTED]' <<< "$OUT" && ok "--redact-only masks Bearer" || fail "--redact-only did not mask Bearer"
grep -qF 'hunter2' <<< "$OUT" && fail "--redact-only leaked original" || ok "--redact-only output has no original"
[[ "$BEFORE_FILES" == "$AFTER_FILES" ]] && ok "--redact-only writes no file" || fail "--redact-only touched the filesystem"

echo "── [6] on-user-prompt.sh hook contract ──"

HP="$WORK/hookproj"; mkdir -p "$HP/scv"

# valid JSON → journaled (author via GIT_AUTHOR_NAME; cwd = project root)
(cd "$HP" && printf '{"prompt":"build a refund button"}' \
  | env "${GIT_ISOLATE[@]}" GIT_AUTHOR_NAME="Hook User" bash "$HOOK_PROMPT")
RC=$?
eq "valid JSON: exit 0" "0" "$RC"
HF="$HP/scv/journal/${DAY}-hook-user.md"
[[ -f "$HF" ]] && ok "hook journaled to per-author file" || fail "hook journal file missing"
grep -qF "build a refund button" "$HF" && ok "prompt content recorded" || fail "prompt content missing"
grep -qE '^### \[[0-9:]+\] user$' "$HF" && ok "hook records speaker=user" || fail "hook speaker wrong"

# hook path also redacts (defense in depth)
(cd "$HP" && printf '{"prompt":"my password=hunter2 ok"}' \
  | env "${GIT_ISOLATE[@]}" GIT_AUTHOR_NAME="Hook User" bash "$HOOK_PROMPT")
grep -qF 'password=[REDACTED]' "$HF" && ok "hook route redacts secrets" || fail "hook route did not redact"
grep -rqF 'hunter2' "$HP" && fail "hook route leaked secret" || ok "hook route left no original secret"

# invalid JSON → exit 0 AND no record
SNAP_BEFORE="$(cd "$HP" && find scv -type f -exec cksum {} + | sort)"
(cd "$HP" && printf 'this is not json {' | env "${GIT_ISOLATE[@]}" GIT_AUTHOR_NAME="Hook User" bash "$HOOK_PROMPT")
RC=$?
SNAP_AFTER="$(cd "$HP" && find scv -type f -exec cksum {} + | sort)"
eq "invalid JSON: exit 0 (non-blocking)" "0" "$RC"
[[ "$SNAP_BEFORE" == "$SNAP_AFTER" ]] && ok "invalid JSON: no record written" || fail "invalid JSON wrote something"

# JSON without prompt / empty stdin → exit 0, no record
(cd "$HP" && printf '{"no_prompt":"x"}' | bash "$HOOK_PROMPT"); eq "JSON without prompt: exit 0" "0" "$?"
(cd "$HP" && printf '' | bash "$HOOK_PROMPT"); eq "empty stdin: exit 0" "0" "$?"
SNAP_AFTER2="$(cd "$HP" && find scv -type f -exec cksum {} + | sort)"
[[ "$SNAP_BEFORE" == "$SNAP_AFTER2" ]] && ok "degenerate inputs: still no record" || fail "degenerate input wrote something"

# un-hydrated dir (no scv/) → exit 0, nothing created
NOSCV="$WORK/noscv"; mkdir -p "$NOSCV"
(cd "$NOSCV" && printf '{"prompt":"hi"}' | bash "$HOOK_PROMPT"); RC=$?
eq "no scv/: exit 0" "0" "$RC"
[[ ! -e "$NOSCV/scv" ]] && ok "no scv/: nothing created" || fail "hook created scv/ in a non-SCV project"

echo "── [6p] plain-language reminder on stdout (v0.31.0+) ──"

# The hook's stdout reaches the model every turn. In a hydrated project it
# 설정은 이제 scv/ 아래 파일에 있다 — 프로젝트 루트의 .env 는 읽히지 않는다.
write_settings() {  # <프로젝트> <JSON>
  mkdir -p "$1/scv"
  printf '%s\n' "$2" > "$1/scv/scv_settings.json"
}

# prints the answer-shape reminder unless the settings file says SCV_PLAIN_LANGUAGE=off;
# the reminder never enters the journal and never changes the exit code.
PL="$WORK/plainproj"; mkdir -p "$PL/scv"
run_pl() { (cd "$1" && printf '{"prompt":"hello"}' | env "${GIT_ISOLATE[@]}" GIT_AUTHOR_NAME="Hook User" bash "$HOOK_PROMPT"); }
OUT="$(run_pl "$PL")"; RC=$?
eq "reminder: exit 0" "0" "$RC"
grep -qF "1–2 sentences" <<<"$OUT" && ok "reminder printed when .env is absent (default on)" || fail "reminder missing with no .env"
grep -qF "SCV_PLAIN_LANGUAGE" <<<"$OUT" && ok "reminder names the off switch" || fail "reminder lacks the switch name"
[[ "$(grep -c . <<<"$OUT")" -le 24 ]] && ok "hook stdout stays within 24 lines (plain + always-on)" || fail "hook stdout longer than 24 lines"
[[ -d "$PL/scv/journal" ]] && ok "reminder path still journals the prompt" || fail "reminder path skipped journaling"
grep -rqF "1–2 sentences" "$PL/scv/journal" && fail "reminder leaked into the journal" || ok "reminder never enters the journal"
# off 는 자기 블록만 끈다 (v0.35.0+: always-on 블록은 별도 스위치 SCV_ALWAYS_ON)
_no_plain() { ! grep -qF "[SCV plain language]" <<<"$(run_pl "$1")"; }
write_settings "$PL" '{"SCV_PLAIN_LANGUAGE": "off"}'
_no_plain "$PL" && ok "off: plain block silent" || fail "off: still printed"
write_settings "$PL" '{"SCV_PLAIN_LANGUAGE": "OFF"}'
_no_plain "$PL" && ok "OFF (any case): plain block silent" || fail "OFF: still printed"
write_settings "$PL" '{"SCV_PLAIN_LANGUAGE": "off"}'
_no_plain "$PL" && ok "quoted off: plain block silent" || fail "quoted off: still printed"
write_settings "$PL" '{"SCV_PLAIN_LANGUAGE": "off", "SCV_ALWAYS_ON": "off"}'
[[ -z "$(run_pl "$PL")" ]] && ok "both switches off: fully silent" || fail "both off: still printed"
write_settings "$PL" '{"SCV_PLAIN_LANGUAGE": "maybe"}'
grep -qF "1–2 sentences" <<<"$(run_pl "$PL")" && ok "unknown value = on" || fail "unknown value silenced the reminder"
write_settings "$PL" '{"OTHER": "1", "SCV_PLAIN_LANGUAGE": "off"}'
_no_plain "$PL" && ok "off on a later line: plain block silent" || fail "off on a later line: still printed"
# sentence cap (v0.31.0+): positive integer → rendered; anything else → 2; off wins
write_settings "$PL" '{"SCV_PLAIN_MAX_SENTENCES": "4"}'
grep -qF "1–4 sentences" <<<"$(run_pl "$PL")" && ok "cap 4 → 1–4 sentences" || fail "cap 4 not rendered"
write_settings "$PL" '{"SCV_PLAIN_MAX_SENTENCES": "1"}'
grep -qF "one sentence" <<<"$(run_pl "$PL")" && ok "cap 1 → one sentence" || fail "cap 1 not rendered"
for bad in abc 0 -3 2.5 ""; do
  write_settings "$PL" "{\"SCV_PLAIN_MAX_SENTENCES\": \"$bad\"}"
  grep -qF "1–2 sentences" <<<"$(run_pl "$PL")" && ok "cap [$bad] → default 2" || fail "cap [$bad] did not fall back to 2"
done
write_settings "$PL" '{"SCV_PLAIN_LANGUAGE": "off", "SCV_PLAIN_MAX_SENTENCES": "4"}'
_no_plain "$PL" && ok "off wins over a cap" || fail "cap printed despite off"
rm -f "$PL/.env"
[[ -z "$(cd "$NOSCV" && printf '{"prompt":"hi"}' | bash "$HOOK_PROMPT")" ]] && ok "no scv/: no reminder" || fail "reminder printed outside an SCV project"
(cd "$PL" && printf 'not json' | bash "$HOOK_PROMPT" >/dev/null); eq "reminder path: invalid JSON still exit 0" "0" "$?"

echo "── [6+] on-stop.sh — non-blocking + transcript extraction ──"

(cd "$HP" && printf 'garbage' | bash "$HOOK_STOP"); eq "on-stop garbage stdin: exit 0" "0" "$?"
(cd "$HP" && printf '{"transcript_path":"/nonexistent/x.jsonl"}' | bash "$HOOK_STOP")
eq "on-stop missing transcript: exit 0 (quiet skip)" "0" "$?"

if command -v jq >/dev/null 2>&1; then
  TR="$WORK/transcript.jsonl"
  {
    printf '{"type":"user","message":{"content":[{"type":"text","text":"user turn"}]}}\n'
    printf 'this line is not json and must be tolerated\n'
    printf '{"type":"assistant","message":{"content":[{"type":"text","text":"assistant summary line"}]}}\n'
  } > "$TR"
  (cd "$HP" && printf '{"transcript_path":"%s"}' "$TR" \
    | env "${GIT_ISOLATE[@]}" GIT_AUTHOR_NAME="Hook User" bash "$HOOK_STOP")
  eq "on-stop valid transcript: exit 0" "0" "$?"
  grep -qF "assistant summary line" "$HF" && ok "on-stop appended assistant text" || fail "on-stop did not append assistant text"
  grep -qE '^### \[[0-9:]+\] assistant$' "$HF" && ok "on-stop records speaker=assistant" || fail "on-stop speaker wrong"
  grep -qF "user turn" "$HF" && fail "on-stop leaked non-assistant turns" || ok "on-stop extracts assistant turns only"

  # [6u] the byte cap must not split a multibyte character (v0.31.2): a long
  # Korean answer (3 bytes per character) forces the 4000-byte cut mid-character;
  # the journal must still be valid UTF-8 and carry the tail intact.
  TRU="$WORK/transcript-utf8.jsonl"
  KO="$(python3 -c 'print("가나다라마바사아자차카타파하" * 150)' 2>/dev/null || printf '가나다라마바사아자차카타파하%.0s' $(seq 1 150))"
  printf '{"type":"assistant","message":{"content":[{"type":"text","text":"%s END-UTF8-MARK"}]}}\n' "$KO" > "$TRU"
  HU="$WORK/utf8proj"; mkdir -p "$HU/scv"
  (cd "$HU" && printf '{"transcript_path":"%s"}' "$TRU" \
    | env "${GIT_ISOLATE[@]}" GIT_AUTHOR_NAME="Hook User" bash "$HOOK_STOP")
  eq "on-stop long multibyte transcript: exit 0" "0" "$?"
  HUF="$HU/scv/journal/${DAY}-hook-user.md"
  [[ -f "$HUF" ]] && ok "on-stop journaled the multibyte answer" || fail "on-stop wrote nothing for the multibyte answer"
  if python3 -c 'import sys; open(sys.argv[1],"rb").read().decode("utf-8")' "$HUF" 2>/dev/null \
     || { ! command -v python3 >/dev/null 2>&1 && iconv -f UTF-8 -t UTF-8 "$HUF" >/dev/null 2>&1; }; then
    ok "journal stays valid UTF-8 after the byte cap"
  else
    fail "journal contains a split multibyte character"
    # diagnostics for a host where the cleanup misbehaves: where and what
    echo "    host: $(uname -s) bash=${BASH_VERSION} head=$(command -v head) od=$(command -v od) iconv=$(command -v iconv || echo none)"
    python3 - "$HUF" <<'PYD' 2>/dev/null || true
import sys
b=open(sys.argv[1],"rb").read()
try:
    b.decode("utf-8"); print("    (decodes cleanly?)")
except UnicodeDecodeError as e:
    s=e.start; print("    invalid at byte", s, "of", len(b), "->", b[max(0,s-24):s+8])
PYD
  fi
  grep -qF "END-UTF8-MARK" "$HUF" && ok "the tail of the answer survived the cap" || fail "the answer tail was lost"
else
  ok "jq absent — on-stop extraction skipped (quiet-skip contract already verified)"
fi

echo
echo "— redaction hardening (adversarial-review reproductions) —"
r() { printf '%s' "$1" | bash "$JOURNAL" --redact-only; }
[[ "$(r '{"password": "hunter2", "api_key": "sk-live-X"}')" == '{"password": [REDACTED], "api_key": [REDACTED]}' ]] \
  && ok "quoted JSON keys redacted" || fail "quoted JSON keys leak"
[[ "$(r "'pwd': hunter2")" == "'pwd': [REDACTED]" ]] \
  && ok "single-quoted key redacted" || fail "single-quoted key leaks"
[[ "$(printf 'password:\nhunter2-m\n' | bash "$JOURNAL" --redact-only)" == $'password:\n[REDACTED]' ]] \
  && ok "multiline key:\\nvalue redacted" || fail "multiline value leaks"
[[ "$(r 'https://admin:hunter2@git.example.com/x')" == 'https://[REDACTED]@git.example.com/x' ]] \
  && ok "URL userinfo redacted" || fail "URL userinfo leaks"
[[ "$(r 'Authorization: token ghp_SECRET')" == 'Authorization: [REDACTED]' ]] \
  && ok "Authorization header redacted" || fail "Authorization header leaks"
[[ "$(r 'X-Api-Key abc123')" == 'X-Api-Key [REDACTED]' ]] \
  && ok "X-Api-Key redacted" || fail "X-Api-Key leaks"
[[ "$(r 'no secrets here, plain text')" == 'no secrets here, plain text' ]] \
  && ok "plain text untouched" || fail "plain text mangled"

# speaker label passes redaction; symlinked journal dir is refused
SPK_DIR="$WORK/spk"; mkdir -p "$SPK_DIR/scv"
( cd "$SPK_DIR" && printf 'body\n' | bash "$JOURNAL" --author t --speaker 'password=SPKLEAK' >/dev/null 2>&1 )
grep -rqF "SPKLEAK" "$SPK_DIR/scv" \
  && fail "speaker label leaked a secret" || ok "speaker label redacted"
LNK_DIR="$WORK/lnk"; mkdir -p "$LNK_DIR/scv" "$WORK/outside"
ln -s "$WORK/outside" "$LNK_DIR/scv/journal"
( cd "$LNK_DIR" && printf 'x\n' | SCV_JOURNAL_DIR=scv/journal bash "$JOURNAL" --author t >/dev/null 2>&1 )
rc=$?
[[ $rc -ne 0 && -z "$(ls -A "$WORK/outside")" ]] \
  && ok "symlinked journal dir refused (fail-closed)" || fail "write escaped through symlinked journal dir"

echo
echo "── result: PASS=$PASS FAIL=$FAIL ──"
[[ $FAIL -eq 0 ]] || exit 1
exit 0
