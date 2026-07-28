// i18n.mjs — deck UI chrome strings + lint/error messages. English is the DEFAULT
// and the fallback for any unrecognized value — same convention as
// scripts/render-template.sh's SCV_LANG handling (settings.json `language` → .env
// `SCV_LANG` resolve this upstream; this module only maps an ALREADY-RESOLVED
// language name to its label set). Content the user actually WROTE (PLAN.md prose,
// screen mockup labels, table data, etc.) is never touched here — only the chrome
// this renderer itself generates (buttons, headings, lint/error copy).

const STRINGS = {
  english: {
    toc: "Table of Contents",
    cover: "Cover",
    prev: "‹ Prev",
    next: "Next ›",
    goals: "Goals",
    nonGoals: "Non-Goals",
    calloutInfo: "Note",
    calloutGood: "Good",
    calloutWarn: "Warning",
    calloutDanger: "Danger",
    calloutNext: "Next",
    nestedTooDeep: "(nesting too deep — truncated)",
    qualityReportTitle: "Quality Report",
    qualityReportSub:
      "Nothing invented beyond the source — these are sections a professional plan usually has but this document is missing.",
    sourcePanelLabel: "Source",
    sourcePanelToggleTitle: "Toggle source panel (S)",
    panelCloseTitle: "Hide (S)",
    themeToggleTitle: "Switch light/dark theme",
    themeLight: "☀ Light",
    themeDark: "☾ Dark",
    documentFallback: (i) => `Document ${i}`,
    resizeHandleTitle: "Drag to resize",
    untitledDeck: "Untitled Plan",
    lintNonGoals: "No Non-goals / Out-of-scope section — scope boundaries may stay ambiguous.",
    lintMetrics: "No Success-metrics section — a baseline→target metric is recommended.",
    lintAcceptance: "No Acceptance-criteria section.",
    lintEdgeCases: "No Edge-cases section.",
    screenParseErrorTitle: "Screen Mockup Parse Error",
    screenParseErrorText: (msg) =>
      `The JSON inside this screen block is invalid (${msg}). Check this block in the source panel.`,
    featureArchitectureLabel: "📐 Structure · FEATURE_ARCHITECTURE",
    testsLabel: "✅ Tests · Acceptance Criteria (TESTS)",
  },
  korean: {
    toc: "목차",
    cover: "표지",
    prev: "‹ 이전",
    next: "다음 ›",
    goals: "목표",
    nonGoals: "비목표",
    calloutInfo: "참고",
    calloutGood: "좋음",
    calloutWarn: "주의",
    calloutDanger: "위험",
    calloutNext: "다음",
    nestedTooDeep: "(중첩이 너무 깊어 생략됨)",
    qualityReportTitle: "품질 리포트",
    qualityReportSub: "원문에 없는 내용은 채우지 않음 — 전문 기획서가 보통 갖추는데 이 문서엔 빠진 항목입니다.",
    sourcePanelLabel: "기획서 원문",
    sourcePanelToggleTitle: "원문 패널 토글 (S)",
    panelCloseTitle: "숨기기 (S)",
    themeToggleTitle: "라이트/다크 전환",
    themeLight: "☀ 라이트",
    themeDark: "☾ 다크",
    documentFallback: (i) => `문서 ${i}`,
    resizeHandleTitle: "드래그해서 크기 조절",
    untitledDeck: "기획서",
    lintNonGoals: "비목표(Non-goals / Out-of-scope) 섹션이 없습니다 — 범위 경계가 모호해질 수 있습니다.",
    lintMetrics: "성공지표(Metrics) 섹션이 없습니다 — baseline→target 지표를 권장합니다.",
    lintAcceptance: "인수기준(Acceptance criteria) 섹션이 없습니다.",
    lintEdgeCases: "예외처리(Edge cases) 섹션이 없습니다.",
    screenParseErrorTitle: "화면 목업 파싱 오류",
    screenParseErrorText: (msg) => `screen 블록의 JSON이 올바르지 않습니다 (${msg}). 원문 패널에서 이 블록을 확인하세요.`,
    featureArchitectureLabel: "📐 구조 · FEATURE_ARCHITECTURE",
    testsLabel: "✅ 테스트 · 인수기준 (TESTS)",
  },
  japanese: {
    toc: "目次",
    cover: "表紙",
    prev: "‹ 前へ",
    next: "次へ ›",
    goals: "目標",
    nonGoals: "非目標",
    calloutInfo: "参考",
    calloutGood: "良好",
    calloutWarn: "注意",
    calloutDanger: "危険",
    calloutNext: "次",
    nestedTooDeep: "(ネストが深すぎるため省略)",
    qualityReportTitle: "品質レポート",
    qualityReportSub: "元文書にない内容は補完しません — 本来の企画書にあるはずが、この文書に欠けている項目です。",
    sourcePanelLabel: "企画書原文",
    sourcePanelToggleTitle: "原文パネルの切り替え (S)",
    panelCloseTitle: "隠す (S)",
    themeToggleTitle: "ライト/ダークテーマ切り替え",
    themeLight: "☀ ライト",
    themeDark: "☾ ダーク",
    documentFallback: (i) => `ドキュメント ${i}`,
    resizeHandleTitle: "ドラッグしてサイズ変更",
    untitledDeck: "企画書",
    lintNonGoals: "非目標(Non-goals / Out-of-scope)セクションがありません — 範囲の境界が曖昧になる可能性があります。",
    lintMetrics: "成功指標(Metrics)セクションがありません — baseline→target 指標を推奨します。",
    lintAcceptance: "受入基準(Acceptance criteria)セクションがありません。",
    lintEdgeCases: "例外処理(Edge cases)セクションがありません。",
    screenParseErrorTitle: "画面モックアップ解析エラー",
    screenParseErrorText: (msg) => `screen ブロックのJSONが正しくありません (${msg})。原文パネルでこのブロックを確認してください。`,
    featureArchitectureLabel: "📐 構造 · FEATURE_ARCHITECTURE",
    testsLabel: "✅ テスト · 受入基準 (TESTS)",
  },
};

// Anything outside the recognized values falls back to English — same rule as
// scripts/render-template.sh.
export function normalizeLang(lang) {
  const l = String(lang || "").toLowerCase();
  return Object.prototype.hasOwnProperty.call(STRINGS, l) ? l : "english";
}

export function makeT(lang) {
  const table = STRINGS[normalizeLang(lang)];
  return (key, ...args) => {
    const v = table[key] ?? STRINGS.english[key];
    return typeof v === "function" ? v(...args) : v;
  };
}
