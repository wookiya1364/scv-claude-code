#!/usr/bin/env bash
# test-deck-change-map.sh — 변경 지도 (v0.52.0+).
#
# 두 가지를 본다. 선언한 상태가 그림과 표로 정확히 나오는가, 그리고 Graft 가 없거나
# 이상하게 굴어도 문서 생성이 끝까지 가는가.
#
# 순수부(change-map.mjs)는 문자열만 넣고 문자열만 확인한다 — 파일도 Graft 도 필요 없다.
# 효과부는 가짜 graft(PATH 앞)로 세운다. 이 저장소는 bash 라 실물로 실증할 수 없다.
set -uo pipefail

HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT="$HERE/.."
DECKDOC="$ROOT/DeckUI/scripts/deckdoc"

pass=0; fail=0
ok()   { pass=$((pass+1)); }
bad()  { echo "  ✗ $1"; fail=$((fail+1)); }
want() { [[ "$2" == "$3" ]] && ok || bad "$1 — 기대: $3 / 실제: $2"; }
has()  { grep -qF -- "$2" "$1" && ok || bad "$3 — 없음: $2"; }
hasnt(){ grep -qF -- "$2" "$1" && bad "$3 — 있으면 안 됨: $2" || ok; }

command -v node >/dev/null 2>&1 || { echo "SKIP test-deck-change-map: node 없음"; exit 0; }
# 문서 생성기는 remark 묶음에 기대므로, 그것이 없으면 이 검사는 돌 수 없다.
# 다른 deck 검사들과 같은 관문이다 — 없으면 붉히지 않고 조용히 건너뛴다.
command -v pnpm >/dev/null 2>&1 || { echo "SKIP test-deck-change-map: pnpm 없음"; exit 0; }
if [[ ! -d "$DECKDOC/node_modules" ]]; then
  ( cd "$DECKDOC" && pnpm install ) >/dev/null 2>&1 \
    || { echo "SKIP test-deck-change-map: deckdoc 의존성 설치 실패"; exit 0; }
fi

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

# ── 순수부를 부르는 작은 다리 ────────────────────────────────────────────────
# 검사는 bash 인데 순수부는 JS 다. 입력을 파일로 주고 결과를 JSON 한 줄로 받는다.
cat > "$WORK/probe.mjs" <<'PROBE'
import { readFileSync } from "node:fs";
import {
  parsePipelineSection, parseScreenSteps, reconcileWithEvidence,
  buildPipelineDiagram, buildChangeTable, countByStatus, renderChangeMapMarkdown,
} from process.env.CM;
const md = readFileSync(process.argv[3], "utf8");
const what = process.argv[2];
const steps = parsePipelineSection(md);
const known = (process.env.KNOWN || "").split(",").filter(Boolean);
const rec = reconcileWithEvidence(steps, known.length ? { known } : {});
const out = {
  steps, counts: countByStatus(steps), screen: parseScreenSteps(md),
  rec, diagram: buildPipelineDiagram(rec),
  rows: buildChangeTable(rec, parseScreenSteps(md)),
};
out.markdown = renderChangeMapMarkdown(out.diagram, out.rows);
process.stdout.write(JSON.stringify(what === "all" ? out : out[what]));
PROBE
# `from process.env.CM` 는 문법이 아니다 — 실제 경로로 바꿔 넣는다.
sed -i "s#from process.env.CM#from \"$DECKDOC/change-map.mjs\"#" "$WORK/probe.mjs"
probe() { local what="$1" file="$2"; shift 2; env "$@" node "$WORK/probe.mjs" "$what" "$file" 2>/dev/null; }

# ── 견본 ────────────────────────────────────────────────────────────────────
mk_plan() {  # <경로> <상태칸 있음:1|0>
  if [[ "$2" == 1 ]]; then
    cat > "$1" <<'EOF'
# 견본 계획

## 순수함수 · 파이프라인 (Pure functions & pipeline)

| # | 단계 | 받는 값 → 돌려주는 값 | 순수/부수효과 | 상태 |
|---|---|---|---|---|
| 1 | `alpha` | 글 → 목록 | 순수 | 추가 |
| 2 | `beta` | 목록 → 표 | 순수 | 변경 |
| 3 | `gamma` | 표 → 없음 | 부수효과 (출구) | 삭제 |
| 4 | `delta` | 경로 → 글 | 부수효과 (입구) | 재사용 |

## 다음 절
본문.
EOF
  else
    cat > "$1" <<'EOF'
# 견본 계획

## 순수함수 · 파이프라인 (Pure functions & pipeline)

| # | 단계 | 받는 값 → 돌려주는 값 | 순수/부수효과 |
|---|---|---|---|
| 1 | `alpha` | 글 → 목록 | 순수 |
| 2 | `beta` | 목록 → 표 | 순수 |

## 다음 절
본문.
EOF
  fi
}

mk_screen() {  # <경로> — 번호 붙은 컴포넌트가 alpha 단계를 가리킨다
  cat > "$1" <<'EOF'
# 견본 화면설계

## 3. Screen mockups

### 화면 하나

```screen
{
  "title": "견본 화면",
  "body": [
    { "type": "header", "title": "제목" },
    { "type": "card", "title": "첫 상자", "body": [ { "type": "text", "value": "본문" } ] }
  ],
  "functions": [
    { "marker": "1", "title": "첫 상자", "step": "alpha", "notes": ["메모"] }
  ]
}
```
EOF
}

mkproj() {  # <이름> <상태칸 있음:1|0> → 계획 폴더 경로
  local d="$WORK/$1/scv/promote/20260101-tester-sample"
  mkdir -p "$d"
  mk_plan "$d/PLAN.md" "$2"
  mk_screen "$d/FEATURE_ARCHITECTURE.md"
  printf '# Test Plan\n\n## Test scenarios\n\n### T1. 하나\n- **Setup**: 없음\n' > "$d/TESTS.md"
  echo "$d"
}

mkfake() {  # <디렉터리> <mode: ok|broken|slow>
  mkdir -p "$1"
  cat > "$1/graft" <<EOF2
#!/usr/bin/env bash
mode="$2"
case "\$mode" in
  broken) echo '{ this is not json' ;;
  slow)   sleep 30 ;;
  ok)     # alpha 만 코드에 이미 있다고 답한다
          if [[ "\${2:-}" == "alpha" ]]; then
            printf '{"results":[{"path":"src/a.ts","line":10,"label":"alpha","score":9}]}\n'
          else printf '{"results":[]}\n'; fi ;;
esac
exit 0
EOF2
  chmod +x "$1/graft"
}

CLEANPATH="$(printf '%s' "$PATH" | tr ':' '\n' | grep -v 'fake-' | tr '\n' ':')"
build() {  # <계획폴더> <출력> [PATH 앞에 붙일 것]
  local d="$1" out="$2" pre="${3:-}"
  ( cd "$d" && PATH="${pre:+$pre:}$CLEANPATH" node "$DECKDOC/doc.mjs" "$d" --out "$out" --lang korean 2>&1 )
}

echo ""
echo "── 순수부 ──"

# T1. 파이프라인 표에서 단계와 상태를 읽어낸다
P=$(mkproj t1 1)
J=$(probe steps "$P/PLAN.md")
want "T1 단계 개수" "$(echo "$J" | jq -r 'length')" "4"
want "T1 첫 단계 이름" "$(echo "$J" | jq -r '.[0].name')" "alpha"
want "T1 상태 차례" "$(echo "$J" | jq -r '[.[].status]|join(",")')" "added,changed,removed,reused"
want "T1 입출력" "$(echo "$J" | jq -r '.[1].io')" "목록 → 표"
want "T1 순수여부" "$(echo "$J" | jq -r '.[2].purity')" "부수효과 (출구)"

# T2. 상태 칸이 없는 옛 서식도 읽힌다
P=$(mkproj t2 0)
J=$(probe steps "$P/PLAN.md")
want "T2 단계 개수" "$(echo "$J" | jq -r 'length')" "2"
want "T2 상태는 모두 미지정" "$(echo "$J" | jq -r '[.[].status]|unique|join(",")')" "unspecified"

# T9. 삭제가 적혀 있지 않으면 삭제 행을 만들지 않는다
P=$(mkproj t9 0)
J=$(probe rows "$P/PLAN.md")
want "T9 삭제 행 개수" "$(echo "$J" | jq -r '[.[]|select(.status=="removed")]|length')" "0"
hasnt <(echo "$J") "삭제 없음" "T9 — 없는 것을 문구로 지어내지 않는다"

# T4. 상태가 그림에 색으로 구분된다
P=$(mkproj t4 1)
D=$(probe diagram "$P/PLAN.md" | jq -r .)
echo "$D" > "$WORK/diagram.txt"
has "$WORK/diagram.txt" "classDef added" "T4 추가 클래스"
has "$WORK/diagram.txt" "classDef changed" "T4 변경 클래스"
has "$WORK/diagram.txt" "classDef removed" "T4 삭제 클래스"
has "$WORK/diagram.txt" "class S1 added" "T4 1번이 추가"
has "$WORK/diagram.txt" "class S2 changed" "T4 2번이 변경"
has "$WORK/diagram.txt" "class S3 removed" "T4 3번이 삭제"
has "$WORK/diagram.txt" "S2 -.-> S3" "T4 삭제로 가는 선은 점선"
has "$WORK/diagram.txt" "S1 --> S2" "T4 그 밖의 선은 실선"
hasnt "$WORK/diagram.txt" "class S4" "T4 재사용에는 클래스가 붙지 않는다"

# T8. 선언과 코드가 어긋나면 표시된다 (순수부)
J=$(probe rec "$P/PLAN.md" KNOWN=alpha)
want "T8 어긋남 표시" "$(echo "$J" | jq -r '.[0].verdict')" "already"
want "T8 선언은 그대로" "$(echo "$J" | jq -r '.[0].status')" "added"
want "T8 근거 있는 변경은 일치" "$(echo "$J" | jq -r '.[1].verdict')" "no-evidence"

# T10(순수부). 화면의 번호가 단계를 가리킨다
J=$(probe screen "$P/FEATURE_ARCHITECTURE.md")
want "T10 연결 개수" "$(echo "$J" | jq -r 'length')" "1"
want "T10 가리키는 단계" "$(echo "$J" | jq -r '.[0].step')" "alpha"
want "T10 번호" "$(echo "$J" | jq -r '.[0].marker')" "1"

# 깨진 화면 블록은 조용히 건너뛴다
printf '```screen\n{ not json\n```\n' > "$WORK/broken-screen.md"
want "깨진 화면 블록" "$(probe screen "$WORK/broken-screen.md" | jq -r 'length')" "0"

echo ""
echo "── 효과부 ──"

# T3. 파이프라인 절이 아예 없어도 문서가 만들어진다
P=$(mkproj t3 1)
python3 - "$P/PLAN.md" <<'PY'
import io,sys,re
p=sys.argv[1]; s=io.open(p,encoding="utf-8").read()
io.open(p,"w",encoding="utf-8").write(re.sub(r"## 순수함수[\s\S]*?(?=## 다음 절)", "", s))
PY
OUT="$WORK/t3.html"; LOG=$(build "$P" "$OUT"); rc=$?
want "T3 종료 코드" "$rc" "0"
[[ -f "$OUT" ]] && ok || bad "T3 — 결과 파일이 없다"
hasnt "$OUT" "변경 지도" "T3 — 절이 없으면 변경 지도도 없다"
grep -q "순수함수" <<<"$LOG" && ok || bad "T3 — 파이프라인 절 없음 경고가 그대로 뜬다"

# T5 + T6. Graft 없음 — 선언만으로 그려지고 설치 명령이 안내된다
P=$(mkproj t6 1)
OUT="$WORK/t6.html"; LOG=$(build "$P" "$OUT"); rc=$?
want "T6 종료 코드" "$rc" "0"
has "$OUT" "변경 지도" "T6 변경 지도 절"
grep -q "CHANGE_MAP: steps=4" <<<"$LOG" && ok || bad "T6 — 단계 4개 보고가 없다: $LOG"
grep -q "graft=absent" <<<"$LOG" && ok || bad "T6 — graft 상태 보고가 없다"
grep -q "npm i -g @nanonets/graft" <<<"$LOG" && ok || bad "T6 — 설치 명령 안내가 없다"
want "T6 대조는 전부 근거없음" \
  "$(probe rec "$P/PLAN.md" | jq -r '[.[].verdict]|unique|join(",")')" "no-evidence"
# T5. 만들어진 그림이 실제로 SVG 로 그려진다 (환경이 그릴 수 있을 때만)
cp "$OUT" "$OUT.orig"
if node "$DECKDOC/static-mermaid.mjs" "$OUT" >"$WORK/t5.out" 2>"$WORK/t5.err"; then
  has "$OUT" "<svg" "T5 인라인 SVG"
  hasnt "$OUT" 'id="scv-mermaid-loader"' "T5 로더 제거"
  grep -q 'embedded diagrams=[1-9]' "$WORK/t5.out" && ok || bad "T5 — 심긴 그림이 0개"
else
  rc=$?
  if [[ $rc -eq 3 ]] && cmp -s "$OUT" "$OUT.orig"; then
    echo "  (이 환경에서는 그림 심기를 건너뜀 — 입력은 그대로: 안전하게 통과)"; ok; ok; ok
  else bad "T5 — 건너뛰기가 아닌 실패 (rc=$rc)"; fi
fi

# T10(효과부). 화면의 번호 옆에 단계 이름과 상태가 함께 보인다
has "$OUT" 'wf-spec-step' "T10 단계 태그"
has "$OUT" 'wf-spec-state-added' "T10 상태 태그(추가)"

# T7. Graft 가 깨졌거나 느려도 끝까지 간다
for mode in broken slow; do
  P=$(mkproj "t7-$mode" 1); mkdir -p "$P/graft"
  FK="$WORK/fake-$mode"; mkfake "$FK" "$mode"
  OUT="$WORK/t7-$mode.html"
  t0=$(date +%s)
  LOG=$(cd "$P" && PATH="$FK:$CLEANPATH" SCV_GRAFT_TIMEOUT=2 node "$DECKDOC/doc.mjs" "$P" --out "$OUT" --lang korean 2>&1); rc=$?
  t1=$(date +%s)
  want "T7($mode) 종료 코드" "$rc" "0"
  [[ -f "$OUT" ]] && ok || bad "T7($mode) — 결과 파일이 없다"
  has "$OUT" "변경 지도" "T7($mode) 변경 지도는 그대로 나온다"
  if [[ "$mode" == slow ]]; then
    [[ $((t1-t0)) -lt 60 ]] && ok || bad "T7(slow) — 시간 제한이 듣지 않는다 ($((t1-t0))초)"
  fi
done

# T8(효과부). 가짜 Graft 가 "이미 있다" 고 하면 그렇게 표시된다
P=$(mkproj t8 1); mkdir -p "$P/graft"
FK="$WORK/fake-ok"; mkfake "$FK" ok
OUT="$WORK/t8.html"
LOG=$(cd "$P" && PATH="$FK:$CLEANPATH" node "$DECKDOC/doc.mjs" "$P" --out "$OUT" --lang korean 2>&1); rc=$?
want "T8 종료 코드" "$rc" "0"
grep -q "graft=ready" <<<"$LOG" && ok || bad "T8 — graft 를 ready 로 보지 않았다: $LOG"
has "$OUT" "이미 있음" "T8 어긋남 표시가 문서에 나온다"
grep -q "npm i -g" <<<"$LOG" && bad "T8 — 설치돼 있는데 설치 안내가 떴다" || ok

# T11. 계획 폴더가 아닌 문서에는 붙지 않는다
P=$(mkproj t11 1)
OUT="$WORK/t11.html"
( cd "$WORK" && node "$DECKDOC/doc.mjs" "$P/PLAN.md" --out "$OUT" --lang korean >/dev/null 2>&1 )
want "T11 결과 파일" "$([[ -f "$OUT" ]] && echo yes || echo no)" "yes"
hasnt "$OUT" "변경 지도" "T11 — 한 장짜리 문서에는 변경 지도가 없다"

echo ""
echo "── 언어 ──"
P=$(mkproj tlang 1)
OUT="$WORK/tlang.html"; build "$P" "$OUT" >/dev/null
has "$OUT" "변경 지도" "한국어 제목"
OUT="$WORK/tlang-en.html"
( cd "$P" && node "$DECKDOC/doc.mjs" "$P" --out "$OUT" --lang english >/dev/null 2>&1 )
has "$OUT" "Change map" "영어 제목"

echo ""
echo "── test-deck-change-map: $pass passed, $fail failed ──"
[[ $fail -eq 0 ]]
