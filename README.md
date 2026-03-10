# claude-statusline

Configure your Claude Code statusline to show limits, directory and git info. Fork of [@kamranahmedse/claude-statusline](https://github.com/kamranahmedse/claude-statusline) with customizable progress bar styles.

![demo](./.github/demo.png)

## Install

```bash
npx @zynoo/claude-statusline
```

With a custom bar style:

```bash
npx @zynoo/claude-statusline --bar-style diamond
```

It backups your old status line if any and copies the status line script to `~/.claude/statusline.sh` and configures your Claude Code settings.

## Requirements

- [jq](https://jqlang.github.io/jq/) — for parsing JSON
- curl — for fetching rate limit data
- git — for branch info

On macOS:

```bash
brew install jq
```

## Configuration

### Bar Style

Use the `--bar-style` flag during install to set the progress bar style:

| Value | Preview |
|-------|---------|
| `diamond` (default) | `▰▰▰▱▱▱▱▱▱▱` |
| `block` | `████░░░░░░` |
| `dot` | `●●●○○○○○○○` |

To change the style later, just re-run the install command:

```bash
npx @zynoo/claude-statusline --bar-style block
```

You can also set it via environment variable in your `.zshrc` or `.bashrc`:

```bash
export CLAUDE_STATUSLINE_BAR_STYLE=diamond
```

## Uninstall

```bash
npx @zynoo/claude-statusline --uninstall
```

If you had a previous statusline, it restores it from the backup. Otherwise it removes the script and cleans up your settings.

## Credits

Based on [claude-statusline](https://github.com/kamranahmedse/claude-statusline) by [Kamran Ahmed](https://github.com/kamranahmedse). Thanks for the great work!

## License

MIT — see [LICENSE](./LICENSE) for details.
