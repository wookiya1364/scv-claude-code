// change-map-evidence.mjs — 변경 지도의 효과부 (v0.52.0+).
//
// 하는 일 하나: 단계 이름들을 받아 Graft 어댑터에게 "이 이름이 코드에 있나" 를 묻고,
// 그 답을 순수부가 쓰는 모양으로 돌려준다. 실패·부재·시간초과는 전부 빈 근거로 흡수한다 —
// 문서 생성은 어떤 경우에도 끝까지 간다.
//
// 원칙(어댑터와 동일): 설치·init·build·훅·MCP 를 절대 부르지 않는다. 읽기만 한다.

import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { resolve } from "node:path";

// 어댑터가 사람에게 보여주는 후보 줄의 모양: "  <경로:줄> — <이름>".
// 어댑터의 JSON 정규화를 그대로 쓰기 위해 --json 이 아니라 이 형태를 읽는다 —
// Graft 의 원본 JSON 모양은 문서화돼 있지 않고, 그 추정은 어댑터가 이미 떠안고 있다.
const ASK_LINE = /^\s*(\S.*?)\s+—\s+(.+?)\s*$/;
const MAX_ASKS = 12; // 그림에 들어갈 만큼만 묻는다. 계획이 길어도 비용이 선형으로 늘지 않는다.

/** graft.sh 의 자리. 이 파일은 deckdoc/ 안에 있고 어댑터는 core/scripts/ 에 있다. */
function adapterPath(coreRoot) {
  return resolve(coreRoot, "scripts", "graft.sh");
}

/** 어댑터를 한 번 부른다. 어떤 실패든 빈 문자열. */
function runAdapter(sh, args, cwd, timeoutMs) {
  try {
    const r = spawnSync("bash", [sh, ...args], {
      cwd,
      timeout: timeoutMs,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    });
    if (!r || r.error || r.status !== 0) return "";
    return String(r.stdout || "");
  } catch {
    return "";
  }
}

/**
 * <단계 이름들> → { known: Set<이름>, callers: {이름: [곳]}, status: <어댑터 상태> }.
 *
 * 어댑터가 ready 가 아니면 즉시 빈 근거를 돌려준다 — Graft 를 실행조차 하지 않는다.
 * 이름 하나가 후보 목록의 라벨과 정확히 같을 때만 "있다" 로 센다. 비슷한 이름을
 * 있다고 치면 "이미 있음" 표시가 거짓이 되고, 거짓 표시는 없는 표시보다 나쁘다.
 */
export function collectEvidence(names, opts = {}) {
  const empty = { known: new Set(), callers: {}, status: "absent" };
  const list = [
    ...new Set(
      (Array.isArray(names) ? names : []).map((n) => String(n || "").trim()).filter(Boolean),
    ),
  ];
  if (!list.length) return empty;

  const coreRoot = opts.coreRoot;
  const cwd = opts.cwd || process.cwd();
  if (!coreRoot) return empty;
  const sh = adapterPath(coreRoot);
  if (!existsSync(sh)) return empty;

  const timeoutMs =
    Number.isInteger(opts.timeoutMs) && opts.timeoutMs > 0 ? opts.timeoutMs : 25000;

  const statusOut = runAdapter(sh, ["status"], cwd, timeoutMs);
  const status = (statusOut.match(/GRAFT_STATUS:\s*(\S+)/) || [, "absent"])[1];
  if (status !== "ready") return { ...empty, status };

  const known = new Set();
  const callers = {};
  for (const name of list.slice(0, MAX_ASKS)) {
    const out = runAdapter(sh, ["ask", name], cwd, timeoutMs);
    if (!out) continue;
    for (const line of out.split(/\r?\n/)) {
      const m = ASK_LINE.exec(line);
      if (!m) continue;
      const where = m[1].trim();
      const label = m[2].trim();
      if (label !== name) continue; // 정확히 같을 때만 — 비슷한 이름을 있다고 치지 않는다
      known.add(name);
      (callers[name] ||= []).push(where);
    }
  }
  return { known, callers, status };
}
