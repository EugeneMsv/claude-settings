#!/bin/bash
# Flag the tmux window of this Claude session with an attention state, and ring
# the bell. Invoked by Claude Code hooks:
#   Stop         -> "done"  (green)  : Claude finished responding
#   Notification -> "input" (orange) : Claude needs input / permission
# A custom window-status-format in ~/.tmux.conf colors the window by this state.
# The flag is cleared when you focus the window (pane-focus-in hook).
[ -n "$TMUX_PANE" ] || exit 0
state="${1:-done}"
win=$(tmux display-message -p -t "$TMUX_PANE" '#{window_id}' 2>/dev/null)
[ -n "$win" ] || exit 0
# Don't flag the window you're already looking at.
active=$(tmux display-message -p -t "$TMUX_PANE" '#{window_active}' 2>/dev/null)
[ "$active" = "1" ] || { tmux set-option -w -t "$win" @claude_alert "$state"; tmux refresh-client -S 2>/dev/null; }
tty=$(tmux display-message -p -t "$TMUX_PANE" '#{pane_tty}' 2>/dev/null)
[ -n "$tty" ] && [ -w "$tty" ] && printf '\a' > "$tty"
exit 0
