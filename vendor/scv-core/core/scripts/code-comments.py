#!/usr/bin/env python3
"""code-comments.py — find, strip and classify code comments (0.98.0+, plan comments-to-catalog).

A project that keeps every function description in its pure-function catalog
(scv/core/catalog/pure) has no comments in its code. This tool is the reading
half of that rule: it finds comment spans per language — strings, template
literals, raw strings, here-documents and regular expressions are not comments —
and turns them into catalog material.

  scan FILE...                 JSON lines, one per comment block (file, line, kind, text, fn, markers)
  strip FILE [--write]         the file without its comments (stdout, or in place)
  count FILE... / count-stdin  "<file>\\t<comment lines>" per file with comments, then "TOTAL\\t<n>"
  gate --file P --after A [--before B]
                               a one-line refusal when the edit adds comment lines (nothing otherwise)

Languages by extension: sh/bash, js/jsx/ts/tsx/mjs/cjs/mts/cts, py, rs, go.
Other files are not code for this rule and yield nothing. Pure parts take text and
return values; only main() reads files and writes output.
"""
import json
import os
import re
import sys

LANGS = {
    'sh': ('.sh', '.bash'),
    'js': ('.js', '.jsx', '.ts', '.tsx', '.mjs', '.cjs', '.mts', '.cts'),
    'py': ('.py',),
    'rs': ('.rs',),
    'go': ('.go',),
}
MARK_RE = re.compile(r'@(pure|deterministic|effect)\b[ \t]*([A-Za-z_$][A-Za-z0-9_$:.-]*)?')
FIELD_RE = re.compile(r'(?:(?<=\s)|^)(역할|종류|예|이유)\s*:\s*')
DIRECTIVE_RE = re.compile(
    r'^(#!|shellcheck\b|eslint[- ]|@ts-|type:\s*ignore|noqa\b|pylint:|prettier-ignore|go:|nolint\b|'
    r'istanbul\b|c8\b|jshint\b|jscs:|tslint:|biome-ignore|deno-lint|@jsx|@flow|@refresh|#\s*sourceMappingURL)')


# @pure lang_of
# 역할: 파일 이름의 확장자로 언어를 고른다 — 모르는 확장자는 빈 값
# 종류: 고르기
# 예: lang_of("src/a.ts") → "js"
def lang_of(path):
    low = path.lower()
    for lang, exts in LANGS.items():
        if low.endswith(exts):
            return lang
    return ''


# @pure _spans_c_like
# 역할: js/ts · rust · go 글에서 주석 구간을 찾는다 — 문자열 · 정규식 · 원시 문자열은 건너뜀
# 종류: 꺼내기
# 예: _spans_c_like("a // b", "js") → [(2, 6)]
def _spans_c_like(text, lang):
    spans, i, n = [], 0, len(text)
    prev = ''
    prev_word = ''
    while i < n:
        c = text[i]
        nx = text[i + 1] if i + 1 < n else ''
        if c == '/' and nx == '/':
            j = text.find('\n', i)
            j = n if j < 0 else j
            spans.append((i, j)); i = j; continue
        if c == '/' and nx == '*':
            depth, j = 1, i + 2
            while j < n and depth:
                if text.startswith('*/', j):
                    depth -= 1; j += 2; continue
                if lang == 'rs' and text.startswith('/*', j):
                    depth += 1; j += 2; continue
                j += 1
            spans.append((i, j)); i = j; continue
        if lang == 'rs' and c == 'r' and (nx == '"' or nx == '#') and not (prev_word and (prev.isalnum() or prev == '_')):
            m = re.match(r'r(#*)"', text[i:])
            if m:
                close = '"' + m.group(1)
                j = text.find(close, i + len(m.group(0)))
                i = n if j < 0 else j + len(close); prev = '"'; prev_word = ''; continue
        if lang == 'go' and c == '`':
            j = text.find('`', i + 1); i = n if j < 0 else j + 1; prev = '`'; prev_word = ''; continue
        if c in '"\'' or (c == '`' and lang == 'js'):
            if lang == 'rs' and c == "'":
                m = re.match(r"'(\\.|[^'\\\n]){1,8}'", text[i:])
                if not m:
                    i += 1; prev = c; prev_word = ''; continue
                i += len(m.group(0)); prev = "'"; prev_word = ''; continue
            i = _skip_string(text, i, c, lang); prev = c; prev_word = ''; continue
        if lang == 'js' and c == '/' and (prev == '' or prev in '(,=:[!&|?{};+-*%<>~^' or prev_word in ('return', 'typeof', 'case', 'in', 'of', 'delete', 'void', 'throw', 'new')):
            j, cls = i + 1, False
            while j < n and text[j] != '\n':
                ch = text[j]
                if ch == '\\':
                    j += 2; continue
                if ch == '[':
                    cls = True
                elif ch == ']':
                    cls = False
                elif ch == '/' and not cls:
                    break
                j += 1
            if j < n and text[j] == '/':
                i = j + 1; prev = '/'; prev_word = ''; continue
        if not c.isspace():
            if c.isalnum() or c in '_$':
                m = re.match(r'[A-Za-z0-9_$]+', text[i:])
                if m:
                    prev_word = m.group(0); i += len(prev_word); prev = prev_word[-1]; continue
            prev = c; prev_word = ''
        i += 1
    return spans


# @pure _skip_string
# 역할: 따옴표로 시작한 문자열 글이 끝난 바로 뒤 자리를 낸다
# 종류: 고르기
# 예: _skip_string("'ab' x", 0, "'", "js") → 4
def _skip_string(text, i, q, lang):
    n, j = len(text), i + 1
    depth = 0
    while j < n:
        ch = text[j]
        if ch == '\\':
            j += 2; continue
        if q == '`' and ch == '$' and j + 1 < n and text[j + 1] == '{':
            depth += 1; j += 2; continue
        if q == '`' and depth and ch == '}':
            depth -= 1; j += 1; continue
        if ch == q and not depth:
            return j + 1
        if ch == '\n' and q != '`':
            return j
        j += 1
    return n


# @pure _spans_py
# 역할: 파이썬 글에서 주석 구간을 찾는다 — 문자열 · 세 따옴표 문자열은 건너뜀
# 종류: 꺼내기
# 예: _spans_py("x = 1  # a") → [(7, 10)]
def _spans_py(text):
    spans, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c == '#':
            j = text.find('\n', i); j = n if j < 0 else j
            spans.append((i, j)); i = j; continue
        if c in '"\'':
            if text.startswith(c * 3, i):
                j = text.find(c * 3, i + 3); i = n if j < 0 else j + 3; continue
            j = i + 1
            while j < n and text[j] != c and text[j] != '\n':
                j += 2 if text[j] == '\\' else 1
            i = j + 1; continue
        i += 1
    return spans


# @pure _spans_sh
# 역할: 셸 글에서 주석 구간을 찾는다 — 따옴표 · $'…' · 여기 문서 · $# 는 건너뜀
# 종류: 꺼내기
# 예: _spans_sh("echo $# # a") → [(8, 11)]
def _spans_sh(text):
    spans, i, n = [], 0, len(text)
    heredocs = []
    while i < n:
        c = text[i]
        if c == '\n' and heredocs:
            j = i + 1
            while heredocs and j < n:
                tag, strip_tabs = heredocs[0]
                e = text.find('\n', j); e = n if e < 0 else e
                line = text[j:e]
                if (line.lstrip('\t') if strip_tabs else line) == tag:
                    heredocs.pop(0)
                j = e + 1
            i = j; continue
        if c == '\\':
            i += 2; continue
        if c == "'":
            j = text.find("'", i + 1); i = n if j < 0 else j + 1; continue
        if c == '$' and i + 1 < n and text[i + 1] == "'":
            j = i + 2
            while j < n and text[j] != "'":
                j += 2 if text[j] == '\\' else 1
            i = j + 1; continue
        if c == '$' and i + 1 < n and text[i + 1] in '#{(':
            if text[i + 1] == '#':
                i += 2; continue
            close = '}' if text[i + 1] == '{' else ')'
            depth, j = 1, i + 2
            while j < n and depth:
                if text[j] == text[i + 1]:
                    depth += 1
                elif text[j] == close:
                    depth -= 1
                elif text[j] in '"\'':
                    k = text.find(text[j], j + 1); j = n if k < 0 else k
                j += 1
            i = j; continue
        if c == '"':
            j = i + 1
            while j < n and text[j] != '"':
                j += 2 if text[j] == '\\' else 1
            i = j + 1; continue
        if c == '<' and text.startswith('<<', i) and not text.startswith('<<<', i):
            m = re.match(r'<<(-?)[ \t]*(["\']?)([A-Za-z_][A-Za-z0-9_]*)\2', text[i:])
            if m:
                heredocs.append((m.group(3), m.group(1) == '-')); i += len(m.group(0)); continue
        if c == '#':
            before = text[i - 1] if i else '\n'
            if before in ' \t\n;|&()':
                j = text.find('\n', i); j = n if j < 0 else j
                spans.append((i, j)); i = j; continue
        i += 1
    return spans


# @pure comment_spans
# 역할: 글과 언어로 주석 구간(시작, 끝) 목록을 낸다 — 첫 줄 #! 는 실행기 지정이라 주석이 아니다(지우면 직접 실행이 깨짐)
# 종류: 꺼내기
# 예: comment_spans("x\n# a", "sh") → [(2, 5)]
def comment_spans(text, lang):
    if lang in ('sh', 'py'):
        spans = _spans_sh(text) if lang == 'sh' else _spans_py(text)
        return [s for s in spans if not (s[0] == 0 and text.startswith('#!'))]
    if lang in ('js', 'rs', 'go'):
        return _spans_c_like(text, lang)
    return []


# @pure strip_comments
# 역할: 주석을 지운 글을 낸다 — 주석만 있던 줄은 줄째, 코드 뒤 주석은 주석과 그 앞 공백만
# 종류: 다듬기
# 예: strip_comments("# a\nx = 1  # b\n", "py") → "x = 1\n"
def strip_comments(text, lang):
    spans = comment_spans(text, lang)
    if not spans:
        return text
    src_lines = text.split('\n')
    touched = set()
    for s, e in spans:
        touched.update(range(text.count('\n', 0, s), text.count('\n', 0, max(s, e - 1)) + 1))
    kept, pos = [], 0
    for idx, line in enumerate(src_lines):
        start, end = pos, pos + len(line)
        pieces, cur = [], start
        for s, e in spans:
            if e <= start or s >= end:
                continue
            if s > cur:
                pieces.append(text[cur:s])
            cur = max(cur, min(e, end))
        if cur < end:
            pieces.append(text[cur:end])
        rest = ''.join(pieces)
        pos = end + 1
        if idx in touched:
            rest = rest.rstrip()
            if rest.strip() == '':
                continue
        kept.append(rest)
    return '\n'.join(kept)


_FN_RES = {
    'sh': [re.compile(r'^\s*(?:function\s+)?([A-Za-z_][A-Za-z0-9_:.-]*)\s*\(\)'), re.compile(r'^\s*function\s+([A-Za-z_][A-Za-z0-9_:.-]*)')],
    'js': [re.compile(r'^\s*(?:export\s+)?(?:default\s+)?(?:async\s+)?function\*?\s*([A-Za-z_$][\w$]*)'),
           re.compile(r'^\s*(?:export\s+)?(?:declare\s+)?(?:const|let|var|class|interface|type|enum)\s+([A-Za-z_$][\w$]*)'),
           re.compile(r'^\s*(?:public\s+|private\s+|protected\s+|static\s+|readonly\s+|async\s+|get\s+|set\s+)*([A-Za-z_$][\w$]*)\s*[(:=<]')],
    'py': [re.compile(r'^\s*(?:async\s+)?def\s+([A-Za-z_]\w*)'), re.compile(r'^\s*class\s+([A-Za-z_]\w*)'), re.compile(r'^([A-Za-z_]\w*)\s*[:=]')],
    'rs': [re.compile(r'^\s*(?:pub(?:\([^)]*\))?\s+)?(?:const\s+|async\s+|unsafe\s+|extern\s+"[^"]*"\s+)*fn\s+([A-Za-z_]\w*)'),
           re.compile(r'^\s*(?:pub(?:\([^)]*\))?\s+)?(?:struct|enum|trait|type|const|static|mod)\s+([A-Za-z_]\w*)'),
           re.compile(r'^\s*impl(?:<[^>]*>)?\s+(?:[\w:<>, ]+\s+for\s+)?([A-Za-z_]\w*)')],
    'go': [re.compile(r'^func\s+(?:\([^)]*\)\s*)?([A-Za-z_]\w*)'), re.compile(r'^\s*(?:type|var|const)\s+([A-Za-z_]\w*)')],
}
_JS_NOT_NAMES = {'if', 'for', 'while', 'switch', 'catch', 'return', 'await', 'yield', 'typeof', 'new', 'else', 'do', 'try', 'case'}


# @pure decl_name
# 역할: 코드 한 줄이 이름 있는 선언(함수 · 상수 · 형)이면 그 이름을 낸다
# 종류: 꺼내기
# 예: decl_name("pub fn grade(g: u8) -> u8 {", "rs") → "grade"
def decl_name(line, lang):
    for rx in _FN_RES.get(lang, []):
        m = rx.match(line)
        if m and m.group(1) not in _JS_NOT_NAMES:
            return m.group(1)
    return ''


# @pure _clean
# 역할: 주석 구간 글에서 주석 기호(# · // · /* */ · 줄머리 *)를 떼어 본문만 남긴다
# 종류: 다듬기
# 예: _clean("// a", "js") → "a"
def _clean(raw, lang):
    t = raw.strip()
    if lang in ('js', 'rs', 'go'):
        if t.startswith('/*'):
            t = t[2:]
            if t.endswith('*/'):
                t = t[:-2]
            lines = [re.sub(r'^\s*\*+ ?', '', l) for l in t.split('\n')]
            return '\n'.join(l.rstrip() for l in lines).strip('\n')
        return re.sub(r'^//[/!]?\s?', '', t)
    return re.sub(r'^#+\s?', '', t)


# @pure comment_blocks
# 역할: 주석 구간을 이어진 덩어리로 묶고 덩어리마다 줄 · 글 · 뒤따르는 선언 이름을 낸다
# 종류: 조립
# 예: comment_blocks("# a\nf() {", "sh")[0]["fn"] → "f"
def comment_blocks(text, lang):
    spans = comment_spans(text, lang)
    lines = text.split('\n')
    starts, acc = [], 0
    for l in lines:
        starts.append(acc); acc += len(l) + 1

    # @pure line_of
    # 역할: 글 위치(글자 번호)가 몇째 줄인지 줄 시작 표에서 찾는다
    # 종류: 고르기
    # 예: line_of(5) → 1 (줄 시작 [0, 4])
    def line_of(off):
        lo, hi = 0, len(starts) - 1
        while lo < hi:
            mid = (lo + hi + 1) // 2
            if starts[mid] <= off:
                lo = mid
            else:
                hi = mid - 1
        return lo

    blocks = []
    for s, e in spans:
        a, b = line_of(s), line_of(max(s, e - 1))
        own = text[starts[a]:s].strip() == ''
        piece = _clean(text[s:e], lang)
        if blocks and own and blocks[-1]['own'] and blocks[-1]['end'] == a - 1:
            blocks[-1]['text'] += '\n' + piece; blocks[-1]['end'] = b
        else:
            blocks.append({'line': a + 1, 'end': b, 'own': own, 'text': piece})
    for blk in blocks:
        nm = ''
        if blk['own']:
            for k in range(blk['end'] + 1, min(len(lines), blk['end'] + 6)):
                if lines[k].strip() == '':
                    continue
                if any(s <= starts[k] < e for s, e in spans):
                    break
                nm = decl_name(lines[k], lang)
                break
        else:
            nm = decl_name(lines[blk['line'] - 1], lang)
        blk['fn'] = nm
        blk['end'] += 1
        del blk['own']
    return blocks


# @pure parse_markers
# 역할: 주석 덩어리 글에서 표식(@pure · @deterministic · @effect)마다 이름 · 역할 · 종류 · 예 · 이유와 남는 글을 뽑는다
# 종류: 꺼내기
# 예: parse_markers("@pure f 역할: 센다 종류: 세기 예: f(1) → 1")[0][0]["role"] → "센다"
def parse_markers(text):
    out, rest = [], []
    cur = None
    for line in text.split('\n'):
        m = MARK_RE.search(line)
        if m:
            cur = {'tier': m.group(1), 'name': m.group(2) or '', 'role': '', 'kind': '', 'examples': [], 'reason': '', 'note': []}
            out.append(cur)
            line = line[m.end():]
        if cur is None:
            rest.append(line); continue
        parts = FIELD_RE.split(line)
        lead = parts[0].strip()
        if lead:
            cur['note'].append(lead)
        for k in range(1, len(parts) - 1, 2):
            label, val = parts[k], parts[k + 1].strip()
            if label == '역할':
                cur['role'] = val
            elif label == '종류':
                cur['kind'] = val
            elif label == '예':
                cur['examples'].append(val)
            elif label == '이유':
                cur['reason'] = val
    return out, '\n'.join(rest).strip()


# @pure classify
# 역할: 주석 글 하나를 표식 · 도구 표시 · 설명 중 하나로 가른다
# 종류: 판정
# 예: classify("eslint-disable-next-line") → "directive"
def classify(text):
    if MARK_RE.search(text):
        return 'marker'
    if DIRECTIVE_RE.match(text.strip()) or text.startswith('!'):
        return 'directive'
    return 'note'


# @pure scan_text
# 역할: 파일 글 하나의 주석 덩어리마다 종류 · 붙은 선언 · 표식을 담은 기록을 낸다
# 종류: 조립
# 예: scan_text("# eslint-disable\n", "js", "a.js")[0]["kind"] → "directive"
def scan_text(text, lang, path):
    recs = []
    for b in comment_blocks(text, lang):
        raw = b['text']
        markers, rest = parse_markers(raw)
        kind = 'marker' if markers else classify(raw)
        for mk in markers:
            if not mk['name']:
                mk['name'] = b['fn']
        recs.append({'file': path, 'line': b['line'], 'end': b['end'], 'kind': kind, 'text': rest if markers else raw,
                     'fn': b['fn'], 'markers': markers})
    return recs


# @pure count_comment_lines
# 역할: 주석이 차지한 줄 수를 센다(코드 뒤 주석도 한 줄로)
# 종류: 세기
# 예: count_comment_lines("x  # a\n# b\n", "sh") → 2
def count_comment_lines(text, lang):
    n = 0
    for s, e in comment_spans(text, lang):
        n += text.count('\n', s, e) + 1
    return n


# @pure gate_reason
# 역할: 편집 전 · 뒤 글로 새 주석 줄이 생기면 거절 한 줄을, 아니면 빈 값을 낸다
# 종류: 판정/gate
# 예: gate_reason("a.py", "x = 1\n", "x = 1\n") → ""
def gate_reason(path, before, after):
    lang = lang_of(path)
    if not lang:
        return ''
    a = count_comment_lines(after, lang)
    b = count_comment_lines(before, lang) if before is not None else 0
    if a <= b:
        return ''
    return ('[SCV 주석 없음] %s 에 주석 %d줄이 생긴다 — 이 프로젝트는 코드에 주석을 두지 않는다. 함수 설명(역할 · 종류 · 예 · 이유)과 '
            '그 밖의 메모는 scv/core/catalog/pure 에 적고, 코드에서는 주석을 빼고 다시 써라(contracts/purity.md).' % (path, a - b))


# @pure entries_tsv
# 역할: 주석 기록들의 순수 표식을 사전 항목 줄(파일 · 층 · 이름 · 역할 · 종류 · 예시들)로 낸다
# 종류: 조립
# 예: entries_tsv([]) → ""
def entries_tsv(records):
    rows, seen = [], set()
    for r in records:
        for m in r['markers']:
            if m['tier'] not in ('pure', 'deterministic') or not m['name']:
                continue
            key = (r['file'], m['name'])
            if key in seen:
                continue
            seen.add(key)
            exs = '\x1f'.join(e for e in m['examples'] if e)
            rows.append('\t'.join([r['file'], m['tier'], m['name'], m['role'].replace('\t', ' '), m['kind'], exs]))
    return '\n'.join(rows)


# @pure render_effects
# 역할: 주석 기록들의 부수효과 표식으로 부수효과 사전 글과 개수를 만든다
# 종류: 조립
# 예: render_effects([])[1] → 0
def render_effects(records):
    out = ['# 부수효과 — 바깥(파일 · 네트워크 · 시각 · 화면)을 바꾸는 함수', '',
           '> 원본 — 코드에는 주석을 두지 않는다. 함수마다 이유 한 줄과 위치를 적는다.', '']
    n = 0
    for r in records:
        for m in r['markers']:
            if m['tier'] != 'effect' or not m['name']:
                continue
            lang = r['file'].rsplit('.', 1)[-1] if '.' in r['file'] else ''
            out += ['### ' + m['name'], '- 이유: ' + (m['reason'] or ' '.join(m['note']) or '(적지 않음)'),
                    '- 위치: %s · @effect · %s' % (r['file'], lang), '']
            n += 1
    return '\n'.join(out).rstrip('\n') + '\n', n


# @pure render_notes
# 역할: 주석 기록들의 설명 · 도구 표시를 파일 · 선언별 메모 글과 개수로 만든다
# 종류: 조립
# 예: render_notes([])[1] → 0
def render_notes(records):
    out = ['# 메모 — 코드에서 옮긴 설명 · 도구 표시', '',
           '> 원본 — 코드에는 주석을 두지 않는다. 함수 설명이 아닌 설명과 도구 표시 줄(#! · eslint-disable · shellcheck 등)은',
           '> 여기 파일 · 선언마다 적는다. 줄 번호는 옮기기 전 원문 기준.', '']
    cur_file, cur_fn, n = None, None, 0
    for r in records:
        texts = []
        if r['kind'] == 'directive' and r['text'].strip():
            texts.append(('도구 표시', r['text']))
        elif r['kind'] == 'note' and r['text'].strip():
            texts.append(('설명', r['text']))
        for m in r['markers']:
            extra = ' '.join(m['note']).strip()
            if extra and m['tier'] != 'effect':
                texts.append(('설명', extra))
        if r['kind'] == 'marker' and r['text'].strip():
            for ln in r['text'].split('\n'):
                if ln.strip():
                    texts.append(('도구 표시' if classify(ln) == 'directive' else '설명', ln))
        if not texts:
            continue
        if r['file'] != cur_file:
            out += ['## ' + r['file'], '']; cur_file, cur_fn = r['file'], None
        fn = r['fn'] or '(파일)'
        if fn != cur_fn:
            out.append('### ' + fn); cur_fn = fn
        for label, tx in texts:
            where = ('줄 %d' % r['line']) if r['end'] <= r['line'] else ('줄 %d–%d' % (r['line'], r['end']))
            out.append('- %s(%s): %s' % (label, where, ' / '.join(x.strip() for x in tx.split('\n') if x.strip())))
            n += 1
        out.append('')
    return '\n'.join(out).rstrip('\n') + '\n', n


# @effect main
# 이유: 파일을 읽고 쓰고, 표준 출력 · 종료 코드로 결과를 낸다
def main(argv):
    if not argv:
        print(__doc__.strip(), file=sys.stderr); return 2
    cmd, args = argv[0], argv[1:]
    if cmd == 'scan':
        for p in args:
            lang = lang_of(p)
            if not lang or not os.path.isfile(p):
                continue
            text = open(p, encoding='utf-8', errors='replace').read()
            for r in scan_text(text, lang, p):
                print(json.dumps(r, ensure_ascii=False))
        return 0
    if cmd == 'strip':
        p = args[0]; write = '--write' in args
        lang = lang_of(p)
        text = open(p, encoding='utf-8', errors='replace').read()
        new = strip_comments(text, lang) if lang else text
        if write:
            if new != text:
                open(p, 'w', encoding='utf-8').write(new)
        else:
            sys.stdout.write(new)
        return 0
    if cmd == 'count-stdin':
        args = [l.strip() for l in sys.stdin if l.strip()]
        cmd = 'count'
    if cmd == 'count':
        total = 0
        for p in args:
            lang = lang_of(p)
            if not lang or not os.path.isfile(p):
                continue
            n = count_comment_lines(open(p, encoding='utf-8', errors='replace').read(), lang)
            if n:
                print('%s\t%d' % (p, n)); total += n
        print('TOTAL\t%d' % total)
        return 0
    if cmd == 'gate':
        opt, k = {}, 0
        while k < len(args):
            if args[k] in ('--file', '--after', '--before') and k + 1 < len(args):
                opt[args[k]] = args[k + 1]; k += 2
            else:
                k += 1
        path, after = opt.get('--file', ''), opt.get('--after', '')
        if not path or not after or not os.path.isfile(after):
            return 0
        bf = opt.get('--before')
        before = open(bf, encoding='utf-8', errors='replace').read() if bf and os.path.isfile(bf) else None
        r = gate_reason(path, before, open(after, encoding='utf-8', errors='replace').read())
        if r:
            print(r)
        return 0
    if cmd == 'migrate':
        opt, k = {}, 0
        while k < len(args):
            if args[k] in ('--catalog', '--entries-out', '--list', '--root') and k + 1 < len(args):
                opt[args[k]] = args[k + 1]; k += 2
            else:
                opt[args[k]] = '1'; k += 1
        files = [l.strip() for l in open(opt['--list'], encoding='utf-8') if l.strip()]
        records, texts = [], {}
        for p in files:
            lang = lang_of(p)
            if not lang or not os.path.isfile(p):
                continue
            text = open(p, encoding='utf-8', errors='replace').read()
            texts[p] = (text, lang)
            rel = os.path.relpath(p, opt['--root']) if opt.get('--root') else p
            records += scan_text(text, lang, rel)
        cat = opt['--catalog']
        eff, ne = render_effects(records)
        notes, nn = render_notes(records)
        ents = entries_tsv(records)
        changed = sum(1 for p, (tx, lg) in texts.items() if strip_comments(tx, lg) != tx)
        lines = sum(count_comment_lines(tx, lg) for tx, lg in texts.values())
        print('MIGRATE\tfiles=%d\tcomment_lines=%d\tpure=%d\teffects=%d\tnotes=%d' % (changed, lines, len([e for e in ents.split('\n') if e]), ne, nn))
        if opt.get('--write-entries-only'):
            open(opt['--entries-out'], 'w', encoding='utf-8').write(ents + ('\n' if ents else ''))
            return 0
        if opt.get('--write'):
            os.makedirs(cat, exist_ok=True)
            open(os.path.join(cat, 'effects.md'), 'w', encoding='utf-8').write(eff)
            open(os.path.join(cat, 'notes.md'), 'w', encoding='utf-8').write(notes)
            open(opt['--entries-out'], 'w', encoding='utf-8').write(ents + ('\n' if ents else ''))
            for p, (tx, lg) in texts.items():
                new = strip_comments(tx, lg)
                if new != tx:
                    open(p, 'w', encoding='utf-8').write(new)
        return 0
    print('code-comments.py: unknown command: %s' % cmd, file=sys.stderr)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
