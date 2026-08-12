#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f core.lock ]] || fail "root core.lock is absent"
[[ -d vendor/scv-core/core ]] || fail "vendored core payload is absent"
[[ -f adapter/claude-code.env ]] || fail "Claude host profile is absent"
[[ -x adapter/scripts/state-index.sh ]] || fail "state-index adapter is absent"
grep -qxF \
  'CORE_STATE_INDEX="$WRAPPER_ROOT/vendor/scv-core/core/scripts/state-index.sh"' \
  adapter/scripts/state-index.sh ||
  fail "state-index adapter does not select the vendored Core resolver"
grep -qxF 'exec "$CORE_STATE_INDEX" "$@"' adapter/scripts/state-index.sh ||
  fail "state-index adapter does not preserve argv during delegation"
if grep -qF '<!-- SCV:HOST-POINTER target=SCV.md -->' \
  adapter/scripts/state-index.sh; then
  fail "state-index adapter duplicates the Core pointer resolver"
fi

./scripts/verify-core.sh

grep -qx 'SCV_ACTION_TEMPLATE=/scv:{action}' adapter/claude-code.env ||
  fail "Claude action template is not /scv:{action}"
grep -qx 'SCV_ARGUMENT_STYLE=template-string' adapter/claude-code.env ||
  fail "Claude argument materialization is not template-string"
grep -qx 'SCV_STATE_INDEX=SCV.md' adapter/claude-code.env ||
  fail "shared state index is not SCV.md"
grep -qx 'SCV_LEGACY_STATE_INDEXES=CLAUDE.md|CODEX.md' adapter/claude-code.env ||
  fail "cross-host legacy state fallback is missing"
grep -qx 'SCV_ROOT_ENV=CLAUDE_PLUGIN_ROOT' adapter/claude-code.env ||
  fail "Claude plugin root contract is missing"
wrapper_version=$(tr -d '[:space:]' < VERSION)
[[ "$(python3 -c 'import json; print(json.load(open(".claude-plugin/plugin.json"))["version"])')" == "$wrapper_version" ]] ||
  fail "Claude plugin manifest version does not match wrapper VERSION"
[[ "$(python3 -c 'import json; print(next(item["version"] for item in json.load(open(".claude-plugin/marketplace.json"))["plugins"] if item["name"] == "scv"))')" == "$wrapper_version" ]] ||
  fail "Claude marketplace version does not match wrapper VERSION"
[[ "$(python3 -c 'import json; print(json.load(open("core.lock"))["source_manifest_sha256"])')" =~ ^[0-9a-f]{64}$ ]] ||
  fail "source manifest digest is absent from core.lock"
[[ ! -e template/scv/CLAUDE.md && ! -e template/scv/CODEX.md ]] ||
  fail "new hydrate template contains a host-specific state pointer"
[[ ! -e template/loop-runner.md ]] ||
  fail "adapter integration template leaked into project hydrate payload"
if grep -RInE '/scv:|\$scv:|Claude Code|Codex' template; then
  fail "host-specific syntax leaked into the shared hydrate template"
fi

for action in \
  codegen deck handoff help install-deps promote regression report \
  routine set-models status sync update work workspace; do
  [[ -f "commands/$action.md" ]] || fail "missing commands/$action.md"
  grep -q "^model: " "commands/$action.md" ||
    fail "commands/$action.md lost Claude model metadata"
done

# The frontmatter must actually parse, and every command must say *when* to
# reach for it. A description that only states what the command does gives the
# model no reason to run it when the user asks in plain language — it writes the
# output itself instead, which is the failure this contract exists to prevent.
# Parsing is checked here because a stray quote inside the description silently
# breaks discovery: the file still looks right to grep.
python3 - <<'PYCHECK' || fail 'command frontmatter is unparseable or lacks an invocation trigger'
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    print("SKIP: PyYAML unavailable; frontmatter parse check skipped")
    sys.exit(0)

failures = []
for path in sorted(Path("commands").glob("*.md")):
    text = path.read_text()
    parts = text.split("---")
    if len(parts) < 3:
        failures.append(f"{path}: no frontmatter block")
        continue
    try:
        data = yaml.safe_load(parts[1])
    except yaml.YAMLError as exc:
        first = str(exc).splitlines()[0]
        failures.append(f"{path}: frontmatter does not parse ({first})")
        continue
    description = (data or {}).get("description", "")
    if "Use when" not in description:
        failures.append(f"{path}: description never says when to use the command")

for line in failures:
    print(f"FAIL: {line}")
sys.exit(1 if failures else 0)
PYCHECK
echo "PASS: command frontmatter parses and states when to invoke"

python3 - <<'PY' || fail '$ARGUMENTS leaked into a pre-model shell block'
from pathlib import Path

failures = []
for directory in (Path("commands"), Path("protocols")):
    for path in sorted(directory.glob("*.md")):
        in_pre_model_shell = False
        for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            stripped = line.strip()
            if not in_pre_model_shell and stripped.startswith("```!"):
                in_pre_model_shell = True
                continue
            if in_pre_model_shell and stripped == "```":
                in_pre_model_shell = False
                continue
            if in_pre_model_shell and "$ARGUMENTS" in line:
                failures.append(f"{path}:{line_number}")
if failures:
    raise SystemExit(
        "unsafe raw argument substitution in pre-model shell block: "
        + ", ".join(failures)
    )
PY

grep -q '/plugin marketplace update' commands/update.md ||
  fail "Claude update guide was not kept adapter-owned"
grep -q 'SCV_MODEL_POLICY' scripts/apply-model-policy.sh ||
  fail "Claude model-policy adapter is missing"

if grep -RInE \
  --exclude='test-core-contract.sh' \
  --exclude-dir=vendor \
  '\$scv:|allow_implicit_invocation|\.codex-plugin|CODEX_PLUGIN_ROOT' \
  adapter commands .claude-plugin scripts README.md README.ko.md README.ja.md; then
  fail "Codex-only syntax leaked into the Claude adapter"
fi

bash tests/test-state-adapter.sh

echo "PASS: Claude wrapper/core contract"
