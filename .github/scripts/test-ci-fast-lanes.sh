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
    re.search(r"(?m)^  push:\n    branches: \[main, stage, develop\]", contract)
    is not None
    and "workflow_dispatch:" not in contract,
    "Core contract runs on promotion PRs and channel pushes (main run record)",
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
# The two-minute cap exists so automatic CI gives fast feedback. promote.yml is
# not CI: it is a manually triggered orchestrator whose whole job is waiting for
# other workflows' checks, so a two-minute cap would guarantee failure. It stays
# out of this rule and is capped separately below.
AUTOMATIC_CI = {
    name: text for name, text in workflows.items() if name != "promote.yml"
}
require(
    all(
        text.count("\n    runs-on:")
        == text.count("\n    timeout-minutes: 2")
        for text in AUTOMATIC_CI.values()
    ),
    "every automatic CI job has a hard two-minute execution limit",
)
require(
    "workflow_dispatch:" in workflows["promote.yml"]
    and "\n  push:" not in workflows["promote.yml"]
    and "\n  schedule:" not in workflows["promote.yml"]
    and "\n  pull_request:" not in workflows["promote.yml"],
    "the promotion orchestrator is manual only — never automatic",
)
require(
    workflows["promote.yml"].count("\n    runs-on:")
    == workflows["promote.yml"].count("\n    timeout-minutes: 45"),
    "the promotion orchestrator is still bounded (45 minutes)",
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
    re.search(r"(?m)^  push:\n    branches: \[main, stage, develop\]", model)
    is not None
    and "group: model-policy-${{ github.event.pull_request.number || github.ref }}"
    in model,
    "model-policy runs on PRs and channel pushes without duplicate concurrent runs",
)
require(
    "group: branch-flow-${{ github.event.pull_request.number || github.ref }}"
    in branch_flow
    and "cancel-in-progress: true" in branch_flow,
    "stale branch-flow checks are cancelled",
)
PY
