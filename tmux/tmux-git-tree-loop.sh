#!/bin/bash
# Refresh loop for the git-tree pane. Renders to a buffer first to avoid flicker.
path="$1"
printf '\033[?7l'  # disable line wrap for this pane
while true; do
  cols=$(tmux display-message -p '#{pane_width}' 2>/dev/null || tput cols 2>/dev/null || printf '80')
  out=$(~/.claude/tmux/tmux-git-tree.sh "$path" "$cols")
  clear
  printf '%s\n' "$out"
  sleep 2
done
