# claude-statusline-codex

A Claude Code statusline adapted for Codex / ChatGPT subscription usage.

This is based on `nilbuild/claude-statusline` / `@kamranahmedse/claude-statusline`, with the usage display changed to prefer CodexBar's Codex subscription data.

## What It Shows

- Current Codex model, for example `gpt-5.5 (1M Context)`
- Claude Code context usage from the statusline JSON
- Current directory and git branch
- Codex current-window usage and reset time
- Codex weekly usage and reset time
- Available full reset credits
- Fallback to Claude usage if CodexBar data is unavailable

Example:

```text
gpt-5.5 (1M Context) │ Context 150K / 1M │ my-project (main*)
current ●○○○○○  23% ⟳ 3:32pm
weekly  ○○○○○○   4% ⟳ jul 7, 10:32am
resets  3 full reset credits
```

## Requirements

- [jq](https://jqlang.github.io/jq/) for JSON parsing
- `git` for branch info
- `curl` for Claude usage fallback
- [Codex CLI](https://developers.openai.com/codex/cli/) logged in with ChatGPT / Codex subscription
- [CodexBar](https://github.com/steipete/CodexBar) for Codex usage limits

On macOS:

```bash
brew install jq codex codexbar
codex login
```

## Install

From this repository checkout:

```bash
node ./bin/install.js
```

Or after publishing/packaging:

```bash
npx claude-statusline-codex
```

The installer backs up your previous statusline if present, copies `bin/statusline.sh` to `~/.claude/statusline.sh`, and configures Claude Code settings.

## How Usage Is Resolved

The script reads Claude Code's statusline JSON from stdin for context and workspace data.

Codex-specific data comes from:

```bash
codex doctor --json
codexbar usage --provider codex --format json --no-color
```

Caching is local to avoid calling CodexBar on every prompt refresh:

- Codex usage cache: 60 seconds
- Codex model cache: 300 seconds

If CodexBar is unavailable or does not return Codex usage, the script falls back to the original Claude OAuth usage endpoint.

## Uninstall

```bash
node ./bin/install.js --uninstall
```

If there was a previous statusline backup, the installer restores it. Otherwise it removes the script and cleans up your Claude Code settings.

## License

MIT
