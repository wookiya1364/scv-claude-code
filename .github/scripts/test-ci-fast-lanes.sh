#!/usr/bin/env bash
# Lock the fast/slow CI lane boundary without adding a YAML dependency.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"

python3 - "$REPO_ROOT" <<'PY'
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
contract = (root / ".github/workflows/core-contract.yml").read_text()
core_sync = (root / ".github/workflows/core-sync.yml").read_text()
model = (root / ".github/workflows/test-model-policy.yml").read_text()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")
    print(f"PASS: {message}")


require(
    re.search(r"(?m)^  push:\n    branches: \[main\]$", contract) is not None,
    "Core contract push lane is main-only",
)
require(
    "group: core-contract-${{ github.event.pull_request.number || github.ref }}"
    in contract
    and "cancel-in-progress: true" in contract,
    "stale Core contract runs are cancelled",
)
require(
    "name: Contract (${{ matrix.os }})" in contract
    and "os: [ubuntu-latest, macos-latest]" in contract,
    "PR smoke retains Ubuntu and macOS portability checks",
)
require(
    "- '.github/scripts/**'" in contract,
    "CI policy script changes trigger the contract workflow",
)
require(
    "name: Cross-platform smoke" in contract
    and "bash tests/test-state-adapter.sh" in contract
    and "bash tests/run-dry.sh" in contract,
    "PR smoke covers cross-host state and shared regression",
)
require(
    "name: Detect atomic sync changes" in contract
    and "tests/test-sync-core-atomicity.sh)" in contract
    and contract.count("github.base_ref == 'develop'") == 2,
    "PR atomicity is path-gated and runs only at the develop entry gate",
)
require(
    contract.count("run: bash tests/test-sync-core-atomicity.sh") == 2,
    "full atomicity exists only in conditional Ubuntu and main macOS lanes",
)
require(
    "name: Full contract (macos-latest)" in contract
    and "timeout-minutes: 25" in contract,
    "main has one bounded full macOS release gate",
)
require(
    "bash tests/test-sync-core-atomicity.sh" not in core_sync
    and "bash tests/test-state-adapter.sh" in core_sync,
    "Core update proposal runs smoke and leaves heavy testing to PR CI",
)
require(
    re.search(r"(?m)^  push:", model) is None
    and "group: model-policy-${{ github.event.pull_request.number || github.ref }}"
    in model,
    "model-policy checks do not repeat after merge",
)
PY
