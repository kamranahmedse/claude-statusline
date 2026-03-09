# claude-statusline

Configure your Claude Code statusline to show limits, directory and git info

![demo](./.github/demo.png)

## Install

Run the command below to set it up

```bash
npx @kamranahmedse/claude-statusline
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

### Time format

By default, the statusline auto-detects your system locale and uses 24-hour or 12-hour time accordingly. To override, add `timeFormat` to your `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash \"$HOME/.claude/statusline.sh\"",
    "timeFormat": "24h"
  }
}
```

| Value | Time | Date + Time |
|-------|------|-------------|
| `"24h"` | `14:35` | `9 Mar, 14:35` |
| `"12h"` | `2:35pm` | `Mar 9, 2:35pm` |

## Uninstall

```bash
npx @kamranahmedse/claude-statusline --uninstall
```

If you had a previous statusline, it restores it from the backup. Otherwise it removes the script and cleans up your settings.

## License

MIT
