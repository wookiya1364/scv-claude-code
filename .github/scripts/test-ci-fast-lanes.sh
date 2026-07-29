#!/usr/bin/env bash
# Lock the fast/slow CI lane boundary without adding a YAML dependency.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"

python3 - "$REPO_ROOT" <<'PY'
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
workflow_dir = root / ".github/workflows"
workflows = {
    path.name: path.read_text()
    for path in sorted(workflow_dir.glob("*.yml"))
}
contract = workflows["core-contract.yml"]
core_sync = workflows["core-sync.yml"]
model = workflows["test-model-policy.yml"]
branch_flow = workflows["branch-flow.yml"]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")
    print(f"PASS: {message}")


require(
    re.search(r"(?m)^  push:", contract) is None
    and "workflow_dispatch:" not in contract,
    "Core contract runs only on promotion PRs",
)
require(
    "group: core-contract-${{ github.event.pull_request.number || github.ref }}"
    in contract
    and "cancel-in-progress: true" in contract,
    "stale Core contract runs are cancelled",
)
require(
    "name: Contract (${{ matrix.os }})" in contract
    and "os: [ubuntu-latest, macos-latest]" in contract
    and "timeout-minutes: 2" in contract,
    "PR smoke retains Ubuntu and macOS portability checks",
)
require(
    "- '.github/scripts/**'" in contract
    and "- '.github/workflows/**'" in contract,
    "CI implementation and policy changes trigger the contract workflow",
)
require(
    "name: Cross-platform smoke" in contract
    and "bash tests/test-core-contract.sh" in contract
    and "bash tests/run-dry.sh" in contract,
    "PR smoke covers cross-host state and shared regression",
)
require(
    "name: Detect updater changes" in contract
    and ".github/scripts/test-sync-core-smoke.sh)" in contract
    and contract.count("github.base_ref == 'develop'") == 2,
    "fast updater smoke is path-gated at the develop entry PR",
)
require(
    contract.count(
        "run: bash .github/scripts/test-sync-core-smoke.sh"
    )
    == 1,
    "automatic CI uses one representative atomic updater smoke",
)
require(
    all(
        text.count("\n    runs-on:")
        == text.count("\n    timeout-minutes: 2")
        for text in workflows.values()
    ),
    "every GitHub Actions job has a hard two-minute execution limit",
)
require(
    "test-sync-core-atomicity.sh"
    not in "\n".join(workflows.values()),
    "the complete adversarial atomicity suite never runs in GitHub Actions",
)
require(
    "bash tests/test-core-contract.sh" in core_sync
    and "bash tests/run-dry.sh" in core_sync
    and "bash tests/test-state-adapter.sh" not in core_sync,
    "Core update proposal reuses the contract without duplicate state tests",
)
require(
    re.search(r"(?m)^  push:", model) is None
    and "group: model-policy-${{ github.event.pull_request.number || github.ref }}"
    in model,
    "model-policy checks do not repeat after merge",
)
require(
    "group: branch-flow-${{ github.event.pull_request.number || github.ref }}"
    in branch_flow
    and "cancel-in-progress: true" in branch_flow,
    "stale branch-flow checks are cancelled",
)
PY
