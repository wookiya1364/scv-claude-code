#!/usr/bin/env bash
# test-readpath-lifecycle.sh — regression tests for the raw-doc lifecycle:
# consume (move to scv/raw/stale/ + ref_docs provenance), unused, refs,
# lifecycle-counts, outdated heuristic, v1→v2 state compatibility, and the
# fail-closed consume preflight.
set -uo pipefail

HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCRIPTS="$HERE/../scripts"
RP="$SCRIPTS/readpath.sh"

pass=0; fail=0
ck() {  # desc expected actual
  if [[ "$2" == "$3" ]]; then pass=$((pass+1)); # echo "  ✓ $1";
  else echo "  ✗ $1 — expected [$2] got [$3]"; fail=$((fail+1)); fi
}
ok() {  # desc cmd... (expect exit 0)
  if "${@:2}" >/dev/null 2>&1; then pass=$((pass+1)); else echo "  ✗ $1 (expected success)"; fail=$((fail+1)); fi
}
no() {  # desc cmd... (expect non-zero)
  if "${@:2}" >/dev/null 2>&1; then echo "  ✗ $1 (expected failure)"; fail=$((fail+1)); else pass=$((pass+1)); fi
}

BASE=$(mktemp -d)
trap 'rm -rf "$BASE"' EXIT

P="$BASE/proj"
mkdir -p "$P/scv/raw/topic"
( cd "$P" && git init -q && git config user.email t@t && git config user.name t \
  && git commit -q --allow-empty -m init )
printf 'readme' > "$P/scv/raw/README.md"
printf 'mentions core/scripts/foo.sh here' > "$P/scv/raw/a.md"
printf 'plain note' > "$P/scv/raw/topic/b.md"
printf 'keep' > "$P/scv/raw/.gitkeep"

run() { ( cd "$P" && bash "$RP" "$@" ); }

# ---- unused: excludes README.md / .gitkeep, includes subdirs ----
ck "unused lists both docs"        "2" "$(run unused | grep -c .)"
ck "unused excludes README"        "0" "$(run unused | grep -c README)"
ck "unused excludes .gitkeep"      "0" "$(run unused | grep -c gitkeep)"
ck "lifecycle-counts before"       "unused=2 stale=0" "$(run lifecycle-counts)"

# ---- consume: moves, records ref_docs, refreshes snapshot ----
run update >/dev/null
OUT=$(run consume 20260804-t-feat1 scv/raw/a.md scv/raw/topic/b.md)
ck "consume reports MOVED a.md"    "1" "$(printf '%s\n' "$OUT" | grep -c $'^MOVED\tscv/raw/a.md\tscv/raw/stale/a.md$')"
ck "consume preserves subdirs"     "1" "$(printf '%s\n' "$OUT" | grep -c $'^MOVED\tscv/raw/topic/b.md\tscv/raw/stale/topic/b.md$')"
ck "a.md moved on disk"            "1" "$( [[ -f "$P/scv/raw/stale/a.md" && ! -e "$P/scv/raw/a.md" ]] && echo 1 || echo 0 )"
ck "ref_docs has slug"             "1" "$(run refs scv/raw/stale/a.md | grep -c '20260804-t-feat1')"
ck "unused now empty"              "0" "$(run unused | grep -c .)"
ck "lifecycle-counts after"        "unused=0 stale=2" "$(run lifecycle-counts)"
ck "diff clean after consume"      "" "$(run diff)"

# ---- re-consume from stale/: slug accumulates, no move ----
OUT=$(run consume 20260804-t-feat2 scv/raw/stale/a.md)
ck "re-consume reports KEPT"       "1" "$(printf '%s\n' "$OUT" | grep -c $'^KEPT\tscv/raw/stale/a.md$')"
REFS=$(run refs scv/raw/stale/a.md)
ck "slugs accumulate"              "1" "$(printf '%s\n' "$REFS" | grep -c '20260804-t-feat1,20260804-t-feat2')"

# ---- collision: same filename consumed twice → suffixed ----
printf 'second a' > "$P/scv/raw/a.md"
OUT=$(run consume 20260804-t-feat3 scv/raw/a.md)
ck "collision suffixes -2"         "1" "$(printf '%s\n' "$OUT" | grep -c $'^MOVED\tscv/raw/a.md\tscv/raw/stale/a-2.md$')"
ck "original stale intact"         "1" "$(grep -c 'core/scripts/foo.sh' "$P/scv/raw/stale/a.md")"

# ---- update preserves ref_docs ----
run update >/dev/null
ck "update keeps ref entries"      "3" "$(run refs | grep -c .)"

# ---- v1 legacy state stays readable (diff works, no crash) ----
V1="$BASE/v1.json"
printf '{\n  "version": 1,\n  "updated_at": "x",\n  "files": {\n    "scv/raw/gone.md": { "size": 3, "mtime": "t" }\n  }\n}\n' > "$V1"
ok "diff against v1 state runs"    bash -c "cd '$P' && STATE_FILE='$V1' bash '$RP' diff; [[ \$? -eq 2 ]]"
ck "v1 state: refs empty"          "0" "$(cd "$P" && STATE_FILE="$V1" bash "$RP" refs | grep -c .)"

# ---- consume preflight is fail-closed ----
no "reject path traversal"         bash -c "cd '$P' && bash '$RP' consume s scv/raw/../x.md"
no "reject outside raw dir"        bash -c "cd '$P' && bash '$RP' consume s scv/promote/x.md"
no "reject README"                 bash -c "cd '$P' && bash '$RP' consume s scv/raw/README.md"
no "reject missing file"           bash -c "cd '$P' && bash '$RP' consume s scv/raw/nope.md"
no "reject invalid slug"           bash -c "cd '$P' && bash '$RP' consume 'bad slug' scv/raw/stale/a.md"
ln -s /etc/hostname "$P/scv/raw/link.md"
no "reject symlink"                bash -c "cd '$P' && bash '$RP' consume s scv/raw/link.md"
rm -f "$P/scv/raw/link.md"
# a bad path in the batch aborts before anything moves
printf 'x' > "$P/scv/raw/good.md"
no "batch with bad path fails"     bash -c "cd '$P' && bash '$RP' consume s scv/raw/good.md scv/raw/nope.md"
ck "good.md not moved on abort"    "1" "$( [[ -f "$P/scv/raw/good.md" ]] && echo 1 || echo 0 )"

# ---- outdated heuristic ----
( cd "$P" && mkdir -p core/scripts && printf 'v1' > core/scripts/foo.sh \
  && git add -A && git commit -q -m base )
run consume 20260804-t-feat4 scv/raw/stale/a.md >/dev/null   # re-stamp ref_commit at HEAD
( cd "$P" && printf 'v2' > core/scripts/foo.sh && git add -A && git commit -q -m change )
OUT=$(run outdated; true)
ck "flags doc mentioning changed file" "1" "$(printf '%s\n' "$OUT" | grep -c $'^OUTDATED-CANDIDATE\tscv/raw/stale/a.md\tcore/scripts/foo.sh')"
ck "unrelated doc not flagged"         "0" "$(printf '%s\n' "$OUT" | grep 'topic/b.md' | grep -c 'OUTDATED-CANDIDATE')"
ok "outdated exits 2 on candidates"    bash -c "cd '$P' && bash '$RP' outdated >/dev/null; [[ \$? -eq 2 ]]"

# no candidates → exit 0 (fresh consume at current HEAD)
run consume 20260804-t-feat5 scv/raw/stale/a.md >/dev/null
ok "outdated exits 0 when fresh"       bash -c "cd '$P' && bash '$RP' outdated >/dev/null"

# ---- review fixes: field integrity with empty ref_commit (no-git repo) ----
P2="$BASE/nogit"
mkdir -p "$P2/scv/raw"
printf 'x' > "$P2/scv/raw/n.md"
( cd "$P2" && bash "$RP" consume s1 scv/raw/n.md >/dev/null )
R2=$(cd "$P2" && bash "$RP" refs)
ck "empty commit → '-' placeholder (no field shift)" "1" \
  "$(printf '%s\n' "$R2" | awk -F'\t' '$3=="-" && $4 ~ /^2/ {print 1}' | head -1)"
( cd "$P2" && bash "$RP" update >/dev/null )
ck "update keeps consumed_at out of ref_commit" "0" "$(grep -c '"ref_commit": "2' "$P2/scv/readpath.json")"

# ---- review fixes: pretty-printed (jq-style) state survives refs/update ----
P3="$BASE/pretty"
mkdir -p "$P3/scv/raw/stale"
printf 'x' > "$P3/scv/raw/stale/p.md"
printf 'y' > "$P3/scv/raw/stale/q.md"
cat > "$P3/scv/readpath.json" <<'EOF'
{
  "version": 2,
  "updated_at": "t",
  "files": {
    "scv/raw/stale/p.md": {
      "size": 1,
      "mtime": "t"
    },
    "scv/raw/stale/q.md": {
      "size": 1,
      "mtime": "t"
    }
  },
  "ref_docs": {
    "scv/raw/stale/p.md": {
      "slugs": [
        "s1",
        "s2"
      ],
      "ref_commit": "abc1234",
      "consumed_at": "2026-08-04T00:00:00Z",
      "origin": "scv/raw/p.md"
    },
    "scv/raw/stale/q.md": {
      "slugs": ["s3"],
      "ref_commit": "abc1234",
      "consumed_at": "2026-08-04T00:00:00Z",
      "origin": "scv/raw/q.md"
    }
  }
}
EOF
R3=$(cd "$P3" && bash "$RP" refs)
ck "pretty state: both entries parsed"     "2" "$(printf '%s\n' "$R3" | grep -c .)"
ck "pretty state: multiline slugs joined"  "1" "$(printf '%s\n' "$R3" | grep -c $'\ts1,s2\t')"
( cd "$P3" && bash "$RP" update >/dev/null )
ck "pretty state: update preserves both"   "2" "$(cd "$P3" && bash "$RP" refs | grep -c .)"
ck "pretty state: origin preserved"        "1" "$(grep -c '"origin": "scv/raw/p.md"' "$P3/scv/readpath.json")"

# ---- review fixes: shared source across folders → REMAPPED, not error ----
P4="$BASE/shared"
mkdir -p "$P4/scv/raw"
( cd "$P4" && git init -q && git config user.email t@t && git config user.name t \
  && git commit -q --allow-empty -m init )
printf 'shared' > "$P4/scv/raw/shared.md"
printf 'bonly'  > "$P4/scv/raw/b-only.md"
( cd "$P4" && bash "$RP" consume folder-a scv/raw/shared.md >/dev/null )
OUT=$(cd "$P4" && bash "$RP" consume folder-b scv/raw/shared.md scv/raw/b-only.md)
ck "shared source → REMAPPED"          "1" "$(printf '%s\n' "$OUT" | grep -c $'^REMAPPED\tscv/raw/shared.md\tscv/raw/stale/shared.md$')"
ck "shared source: both slugs"         "1" "$(cd "$P4" && bash "$RP" refs scv/raw/stale/shared.md | grep -c 'folder-a,folder-b')"
ck "b-only still moved"                "1" "$( [[ -f "$P4/scv/raw/stale/b-only.md" ]] && echo 1 || echo 0 )"

# ---- review fixes: duplicate args rejected atomically ----
printf 'd' > "$P4/scv/raw/dup.md"
no "duplicate path args rejected"      bash -c "cd '$P4' && bash '$RP' consume s scv/raw/dup.md scv/raw/dup.md"
ck "dup.md untouched after reject"     "1" "$( [[ -f "$P4/scv/raw/dup.md" ]] && echo 1 || echo 0 )"
no "path variant (//) counts as dup"   bash -c "cd '$P4' && bash '$RP' consume s scv/raw/dup.md scv/raw//dup.md"

# ---- review fixes: path variants normalize to one entry ----
( cd "$P4" && bash "$RP" consume s-norm scv/raw//dup.md >/dev/null )
ck "// variant normalized in entry"    "1" "$(cd "$P4" && bash "$RP" refs scv/raw/stale/dup.md | grep -c 's-norm')"

# ---- review fixes: symlinked dir component rejected ----
mkdir -p "$P4/outside"
ln -s ../../outside "$P4/scv/raw/linkdir"
printf 'x' > "$P4/outside/esc.md"
no "symlinked dir component rejected"  bash -c "cd '$P4' && bash '$RP' consume s scv/raw/linkdir/esc.md"
rm -f "$P4/scv/raw/linkdir"

# ---- review fixes: spaces in filenames survive diff/status-counts ----
P5="$BASE/spaces"
mkdir -p "$P5/scv/raw"
printf 'x' > "$P5/scv/raw/my note.md"
( cd "$P5" && bash "$RP" update >/dev/null )
ok "diff with space filename exits 0"  bash -c "cd '$P5' && bash '$RP' diff"
printf 'y' > "$P5/scv/raw/other.md"
ok "diff detects change (exit 2)"      bash -c "cd '$P5' && bash '$RP' diff >/dev/null; [[ \$? -eq 2 ]]"
ck "status-counts sees the add"        "1" "$(cd "$P5" && bash "$RP" status-counts | grep -c 'added=1')"

# ---- review fixes: unsafe filenames skipped/rejected, state stays valid ----
printf 'x' > "$P5/scv/raw/we\"ird.md"
( cd "$P5" && bash "$RP" update >/dev/null 2>&1 )
ok "state stays parseable JSON"        python3 -c "import json;json.load(open('$P5/scv/readpath.json'))"
no "consume rejects quoted filename"   bash -c "cd '$P5' && bash '$RP' consume s 'scv/raw/we\"ird.md'"

# ---- review fixes: monorepo module via env overrides ----
P6="$BASE/mono"
mkdir -p "$P6/scv/raw" "$P6/FE/scv/raw"
( cd "$P6" && git init -q && git config user.email t@t && git config user.name t \
  && git commit -q --allow-empty -m init )
printf 'fe' > "$P6/FE/scv/raw/design.md"
OUT=$(cd "$P6" && RAW_DIR=FE/scv/raw STATE_FILE=FE/scv/readpath.json bash "$RP" consume fe-slug FE/scv/raw/design.md)
ck "module consume via env overrides"  "1" "$(printf '%s\n' "$OUT" | grep -c $'^MOVED\tFE/scv/raw/design.md\tFE/scv/raw/stale/design.md$')"
ck "module state written to module"    "1" "$( [[ -f "$P6/FE/scv/readpath.json" && ! -f "$P6/scv/readpath.json" ]] && echo 1 || echo 0 )"

echo ""
echo "── test-readpath-lifecycle: $pass passed, $fail failed ──"
exit $(( fail > 0 ? 1 : 0 ))
