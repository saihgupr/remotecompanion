# rc-mcp

A small [MCP](https://modelcontextprotocol.io) server that lets an AI assistant (Claude Code, the Claude desktop app, or any MCP client) see and use an iPhone running RemoteCompanion.

The assistant looks at screenshots with a grid labelled in screen points, reads the screen's text with text recognition, and acts with real touches and RemoteCompanion commands. It all runs over SSH from your computer. Nothing extra is installed on the phone.

## Needs
- RemoteCompanion 4.6 for `look`, `read_text`, `tap_text` and `wait_text`. The touch, app and `rc_command` tools also work on 4.5.
- SSH to the phone as `mobile`, with a key (no password prompt).
- RemoteCompanion's Web UI server, which runs on the phone, for the trigger and config tools. `rc_state` falls back to `rc-client` status commands when the Web UI cannot answer.
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
| `rc_help` | Every RemoteCompanion command, offline: categories, the 15 most useful, or a search |
| `rc_state` | wifi, bluetooth, cellular, airplane, location, battery, low power, appearance, DND, focus and more, in one read-only call |
| `rc_command` | Any RemoteCompanion command |
| `rc_trigger` | `list`, `get`, `run`, `stop`, `save`, `delete`, `enable` |
| `rc_config` | `get`, `backup`, `restore`, `set` |
| `rc_sequence` | `validate`: check a trigger's actions before saving them |
| `rc_deeplink` | Open a RemoteCompanion screen with `remotecompanion://` |
| `rc_dev` | `logs`, `runs`, `history`, `file`, `screenshot`: read-only debugging |
| `rc_testkit` | The app's Test Kit: `info`, `probe`, `run`, `journal`, `mark`, `suites`, `suite`, `report`, `reports`, `snapshot`, `restore` |
| `rc_addon` | Add-on development: `list`, `validate`, `parse`, `trace`, `reload`, `enable`, `disable`, `settings`, `set` |
| `status` | Screen on or off, locked, the app in front, the RemoteCompanion version, and the battery |
| `look` | A screenshot with a grid labelled in screen points (half size by default) |
| `read_text` | The screen's text once it stops changing, a line each with its position in points |
| `gesture` | One touch or gesture: `kind` is `tap`, `hold`, `swipe`, `drag`, `two_finger_swipe` or `pinch` |
| `tap_text`, `wait_text` | Tap text on the screen, or wait until it shows |
| `type` | Types into the field being edited |
| `open_app`, `home`, `wake` | Open an app, go home, wake and unlock |
| `list_phones` | The phones it can reach |

Each action returns a fresh screenshot once the screen stops changing, so one call both acts and shows the result. Pass `look: false` to skip it.

`gesture` kinds, and the points each one needs:

- `tap`: x, y.
- `hold`: x, y, and seconds (default 1).
- `swipe`: x1, y1, x2, y2, and seconds (default 0.3). Scroll down by swiping up. Starting exactly on a screen edge makes it an edge swipe: from the bottom edge up goes home, from the left edge goes back. Faster swipes fling further.
- `drag`: x1, y1, x2, y2, and seconds (default 0.62). Lets go slowly, so the content stops where it is put: sliders, moving items, scrolling an exact distance.
- `two_finger_swipe`: x1, y1, x2, y2, and seconds (default 0.4). Pans, e.g. a map.
- `pinch`: x, y, scale, and seconds (default 0.6). Scale above 1 zooms in, below 1 zooms out.

A missing or wrong argument comes back as an error naming what that kind needs, before anything is sent to the phone.

`tap_text` taps the text itself. A home screen app's name is a label on iOS, not part of its button, so tapping it does nothing. Use `open_app` for apps.

## Commands first, screen second

Almost everything the phone can do has a command, and a command is faster, steadier and cheaper than
screenshots and taps: no waiting for the screen to settle, no position to get wrong.

1. `rc_state` (or `status`): what is actually on or off.
2. `rc_help` when the spelling is uncertain. It reads `rc_commands.json` next to the server, so it
   works with no phone at all.
3. `rc_command`: prefer the explicit setters (`wifi on`, `bt off`, `dnd on`, `appearance dark`,
   `rotate lock`) over toggles, so the phone ends in the state you meant.
4. Touches, `look` and `read_text` are for what has no command, or to verify that a command did what
   it said.

Triggers and the config are read and written through the phone's own Web UI (`127.0.0.1:8080`), by
`curl` on the phone, so the requests are local and need no API token. `rc_trigger save` and `delete`
back the config up to `~/.local/share/rc-mcp/backups` (mode 0600, `~/.cache/rc-mcp/backups` if that
is not writable) before writing, and read it back to check the phone kept what was sent.

`rc_trigger save` refuses a key that nothing produces: a built-in trigger family (`sched_`,
`app_launch_`, `addon_`, `trigger_*` and the rest) or an installed add-on. Pass `force: true` only
when you know the key is right.

`rc_deeplink` opens a RemoteCompanion screen (`settings`, `ha`, `trigger?key=...`). It brings the app
to the front, so it changes what is on screen.

`rc_config set` changes one top-level key (`key`, `value`). It refuses a key that isn't there already
unless `create: true`, lists the current keys when it refuses, backs the config up first, and reads it
back to check the phone kept the value. It never changes a nested field: use `rc_trigger save` for the
inside of a trigger.

## Debugging and testing

- `rc_dev` reads the phone's log (`logs`: the last 150 lines, with `lines` and a case-insensitive
  `grep`), the runs going (`runs`), the runs that ended (`history`), a file off the phone (`file`: as
  text, or its size and a base64 head when it isn't UTF-8), and saves a full-size screenshot on this
  Mac (`screenshot`). The Test Kit journal is separate: use `rc_testkit journal`.
- `rc_testkit` is the app's own Test Kit: `info` and `probe` (state), `run` (runs a command now),
  `journal` (`since`, `type`, `limit`), `mark` (annotates the journal), `suites` and `suite` (a suite
  can take up to 5 minutes), `report` and `reports` (redacted by default; `redact: false` gives the raw
  report), `snapshot`, and `restore` (puts the device's state back). `run` and `restore` change the
  phone.
- `rc_addon` is the add-on development loop: `list`, `validate` (a local file is copied to
  `/var/mobile/tmp`, checked, and removed; without a local file the path is read on the phone),
  `parse` (how a command reads, without running it), `trace` (runs the command and says what each step
  did or skipped), `reload`, `enable`, `disable`, `settings`, and `set`.

Logs, journal events and reports can hold personal data: messages, app names, text on screen. They go
to the assistant you connect. `rc_dev screenshot` saves its copy on this Mac at
`~/.local/share/rc-mcp/screenshots` (mode 0600) unless `path` gives another place.

## Locked phones
`wake` turns the screen on and unlocks a phone without a passcode. For one with a passcode, the person holding it can enter the code in Settings › Diagnostics › Test Kit. The phone keeps it for a while and uses it only for requests made on the phone itself, such as this server's over SSH. The code is never sent to the assistant.

Tools that touch the screen stop with "the screen is off, call wake" instead of returning a black picture or a tap that quietly did nothing. `look` and `read_text` add a line when the phone is locked, and `status` says it outright.

## Privacy
Screenshots and text show whatever is on screen, including notifications and messages. They go to the assistant you connect, so only connect phones and assistants you trust with that.
