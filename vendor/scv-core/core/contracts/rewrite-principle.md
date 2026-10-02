# rewrite-principle — 다시 쓴 요청에 붙는 SCV 원칙

이 파일이 원칙 문구의 유일한 자리다(`scv/SCV.md` Top-level rules 4조: 같은 요구는 한 곳에만). 등록
(`scripts/model-prompting.sh register`)이 성공하면 이 파일에서 `SCV_LANG` 에 맞는 구역을 꺼내, 다시 쓴 요청 줄 끝에
그 구역의 표식을 붙이고 그 아래 `PRINCIPLE:` 다음 줄부터 원칙 전문을 싣는다. 다시 쓰기 규약
(`protocols/help/prompt-refine.md`)은 이 파일을 가리키기만 한다. 도움말 답 모양 절(`protocols/help.md`)은 2026-09-16 잠금으로
바이트 그대로 두고, 풀 문제가 있을 때는 이 원칙의 단위 표가 그 절의 항목 표를 대신한다 — 각 구역의 마지막 문장이 그렇게
선언한다(Top-level rules 해소 순서 4, 사용자 결정 2026-10-01).

- 스위치: 설정 `SCV_REWRITE_PRINCIPLE` — `on`(기본) | `off`. `off` 면 등록 출력이 이 기능이 없던 때와 같다.
- SCV 는 원칙이 붙었는지만 본다. 답이 원칙대로인지는 판정하지 않는다(사용자 결정, 2026-09-30) — 한 가지만 예외: 답의 끝
  메시지에 문제 표나 '생길 수 있는 문제' 칸이 있으면 종료 훅이 같은 턴에 한 번 막는다(다른 검사가 먼저 막았어도 — 검사마다 한
  턴에 한 번, `contracts/choices.md` 7항)(사용자 결정, 2026-10-01 — 문제는 해결책
  안에서 막고 사용자에게 보이지 않는다). 판정은 `scripts/model-prompting.sh principle-gate`.
- 문제 표 · '생길 수 있는 문제' 칸 · 위치 표시 문장은 없앴다(사용자 결정 2026-10-01): 해결책이 문제를 막는 길까지 담고,
  막을 수 없는 것 중 사용자가 정할 것은 `contracts/choices.md` 대로 묻고, 남는 한계는 추천 칸 이유에 한 줄로 적는다.
- 구역 문법: `<!-- principle:<언어> -->` 한 줄로 시작해 다음 구역 표식이나 파일 끝까지. 구역 첫 줄은
  `tag: <표식>`, 나머지가 원칙 전문이다. 언어는 `SCV_LANG` 값이고, 구역이 없는 언어는 english 구역을 쓴다.

<!-- principle:korean -->
tag: [SCV 원칙 적용 — 단위 표]
[SCV 원칙] 이 사용자는 정확한 피드백을 가장 중요하게 여긴다. 듣기 좋은 말 대신 사실을 말하라. 풀 문제가 있으면 작은 단위로 나눠 단위 표 하나로 답하라.
단위 표 — '단위 | 해결책 | 추천' 세 칸. 해결책은 쓸 수 있는 방법에 번호를 붙여 모두 적되, 방법마다 그 방법이 부를 문제를 막는 길까지 담는다. 추천은 그중 하나와 고른 이유를 적는다(해결책과 추천은 다를 수 있다). 생길 수 있는 문제를 따로 나열하지 않는다 — 해결책이 막는다. 해결책으로 막을 수 없는 것 중 사용자가 정할 것은 고르게 할 때 규칙(contracts/choices.md)대로 묻고, 남는 한계(확인하지 못한 것)는 추천 칸 이유에 한 줄로 적는다.
한 행이 터미널 한 줄(약 80칸, 한글 약 40자)에 들어가게 칸을 짧게 쓴다 — 넘치면 표가 줄글처럼 풀려 보인다. 길어지는 설명은 표 아래 번호 메모로 옮긴다. 도움말 답의 항목 표 대신 쓸 때는 지금 상태(확인)를 단위 칸에, 크기를 추천 칸에 적는다.
<!-- principle:english -->
tag: [SCV principle applied — unit table]
[SCV principle] This user values accurate feedback above all. State facts instead of pleasing words. When there is a problem to solve, split it into small units and answer with one unit table.
Unit table — three columns 'Unit | Solutions | Recommendation'. List every usable solution, numbered, and let each one carry how it prevents the problems it would cause. The recommendation names one of them and why it was chosen (the solutions and the recommendation can differ). Do not list possible problems separately — the solutions prevent them. Of what no solution can prevent, ask the user what is theirs to decide by the choice rule (contracts/choices.md), and state a remaining limit (something unverified) in one line in the recommendation's reason.
Keep every row within one terminal line (about 80 columns) with short cells — a wider table unfolds into plain prose. Move longer explanations into numbered notes below the table. When this replaces the help answer's item table, put the current state (confirmed) in the unit cell and the size in the recommendation cell.
<!-- principle:japanese -->
tag: [SCV原則適用 — 単位表]
[SCV原則] このユーザーは正確なフィードバックを何より重視する。耳触りのよい言葉ではなく事実を述べよ。解くべき問題があれば、小さな単位に分けて単位表一つで答えよ。
単位表 — '単位 | 解決策 | 推奨' の三列。解決策は使える方法に番号を付けてすべて書き、方法ごとにその方法が招く問題を防ぐ手立てまで含める。推奨はそのうち一つと選んだ理由を書く（解決策と推奨は異なりうる）。起こりうる問題を別に並べない — 解決策が防ぐ。解決策で防げないもののうち、ユーザーが決めることは選ばせるときの規則（contracts/choices.md）どおりに尋ね、残る限界（確認できなかったこと）は推奨欄の理由に一行で書く。
一行がターミナルの一行（約80桁、全角約40字）に収まるよう欄を短く書く — はみ出すと表が文章のように崩れて見える。長くなる説明は表の下の番号付きメモに移す。ヘルプ回答の項目表の代わりに使うときは、現状（確認済み）を単位欄に、規模を推奨欄に書く。
