# Rewritten-request word list (STE)

help prints the section that matches `SCV_LANG` as `STE:` at the end of its guide lines, once per
protocol fingerprint (`model-prompting.sh guide`, 0.84.0+); after that a one-line reminder. The
rewritten request (`contracts/writing.md` 4, `protocols/help/prompt-refine.md` 2) follows it.
`SCV_REWRITE_STE=off` stops it. A language with no section gets nothing — the rewrite works as before.

Why a list: the rewrite rule gave a direction ("the best prompt for this model") and no list, and a
direction alone leaves every word to the writer. ASD-STE100 (Simplified Technical English, the
aircraft-maintenance writing standard) answers that with fixed rules and a fixed word list. The Korean
section carries its rules into Korean; the words come from real long conversations (the slay sessions,
269 user requests, 2026-11-08).

Evidence (2026-11-08, 20 real past requests, blind Sonnet judge, rubric fixed before each run):
rewrites 15 wins · 3 losses · 2 ties against the current way (keeps meaning 4.35/3.60 · one reading
4.05/4.00 · easy to confirm 4.80/3.75 · no padding 4.75/3.05), 157 vs 269 characters; the answers
written from them 10 · 8 · 2. Version 2 lost on "one reading" (questions turned into orders, "check"
dropped, questions turned into conditions, repeats, added requirements) — rules R11–R15 close those.

<!-- ste:korean -->
다시 쓴 요청은 이 목록대로 쓴다 (한국어판 STE — ASD-STE100 규칙을 한국어로 옮김).
R1 문장 하나에 지시 하나.
R2 지시 문장은 15어절 이하, 설명 문장은 20어절 이하.
R3 동사는 사용자가 쓴 것을 그대로 쓴다. 사용자가 동사를 쓰지 않았을 때만 '허용 동사'에서 고른다. 요청에 없는 행동 · 금지 · 조건 · 출력 형식을 더하지 않는다.
R4 문장 끝은 요청의 말투를 따른다(사용자가 '~해라'면 '~해라', '~해 줘'면 '~해 줘').
R5 대상을 반드시 적는다(무엇을 · 어디의). 주어나 목적어를 빼지 않는다.
R6 조건은 문장 앞에: '~이면 ~해라'.
R7 정도는 숫자나 눈으로 볼 수 있는 결과로 쓴다. 요청에 '느낌 · 자연스럽게 · 제대로 · 잘'이 있으면 무엇이 어떻게 보여야 하는지로 바꾸되, 사용자 말에서 찾을 수 없으면 그 말을 따옴표로 남기고 뜻을 지어내지 않는다.
R8 '금지 낱말'은 쓰지 않는다. 요청의 '등'은 요청에 나온 항목만 적고 끝낸다(항목을 지어 더하지 않는다).
R9 한 낱말에 한 뜻. '용어'를 바꿔 부르지 않는다.
R10 사용자가 쓴 고유한 이름(파일 · 기능 · 카드 · 사람)은 그대로 둔다.
R11 질문은 질문으로 둔다. 사용자가 물었으면 '~인지 알려 줘'로 쓰고, 묻는 내용을 실행 명령(병합해 · 릴리스해 따위)으로 바꾸지 않는다.
R12 상태 · 사실을 묻는 질문은 '확인해서 알려 줘'로 쓴다 — 기억이 아니라 실제로 열어 보고 답하라는 뜻이다.
R13 질문을 조건문으로 바꾸지 않는다. '없어?'는 '있는지 알려 줘'이지 '있으면 알려 줘'가 아니다.
R14 같은 내용을 두 번 쓰지 않는다.
R15 요청의 지시어(이거 · 그거)가 가리키는 것을 요청과 대화에서 찾을 수 없으면 지시어를 그대로 두고 뜻을 지어내지 않는다.
허용 동사: 읽어라 · 찾아라 · 재라 · 만들어라 · 고쳐라 · 바꿔라 · 없애라 · 지워라 · 옮겨라 · 늘려라 · 줄여라 · 나눠라 · 실행해라 · 시작해라 · 끝내라 · 보여라 · 알려라 · 적어라 · 물어라 · 멈춰라 · 남겨라 · 정해라
금지 낱말: 등 · 잘 · 느낌 · 제대로 · 자연스럽게 · 적당히 · 적절히 · 알아서 · 처리 · 정리 · 관련 · 개선 · 최적화 · 가능하면 · 충분히 · 깔끔하게 · 좋게 · 꼼꼼히 · 다양한
용어: 요청=사용자가 보낸 글 · 답=모델이 사용자에게 쓴 글 · 세션=대화 창 하나 · 시험=자동으로 도는 검사 · 기록=파일에 남긴 글 · 확인=실제로 열거나 실행해 본 것
