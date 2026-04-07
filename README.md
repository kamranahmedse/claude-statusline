# claude-statusline (fork)

A redesigned Claude Code statusline with pastel colors, right-aligned layout, and cost tracking.

Forked from [kamranahmedse/claude-statusline](https://github.com/kamranahmedse/claude-statusline).

## What's different

- **Pastel color palette** — soft, low-contrast colors that don't strain your eyes
- **Right-aligned layout** — context window (line 1) and cost info (line 2) align to the right edge
- **Cost tracking** — daily and total cost via [ccusage](https://github.com/ryoppippi/ccusage), refreshed in background
- **Context window** — block progress bar with token count (e.g. `⚡██░░░ 20% (200k/1M)`), dynamic color at 20% threshold
- **Git diff stats** — `(+42 -10 ?3)` showing insertions, deletions, and untracked files
- **Nerd Font icons** — git branch, refresh timer, session clock
- **Buddy-aware margin** — configurable right margin for Claude Code's companion
- **`CLAUDE_CONFIG_DIR` support** — respects custom config directories
- **`padding: 0`** — full-width statusline layout

## Install

```bash
# Install to ~/.claude (default)
bun bin/install.js

# Install to custom config dir
CLAUDE_CONFIG_DIR=/path/to/.claude bun bin/install.js
```

## Requirements

- [jq](https://jqlang.github.io/jq/) — for parsing JSON
- curl — for fetching rate limit data
- git — for branch and diff info
- python3 — for accurate terminal width calculation
- [Nerd Font](https://www.nerdfonts.com/) — for icons (recommended: **JetBrainsMono Nerd Font Mono** — icons forced to single cell width, no alignment issues)
- [ccusage](https://github.com/ryoppippi/ccusage) (optional) — for cost tracking

```bash
brew install jq
bun install -g ccusage
```

## Configuration

In your `settings.json` (`~/.claude/settings.json` or `$CLAUDE_CONFIG_DIR/settings.json`):

```jsonc
{
  // Set to "buddy" if you have the companion enabled, omit otherwise
  "statusLineMargin": "buddy"
}
```

## Uninstall

```bash
bun bin/install.js --uninstall
```

## License

MIT
