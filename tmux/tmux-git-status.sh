#!/bin/bash
p="$1"
git -C "$p" rev-parse --git-dir >/dev/null 2>&1 || exit 0
b=$(git -C "$p" rev-parse --abbrev-ref HEAD 2>/dev/null)
[ -n "$b" ] || exit 0
printf "%s" "$b"
s=$(git -C "$p" diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
u=$(git -C "$p" diff --name-only 2>/dev/null | wc -l | tr -d ' ')
[ "${s:-0}" -gt 0 ] && printf " +%s" "$s"
[ "${u:-0}" -gt 0 ] && printf " !%s" "$u"
a=$(git -C "$p" rev-list --count "HEAD@{upstream}..HEAD" 2>/dev/null)
[ "${a:-0}" -gt 0 ] 2>/dev/null && printf " ↑%s" "$a"
r=$(git -C "$p" rev-list --count "HEAD..HEAD@{upstream}" 2>/dev/null)
[ "${r:-0}" -gt 0 ] 2>/dev/null && printf " ↓%s" "$r"
base=$(git -C "$p" rev-parse --abbrev-ref origin/HEAD 2>/dev/null | sed 's|origin/||')
c=$(git -C "$p" rev-list --count "${base:-main}..HEAD" 2>/dev/null)
[ "${c:-0}" -gt 0 ] 2>/dev/null && printf " commits=%s" "$c"
