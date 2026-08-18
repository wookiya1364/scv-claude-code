#!/usr/bin/env bash
# sync's dirty refusal — the rule that replaced .scv-backup/.
#
# The old backup machinery answered "how do I get the old content back" with a
# gitignored snapshot directory, while the retired-docs pass in the same script
# answered "git history". One file, two answers. Now there is one: a file git
# can restore may be replaced, a file git cannot restore is refused by name.
# These cases pin the refusal down from both sides — what must be refused, and
# what must still flow.

set -uo pipefail

# Layout-agnostic payload resolution — this file is projected into wrappers
# exactly like test-guard.sh, and inherits the same root-search obligation.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE=""
for up in "$HERE/.." "$HERE/../.."; do
  for sub in core vendor/scv-core/core plugins/scv/vendor/scv-core/core; do
    if [[ -f "$up/$sub/scripts/sync.sh" ]]; then
      CORE="$(cd "$up/$sub" && pwd)"; break 2
    fi
  done
done
[[ -n "$CORE" ]] || { echo "test-sync-dirty: payload not found from $HERE" >&2; exit 1; }
SYNC="$CORE/scripts/sync.sh"
HYDRATE="$CORE/scripts/hydrate.sh"

PASS=0; FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $1"; [[ $# -gt 1 ]] && printf '      %s\n' "$2"; FAIL=$((FAIL+1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

# mk_project <name> [nogit] — hydrated project, committed unless nogit
mk_project() {
  local d="$WORK/$1"
  mkdir -p "$d"
  ( cd "$d"
    if [[ "${2:-}" != "nogit" ]]; then
      git init -q .
      git config user.email t@e; git config user.name t
    fi
    bash "$HYDRATE" init . >/dev/null 2>&1
    if [[ "${2:-}" != "nogit" ]]; then
      git add -A >/dev/null 2>&1 && git commit -qm seed >/dev/null 2>&1
    fi
  ) || { echo "mk_project $1 failed" >&2; exit 1; }
  printf '%s' "$d"
}

# The overwrite-policy file this suite bends. If the policy ever changes, the
# cases below stop testing what they claim to — fail loudly instead.
TARGET="scv/PROMOTE.md"
grep -q '^merge_policy: overwrite' "$CORE/template/scv/PROMOTE.md" \
  || { echo "test-sync-dirty: $TARGET is no longer merge_policy: overwrite — retarget this suite" >&2; exit 1; }

echo "=== T1 — no snapshot directory, ever ==="
P="$(mk_project t1)"
( cd "$P" && printf '\nlocal drift\n' >> "$TARGET" && git commit -qam drift )
out="$(bash "$SYNC" --project-dir "$P" 2>&1)"
grep -q 'local drift' "$P/$TARGET" && fail "T1 a committed drift was not overwritten" \
                                   || pass "T1 a committed drift is overwritten (git holds the old content)"
[[ -e "$P/.scv-backup" ]] && fail "T1 .scv-backup was created" || pass "T1 no .scv-backup directory"
grep -q 'Backups:' <<<"$out" && fail "T1 a Backups report survived" || pass "T1 no Backups report"

echo "=== T2 — an uncommitted change refuses by name ==="
P="$(mk_project t2)"
( cd "$P" && printf '\nuncommitted work\n' >> "$TARGET" )
out="$(bash "$SYNC" --project-dir "$P" 2>&1)"
grep -q 'uncommitted work' "$P/$TARGET" && pass "T2 the dirty file was not touched" \
                                        || fail "T2 the dirty file was overwritten — work lost"
grep -q "DIRTY.*$TARGET" <<<"$out" && pass "T2 the refusal names the file" \
                                   || fail "T2 no DIRTY report" "$out"
out="$(bash "$SYNC" --project-dir "$P" --force "$TARGET" 2>&1)"
grep -q 'uncommitted work' "$P/$TARGET" && fail "T2 --force did not override" \
                                        || pass "T2 --force overrides the refusal"

echo "=== T3 — no git history means no overwrite ==="
P="$(mk_project t3)"
( cd "$P" && git rm -q --cached "$TARGET" && git commit -qm untrack \
  && printf '\nuntracked variant\n' >> "$TARGET" )
out="$(bash "$SYNC" --project-dir "$P" 2>&1)"
grep -q 'untracked variant' "$P/$TARGET" && pass "T3 an untracked differing file is refused" \
                                         || fail "T3 an untracked file was overwritten — unrecoverable"
P="$(mk_project t3b nogit)"
printf '\nno repo here\n' >> "$P/$TARGET"
out="$(bash "$SYNC" --project-dir "$P" 2>&1)"
grep -q 'no repo here' "$P/$TARGET" && pass "T3 outside a git work tree every differing file is refused" \
                                    || fail "T3 a no-git project was overwritten"
grep -q 'DIRTY' <<<"$out" && pass "T3 the no-git refusal is reported" || fail "T3 silent refusal" "$out"

echo "=== T4 — identical files stay silent (first sync after hydrate) ==="
# Right after hydrate, before any commit, every file is untracked AND equal to
# the template. The equality check must run before the dirty check, or the
# first sync a project ever sees would drown in refusals.
P="$WORK/t4"; mkdir -p "$P"
( cd "$P" && git init -q . && git config user.email t@e && git config user.name t \
  && bash "$HYDRATE" init . >/dev/null 2>&1 )
out="$(bash "$SYNC" --project-dir "$P" 2>&1)"
grep -q 'DIRTY' <<<"$out" && fail "T4 identical untracked files were reported dirty" "$out" \
                          || pass "T4 identical files skip before the dirty check"

echo "=== T5 — merge-on-markers respects the same refusal ==="
P="$(mk_project t5)"
( cd "$P" && printf '\nedit outside markers\n' >> scv/SCV.md )
out="$(bash "$SYNC" --project-dir "$P" 2>&1)"
if grep -q 'edit outside markers' "$P/scv/SCV.md"; then
  # Either the merge preserved it (template unchanged → cmp equal is impossible
  # here since we appended) or the refusal fired. Both keep the edit; the
  # refusal is the one that reports it.
  grep -q "DIRTY.*SCV.md" <<<"$out" && pass "T5 a locally edited SCV.md is refused, not merged over" \
                                    || fail "T5 the edit survived but no DIRTY report explains why" "$out"
else
  fail "T5 a local edit outside PROJECT:LOCAL was lost to the merge"
fi

echo "=== T6 — a committed divergence still merges (the refusal is only for the unrestorable) ==="
P="$(mk_project t6)"
( cd "$P"
  perl -0pi -e 's/(<!-- PROJECT:LOCAL START -->).*?(<!-- PROJECT:LOCAL END -->)/$1\nkeep-me: local rule\n$2/s' scv/SCV.md
  printf '\ncommitted note outside markers\n' >> scv/SCV.md
  git commit -qam customized )
out="$(bash "$SYNC" --project-dir "$P" 2>&1)"
grep -q "MERGE.*SCV.md" <<<"$out" && pass "T6 a committed divergence takes the MERGE path" \
                                  || fail "T6 no MERGE for a committed divergence" "$out"
grep -q 'keep-me: local rule' "$P/scv/SCV.md" && pass "T6 the PROJECT:LOCAL block survived the merge" \
                                              || fail "T6 the merge lost the PROJECT:LOCAL block"
grep -q 'committed note outside markers' "$P/scv/SCV.md" && fail "T6 the outside-marker edit survived — merge did not run" \
                                                         || pass "T6 the outside-marker edit was replaced (git holds it)"

echo "=== T7 — a symlinked doc is never written through ==="
# git status reports a tracked symlink as clean, and cp would write through it
# into a file that lives outside the repo — bytes git never stored. The
# adversarial review destroyed an 853-line file this way.
P="$(mk_project t7)"
mkdir -p "$WORK/outside"
printf 'IRREPLACEABLE NOTES\n' > "$WORK/outside/notes.md"
( cd "$P" && rm "$TARGET" && ln -s "$WORK/outside/notes.md" "$TARGET" \
  && git add -A && git commit -qm link )
out="$(bash "$SYNC" --project-dir "$P" 2>&1)"
grep -q 'IRREPLACEABLE NOTES' "$WORK/outside/notes.md" && pass "T7 the link target is untouched" \
                                                       || fail "T7 sync wrote through the symlink"
grep -q "DIRTY.*$TARGET" <<<"$out" && pass "T7 the symlink is refused by name" \
                                   || fail "T7 no refusal for the symlink" "$out"

echo "=== T8 — a symlinked scv/ directory skips the whole template pass ==="
P="$WORK/t8"; mkdir -p "$P" "$WORK/shared-scv"
( cd "$P" && git init -q . && git config user.email t@e && git config user.name t )
( cd "$WORK" && cp -R "$(dirname "$(mk_project t8seed)")/t8seed/scv/." "$WORK/shared-scv/" )
printf 'SHARED TEAM CONTENT\n' >> "$WORK/shared-scv/PROMOTE.md"
ln -s "$WORK/shared-scv" "$P/scv"
( cd "$P" && git add -A >/dev/null 2>&1 && git commit -qm seed >/dev/null 2>&1 )
out="$(bash "$SYNC" --project-dir "$P" 2>&1)"
grep -q 'SHARED TEAM CONTENT' "$WORK/shared-scv/PROMOTE.md" && pass "T8 the shared tree is untouched" \
                                                            || fail "T8 sync wrote into the symlinked directory"
grep -q "WARN.*symlinked directory" <<<"$out" && pass "T8 the skip is reported once" \
                                              || fail "T8 no WARN for the symlinked scv/" "$out"

echo "=== T9 — a refusal keeps the version stamp where it was ==="
# Advancing the stamp past a refused file would mark the migration complete
# while the stale file stays stale forever — and the automatic refresh, gated
# on that stamp, would never retry.
P="$(mk_project t9)"
# perl -pi, not sed -i — BSD sed treats the expression as a backup suffix.
perl -pi -e 's|<!-- STANDARD:VERSION -->[^<]*<!-- /STANDARD:VERSION -->|<!-- STANDARD:VERSION -->2.0.0<!-- /STANDARD:VERSION -->|' "$P/scv/SCV.md"
( cd "$P" && git commit -qam stale && printf '\nuncommitted work\n' >> "$TARGET" )
out="$(bash "$SYNC" --project-dir "$P" 2>&1)"
stamp="$(sed -n 's/.*<!-- STANDARD:VERSION -->\(.*\)<!-- \/STANDARD:VERSION -->.*/\1/p' "$P/scv/SCV.md" | head -1)"
[[ "$stamp" == "2.0.0" ]] && pass "T9 the stamp did not advance past the refusal" \
                          || fail "T9 the stamp advanced to $stamp while $TARGET was refused"
( cd "$P" && git commit -qam keep >/dev/null 2>&1 )
out="$(bash "$SYNC" --project-dir "$P" 2>&1)"
stamp="$(sed -n 's/.*<!-- STANDARD:VERSION -->\(.*\)<!-- \/STANDARD:VERSION -->.*/\1/p' "$P/scv/SCV.md" | head -1)"
[[ "$stamp" != "2.0.0" ]] && pass "T9 after the user commits, the next run completes and stamps" \
                          || fail "T9 the retry did not converge"
grep -q "STAMP.*SCV.md" <<<"$out" && pass "T9 the stamp write is reported, not silent" \
                                  || fail "T9 no STAMP line in the report" "$out"

echo "=== T10 — assume-unchanged does not fool the refusal ==="
P="$(mk_project t10)"
( cd "$P" && printf '\nLOCAL-ONLY CONFIG\n' >> "$TARGET" \
  && git update-index --assume-unchanged "$TARGET" )
out="$(bash "$SYNC" --project-dir "$P" 2>&1)"
grep -q 'LOCAL-ONLY CONFIG' "$P/$TARGET" && pass "T10 assume-unchanged content survived" \
                                         || fail "T10 sync trusted git status and destroyed assume-unchanged content"

echo
echo "  passed: $PASS  failed: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
