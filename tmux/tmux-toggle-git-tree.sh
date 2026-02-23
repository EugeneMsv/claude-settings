#!/bin/bash
# Toggle the git-tree split pane in the current tmux window.
# Called by tmux bind-key; keeps focus on the originating pane.

# Use a window option to track the pane ID — more reliable than title detection
pane_id=$(tmux show-window-options -v @git_tree_pane 2>/dev/null)

# Check the stored ID is still alive
if [[ -n "$pane_id" ]] && tmux list-panes -F "#{pane_id}" 2>/dev/null | grep -qF "$pane_id"; then
  tmux kill-pane -t "$pane_id"
  tmux set-window-option -u @git_tree_pane
else
  original=$(tmux display-message -p '#{pane_id}')
  path=$(tmux display-message -p '#{pane_current_path}')
  pane_id=$(tmux split-window -h -p 35 -c "$path" -P -F "#{pane_id}" \
    "~/.claude/tmux/tmux-git-tree-loop.sh '$path'")
  tmux set-window-option @git_tree_pane "$pane_id"
  tmux select-pane -t "$original"
fi
