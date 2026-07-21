---
name: gclean
description: merge 후 원격에서 삭제된(upstream [gone]) 로컬 작업 브랜치를 안전하게 정리한다. 보호 브랜치(main·develop·stage)와 현재 브랜치는 절대 삭제하지 않고, 삭제 결과와 복구용 SHA를 출력한다.
trigger: /gclean
---

# /gclean — merge되어 사라진 로컬 브랜치 정리

원격에서 삭제된(merge 후 GitHub/GitLab이 head 브랜치를 지운) 브랜치의 **로컬 잔여**를 정리한다.

## 절대 규칙
- **보호 브랜치 `main` · `develop` · `stage` 는 절대 삭제하지 않는다.**
- **현재 체크아웃된 브랜치는 절대 삭제하지 않는다.**
- upstream이 `[gone]` 인 것만 대상 (= 원격이 사라짐). ahead/behind/정상 추적 브랜치는 건드리지 않는다.
- 삭제 결과(브랜치명 + 복구용 SHA)를 반드시 출력한다.

## 실행 (아래 블록을 한 번에 그대로 실행)

```bash
git fetch --prune
CURRENT=$(git symbolic-ref --quiet --short HEAD || echo "(detached)")

# gone(원격 삭제) 로컬 브랜치 목록 — 트렁크/현재 제외
GONE=$(git for-each-ref --format '%(refname:short) %(upstream:track)' refs/heads \
  | awk '$2=="[gone]"{print $1}' \
  | grep -vxE 'main|develop|stage' \
  | { grep -vxF "$CURRENT" || true; })

if [ -z "$GONE" ]; then
  echo "정리할 브랜치 없음 (gone 상태 로컬 브랜치가 없습니다)."
else
  echo "=== 삭제 대상 (upstream=gone) ==="
  # 반드시 while read 로 순회 (for b in $GONE 는 여러 줄에서 워드분할 실패)
  printf '%s\n' "$GONE" | while IFS= read -r b; do
    [ -z "$b" ] && continue
    sha=$(git rev-parse --short "$b")
    printf "  %-40s %s\n" "$b" "$(git log -1 --format='%h %s' "$b")"
    git branch -D "$b" >/dev/null 2>&1 && echo "    → 삭제됨 (복구용 SHA $sha)" || echo "    → 삭제 실패"
  done
fi
```

실행 후 결과를 사용자에게 보고하라. 목록에 **merge된 작업 브랜치가 아닌 예상 밖 브랜치**가 보이면 언급하고 확인을 권한다(그래도 삭제는 로컬 전용이라 복구 가능).

## 복구 (실수 시)
삭제는 로컬 전용이며 30일간 reflog로 복구 가능:
```bash
git reflog                 # 또는: git fsck --no-reflogs --lost-found
git branch <name> <sha>    # 위 출력의 '복구용 SHA'로 되살리기
```

## 참고
- `[gone]` 은 "원격 브랜치가 삭제됨"만 의미한다. 드물게 "merge 안 됐는데 원격만 삭제"된 경우도 포함될 수 있다.
- 브랜치 전략은 `.github/BRANCHING.md` 참조.
