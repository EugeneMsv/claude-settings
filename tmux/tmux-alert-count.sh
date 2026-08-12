#!/bin/bash
# Aggregate Claude attention counter for the tmux status-right.
# Counts windows in the given session by their @claude_alert state and emits a
# colored summary (green = finished/done, orange = needs input). Empty when clear.
# Invoked from status-right as: #(~/.claude/tmux/tmux-alert-count.sh #{session_name})
session="${1:-}"
[ -n "$session" ] || exit 0
done_n=0
input_n=0
while IFS= read -r state; do
    case "$state" in
        done)  done_n=$((done_n + 1)) ;;
        input) input_n=$((input_n + 1)) ;;
    esac
done < <(tmux list-windows -t "$session" -F '#{@claude_alert}' 2>/dev/null)
out=""
[ "$done_n" -gt 0 ]  && out="#[fg=colour114,bold]done:${done_n}#[default]"
[ "$input_n" -gt 0 ] && out="${out}${out:+ }#[fg=colour214,bold]input:${input_n}#[default]"
[ -n "$out" ] && printf '%s ' "$out"
exit 0
