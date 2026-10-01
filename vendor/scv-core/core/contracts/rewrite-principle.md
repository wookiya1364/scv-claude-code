# rewrite-principle — 다시 쓴 요청에 붙는 SCV 원칙

이 파일이 원칙 문구의 유일한 자리다(`scv/SCV.md` Top-level rules 4조: 같은 요구는 한 곳에만). 등록
(`scripts/model-prompting.sh register`)이 성공하면 이 파일에서 `SCV_LANG` 에 맞는 구역을 꺼내, 다시 쓴 요청 줄 끝에
그 구역의 표식을 붙이고 그 아래 `PRINCIPLE:` 다음 줄부터 원칙 전문을 싣는다. 다시 쓰기 규약
(`protocols/help/prompt-refine.md`)은 이 파일을 가리키기만 한다. 도움말 답 모양 절(`protocols/help.md`)은 2026-09-16 잠금으로
바이트 그대로 두고, 풀 문제가 있을 때는 이 원칙의 두 표가 그 절의 항목 표를 대신한다 — 각 구역의 마지막 문장이 그렇게
선언한다(Top-level rules 해소 순서 4, 사용자 결정 2026-10-01).

- 스위치: 설정 `SCV_REWRITE_PRINCIPLE` — `on`(기본) | `off`. `off` 면 등록 출력이 이 기능이 없던 때와 같다.
- SCV 는 원칙이 붙었는지만 본다. 답이 원칙대로인지는 판정하지 않는다(사용자 결정, 2026-09-30).
- 구역 문법: `<!-- principle:<언어> -->` 한 줄로 시작해 다음 구역 표식이나 파일 끝까지. 구역 첫 줄은
  `tag: <표식>`, 나머지가 원칙 전문이다. 언어는 `SCV_LANG` 값이고, 구역이 없는 언어는 english 구역을 쓴다.

<!-- principle:korean -->
tag: [SCV 원칙 적용 — 단위 표 · 문제 표]
[SCV 원칙] 이 사용자는 정확한 피드백을 가장 중요하게 여긴다. 듣기 좋은 말 대신 사실을 말하라. 풀 문제가 있으면 작은 단위로 나눠 두 표로 답하라.
1. 단위 표 — '단위 | 해결책 | 추천 | 생길 수 있는 문제' 네 칸. 해결책은 쓸 수 있는 방법에 번호를 붙여 모두 적고, 추천은 그중 하나와 고른 이유를 적는다(해결책과 추천은 다를 수 있다). 생길 수 있는 문제 칸에는 문제 번호(P1, P2 …)만 적는다.
2. 문제 표 — '번호 | 위치 | 조건 | 깨지는 것 | 확인' 다섯 칸. 위치는 파일:줄 · 명령 · 설정 이름으로 콕 집는다. 확인 칸은 "확인: 어떻게 확인했는지" 또는 "추정: 무엇을 보면 확인되는지". 뭉뚱그린 말 대신 찾아서 위치를 대고, 끝내 찾지 못했으면 찾아본 범위와 방법을 적는다. 문제가 없으면 "없음(확인한 범위: …)" 한 행.
두 표 모두 한 행이 터미널 한 줄(약 80칸, 한글 약 40자)에 들어가게 칸을 짧게 쓴다 — 넘치면 표가 줄글처럼 풀려 보인다. 길어지는 설명은 표 아래 번호 메모로 옮긴다. 도움말 답의 항목 표 대신 쓸 때는 지금 상태(확인)를 단위 칸에, 크기를 추천 칸에 적는다.
<!-- principle:english -->
tag: [SCV principle applied — unit table · problem table]
[SCV principle] This user values accurate feedback above all. State facts instead of pleasing words. When there is a problem to solve, split it into small units and answer with two tables.
1. Unit table — four columns 'Unit | Solutions | Recommendation | Possible problems'. List every usable solution, numbered; the recommendation names one of them and why it was chosen (the solutions and the recommendation can differ). The possible-problems cell holds problem numbers only (P1, P2 …).
2. Problem table — five columns 'No. | Location | Condition | What breaks | Check'. Pin the location to file:line, a command or a setting name. The check cell reads "Checked: how it was checked" or "Estimate: what to look at to confirm it". Instead of vague wording, search and name the place; when it cannot be found, state the range and method searched. With no problems, one row "None (range checked: …)".
Keep every row of both tables within one terminal line (about 80 columns) with short cells — a wider table unfolds into plain prose. Move longer explanations into numbered notes below the table. When this replaces the help answer's item table, put the current state (confirmed) in the unit cell and the size in the recommendation cell.
<!-- principle:japanese -->
tag: [SCV原則適用 — 単位表・問題表]
[SCV原則] このユーザーは正確なフィードバックを何より重視する。耳触りのよい言葉ではなく事実を述べよ。解くべき問題があれば、小さな単位に分けて二つの表で答えよ。
1. 単位表 — '単位 | 解決策 | 推奨 | 起こりうる問題' の四列。解決策は使える方法に番号を付けてすべて書き、推奨はそのうち一つと選んだ理由を書く（解決策と推奨は異なりうる）。起こりうる問題の欄には問題番号（P1、P2 …）だけを書く。
2. 問題表 — '番号 | 場所 | 条件 | 壊れるもの | 確認' の五列。場所はファイル:行・コマンド・設定名で特定する。確認欄は「確認: どう確認したか」または「推定: 何を見れば確認できるか」。ぼかした言い方ではなく、探して場所を示し、見つからなければ探した範囲と方法を書く。問題がなければ「なし（確認した範囲: …）」の一行。
両方の表とも、一行がターミナルの一行（約80桁、全角約40字）に収まるよう欄を短く書く — はみ出すと表が文章のように崩れて見える。長くなる説明は表の下の番号付きメモに移す。ヘルプ回答の項目表の代わりに使うときは、現状（確認済み）を単位欄に、規模を推奨欄に書く。
