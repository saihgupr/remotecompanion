# rc-mcp

An [MCP](https://modelcontextprotocol.io) server that lets an assistant (Claude, or any MCP
client) see and use an iPhone running RemoteCompanion: read the screen as text, press, tap,
hold, swipe and type, open apps, run any RemoteCompanion command and read the log.

It runs on your computer and reaches the phone over SSH, using `rc-screen` and `rc-client` on
the phone. One file, Python 3.8 or later, nothing to install.

## Setup

1. Set up SSH from the computer to the phone with a key (the user is `mobile` by default).
2. Add the server to your MCP client. For Claude Code:

   ```sh
   claude mcp add rc-phone -e RC_PHONES="iphone=192.168.1.20" -e RC_SSH_KEY="~/.ssh/id_ed25519" -- python3 /path/to/rc_mcp.py
   ```

| Variable | Meaning |
|---|---|
| `RC_PHONES` | Phones by name: `name=host,name=host`. The first is the default. |
| `RC_SSH_USER` | SSH user (default `mobile`) |
| `RC_SSH_KEY` | SSH private key |
| `RC_SSH_PORT` | SSH port (default 22) |
| `RC_WEB_PORT` | Web UI port, for `log` (default 8080) |
| `RC_SCREEN` | `rc-screen` on the phone, for development (default: the installed one) |

## Tools

| Tool | What it does |
|---|---|
| `screen` | The screen as an outline: alerts and keyboard first, top bar, sections, rows, bottom bar (or `format` list / json) |
| `find` | Elements whose label or value contains some text |
| `press` | Activates an element, as VoiceOver does |
| `tap`, `hold` | A real touch on an element or at x, y |
| `swipe` | A real swipe; from a screen edge it's an edge swipe (home, back) |
| `pinch`, `rotate`, `two_finger_swipe` | Two-finger gestures: zoom in or out, turn, pan |
| `type` | Types into the field being edited (`replace` empties it first) |
| `clear` | Empties the field being edited |
| `set_switch` | Turns a switch on or off, only pressing it if it needs to change |
| `adjust` | Moves a slider, stepper or picker: up, down, or to a percentage |
| `menu` | Opens an element's menu (like a long press) |
| `wait` | Waits until some text is on screen and the screen has settled |
| `scroll_to` | Scrolls the list until some text is on screen |
| `open_app`, `home`, `wake` | Opens an app, goes home, turns the screen on |
| `screen_events`, `watch_stop` | A live log of what changes on the screen; `wait` waits for the next change |
| `rc_command` | Any RemoteCompanion command, with its reply |
| `log` | The end of RemoteCompanion's log |
| `list_phones` | The phones it can reach |

Every tool takes an optional `phone`. Actions take `show_screen` to return the screen after they
settle.

The phone has to be unlocked: `wake` turns the screen on, but a passcode is for the person
holding the phone to enter.
