# rc-mcp

A small [MCP](https://modelcontextprotocol.io) server that lets an AI assistant (Claude Code, the Claude desktop app, or any MCP client) see and use an iPhone running RemoteCompanion.

The assistant looks at screenshots with a grid labelled in screen points, reads the screen's text with text recognition, and acts with real touches and RemoteCompanion commands. It all runs over SSH from your computer. Nothing extra is installed on the phone.

## Needs
- RemoteCompanion 4.6 for `look`, `read_text`, `tap_text` and `wait_text`. The touch, app and `rc_command` tools also work on 4.5.
- SSH to the phone as `mobile`, with a key (no password prompt).
- Python 3.8 or later and `ssh` on your computer. No other packages.

## Set up
Add it to your MCP client. For Claude Code:

```sh
claude mcp add rc-phone \
  -e RC_PHONES="15=192.168.1.20" \
  -e RC_SSH_KEY=~/.ssh/id_ed25519 \
  -- python3 /path/to/remotecompanion/tools/rc-mcp/rc_mcp.py
```

For a client with a JSON config:

```json
{
  "mcpServers": {
    "rc-phone": {
      "command": "python3",
      "args": ["/path/to/remotecompanion/tools/rc-mcp/rc_mcp.py"],
      "env": { "RC_PHONES": "15=192.168.1.20", "RC_SSH_KEY": "~/.ssh/id_ed25519" }
    }
  }
}
```

| Setting | Meaning |
|---|---|
| `RC_PHONES` | Phones by name: `name=host,name=host`. The first is the default. A phone can list fallbacks separated by `\|`: `15=iphone.local\|192.168.1.20` is tried in turn, so a `.local` name that stops resolving after a respring still works. |
| `RC_SSH_KEY` | SSH private key (default: SSH's own choice) |
| `RC_SSH_USER` | SSH user (default `mobile`) |
| `RC_SSH_PORT` | SSH port (default 22) |

## Tools

| Tool | What it does |
|---|---|
| `look` | A screenshot with a grid labelled in screen points (half size by default) |
| `read_text` | The screen's text once it stops changing, a line each with its position in points |
| `tap`, `hold`, `swipe`, `drag`, `two_finger_swipe`, `pinch` | Touches at points |
| `tap_text`, `wait_text` | Tap text on the screen, or wait until it shows |
| `type` | Types into the field being edited |
| `open_app`, `home`, `wake` | Open an app, go home, wake and unlock |
| `status` | Screen on or off, locked, the app in front, the RemoteCompanion version, and the battery |
| `rc_command` | Any RemoteCompanion command |
| `list_phones` | The phones it can reach |

Each action returns a fresh screenshot once the screen stops changing, so one call both acts and shows the result. Pass `look: false` to skip it.

`tap_text` taps the text itself. A home screen app's name is a label on iOS, not part of its button, so tapping it does nothing. Use `open_app` for apps.

## Locked phones
`wake` turns the screen on and unlocks a phone without a passcode. For one with a passcode, the person holding it can enter the code in Settings › Diagnostics › Test Kit. The phone keeps it for a while and uses it only for requests made on the phone itself, such as this server's over SSH. The code is never sent to the assistant.

Tools that touch the screen stop with "the screen is off, call wake" instead of returning a black picture or a tap that quietly did nothing. `look` and `read_text` add a line when the phone is locked, and `status` says it outright.

## Privacy
Screenshots and text show whatever is on screen, including notifications and messages. They go to the assistant you connect, so only connect phones and assistants you trust with that.
