#!/bin/bash
set -f

input=$(cat)

if [ -z "$input" ]; then
    printf "Claude"
    exit 0
fi

# ── Colors ──────────────────────────────────────────────
blue='\033[38;2;160;200;245m'
orange='\033[38;2;240;200;150m'
green='\033[38;2;170;230;170m'
cyan='\033[38;2;130;200;220m'
red='\033[38;2;240;150;150m'
yellow='\033[38;2;240;230;160m'
white='\033[38;2;210;215;220m'
magenta='\033[38;2;200;175;225m'
white_dim='\033[38;2;175;175;178m'
cyan_dim='\033[38;2;90;145;160m'
magenta_dim='\033[38;2;130;115;142m'
orange_bright='\033[38;2;220;180;130m'
orange_dim='\033[38;2;150;125;95m'
orange_dark='\033[38;2;120;100;78m'
dim='\033[2m'
reset='\033[0m'

sep=" ${dim}│${reset} "

# ── Terminal width + right-align helper ────────────────
term_width=""
# Try parent process tty (works inside pipes)
parent_tty=$(ps -o tty= -p $(ps -o ppid= -p $$) 2>/dev/null | tr -d ' ')
if [ -n "$parent_tty" ] && [ "$parent_tty" != "??" ] && [ "$parent_tty" != "?" ]; then
    term_width=$(stty size < "/dev/${parent_tty}" 2>/dev/null | awk '{print $2}')
fi
# Fallback to tput
[ -z "$term_width" ] && term_width=$(tput cols 2>/dev/null)
[ -z "$term_width" ] && term_width=120
# Account for Claude Code's padding + buddy if enabled
status_margin=6
_settings="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
if [ -f "$_settings" ]; then
    buddy_flag=$(jq -r '.statusLineMargin // empty' "$_settings" 2>/dev/null)
    [ "$buddy_flag" = "buddy" ] && status_margin=18
fi
term_width=$(( term_width - status_margin ))

# Get visible display width (strip ANSI, use python3 for wcwidth, fallback wc)
visible_width() {
    local stripped
    stripped=$(printf "%b" "$1" | sed $'s/\033\[[0-9;]*m//g')
    local w
    w=$(python3 -c "
import unicodedata,sys
s=sys.stdin.read().rstrip('\n')
w=0
for c in s:
    eaw=unicodedata.east_asian_width(c)
    if eaw in('W','F'):w+=2
    elif unicodedata.category(c) in('Mn','Me','Cf'):pass
    else:w+=1
print(w)" <<< "$stripped" 2>/dev/null)
    [ -z "$w" ] && w=${#stripped}
    printf "%s" "$w"
}

# Build a line: left + space padding + right, filling terminal width
align_lr() {
    local left="$1" right="$2"
    local left_w right_w spaces pad=""
    left_w=$(visible_width "$left")
    right_w=$(visible_width "$right")
    spaces=$(( term_width - left_w - right_w ))
    [ "$spaces" -lt 1 ] && spaces=1
    printf -v pad "%${spaces}s" ""
    printf "%b%s%b" "$left" "$pad" "$right"
}

# ── Helpers ─────────────────────────────────────────────
color_for_pct() {
    local pct=$1
    if [ "$pct" -ge 90 ]; then printf "$red"
    elif [ "$pct" -ge 70 ]; then printf "$yellow"
    elif [ "$pct" -ge 50 ]; then printf "$orange"
    else printf "$green"
    fi
}

build_bar() {
    local pct=$1
    local width=$2
    local bar_color=$3
    [ "$pct" -lt 0 ] 2>/dev/null && pct=0
    [ "$pct" -gt 100 ] 2>/dev/null && pct=100

    local filled=$(( pct * width / 100 ))
    local empty=$(( width - filled ))

    local filled_str="" empty_str=""
    for ((i=0; i<filled; i++)); do filled_str+="━"; done
    for ((i=0; i<empty; i++)); do empty_str+="┅"; done

    printf "${bar_color}${filled_str}${dim}${empty_str}${reset}"
}

format_epoch_time() {
    local epoch=$1
    local style=$2
    [ -z "$epoch" ] || [ "$epoch" = "null" ] || [ "$epoch" = "0" ] && return

    local result=""
    case "$style" in
        time)
            result=$(date -j -r "$epoch" +"%-H:%M" 2>/dev/null)
            [ -z "$result" ] && result=$(date -d "@$epoch" +"%-H:%M" 2>/dev/null)
            ;;
        datetime)
            result=$(date -j -r "$epoch" +"%-m/%-d %H:%M" 2>/dev/null)
            [ -z "$result" ] && result=$(date -d "@$epoch" +"%-m/%-d %H:%M" 2>/dev/null)
            ;;
        *)
            result=$(date -j -r "$epoch" +"%-m/%-d" 2>/dev/null)
            [ -z "$result" ] && result=$(date -d "@$epoch" +"%-m/%-d" 2>/dev/null)
            result=$(echo "$result" | tr '[:upper:]' '[:lower:]')
            ;;
    esac
    printf "%s" "$result"
}

iso_to_epoch() {
    local iso_str="$1"

    local epoch
    epoch=$(date -d "${iso_str}" +%s 2>/dev/null)
    if [ -n "$epoch" ]; then
        echo "$epoch"
        return 0
    fi

    local stripped="${iso_str%%.*}"
    stripped="${stripped%%Z}"
    stripped="${stripped%%+*}"
    stripped="${stripped%%-[0-9][0-9]:[0-9][0-9]}"

    if [[ "$iso_str" == *"Z"* ]] || [[ "$iso_str" == *"+00:00"* ]] || [[ "$iso_str" == *"-00:00"* ]]; then
        epoch=$(env TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2>/dev/null)
        [ -z "$epoch" ] && epoch=$(env TZ=UTC date -d "${stripped/T/ }" +%s 2>/dev/null)
    else
        epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2>/dev/null)
        [ -z "$epoch" ] && epoch=$(date -d "${stripped/T/ }" +%s 2>/dev/null)
    fi

    if [ -n "$epoch" ]; then
        echo "$epoch"
        return 0
    fi

    return 1
}

# ── Extract JSON data ───────────────────────────────────
model_name=$(echo "$input" | jq -r '.model.display_name // "Claude"')

size=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
[ "$size" -eq 0 ] 2>/dev/null && size=200000

input_tokens=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // 0')
cache_create=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
cache_read=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
current=$(( input_tokens + cache_create + cache_read ))

if [ "$size" -gt 0 ]; then
    pct_used=$(( current * 100 / size ))
else
    pct_used=0
fi

# Format token count: 200000 → 200k, 1000000 → 1M
fmt_tokens() {
    local n=$1
    if [ "$n" -ge 1000000 ]; then
        echo "$(( n / 1000000 ))M"
    elif [ "$n" -ge 1000 ]; then
        echo "$(( n / 1000 ))k"
    else
        echo "$n"
    fi
}
current_fmt=$(fmt_tokens "$current")
size_fmt=$(fmt_tokens "$size")

effort="default"
settings_path="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
if [ -f "$settings_path" ]; then
    effort=$(jq -r '.effortLevel // "default"' "$settings_path" 2>/dev/null)
fi

# ── LINE 1: Model │ Context % │ Directory (branch) │ Session │ Effort ──
pct_color=$(color_for_pct "$pct_used")
cwd=$(echo "$input" | jq -r '.cwd // ""')
[ -z "$cwd" ] || [ "$cwd" = "null" ] && cwd=$(pwd)
dirname=$(basename "$cwd")

git_branch=""
if git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git_branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null)
fi

session_duration=""
session_start=$(echo "$input" | jq -r '.session.start_time // empty')
if [ -n "$session_start" ] && [ "$session_start" != "null" ]; then
    start_epoch=$(iso_to_epoch "$session_start")
    if [ -n "$start_epoch" ]; then
        now_epoch=$(date +%s)
        elapsed=$(( now_epoch - start_epoch ))
        if [ "$elapsed" -ge 3600 ]; then
            session_duration="$(( elapsed / 3600 ))h$(( (elapsed % 3600) / 60 ))m"
        elif [ "$elapsed" -ge 60 ]; then
            session_duration="$(( elapsed / 60 ))m"
        else
            session_duration="${elapsed}s"
        fi
    fi
fi


# Simplify model name: "Opus 4.6 (1M context)" → "Opus 4.6" + dim "(1M)"
blue_dim='\033[38;2;100;135;175m'
model_base=$(echo "$model_name" | sed 's/ ([^)]*)//')
model_ctx=$(echo "$model_name" | sed -n 's/.*(\([^)]*\)).*/\1/p' | sed 's/ context//')
line1_left="${blue}${model_base}${reset}"
[ -n "$model_ctx" ] && line1_left+=" ${blue_dim}(${model_ctx})${reset}"

pink='\033[38;2;240;160;180m'
if [ "$pct_used" -ge 20 ]; then
    ctx_color="$pink"
else
    ctx_color="$white_dim"
fi
ctx_filled=$(( pct_used * 15 / 100 ))
ctx_empty=$(( 15 - ctx_filled ))
ctx_bar="${ctx_color}"
for ((i=0; i<ctx_filled; i++)); do ctx_bar+="█"; done
ctx_bar+="${dim}"
for ((i=0; i<ctx_empty; i++)); do ctx_bar+="░"; done
ctx_bar+="${reset}"
ctx_info='\033[38;2;115;115;118m'
line1_right="${ctx_color}⚡${reset}${ctx_bar} ${ctx_color}${pct_used}%${reset} ${ctx_info}(${current_fmt}/${size_fmt})${reset}"
if [ -n "$git_branch" ]; then
    line1_left+="${sep}"
    line1_left+="${white_dim}"$'\xef\x90\x98'" ${git_branch}${reset}"
    # Git diff stats (staged + unstaged + untracked)
    unstaged=$(git -C "$cwd" diff --shortstat 2>/dev/null)
    staged=$(git -C "$cwd" diff --cached --shortstat 2>/dev/null)
    untracked=$(git -C "$cwd" ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
    ins=0 del=0
    for stat_line in "$unstaged" "$staged"; do
        [ -z "$stat_line" ] && continue
        i=$(echo "$stat_line" | grep -o '[0-9]* insertion' | grep -o '[0-9]*')
        d=$(echo "$stat_line" | grep -o '[0-9]* deletion' | grep -o '[0-9]*')
        [ -n "$i" ] && ins=$(( ins + i ))
        [ -n "$d" ] && del=$(( del + d ))
    done
    git_changes=""
    [ "$ins" -gt 0 ] && git_changes+="${green}+${ins}${reset}"
    [ "$del" -gt 0 ] && { [ -n "$git_changes" ] && git_changes+=" "; git_changes+="${red}-${del}${reset}"; }
    [ "$untracked" -gt 0 ] && { [ -n "$git_changes" ] && git_changes+=" "; git_changes+="${yellow}?${untracked}${reset}"; }
    [ -n "$git_changes" ] && line1_left+=" ${white_dim}(${reset}${git_changes}${white_dim})${reset}"
fi
if [ -n "$session_duration" ]; then
    line1_left+="${sep}"
    line1_left+="${blue}󰔟 ${reset}${white}${session_duration}${reset}"
fi

# ── Rate limits from stdin (primary) ───────────────────
has_stdin_rates=false
five_hour_pct=""
five_hour_reset_epoch=""
seven_day_pct=""
seven_day_reset_epoch=""

stdin_five_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
if [ -n "$stdin_five_pct" ]; then
    has_stdin_rates=true
    five_hour_pct=$(printf "%.0f" "$stdin_five_pct")
    five_hour_reset_epoch=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
    seven_day_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty' | awk '{printf "%.0f", $1}')
    seven_day_reset_epoch=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
fi

# ── Fallback: API call (cached) ────────────────────────
cache_file="/tmp/claude/statusline-usage-cache.json"
cache_max_age=60
mkdir -p /tmp/claude

usage_data=""
extra_enabled="false"

if ! $has_stdin_rates; then
    needs_refresh=true

    if [ -f "$cache_file" ]; then
        cache_mtime=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null)
        now=$(date +%s)
        cache_age=$(( now - cache_mtime ))
        if [ "$cache_age" -lt "$cache_max_age" ]; then
            needs_refresh=false
            usage_data=$(cat "$cache_file" 2>/dev/null)
        fi
    fi

    if $needs_refresh; then
        token=""
        if [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
            token="$CLAUDE_CODE_OAUTH_TOKEN"
        elif command -v security >/dev/null 2>&1; then
            blob=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
            if [ -n "$blob" ]; then
                token=$(echo "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
            fi
        fi
        if [ -z "$token" ] || [ "$token" = "null" ]; then
            creds_file="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json"
            if [ -f "$creds_file" ]; then
                token=$(jq -r '.claudeAiOauth.accessToken // empty' "$creds_file" 2>/dev/null)
            fi
        fi
        if [ -z "$token" ] || [ "$token" = "null" ]; then
            if command -v secret-tool >/dev/null 2>&1; then
                blob=$(timeout 2 secret-tool lookup service "Claude Code-credentials" 2>/dev/null)
                if [ -n "$blob" ]; then
                    token=$(echo "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
                fi
            fi
        fi

        if [ -n "$token" ] && [ "$token" != "null" ]; then
            response=$(curl -s --max-time 5 \
                -H "Accept: application/json" \
                -H "Content-Type: application/json" \
                -H "Authorization: Bearer $token" \
                -H "anthropic-beta: oauth-2025-04-20" \
                -H "User-Agent: claude-code/2.1.34" \
                "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
            if [ -n "$response" ] && echo "$response" | jq -e '.five_hour' >/dev/null 2>&1; then
                usage_data="$response"
                echo "$response" > "$cache_file"
            fi
        fi
        if [ -z "$usage_data" ] && [ -f "$cache_file" ]; then
            usage_data=$(cat "$cache_file" 2>/dev/null)
        fi
    fi

    if [ -n "$usage_data" ] && echo "$usage_data" | jq -e . >/dev/null 2>&1; then
        five_hour_pct=$(echo "$usage_data" | jq -r '.five_hour.utilization // 0' | awk '{printf "%.0f", $1}')
        five_hour_reset_iso=$(echo "$usage_data" | jq -r '.five_hour.resets_at // empty')
        five_hour_reset_epoch=$(iso_to_epoch "$five_hour_reset_iso")
        seven_day_pct=$(echo "$usage_data" | jq -r '.seven_day.utilization // 0' | awk '{printf "%.0f", $1}')
        seven_day_reset_iso=$(echo "$usage_data" | jq -r '.seven_day.resets_at // empty')
        seven_day_reset_epoch=$(iso_to_epoch "$seven_day_reset_iso")

        extra_enabled=$(echo "$usage_data" | jq -r '.extra_usage.is_enabled // false')
    fi
else
    if [ -f "$cache_file" ]; then
        usage_data=$(cat "$cache_file" 2>/dev/null)
        if [ -n "$usage_data" ] && echo "$usage_data" | jq -e . >/dev/null 2>&1; then
            extra_enabled=$(echo "$usage_data" | jq -r '.extra_usage.is_enabled // false')
        fi
    fi
fi

# ── Rate limit lines ────────────────────────────────────
line2_left=""
line3=""
bar_width=15

if [ -n "$five_hour_pct" ]; then
    five_hour_reset=$(format_epoch_time "$five_hour_reset_epoch" "time")
    five_hour_bar=$(build_bar "$five_hour_pct" "$bar_width" "$cyan")

    line2_left+="${cyan}Session${reset} ${five_hour_bar} ${cyan}${five_hour_pct}%${reset}"
    [ -n "$five_hour_reset" ] && line2_left+=" ${cyan_dim}󰑐 (${five_hour_reset})${reset}"
fi

if [ -n "$seven_day_pct" ]; then
    seven_day_reset=$(format_epoch_time "$seven_day_reset_epoch" "datetime")
    seven_day_bar=$(build_bar "$seven_day_pct" "$bar_width" "$magenta")

    [ -n "$line2_left" ] && line2_left+="${sep}"
    line2_left+="${magenta}Weekly${reset} ${seven_day_bar} ${magenta}${seven_day_pct}%${reset}"
    [ -n "$seven_day_reset" ] && line2_left+=" ${magenta_dim}󰑐 (${seven_day_reset})${reset}"
fi

if [ "$extra_enabled" = "true" ] && [ -n "$usage_data" ]; then
    extra_used=$(echo "$usage_data" | jq -r '.extra_usage.used_credits // 0' | awk '{printf "%.2f", $1/100}')
    extra_limit=$(echo "$usage_data" | jq -r '.extra_usage.monthly_limit // 0' | awk '{printf "%.2f", $1/100}')

    line3+="${white_dim}Extra${reset} ${white_dim}\$${extra_used}${reset}${white_dim}/${reset}${ctx_info}\$${extra_limit}${reset}"
fi

# ── Total cost (ccusage, cached) ───────────────────────
cost_cache="/tmp/claude/statusline-cost-cache.txt"
cost_cache_max_age=300
total_cost=""

today_cost=""

if command -v ccusage >/dev/null 2>&1; then
    cost_needs_refresh=true
    if [ -f "$cost_cache" ]; then
        cost_mtime=$(stat -c %Y "$cost_cache" 2>/dev/null || stat -f %m "$cost_cache" 2>/dev/null)
        cost_now=$(date +%s)
        cost_age=$(( cost_now - cost_mtime ))
        [ "$cost_age" -lt "$cost_cache_max_age" ] && cost_needs_refresh=false
    fi

    # Refresh in background — never block statusline rendering
    if $cost_needs_refresh; then
        (ccusage daily --json --offline 2>/dev/null | jq -r '
            (.daily[-1].totalCost // 0 | tostring) + ":" +
            (.totals.totalCost // 0 | tostring)
        ' | awk -F: '{printf "%.2f:%.2f", $1, $2}' > "$cost_cache") &
    fi

    # Always read from cache (may be stale on first run)
    if [ -f "$cost_cache" ]; then
        cached=$(cat "$cost_cache" 2>/dev/null)
        today_cost="${cached%%:*}"
        total_cost="${cached##*:}"
    fi
fi

# ── Output ──────────────────────────────────────────────
# Line 1: left=model+branch+session+effort, right=context bar
align_lr "$line1_left" "$line1_right"

# Line 2: left=Session+Weekly, right=Today+All cost
line2_right=""
if [ -n "$today_cost" ] || [ -n "$total_cost" ]; then
    [ -n "$today_cost" ] && line2_right+="${yellow}\$${today_cost}${reset}"
    [ -n "$today_cost" ] && [ -n "$total_cost" ] && line2_right+=" ${white_dim}→${reset} "
    [ -n "$total_cost" ] && line2_right+="${yellow}\$${total_cost}${reset}"
fi

if [ -n "$line2_left" ] || [ -n "$line2_right" ]; then
    printf "\n\n"
    align_lr "$line2_left" "$line2_right"
fi

# Line 3: Extra (if enabled)
if [ -n "$line3" ]; then
    printf "\n"
    printf "%b" "$line3"
fi

exit 0
