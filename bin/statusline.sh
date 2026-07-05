#!/bin/bash
set -f

input=$(cat)

if [ -z "$input" ]; then
    printf "Claude"
    exit 0
fi

# ── 终端宽度检测：窄于阈值走 compact 模式（单行精简） ──
term_cols=$(tput cols 2>/dev/null)
[ -z "$term_cols" ] && term_cols=$(stty size 2>/dev/null | awk '{print $2}')
[ -z "$term_cols" ] && term_cols=${COLUMNS:-999}
compact_mode=false
if [ "$term_cols" -lt 100 ] 2>/dev/null; then
    compact_mode=true
fi

# ── Colors ──────────────────────────────────────────────
blue='\033[38;2;0;153;255m'
orange='\033[38;2;255;176;85m'
green='\033[38;2;0;175;80m'
cyan='\033[38;2;86;182;194m'
red='\033[38;2;255;85;85m'
yellow='\033[38;2;230;200;0m'
white='\033[38;2;220;220;220m'
magenta='\033[38;2;180;140;255m'
dim='\033[2m'
reset='\033[0m'

sep=" ${dim}│${reset} "

# ── Helpers ─────────────────────────────────────────────
format_tokens() {
    local num=$1
    if [ "$num" -ge 1000000 ]; then
        awk "BEGIN {v = $num / 1000000; if (v == int(v)) printf \"%dM\", v; else printf \"%.1fM\", v}"
    elif [ "$num" -ge 1000 ]; then
        awk "BEGIN {v = $num / 1000; if (v == int(v)) printf \"%dK\", v; else printf \"%.1fK\", v}"
    else
        printf "%d" "$num"
    fi
}

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
    [ "$pct" -lt 0 ] 2>/dev/null && pct=0
    [ "$pct" -gt 100 ] 2>/dev/null && pct=100

    local filled=$(( pct * width / 100 ))
    local empty=$(( width - filled ))
    local bar_color
    bar_color=$(color_for_pct "$pct")

    local filled_str="" empty_str=""
    for ((i=0; i<filled; i++)); do filled_str+="●"; done
    for ((i=0; i<empty; i++)); do empty_str+="○"; done

    printf "${bar_color}${filled_str}${dim}${empty_str}${reset}"
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
    else
        epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2>/dev/null)
    fi

    if [ -n "$epoch" ]; then
        echo "$epoch"
        return 0
    fi

    return 1
}

format_reset_time() {
    local iso_str="$1"
    local style="$2"
    [ -z "$iso_str" ] || [ "$iso_str" = "null" ] && return

    local epoch
    epoch=$(iso_to_epoch "$iso_str")
    [ -z "$epoch" ] && return

    case "$style" in
        time)
            date -j -r "$epoch" +"%l:%M%p" 2>/dev/null | sed 's/^ //; s/\.//g' | tr '[:upper:]' '[:lower:]' || \
            date -d "@$epoch" +"%l:%M%P" 2>/dev/null | sed 's/^ //; s/\.//g'
            ;;
        datetime)
            date -j -r "$epoch" +"%b %-d, %l:%M%p" 2>/dev/null | sed 's/  / /g; s/^ //; s/\.//g' | tr '[:upper:]' '[:lower:]' || \
            date -d "@$epoch" +"%b %-d, %l:%M%P" 2>/dev/null | sed 's/  / /g; s/^ //; s/\.//g'
            ;;
        *)
            date -j -r "$epoch" +"%b %-d" 2>/dev/null | tr '[:upper:]' '[:lower:]' || \
            date -d "@$epoch" +"%b %-d" 2>/dev/null
            ;;
    esac
}

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/claude"
mkdir -p "$cache_dir"

read_cache_if_fresh() {
    local file="$1"
    local max_age="$2"
    [ ! -f "$file" ] && return 1

    local cache_mtime now cache_age
    cache_mtime=$(stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null)
    [ -z "$cache_mtime" ] && return 1
    now=$(date +%s)
    cache_age=$(( now - cache_mtime ))
    [ "$cache_age" -ge "$max_age" ] && return 1

    cat "$file" 2>/dev/null
}

# ── Codex status resolution ─────────────────────────────
get_codex_model() {
    local cache_file="$cache_dir/statusline-codex-model-cache.txt"
    local model

    model=$(read_cache_if_fresh "$cache_file" 300)
    if [ -n "$model" ]; then
        echo "$model"
        return 0
    fi

    if command -v codex >/dev/null 2>&1; then
        model=$(codex doctor --json 2>/dev/null | jq -r '.checks["config.load"].details.model // empty' 2>/dev/null)
        if [ -n "$model" ] && [ "$model" != "null" ]; then
            echo "$model" > "$cache_file"
            echo "$model"
            return 0
        fi
    fi

    return 1
}

get_codex_usage() {
    local cache_file="$cache_dir/statusline-codex-usage-cache.json"
    local data

    data=$(read_cache_if_fresh "$cache_file" 60)
    if [ -n "$data" ] && echo "$data" | jq -e '.[0].usage.primary.usedPercent' >/dev/null 2>&1; then
        echo "$data"
        return 0
    fi

    if command -v codexbar >/dev/null 2>&1; then
        data=$(codexbar usage --provider codex --format json --no-color 2>/dev/null)
        if [ -n "$data" ] && echo "$data" | jq -e '.[0].usage.primary.usedPercent' >/dev/null 2>&1; then
            echo "$data" > "$cache_file"
            echo "$data"
            return 0
        fi
    fi

    if [ -f "$cache_file" ]; then
        data=$(cat "$cache_file" 2>/dev/null)
        if [ -n "$data" ] && echo "$data" | jq -e '.[0].usage.primary.usedPercent' >/dev/null 2>&1; then
            echo "$data"
            return 0
        fi
    fi

    return 1
}

# ── Extract JSON data ───────────────────────────────────
model_display=$(echo "$input" | jq -r '.model.display_name // "Claude"')
model_raw=$(printf "%s" "$model_display" | tr '[:upper:]' '[:lower:]')
model_name="$model_display"

size=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
[ "$size" -eq 0 ] 2>/dev/null && size=200000

# Prefer the backend model name exposed by a local Anthropic-compatible proxy.
# Example: ANTHROPIC_DEFAULT_OPUS_MODEL_NAME=gpt-5.5 -> "gpt-5.5 via Opus".
case "$model_raw" in
    *opus*)
        [ -n "$ANTHROPIC_DEFAULT_OPUS_MODEL_NAME" ] && model_name="$ANTHROPIC_DEFAULT_OPUS_MODEL_NAME via Opus"
        ;;
    *fable*)
        [ -n "$ANTHROPIC_DEFAULT_FABLE_MODEL_NAME" ] && model_name="$ANTHROPIC_DEFAULT_FABLE_MODEL_NAME via Fable"
        ;;
    *sonnet*)
        [ -n "$ANTHROPIC_DEFAULT_SONNET_MODEL_NAME" ] && model_name="$ANTHROPIC_DEFAULT_SONNET_MODEL_NAME via Sonnet"
        ;;
    *haiku*)
        [ -n "$ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME" ] && model_name="$ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME via Haiku"
        ;;
esac

input_tokens=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // 0')
cache_create=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
cache_read=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
current=$(( input_tokens + cache_create + cache_read ))

used_tokens=$(format_tokens $current)
total_tokens=$(format_tokens $size)

if [ "$size" -gt 0 ]; then
    pct_used=$(( current * 100 / size ))
else
    pct_used=0
fi

thinking_on=false
settings_path="$HOME/.claude/settings.json"
if [ -f "$settings_path" ]; then
    thinking_val=$(jq -r '.alwaysThinkingEnabled // false' "$settings_path" 2>/dev/null)
    [ "$thinking_val" = "true" ] && thinking_on=true
fi

# ── LINE 1: Model │ Context % │ Directory (branch) │ Session │ Thinking ──
pct_color=$(color_for_pct "$pct_used")
cwd=$(echo "$input" | jq -r '.cwd // ""')
[ -z "$cwd" ] || [ "$cwd" = "null" ] && cwd=$(pwd)
dirname=$(basename "$cwd")

git_branch=""
git_dirty=""
if git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git_branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null)
    if [ -n "$(git -C "$cwd" status --porcelain 2>/dev/null)" ]; then
        git_dirty="*"
    fi
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

line1="${blue}${model_name}${reset}"
line1+="${sep}"
line1+="${dim}Context${reset} ${pct_color}${used_tokens}${reset} ${dim}/${reset} ${pct_color}${total_tokens}${reset}"
line1+="${sep}"
line1+="${cyan}${dirname}${reset}"
if [ -n "$git_branch" ]; then
    branch_disp="$git_branch"
    if $compact_mode && [ ${#branch_disp} -gt 18 ]; then
        branch_disp="${branch_disp:0:17}…"
    fi
    line1+=" ${green}(${branch_disp}${red}${git_dirty}${green})${reset}"
fi
if ! $compact_mode; then
    if [ -n "$session_duration" ]; then
        line1+="${sep}"
        line1+="${dim}⏱ ${reset}${white}${session_duration}${reset}"
    fi
    line1+="${sep}"
    if $thinking_on; then
        line1+="${magenta}◐ thinking${reset}"
    else
        line1+="${dim}◑ thinking${reset}"
    fi
fi

# ── Claude OAuth token resolution (fallback only) ───────
get_oauth_token() {
    local token=""

    if [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
        echo "$CLAUDE_CODE_OAUTH_TOKEN"
        return 0
    fi

    if command -v security >/dev/null 2>&1; then
        local blob
        blob=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
        if [ -n "$blob" ]; then
            token=$(echo "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
            if [ -n "$token" ] && [ "$token" != "null" ]; then
                echo "$token"
                return 0
            fi
        fi
    fi

    local creds_file="${HOME}/.claude/.credentials.json"
    if [ -f "$creds_file" ]; then
        token=$(jq -r '.claudeAiOauth.accessToken // empty' "$creds_file" 2>/dev/null)
        if [ -n "$token" ] && [ "$token" != "null" ]; then
            echo "$token"
            return 0
        fi
    fi

    if command -v secret-tool >/dev/null 2>&1; then
        local blob
        blob=$(timeout 2 secret-tool lookup service "Claude Code-credentials" 2>/dev/null)
        if [ -n "$blob" ]; then
            token=$(echo "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
            if [ -n "$token" ] && [ "$token" != "null" ]; then
                echo "$token"
                return 0
            fi
        fi
    fi

    echo ""
}

get_claude_usage() {
    local cache_file="$cache_dir/statusline-claude-usage-cache.json"
    local usage_data response token

    usage_data=$(read_cache_if_fresh "$cache_file" 60)
    if [ -n "$usage_data" ] && echo "$usage_data" | jq -e '.five_hour' >/dev/null 2>&1; then
        echo "$usage_data"
        return 0
    fi

    token=$(get_oauth_token)
    if [ -n "$token" ] && [ "$token" != "null" ]; then
        response=$(curl -s --max-time 5 \
            -H "Accept: application/json" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $token" \
            -H "anthropic-beta: oauth-2025-04-20" \
            -H "User-Agent: claude-code/2.1.34" \
            "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
        if [ -n "$response" ] && echo "$response" | jq -e '.five_hour' >/dev/null 2>&1; then
            echo "$response" > "$cache_file"
            echo "$response"
            return 0
        fi
    fi

    if [ -f "$cache_file" ]; then
        usage_data=$(cat "$cache_file" 2>/dev/null)
        if [ -n "$usage_data" ] && echo "$usage_data" | jq -e '.five_hour' >/dev/null 2>&1; then
            echo "$usage_data"
            return 0
        fi
    fi

    return 1
}

# ── Rate limit lines ────────────────────────────────────
rate_lines=""
usage_data=$(get_codex_usage)
usage_provider="codex"
if [ -z "$usage_data" ]; then
    usage_data=$(get_claude_usage)
    usage_provider="claude"
fi

if [ -n "$usage_data" ] && echo "$usage_data" | jq -e . >/dev/null 2>&1; then
    if $compact_mode; then
        bar_width=6
    else
        bar_width=10
    fi

    if [ "$usage_provider" = "codex" ]; then
        primary_pct=$(echo "$usage_data" | jq -r '.[0].usage.primary.usedPercent // 0' | awk '{printf "%.0f", $1}')
        primary_reset_iso=$(echo "$usage_data" | jq -r '.[0].usage.primary.resetsAt // empty')
        primary_reset=$(format_reset_time "$primary_reset_iso" "time")
        primary_bar=$(build_bar "$primary_pct" "$bar_width")
        primary_pct_color=$(color_for_pct "$primary_pct")
        primary_pct_fmt=$(printf "%3d" "$primary_pct")

        rate_lines+="${white}current${reset} ${primary_bar} ${primary_pct_color}${primary_pct_fmt}%${reset} ${dim}⟳${reset} ${white}${primary_reset}${reset}"

        secondary_pct=$(echo "$usage_data" | jq -r '.[0].usage.secondary.usedPercent // 0' | awk '{printf "%.0f", $1}')
        secondary_reset_iso=$(echo "$usage_data" | jq -r '.[0].usage.secondary.resetsAt // empty')
        secondary_reset=$(format_reset_time "$secondary_reset_iso" "datetime")
        secondary_bar=$(build_bar "$secondary_pct" "$bar_width")
        secondary_pct_color=$(color_for_pct "$secondary_pct")
        secondary_pct_fmt=$(printf "%3d" "$secondary_pct")

        rate_lines+="\n${white}weekly${reset}  ${secondary_bar} ${secondary_pct_color}${secondary_pct_fmt}%${reset} ${dim}⟳${reset} ${white}${secondary_reset}${reset}"

        reset_credits=$(echo "$usage_data" | jq -r '.[0].usage.codexResetCredits.availableCount // empty')
        if [ -n "$reset_credits" ] && [ "$reset_credits" != "null" ]; then
            rate_lines+="\n${white}resets${reset}  ${green}${reset_credits}${reset} ${dim}full reset credits${reset}"
        fi
    else
        five_hour_pct=$(echo "$usage_data" | jq -r '.five_hour.utilization // 0' | awk '{printf "%.0f", $1}')
        five_hour_reset_iso=$(echo "$usage_data" | jq -r '.five_hour.resets_at // empty')
        five_hour_reset=$(format_reset_time "$five_hour_reset_iso" "time")
        five_hour_bar=$(build_bar "$five_hour_pct" "$bar_width")
        five_hour_pct_color=$(color_for_pct "$five_hour_pct")
        five_hour_pct_fmt=$(printf "%3d" "$five_hour_pct")

        rate_lines+="${white}current${reset} ${five_hour_bar} ${five_hour_pct_color}${five_hour_pct_fmt}%${reset} ${dim}⟳${reset} ${white}${five_hour_reset}${reset}"

        seven_day_pct=$(echo "$usage_data" | jq -r '.seven_day.utilization // 0' | awk '{printf "%.0f", $1}')
        seven_day_reset_iso=$(echo "$usage_data" | jq -r '.seven_day.resets_at // empty')
        seven_day_reset=$(format_reset_time "$seven_day_reset_iso" "datetime")
        seven_day_bar=$(build_bar "$seven_day_pct" "$bar_width")
        seven_day_pct_color=$(color_for_pct "$seven_day_pct")
        seven_day_pct_fmt=$(printf "%3d" "$seven_day_pct")

        rate_lines+="\n${white}weekly${reset}  ${seven_day_bar} ${seven_day_pct_color}${seven_day_pct_fmt}%${reset} ${dim}⟳${reset} ${white}${seven_day_reset}${reset}"

        extra_enabled=$(echo "$usage_data" | jq -r '.extra_usage.is_enabled // false')
        if [ "$extra_enabled" = "true" ]; then
            extra_pct=$(echo "$usage_data" | jq -r '.extra_usage.utilization // 0' | awk '{printf "%.0f", $1}')
            extra_used=$(echo "$usage_data" | jq -r '.extra_usage.used_credits // 0' | awk '{printf "%.2f", $1/100}')
            extra_limit=$(echo "$usage_data" | jq -r '.extra_usage.monthly_limit // 0' | awk '{printf "%.2f", $1/100}')
            extra_bar=$(build_bar "$extra_pct" "$bar_width")
            extra_pct_color=$(color_for_pct "$extra_pct")

            extra_reset=$(date -v+1m -v1d +"%b %-d" 2>/dev/null | tr '[:upper:]' '[:lower:]')
            if [ -z "$extra_reset" ]; then
                extra_reset=$(date -d "$(date +%Y-%m-01) +1 month" +"%b %-d" 2>/dev/null | tr '[:upper:]' '[:lower:]')
            fi

            extra_col="${white}extra${reset}   ${extra_bar} ${extra_pct_color}\$${extra_used}${dim}/${reset}${white}\$${extra_limit}${reset}"
            extra_reset_line="${dim}resets ${reset}${white}${extra_reset}${reset}"
            rate_lines+="\n${extra_col}"
            rate_lines+="\n${extra_reset_line}"
        fi
    fi
fi

# ── Output ──────────────────────────────────────────────
printf "%b" "$line1"
if [ -n "$rate_lines" ]; then
    if $compact_mode; then
        printf "\n%b" "$rate_lines"
    else
        printf "\n\n%b" "$rate_lines"
    fi
fi

exit 0
