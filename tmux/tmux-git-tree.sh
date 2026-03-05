#!/bin/bash
# Renders git changed files as a colored directory tree.
# Usage: tmux-git-tree.sh [path]

p="${1:-.}"
cols="${2:-}"
git -C "$p" rev-parse --git-dir >/dev/null 2>&1 || { printf "Not a git repo\n"; exit 0; }

# ANSI colors (bright variants)
GREEN='\033[1;92m'
YELLOW='\033[1;93m'
BLUE='\033[1;38;5;39m'
RED='\033[1;91m'
DIM_GREEN='\033[32m'
DIM_BLUE='\033[38;5;25m'
DIM_RED='\033[31m'
RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
CYAN='\033[1;96m'

# Build tab-separated change list: path TAB status_char TAB source
# Staged entries come first so awk keeps them on deduplication
raw_changes=$(
  {
    git -C "$p" diff --cached --name-status 2>/dev/null | while IFS=$'\t' read -r status old_path new_path; do
      if [[ "$status" == R* ]]; then path="$new_path"; else path="$old_path"; fi
      [[ -n "$path" ]] && printf '%s\t%s\tstaged\n' "$path" "${status:0:1}"
    done
    git -C "$p" diff --name-status 2>/dev/null | while IFS=$'\t' read -r status old_path new_path; do
      if [[ "$status" == R* ]]; then path="$new_path"; else path="$old_path"; fi
      [[ -n "$path" ]] && printf '%s\t%s\tunstaged\n' "$path" "${status:0:1}"
    done
  } | awk -F'\t' '!seen[$1]++' | sort
)

# Counts
total=0
staged_count=0
unstaged_count=0
if [[ -n "$raw_changes" ]]; then
  total=$(printf '%s\n' "$raw_changes" | grep -c .)
  staged_count=$(printf '%s\n' "$raw_changes" | awk -F'\t' '$3=="staged"' | grep -c .)
  unstaged_count=$(printf '%s\n' "$raw_changes" | awk -F'\t' '$3=="unstaged"' | grep -c .)
fi

# Branch and tracking info
branch=$(git -C "$p" rev-parse --abbrev-ref HEAD 2>/dev/null)
upstream=$(git -C "$p" rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null)
ahead=0; behind=0
if [[ -n "$upstream" ]]; then
  read -r ahead behind <<< "$(git -C "$p" rev-list --left-right --count HEAD...@{u} 2>/dev/null)"
fi

# Diff stats (staged + unstaged combined, HEAD vs working tree)
stats=$(git -C "$p" diff HEAD --shortstat 2>/dev/null)
ins=$(printf '%s' "$stats" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+')
del=$(printf '%s' "$stats" | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+')

# Terminal width
[[ -z "$cols" ]] && cols=$(tmux display-message -p '#{pane_width}' 2>/dev/null || tput cols 2>/dev/null || printf '80')
divider=$(printf '%*s' "$cols" '' | tr ' ' '─')

# Render change tree into a function to avoid case-in-$() parser issues
render_changes() {
  printf "${BOLD} %s${RESET}" "$branch"
  [[ "$staged_count" -gt 0 ]] && printf " ${GREEN}+%s${RESET}" "$staged_count"
  [[ "$unstaged_count" -gt 0 ]] && printf " ${YELLOW}!%s${RESET}" "$unstaged_count"
  [[ "$ahead" -gt 0 ]] && printf "  ${GREEN}↑%s${RESET}" "$ahead"
  [[ "$behind" -gt 0 ]] && printf "  ${RED}↓%s${RESET}" "$behind"
  printf '\n'
  printf "${BOLD} Changed (%d)${RESET}" "$total"
  [[ -n "$ins" ]] && printf "  ${GREEN}+%s${RESET}" "$ins"
  [[ -n "$del" ]] && printf "  ${RED}-%s${RESET}" "$del"
  printf '\n'
  printf "${DIM}%s${RESET}\n" "$divider"

  if [[ "$total" -eq 0 ]]; then
    printf "${DIM} (no changes)${RESET}\n"
  else
    prev_dirs=()
    prev_vdepths=()

    while IFS=$'\t' read -r fpath status source; do
      [[ -z "$fpath" ]] && continue

      if [[ "$source" == "staged" ]]; then
        case "$status" in
          A) color="$GREEN" ;;
          D) color="$RED"   ;;
          *) color="$BLUE"  ;;
        esac
      else
        case "$status" in
          A) color="$DIM_GREEN" ;;
          D) color="$DIM_RED"   ;;
          *) color="$DIM_BLUE"  ;;
        esac
      fi

      IFS='/' read -ra parts <<< "$fpath"
      n_dirs=$(( ${#parts[@]} - 1 ))
      filename="${parts[$(( ${#parts[@]} - 1 ))]}"

      common=0
      for (( i=0; i<n_dirs && i<${#prev_dirs[@]}; i++ )); do
        if [[ "${parts[$i]}" == "${prev_dirs[$i]}" ]]; then
          (( common++ ))
        else
          break
        fi
      done

      # Visual depth: 1 per printed group, not per segment
      if [[ "$common" -eq 0 ]]; then
        vdepth=0
      else
        vdepth=$(( prev_vdepths[common - 1] + 1 ))
      fi

      # Print new dirs, collapsing up to 3 per line if they fit in terminal width
      i=common
      while (( i < n_dirs )); do
        for (( try=3; try>=1; try-- )); do
          end=$(( i + try ))
          (( end > n_dirs )) && end=$n_dirs
          group=""
          for (( j=i; j<end; j++ )); do
            group="${group}${parts[$j]}/"
          done
          indent_str=$(printf '%*s' "$vdepth" '' | tr ' ' '-')
          if (( (${#indent_str} + ${#group}) <= cols || try == 1 )); then
            printf "${DIM}%s${RESET}${BOLD}%s${RESET}\n" "$indent_str" "$group"
            for (( k=i; k<end; k++ )); do prev_vdepths[$k]=$vdepth; done
            i=$end
            (( vdepth++ ))
            break
          fi
        done
      done

      prev_dirs=()
      for (( i=0; i<n_dirs; i++ )); do
        prev_dirs[$i]="${parts[$i]}"
      done

      indent=$(printf '%*s' "$vdepth" '' | tr ' ' '-')
      printf "${DIM}%s${RESET}${color}%s${RESET}\n" "$indent" "$filename"

    done <<< "$raw_changes"
  fi

  printf "${DIM}%s${RESET}\n" "$divider"
  printf "${DIM} Staged: %d  Unstaged: %d${RESET}\n" "$staged_count" "$unstaged_count"
}

render_changes
printf "${DIM}%s${RESET}\n" "$divider"
printf "${BOLD} Commits${RESET}\n"
git -C "$p" log --no-decorate -n 10 \
    --format="%ad%x09%an%x09%s" \
    --date=format:"%m/%d %H:%M" 2>/dev/null \
  | while IFS=$'\t' read -r date author msg; do
      if [[ "$author" == *" "* ]]; then
        first="${author%% *}"; last="${author##* }"
      elif [[ "$author" == *"."* ]]; then
        first="${author%%.*}"; last="${author##*.}"
      else
        first="$author"; last="$author"
      fi
      [[ "$first" == "$last" ]] && short="$first" || short="$first ${last:0:1}."
      line=" $date  $short  $msg"
      printf "${DIM}%s${RESET}\n" "${line:0:$cols}"
    done

# AI Contribution
repo_root=$(git -C "$p" rev-parse --show-toplevel 2>/dev/null)
branch_sanitized=$(printf '%s' "$branch" | tr '/\\' '-')
herald_file="$repo_root/.claude/herald/${branch_sanitized}.json"
tracker_file="$repo_root/.claude/ai-tracking-${branch_sanitized}.json"
[[ -f "$herald_file" ]] && ai_file="$herald_file" || ai_file="$tracker_file"

if [[ -f "$ai_file" ]]; then
  ai_data=$(awk '
    /^    "ai":/      { in_ai=1; in_hu=0 }
    /^    "human":/   { in_ai=0; in_hu=1 }
    /^      "total":/   { sect="total" }
    /^      "added":/   { sect="added" }
    /^      "removed":/ { sect="removed" }
    /^        "lines":/ {
      val=$0; gsub(/^[^:]*: /,"",val); gsub(/,?[ \t]*$/,"",val)
      if(in_ai && sect=="total")   ai_tl=val
      if(in_ai && sect=="added")   ai_al=val
      if(in_ai && sect=="removed") ai_rl=val
      if(in_hu && sect=="total")   hu_tl=val
      if(in_hu && sect=="added")   hu_al=val
      if(in_hu && sect=="removed") hu_rl=val
    }
    /^        "percentage":/ {
      val=$0; gsub(/^[^:]*: /,"",val); gsub(/,?[ \t]*$/,"",val)
      if(in_ai && sect=="total") ai_tp=val
      if(in_hu && sect=="total") hu_tp=val
    }
    END { printf "%s|%s|%s|%s|%s|%s|%s|%s\n", ai_tl,ai_tp,hu_tl,hu_tp,ai_al,ai_rl,hu_al,hu_rl }
  ' "$ai_file")

  if [[ -n "$ai_data" && "$ai_data" != "|||||||" ]]; then
    IFS='|' read -r ai_lines ai_pct hu_lines hu_pct ai_added ai_removed hu_added hu_removed <<< "$ai_data"

    # Single split bar: cyan (AI) left, yellow (Human) right
    bar_width=28
    ai_w=$(( (${ai_pct%.*} * bar_width + 50) / 100 ))
    [[ $ai_w -gt $bar_width ]] && ai_w=$bar_width
    [[ $ai_w -lt 0 ]] && ai_w=0
    ai_seg=""; hu_seg=""
    for (( i=0;    i<ai_w;      i++ )); do ai_seg+="▓"; done
    for (( i=ai_w; i<bar_width; i++ )); do hu_seg+="▓"; done

    # Strings for each column (no ANSI — used for length measurement)
    ai_pct_str=$(printf "%.1f%%" "$ai_pct")
    hu_pct_str=$(printf "%.1f%%" "$hu_pct")
    ai_stat_str=$(printf "%d: +%d -%d" "$ai_lines" "$ai_added" "$ai_removed")
    hu_stat_str=$(printf "%d: +%d -%d" "$hu_lines" "$hu_added" "$hu_removed")

    # | separator always at bar centre: 1(space) + 1([) + bar_width/2
    lw=$(( bar_width / 2 + 1 ))

    p1=$(( lw - 2 ));           [[ $p1 -lt 0 ]] && p1=0   # pad after "AI"
    p2=$(( lw - ${#ai_pct_str} )); [[ $p2 -lt 0 ]] && p2=0
    p4=$(( lw - ${#ai_stat_str} )); [[ $p4 -lt 0 ]] && p4=0

    printf "${DIM}%s${RESET}\n" "$divider"
    printf " ${CYAN}${BOLD}AI${RESET}%*s|${YELLOW}${BOLD}    Human${RESET}\n"        "$p1" ""
    printf " ${CYAN}%s${RESET}%*s|${YELLOW}    %s${RESET}\n"  "$ai_pct_str"  "$p2" "" "$hu_pct_str"
    printf " [${CYAN}%s${RESET}${YELLOW}%s${RESET}]\n"        "$ai_seg" "$hu_seg"
    printf "${DIM} %s%*s| %s${RESET}\n"                       "$ai_stat_str" "$p4" "" "$hu_stat_str"
  fi
fi
