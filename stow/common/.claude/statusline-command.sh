#!/usr/bin/env bash
input=$(cat)

RESET=$'\033[0m'
CYAN=$'\033[36m'
BLUE=$'\033[34m'
MAGENTA=$'\033[35m'
YELLOW=$'\033[33m'
GREEN=$'\033[32m'

model=$(jq -r '.model.display_name // .model.id // empty' <<<"$input" | sed 's/Claude //')
cwd=$(jq -r '.workspace.current_dir // .cwd // empty' <<<"$input")
used=$(jq -r '.context_window.used_percentage // empty' <<<"$input")
five_hour=$(jq -r '.rate_limits.five_hour.used_percentage // empty' <<<"$input")
resets_at=$(jq -r '.rate_limits.five_hour.resets_at // empty' <<<"$input")

dir_display=""
[[ -n $cwd ]] && dir_display="${cwd/#$HOME/\~}"

branch=""
if [[ -n $cwd ]] && git -C "$cwd" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null)
  [[ -n $branch ]] || branch=$(git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
fi

parts=()
[[ -n $model ]] && parts+=("${CYAN}⚡ ${model}${RESET}")
[[ -n $dir_display ]] && parts+=("${BLUE}${dir_display}${RESET}")
[[ -n $branch ]] && parts+=("${MAGENTA} ${branch}${RESET}")
[[ -n $used ]] && parts+=("${YELLOW}🧠 $(printf '%.0f' "$used")%${RESET}")

if [[ -n $five_hour ]]; then
  five_hour_fmt="⏳ $(printf '%.0f' "$five_hour")%"
  if [[ -n $resets_at ]]; then
    reset_time=$(date -d "@$resets_at" '+%H:%M' 2>/dev/null || date -r "$resets_at" '+%H:%M' 2>/dev/null)
    [[ -n $reset_time ]] && five_hour_fmt="$five_hour_fmt (reset $reset_time)"
  fi
  parts+=("${GREEN}${five_hour_fmt}${RESET}")
fi

output=""
for part in "${parts[@]}"; do
  [[ -z $output ]] && output=$part || output="$output · $part"
done
printf '%s' "$output"
