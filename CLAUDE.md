# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

claude-statusline is an npm package (`@zynoo/claude-statusline`), forked from `@kamranahmedse/claude-statusline`, that provides a custom status line for Claude Code CLI. It displays model info, context window usage, rate limits, directory/git branch, session duration, and effort level.

## Installation & Testing

```bash
# Run via bunx (configured in Claude Code settings.json)
bunx @zynoo/claude-statusline

# With all options
bunx @zynoo/claude-statusline --cache-ttl 120 --bar-style shade --usage-style compact
```

There are no automated tests or linting. Testing is manual — install the statusline and verify it renders correctly in Claude Code.

**Requirements**: jq, curl, git must be installed on the system.

## Architecture

Two files do all the work:

- **`bin/install.js`** — Node.js CLI entry point. Passes CLI arguments through to the shell script.

- **`bin/statusline.sh`** — Bash script that Claude Code invokes. Reads JSON context from stdin (model, tokens, session info), fetches rate limits from the Anthropic API (cached with configurable TTL in `/tmp/claude/`), and outputs a colored status display.

### Data Flow

1. Claude Code pipes JSON context to `statusline.sh` via stdin
2. Script extracts model name, context usage, cwd, session start time
3. Git branch/dirty state detected if in a repo
4. Effort level detected from session transcript JSONL (supports max/xhigh/high/medium/low), fallback to settings.json
5. OAuth token retrieved (env var → macOS Keychain → credentials file → Linux secret-tool)
6. Rate limit data fetched from API with file-based caching (default 120s, configurable via `--cache-ttl`)
7. Formatted output with Catppuccin Mocha ANSI colors rendered to stdout

### Status Line Output

- **Default mode**: Line 1 (model, context %, dir, branch, session, effort) + multi-line rate limits
- **Compact mode** (`--usage-style compact`): Line 1 + single-line usage with remaining time

### CLI Arguments

- `--cache-ttl <seconds>` — API cache TTL (default 120)
- `--bar-style <style>` — Bar character style: `diamond` (default), `block`, `dot`, `arrow`, `square`, `shade`
- `--usage-style <style>` — Usage layout: `default` (multi-line) or `compact` (single-line)
- `--time-style <style>` — Time format: `remaining` (default, e.g. `1h·4m left`) or `absolute` (e.g. `12:00am`)

### Environment Variables

CLI arguments take priority over environment variables:

- `CLAUDE_STATUSLINE_BAR_STYLE` — Same as `--bar-style`
- `CLAUDE_STATUSLINE_USAGE_STYLE` — Same as `--usage-style`
- `CLAUDE_STATUSLINE_TIME_STYLE` — Same as `--time-style`
