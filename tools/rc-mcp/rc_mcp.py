#!/usr/bin/env python3
"""rc-mcp: a small MCP server that lets an AI assistant see and use an iPhone running
RemoteCompanion. It looks at the screen with screenshots (with a grid labelled in screen points)
and text recognition, and acts with touches and RemoteCompanion commands, over SSH.

No dependencies beyond Python 3.8 and the ssh command. Speaks MCP over stdio (one JSON message
per line). See README.md next to this file.

Settings (environment variables):
  RC_PHONES    phones by name, "name=host,name=host" (e.g. "15=192.168.1.20,8=192.168.1.21");
               the first is the default. A phone can list fallbacks: "15=iphone.local|192.168.1.20"
               is tried in turn, so a .local name that stops resolving after a respring still works
  RC_SSH_USER  SSH user on the phone (default: mobile)
  RC_SSH_KEY   SSH private key (default: SSH's own choice)
  RC_SSH_PORT  SSH port (default: 22)
"""

import difflib
import json
import os
import re
import shlex
import subprocess
import sys
import time
from urllib.parse import urlencode, urlsplit

VERSION = "1.0.0"
PROTOCOL = "2025-06-18"
# Where rc-client and the shell tools are: rootless (/var/jb) or rootful (/usr) on the PATH, else
# roothide's randomly named jailbreak folder. Shell built-ins only: stock iOS has no /bin/sh, and
# nullglob keeps zsh from stopping on a pattern with no match (bash has no setopt and doesn't need it)
PHONE_PATH = ("PATH=/var/jb/usr/bin:/var/jb/bin:/usr/bin:/bin:$PATH; "
              "command -v rc-client >/dev/null 2>&1 || { setopt nullglob 2>/dev/null; "
              "for d in /var/containers/Bundle/Application/.jbroot-*; do "
              "[ -x \"$d/usr/bin/rc-client\" ] && PATH=\"$d/usr/bin:$d/bin:$PATH\" && break; done; }; ")
SHOT = "/var/mobile/tmp/rc-mcp-look"


class ToolError(Exception):
    pass


# ---- the phone ----

def phones():
    """Configured phones: name -> addresses, in the order to try them"""
    known = {}
    for part in os.environ.get("RC_PHONES", "").split(","):
        if "=" in part:
            name, hosts = part.split("=", 1)
            addresses = [h.strip() for h in hosts.split("|") if h.strip()]
            if addresses:
                known[name.strip()] = addresses
    return known


_LAST_GOOD = {}  # phone -> the address that answered last, tried first


def phone_for(name):
    """The configured phone's name, checked against RC_PHONES"""
    known = phones()
    if not known:
        raise ToolError("No phones set up: set RC_PHONES, e.g. RC_PHONES=\"15=192.168.1.20\".")
    if not name:
        return next(iter(known))
    if name not in known:
        raise ToolError("Unknown phone '%s'. Known: %s" % (name, ", ".join(known)))
    return name


def ssh_args(address, command):
    """The ssh command line for one address"""
    args = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8",
            # One connection kept open between calls, so each call is quick
            "-o", "ControlMaster=auto", "-o", "ControlPersist=120",
            "-o", "ControlPath=" + os.path.join(os.path.expanduser("~"), ".ssh", "rc-mcp-%C")]
    if os.environ.get("RC_SSH_KEY"):
        args += ["-i", os.path.expanduser(os.environ["RC_SSH_KEY"]), "-o", "IdentitiesOnly=yes"]
    if os.environ.get("RC_SSH_PORT"):
        args += ["-p", os.environ["RC_SSH_PORT"]]
    args += ["%s@%s" % (os.environ.get("RC_SSH_USER", "mobile"), address), PHONE_PATH + command]
    return args


def addresses_for(phone):
    """The phone's addresses in the order to try them: the one that answered last first"""
    addresses = phones().get(phone) or [phone]
    last = _LAST_GOOD.get(phone)
    if last in addresses:
        addresses = [last] + [a for a in addresses if a != last]
    return addresses


def ssh(phone, command, timeout=60):
    """Runs a shell command on the phone; returns (exit status, stdout, stderr). A phone with several
    addresses is tried in turn (the one that answered last first), so a name that stopped resolving
    does not fail the call while its IP works."""
    addresses = addresses_for(phone)
    failures = []
    for address in addresses:
        try:
            p = subprocess.run(ssh_args(address, command), stdin=subprocess.DEVNULL,
                               capture_output=True, timeout=timeout)
        except subprocess.TimeoutExpired:
            failures.append("%s (no answer in %d s)" % (address, timeout))
            continue
        out = p.stdout.decode("utf-8", "replace").rstrip("\n")
        err = p.stderr.decode("utf-8", "replace").rstrip("\n")
        if p.returncode != 255:
            _LAST_GOOD[phone] = address
            return p.returncode, out, err
        failures.append("%s (%s)" % (address, (err or "no answer").splitlines()[-1]))
    hint = ""
    if len(addresses) == 1:
        hint = " If a .local name stopped resolving, add the phone's IP: RC_PHONES=\"%s=%s|<ip>\"." % (phone, addresses[0])
    raise ToolError("Couldn't reach %s over SSH. Tried %s.%s" % (phone, " and ".join(failures), hint))


def ssh_input(phone, command, data, timeout=60):
    """Runs a shell command on the phone with `data` (bytes) on its standard input: a config body
    never belongs in a command line, where it would be quoted, logged and split."""
    addresses = addresses_for(phone)
    failures = []
    for address in addresses:
        try:
            p = subprocess.run(ssh_args(address, command), input=data,
                               capture_output=True, timeout=timeout)
        except subprocess.TimeoutExpired:
            failures.append("%s (no answer in %d s)" % (address, timeout))
            continue
        out = p.stdout.decode("utf-8", "replace").rstrip("\n")
        err = p.stderr.decode("utf-8", "replace").rstrip("\n")
        if p.returncode != 255:
            _LAST_GOOD[phone] = address
            return p.returncode, out, err
        failures.append("%s (%s)" % (address, (err or "no answer").splitlines()[-1]))
    raise ToolError("Couldn't reach %s over SSH. Tried %s." % (phone, " and ".join(failures)))


def rc(command):
    """A RemoteCompanion command, as a shell command for the phone"""
    return "rc-client " + shlex.quote(command)


def run(phone, command, timeout=60):
    """Runs a RemoteCompanion command; its reply, or ToolError when it failed"""
    code, out, err = ssh(phone, rc(command), timeout)
    text = "\n".join(t for t in (out, err) if t)
    if code != 0 or text.startswith("Error"):
        raise ToolError(text or "Failed (exit %d)" % code)
    return text


def quoted(text):
    return '"%s"' % str(text).replace("\n", " ")


# ---- the phone's own Web UI ----
# The request is made on the phone, over SSH, so 127.0.0.1 is local and needs no API token. Nothing
# here changes the device by itself: the callers decide, and only after backing the config up.

WEB_UI = "http://127.0.0.1:8080"


def web(phone, path, body=None, timeout=40):
    """GET (body None) or POST `body` to the phone's Web UI; returns the parsed JSON reply. Raises
    ToolError with the HTTP body when the Web UI refused, so the message says why."""
    seconds = 10 if body is None else 15
    command = "curl -s -m %d -w '\\n%%{http_code}'" % seconds
    if body is not None:
        # The body goes over stdin: a whole config on a command line would be split and logged
        command += " -X POST -H 'Content-Type: application/json' --data-binary @-"
    command += " " + WEB_UI + path
    if body is None:
        code, out, err = ssh(phone, command, timeout=timeout)
    else:
        code, out, err = ssh_input(phone, command, body.encode("utf-8"), timeout=timeout)
    text = (out or "").rstrip()
    status, reply = 0, text
    last = text.rsplit("\n", 1)[-1].strip()
    if last.isdigit():
        status = int(last)
        reply = text[:len(text) - len(last)].rstrip()
    if code != 0:
        detail = "\n".join(t for t in (err, reply) if t)
        raise ToolError("Couldn't reach the phone's Web UI: %s\nIs the Web UI on? (RemoteCompanion > "
                        "Settings > Web UI.)" % (detail or "exit %d" % code))
    if status == 0:
        raise ToolError("The phone's Web UI sent no HTTP status (%s). Is the Web UI on? (RemoteCompanion > "
                        "Settings > Web UI.)" % (reply or "no reply"))
    if status >= 400:
        raise ToolError("HTTP %d from %s: %s" % (status, path, reply or "(no body)"))
    if not reply:
        return {}
    try:
        return json.loads(reply)
    except ValueError:
        raise ToolError("The phone's Web UI sent something that isn't JSON: %s" % reply[:400])


def web_config(phone):
    """The whole trigger config, as the phone's Web UI has it"""
    config = web(phone, "/api/config")
    if not isinstance(config, dict):
        raise ToolError("The phone's config isn't a JSON object; not touching it.")
    return config


def web_triggers(config):
    triggers = config.get("triggers")
    if not isinstance(triggers, dict):
        raise ToolError("The phone's config has no triggers object; not touching it.")
    return triggers


# ---- the commands index (rc_commands.json) ----

COMMANDS_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "rc_commands.json")
_COMMANDS = []

# The 15 commands worth knowing first: mostly the explicit on/off forms, which say what will happen
# where a toggle only says what might.
TOP_COMMANDS = [
    "wifi on", "bt on", "airplane on", "low power on", "dnd on", "focus on <name>",
    "appearance dark", "autolock", "volume <0-100>", "brightness <0-100>", "play", "lock",
    "open <app>", "trigger:<id>", "screen ocr",
]


def commands():
    """Every command in rc_commands.json, loaded once"""
    global _COMMANDS
    if _COMMANDS:
        return _COMMANDS
    try:
        with open(COMMANDS_FILE, "r", encoding="utf-8") as f:
            rows = json.load(f)
    except (OSError, ValueError) as e:
        raise ToolError("Can't read rc_commands.json next to rc_mcp.py: %s" % e)
    if not isinstance(rows, list):
        raise ToolError("rc_commands.json should hold a list of commands.")
    _COMMANDS = [row for row in rows if isinstance(row, dict) and str(row.get("command") or "").strip()]
    if not _COMMANDS:
        raise ToolError("rc_commands.json has no commands in it.")
    return _COMMANDS


def command_line(row):
    """One help line: command, what it does, and an example"""
    example = row.get("example") or row.get("command") or ""
    return "%s — %s (e.g. %s)" % (row["command"], row.get("description") or "", example)


def top_line(row, by_command):
    """A useful command's line. An "on" command shows its "off" form too: a toggle alone would hide
    which state the command leaves the phone in."""
    name = row["command"]
    if name.endswith(" on"):
        off = by_command.get(name[:-3] + " off")
        if off:
            description = row.get("description") or ""
            if description.endswith(" on"):
                description = description[:-3] + " on or off"
            return "%s / %s — %s (e.g. %s; %s)" % (name, off["command"], description,
                                                   row.get("example") or name,
                                                   off.get("example") or off["command"])
    return command_line(row)


def closest_commands(text, count=3):
    """The commands most like `text`, by simple similarity: a typo's best guesses"""
    text = text.lower().strip()
    scored = []
    for row in commands():
        ratio = difflib.SequenceMatcher(None, text, row["command"].lower()).ratio()
        scored.append((ratio, row))
    scored.sort(key=lambda pair: (-pair[0], pair[1]["command"]))
    return [row for _, row in scored[:count]]


def help_matches(tokens):
    """Rows that every token of the query points at, best first: a token matches a command's own
    word first, then any word that starts with it, then any word it is part of."""
    scored = []
    for row in commands():
        command = row["command"].lower()
        command_words_here = [w for w in re.split(r"[^a-z0-9]+", command) if w]
        text = " ".join([command, (row.get("description") or "").lower(), (row.get("category") or "").lower()])
        words = [w for w in re.split(r"[^a-z0-9]+", text) if w]
        score = 0
        for token in tokens:
            if token in command_words_here:
                score += 5
                if command_words_here[0] == token or command_words_here[0].startswith(token + ":"):
                    score += 3
            elif any(w.startswith(token) for w in command_words_here):
                score += 4
            elif any(w.startswith(token) for w in words):
                score += 2
            elif token in text:
                score += 1
            else:
                score = 0
                break
        if score:
            scored.append((score, row))
    scored.sort(key=lambda pair: (-pair[0], pair[1]["command"]))
    return [row for _, row in scored]


# ---- config backups ----
# Before any write, the config as it was, owner-only. A write that fails after a backup does no harm;
# one that fails without a backup can lose a trigger nobody remembers.

BACKUP_FOLDERS = ("~/.local/share/rc-mcp/backups", "~/.cache/rc-mcp/backups")


def backup_folder():
    """A writable place for config backups, the documented one first"""
    problem = None
    for pattern in BACKUP_FOLDERS:
        folder = os.path.expanduser(pattern)
        try:
            os.makedirs(folder, mode=0o700, exist_ok=True)
            return folder
        except OSError as e:
            problem = e
    raise ToolError("Can't make a backup folder (%s). Not writing to the phone." % problem)


def save_backup(config):
    """Saves the config in the backups folder, mode 0600, and returns the path. Raises when the file
    is missing or empty, so the caller never writes to the phone without a good backup."""
    folder = backup_folder()
    stamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
    data = json.dumps(config, indent=1, sort_keys=True).encode("utf-8")
    path = os.path.join(folder, "config-%s.json" % stamp)
    n = 1
    while os.path.exists(path):
        n += 1
        path = os.path.join(folder, "config-%s-%d.json" % (stamp, n))
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "wb") as f:
        f.write(data)
    os.chmod(path, 0o600)
    if not os.path.exists(path) or os.path.getsize(path) == 0:
        raise ToolError("The backup at %s is missing or empty. Not writing to the phone." % path)
    try:
        with open(path, "r", encoding="utf-8") as f:
            json.load(f)
    except (OSError, ValueError) as e:
        raise ToolError("The backup at %s can't be read back (%s). Not writing to the phone." % (path, e))
    return path


# ---- actions and triggers ----

ACTION_TYPES = ("if", "else", "lua", "set_variable")
NUMBERED = {"volume": (0, 100), "set-vol": (0, 100), "brightness": (0, 100)}


def wobbly(action):
    """The problems with one action: an object of type if/else/lua (or the app's set_variable), or a
    non-empty string"""
    if isinstance(action, dict):
        kind = action.get("type")
        if kind not in ACTION_TYPES:
            return ["an object action needs type if, else or lua (got %r)" % (kind,)]
        if kind == "if" and not str(action.get("conditionKey") or "").strip():
            return ["an if action needs conditionKey"]
        if kind == "lua" and not str(action.get("script") or "").strip():
            return ["a lua action needs script"]
        if kind == "set_variable" and not str(action.get("name") or "").strip():
            return ["a set_variable action needs name"]
        return []
    if not isinstance(action, str):
        return ["an action must be a string or an object (got %s)" % type(action).__name__]
    if not action.strip():
        return ["an empty action"]
    return []


def command_prefixes():
    """The literal words a command starts with, before any placeholder: 'wifi on' is ('wifi', 'on'),
    'volume <0-100>' is ('volume',), 'gesture tap X Y' is ('gesture', 'tap'), 'trigger:<id>' is
    ('trigger:',), 'screen tap "Text"' is ('screen', 'tap')."""
    prefixes = []
    for row in commands():
        words = row["command"].strip().split(" ")
        first = words[0].lower()
        if first.startswith("trigger:") or first.startswith("shortcut:"):
            prefixes.append((first.split(":", 1)[0] + ":",))
            continue
        literal = [first]
        for word in words[1:]:
            if any(ch in word for ch in '<["') or word.isupper():
                break  # a placeholder: <id>, "Text", X Y, SCALE
            literal.append(word.lower())
        prefixes.append(tuple(literal))
    return prefixes


def known_action(text):
    """Whether an action starts with a command in rc_commands.json (an add-on's command is not in it)"""
    words = text.lower().split()
    if not words:
        return False
    for prefix in command_prefixes():
        if not prefix:
            continue
        if prefix[0] in ("trigger:", "shortcut:") and words[0].startswith(prefix[0]):
            return True
        if len(words) >= len(prefix) and tuple(words[:len(prefix)]) == prefix:
            return True
    return False


def word_check(action, strict):
    """Problems (strict) or warnings (not strict) with a string action's command and arguments"""
    text = action.strip()
    first = re.split(r"\s+", text, maxsplit=1)[0].lower()
    if not known_action(text):
        tries = ", ".join(row["command"] for row in closest_commands(text))
        message = ("'%s' isn't a command I know. Closest: %s. (An add-on's command starts with its id, and an "
                   "action can also be an if/else/lua object.)" % (text, tries))
        return [message] if strict else ["warning: " + message]
    problems = []
    rest = text[len(first):].strip()
    if first == "delay":
        try:
            if float(rest) < 0:
                problems.append("delay needs a positive number of seconds (got '%s')" % rest)
        except ValueError:
            problems.append("delay needs a number of seconds (got '%s')" % rest)
    elif first in NUMBERED:
        low, high = NUMBERED[first]
        second = (text.lower().split() + [""])[1]
        if second in ("up", "down") or (first == "volume" and not rest):
            pass  # volume up / volume down, or volume on its own to read it
        elif not rest:
            problems.append("%s needs a number from %d to %d" % (first, low, high))
        else:
            try:
                value = float(rest)
                if value < low or value > high:
                    problems.append("%s needs a number from %d to %d (got '%s')" % (first, low, high, rest))
            except ValueError:
                problems.append("%s needs a number from %d to %d (got '%s')" % (first, low, high, rest))
    elif first.startswith("trigger:") and not first.split(":", 1)[1]:
        problems.append("trigger: needs a trigger id after the colon")
    elif first.startswith("shortcut:") and not first.split(":", 1)[1]:
        problems.append("shortcut: needs a shortcut name after the colon")
    return problems


def sequence_check(sequence, strict=True):
    """Problems and warnings with a list of actions (strings and if/else/lua objects)"""
    if not isinstance(sequence, list):
        return ["a sequence is a JSON array of actions"], []
    problems, warnings = [], []
    if not sequence:
        problems.append("the sequence is empty")
    for number, action in enumerate(sequence, 1):
        for problem in wobbly(action):
            problems.append("action %d: %s" % (number, problem))
        if isinstance(action, str) and action.strip():
            for problem in word_check(action, strict):
                if problem.startswith("warning: "):
                    warnings.append("action %d: %s" % (number, problem[len("warning: "):]))
                else:
                    problems.append("action %d: %s" % (number, problem))
    return problems, warnings


# Keys a built-in producer makes. A key from none of these, and from no add-on, is one nothing fires.
PRODUCERS = ("sched_", "app_launch_", "app_exit_", "addon_", "output_", "output_set_", "trigger_",
             "nfc_", "wifi_", "bt_", "notif_", "notify_", "notiftap_", "notifbtn_", "mqtt_", "mqtt_sub_",
             "ac_", "watch_")
PRODUCER_KEYS = ("power_long_press", "power_triple_click", "power_volume_up", "power_double_tap",
                 "touchid_tap", "touchid_hold", "shake")


def addon_trigger_keys(phone):
    """The trigger keys installed add-ons produce: addon_<add-on id>_<trigger id>"""
    try:
        catalog = web(phone, "/api/addons", timeout=30)
    except ToolError:
        return set()
    keys = set()
    for addon in catalog.get("addons") or []:
        if not isinstance(addon, dict):
            continue
        for event in addon.get("events") or []:
            trigger = event.get("trigger") if isinstance(event, dict) else None
            if isinstance(trigger, dict) and trigger.get("id"):
                keys.add("addon_%s_%s" % (addon.get("id", ""), trigger["id"]))
    return keys


def producer_trouble(phone, key, trigger):
    """Why a trigger key would never fire, or None when a built-in or an add-on produces it"""
    if key in PRODUCER_KEYS or key.startswith(PRODUCERS):
        if key.startswith("sched_"):
            schedule = trigger.get("schedule")
            if not isinstance(schedule, dict) or not all(part in schedule for part in ("hour", "minute", "days")):
                return ("'%s' is a scheduled trigger but has no schedule object with hour, minute and days, "
                        "so it would never fire." % key)
        elif key.startswith("app_launch_") and "." not in key[len("app_launch_"):]:
            return ("'%s' is an app-launch trigger but the rest of the key is not a bundle id, so it would "
                    "never fire." % key)
        elif key.startswith("addon_") and key not in addon_trigger_keys(phone):
            return ("'%s' is an add-on trigger but no installed add-on provides it, so it would never fire." % key)
        return None
    if key in addon_trigger_keys(phone):
        return None
    return "No built-in trigger or installed add-on produces the key '%s', so it would never fire." % key


# ---- what the phone is doing ----


_STATE = {}  # phone -> (when read, state)
STATE_TTL = 6.0


def probe(phone, fresh=False):
    """The phone's state from its Test Kit: locked, screenOn, frontApp, orientation, battery, and the
    RemoteCompanion version. Cached for a moment, so a run of actions does not pay for it each time."""
    hit = _STATE.get(phone)
    if hit and not fresh and time.time() - hit[0] < STATE_TTL:
        return hit[1]
    _, out, _ = ssh(phone, rc("testkit probe"), timeout=20)
    state = {}
    for line in reversed(out.splitlines()):
        try:
            state = json.loads(line)
            break
        except ValueError:
            continue
    if not isinstance(state, dict) or not state:
        raise ToolError("Couldn't read the phone's state (testkit probe returned nothing usable).")
    _STATE[phone] = (time.time(), state)
    return state


def require_awake(phone):
    """A tool that touches or reads the screen needs it on: a black screen otherwise looks like an
    empty screen or a tap that worked and did nothing."""
    state = probe(phone)
    if state.get("screenOn") is False:
        raise ToolError("The screen is off. Call wake to turn it on and unlock the phone.")
    return state


def screen_version(phone):
    """The RemoteCompanion version and its numbers, for the screen-command check"""
    state = probe(phone)
    version = (state.get("device") or {}).get("tweakVersion") or ""
    parts = []
    for piece in version.split(".")[:3]:
        if not piece.isdigit():
            parts = []
            break
        parts.append(int(piece))
    return version, tuple(parts)


def require_screen(phone):
    """Reading and tapping text needs RemoteCompanion 4.6's screen commands. Older versions answer
    nothing at all, which used to look like an empty screen or a screenshot that failed."""
    version, parts = screen_version(phone)
    if parts and parts < (4, 6):
        raise ToolError("RemoteCompanion %s on this phone has no screen commands, so look, read_text, "
                        "tap_text and wait_text can't work. Touch, app and rc_command tools still do."
                        % version)
    return probe(phone)


def locked_note(state):
    """A line for a screenshot or text read while the lock screen is showing"""
    if state.get("locked"):
        return "The phone is locked: call wake to unlock it."
    return ""


def screen_ready(phone):
    """The checks a tool that reads or touches the screen needs first"""
    state = require_awake(phone)
    require_screen(phone)
    return state


def screen_capable(phone):
    """Whether this phone can take a screenshot at all (4.6's screen commands)"""
    _, parts = screen_version(phone)
    return not (parts and parts < (4, 6))


# ---- the screen ----

def settle_steps():
    """A shell step that waits until the screen stops changing (a page sliding in, an app opening),
    checked inside SpringBoard: at most 3 s, since a clock or spinner never settles"""
    return rc("screen settle 3") + " >/dev/null"


def capture(phone, scale, grid, settle):
    """The screen as a JPEG (base64) at `scale` of its points, with a grid every `grid` points
    when above 0, taken once the screen stops changing when `settle`. Returns (data, width, height)."""
    steps = [settle_steps()] if settle else []
    steps.append(rc("screen capture %s.jpg %g 0.6%s" % (SHOT, scale, (" grid %g" % grid) if grid else "")))
    steps.append("echo; base64 < %s.jpg | tr -d '\\n'; rm -f %s.jpg" % (SHOT, SHOT))
    code, out, err = ssh(phone, "; ".join(steps), timeout=40)
    lines = [l for l in out.splitlines() if l.strip()]
    info = next((l for l in lines if l.startswith(SHOT + ".jpg") or l.startswith("Error")), "")
    if code != 0 or not info.startswith(SHOT) or len(lines) < 2:
        raise ToolError("Couldn't take a screenshot: %s" % (info or err or out or "no reply"))
    width, height = (int(v) for v in info.split()[1].split("x"))
    return lines[-1].strip(), width, height


def look(phone, args, note=""):
    """A screenshot as MCP content, with how to read positions off it"""
    grid = args.get("grid", 100)
    grid = 100 if grid is True else (0 if grid in (False, None) else float(grid))
    scale = min(max(float(args.get("scale", 0.5)), 0.2), 1.0)
    data, w, h = capture(phone, scale, grid, args.get("settle", True))
    text = ("Screenshot %dx%d px of the %.0fx%.0f point screen (1 px = %g points). Give positions in screen points."
            % (w, h, w / scale, h / scale, round(1 / scale, 2)))
    if grid:
        text += " Grid lines every %g points, labelled with their point." % grid
    if note.strip():
        text = note.strip() + "\n" + text
    return {"content": [{"type": "image", "data": data, "mimeType": "image/jpeg"}, {"type": "text", "text": text}]}


def after(phone, reply, args, settle=False):
    """After an action: a fresh screenshot unless look is false. `settle`: even without one, wait
    for the screen to stop changing (an app opening), so the next call sees it."""
    if not args.get("look", True):
        if settle:
            ssh(phone, settle_steps(), timeout=20)
        return reply
    if not screen_capable(phone):
        # The action may have worked on a phone older than 4.6, which can't take a screenshot
        return "%s\nNo screenshot: this phone's RemoteCompanion has no screen commands (they need 4.6)." % reply
    return look(phone, {"grid": args["grid"]} if "grid" in args else {}, reply)


# ---- tools ----

def t_list_phones(args):
    known = phones()
    if not known:
        return "No phones set up (RC_PHONES)."
    lines = []
    for i, (name, addresses) in enumerate(known.items()):
        lines.append("%s%s: %s" % (name, " (default)" if i == 0 else "", ", ".join(addresses)))
    return "\n".join(lines)


def t_status(args):
    phone = phone_for(args.get("phone"))
    state = probe(phone, fresh=True)
    device = state.get("device") or {}
    battery = state.get("battery") or {}
    bits = ["screen on" if state.get("screenOn") else "screen off",
            "locked" if state.get("locked") else "unlocked"]
    if state.get("orientation"):
        bits.append(str(state["orientation"]).lower())
    lines = ["%s: %s." % (phone, ", ".join(bits)),
             "Front app: %s" % (state.get("frontApp") or "unknown")]
    if device.get("tweakVersion"):
        lines.append("RemoteCompanion %s on iOS %s" % (device["tweakVersion"], device.get("ios", "?")))
    level = battery.get("level")
    if isinstance(level, (int, float)):
        lines.append("Battery %.0f%%%s" % (level * 100, ", charging" if battery.get("charging") else ""))
    for field, label in (("dnd", "DND"), ("dndOn", "DND"), ("doNotDisturb", "DND")):
        value = state.get(field)
        if isinstance(value, bool):
            lines.append("%s: %s" % (label, "on" if value else "off"))
    return "\n".join(lines)


def t_look(args):
    phone = phone_for(args.get("phone"))
    state = screen_ready(phone)
    return look(phone, args, locked_note(state))


def t_read_text(args):
    phone = phone_for(args.get("phone"))
    state = screen_ready(phone)
    command = rc("screen ocr" + (" fast" if args.get("fast") else ""))
    if args.get("settle", True):
        command = settle_steps() + "; " + command
    code, out, err = ssh(phone, command, timeout=40)
    text = "\n".join(t for t in (out, err) if t)
    if code != 0 or text.startswith("Error"):
        raise ToolError(text or "Failed (exit %d)" % code)
    if not text.strip():
        text = "(no text on the screen)"
    note = locked_note(state)
    return note + "\n" + text if note else text


# kind -> (the phone's gesture word, the points it needs, default seconds; None means the word takes none)
GESTURES = {
    "tap": ("tap", ("x", "y"), None),
    "hold": ("hold", ("x", "y"), 1),
    "swipe": ("swipe", ("x1", "y1", "x2", "y2"), 0.3),
    "drag": ("drag", ("x1", "y1", "x2", "y2"), 0.62),
    "two_finger_swipe": ("swipe2", ("x1", "y1", "x2", "y2"), 0.4),
    "pinch": ("pinch", ("x", "y", "scale"), 0.6),
}
GESTURE_KINDS = list(GESTURES)


def t_gesture(args):
    """One touch or gesture. Its kind picks the points it needs, all checked before the phone is
    touched, so a wrong call costs nothing."""
    kind = args.get("kind")
    if kind not in GESTURES:
        raise ToolError("kind must be one of: %s." % ", ".join(GESTURE_KINDS))
    word, needs, seconds_default = GESTURES[kind]
    if any(not isinstance(args.get(name), (int, float)) or isinstance(args.get(name), bool) for name in needs):
        raise ToolError("kind=%s needs %s." % (kind, ", ".join(needs)))
    words = [word] + ["%g" % args[name] for name in needs]
    if seconds_default is not None:
        words.append("%g" % float(args.get("seconds", seconds_default)))
    phone = phone_for(args.get("phone"))
    require_awake(phone)
    return after(phone, run(phone, "gesture " + " ".join(words)), args)


def t_tap_text(args):
    phone = phone_for(args.get("phone"))
    screen_ready(phone)
    tap = rc("screen tap " + quoted(args["text"]))
    code, out, _ = ssh(phone, tap, timeout=30)
    if out.startswith("Error") and "isn't on the screen" in out:
        # It may still be on its way (a screen opening): wait for it a moment, then tap
        code, out, _ = ssh(phone, rc("screen wait %s 3" % quoted(args["text"])) + " && " + tap, timeout=40)
        out = out.splitlines()[-1] if out else out
    if code != 0 or out.startswith("Error"):
        raise ToolError(out or "\"%s\" isn't on the screen" % args["text"])
    return after(phone, out, args)


def t_wait_text(args):
    phone = phone_for(args.get("phone"))
    screen_ready(phone)
    seconds = min(max(float(args.get("seconds", 10)), 0.5), 120)
    reply = run(phone, "screen wait %s %g" % (quoted(args["text"]), seconds), timeout=seconds + 20)
    return after(phone, reply, args) if args.get("look") else reply


def t_type(args):
    phone = phone_for(args.get("phone"))
    require_awake(phone)
    return after(phone, run(phone, "type " + str(args["text"])), args)


def t_open_app(args):
    phone = phone_for(args.get("phone"))
    require_awake(phone)
    reply = run(phone, "open " + str(args["app"]))
    # A launching app can show the same blank frame twice, which would pass for settled
    ssh(phone, "sleep 0.8")
    return after(phone, reply, args, settle=True)


def t_home(args):
    phone = phone_for(args.get("phone"))
    require_awake(phone)
    return after(phone, run(phone, "home"), args, settle=True)


def t_wake(args):
    phone = phone_for(args.get("phone"))
    run(phone, "unlock")
    _, status, _ = ssh(phone, "sleep 1.2; " + rc("lock status"))
    if "unlocked" in status.lower():
        _STATE.pop(phone, None)
        return after(phone, "Awake and unlocked.", args)
    # The Test Kit can unlock with a passcode the person entered on the phone; the code never
    # leaves the phone, and only a local request (this one, over SSH) can use it
    code, out, _ = ssh(phone, rc("testkit unlock"), timeout=20)
    _STATE.pop(phone, None)
    try:
        reply = json.loads(out.strip().splitlines()[-1]) if code == 0 and out.strip() else {}
    except (ValueError, IndexError):
        reply = {}
    if reply.get("unlocked"):
        return after(phone, "Awake, and unlocked with the passcode set in the Test Kit.", args)
    return ("The screen is on but the phone is still locked. Only the person holding the phone should enter "
            "its passcode (on the phone, or in Settings > Diagnostics > Test Kit to let assistants unlock it for a while).")


def t_rc_command(args):
    phone = phone_for(args.get("phone"))
    timeout = max(1.0, min(float(args.get("timeout", 60)), 120))
    _, out, err = ssh(phone, rc(args["command"]), timeout=timeout)
    _STATE.pop(phone, None)  # it may have locked, respringed or opened something
    text = "\n".join(t for t in (out, err) if t)
    if text.strip():
        return text
    return ("(no reply: the command may not exist, or it may not print anything. Run rc_help <words> "
            "to check the spelling before assuming it worked.)")


def t_rc_help(args):
    rows = commands()
    query = " ".join(str(args.get("query") or "").split())
    if not query:
        order, counts = [], {}
        for row in rows:
            category = row.get("category") or "Other"
            if category not in counts:
                order.append(category)
                counts[category] = 0
            counts[category] += 1
        by_command = {row["command"]: row for row in rows}
        lines = ["RemoteCompanion commands (%d in all), by category:" % len(rows),
                 ", ".join("%s (%d)" % (name, counts[name]) for name in order),
                 "",
                 "Most useful (run any of these with rc_command):"]
        for name in TOP_COMMANDS:
            row = by_command.get(name)
            if row:
                lines.append(top_line(row, by_command))
        lines += ["",
                  "Search with words, e.g. rc_help wifi, rc_help focus, rc_help gesture, rc_help trigger."]
        return "\n".join(lines)
    tokens = [t for t in re.split(r"[^a-z0-9]+", query.lower()) if t]
    found = help_matches(tokens)
    if not found:
        closest = closest_commands(query)
        return ("Nothing matches '%s'. Closest commands:\n%s" % (query, "\n".join(command_line(row) for row in closest)))
    lines = [command_line(row) for row in found[:12]]
    if len(found) > 12:
        lines.append("(%d more: add a word to narrow it down.)" % (len(found) - 12))
    return "\n".join(lines)


# /api/answers holds the first line of each of these read-only commands: no toggling, no writing
STATE_GROUPS = (
    ("Network", ("wifi status", "bt status", "cell status", "airplane status", "location status")),
    ("Power", ("battery", "low power status")),
    ("Device", ("orientation status", "appearance status", "autolock status", "flashlight status",
                "ringer status", "dnd status", "focus status", "lock status")),
    ("Playback", ("is-playing", "volume")),
    ("Other", ("carplay status", "vibration silent-status", "haptics status", "screenrecord status",
               "timer status", "proximity status")),
)
FALLBACK_STATUS = ("wifi status", "bt status", "cell status", "airplane status", "location status",
                   "low power status", "dnd status", "focus status", "appearance status", "autolock status")


STATE_LABELS = {
    "wifi status": "wifi", "bt status": "bluetooth", "cell status": "cellular",
    "airplane status": "airplane", "location status": "location", "battery": "battery",
    "low power status": "low power", "orientation status": "orientation",
    "appearance status": "appearance", "autolock status": "auto-lock",
    "flashlight status": "flashlight", "ringer status": "ringer", "dnd status": "dnd",
    "focus status": "focus", "lock status": "lock", "is-playing": "playing",
    "volume": "volume", "carplay status": "carplay", "vibration silent-status": "silent vibration",
    "haptics status": "haptics", "screenrecord status": "screen recording",
    "timer status": "timer", "proximity status": "proximity",
}
# The phone's answers name themselves ("WiFi ON", "Battery: 87%"): the label says that part, so drop it
ANSWER_PREFIXES = ("wifi ", "bluetooth ", "cellular data ", "airplane mode ", "low power mode ",
                   "location services ", "flashlight ", "dnd ", "low power ", "location ", "ringer ")


def answer_text(key, value):
    """One answer as a short phrase with its label; empty when the phone didn't answer"""
    if value is None:
        return ""
    text = " ".join(str(value).split()).rstrip(".")
    if not text or text.lower().startswith("error"):
        return ""
    lower = text.lower()
    label = STATE_LABELS.get(key, "")
    for prefix in ANSWER_PREFIXES:
        if lower.startswith(prefix):
            text = text[len(prefix):].strip()
            lower = text.lower()
            break
    if label and lower.startswith(label + ":"):
        text = text.split(":", 1)[1].strip()
    if len(text.split()) == 1:
        text = text.lower()  # ON, OFF, PORTRAIT, Locked: a single word reads better small
    return ("%s %s" % (label, text)).strip()


def fallback_answers(phone):
    """A few status commands in one SSH call, when the Web UI is off: markers say which answer is which"""
    markers = {key.replace(" ", "_"): key for key in FALLBACK_STATUS}
    shell = "; ".join("echo __rc_%s__; %s" % (marker, rc(key)) for marker, key in markers.items())
    _, out, _ = ssh(phone, shell, timeout=40)
    values, current = {}, None
    for line in out.splitlines():
        text = line.strip()
        if text.startswith("__rc_") and text.endswith("__"):
            current = markers.get(text[len("__rc_"):-2])
        elif current and text:
            values.setdefault(current, text)
    return values


def t_rc_state(args):
    phone = phone_for(args.get("phone"))
    answers, source = {}, "the phone's Web UI (/api/answers)"
    try:
        reply = web(phone, "/api/answers", timeout=30)
        if not isinstance(reply, dict):
            raise ToolError("the reply wasn't an object")
        answers = reply
    except ToolError:
        answers = fallback_answers(phone)
        source = "rc-client status commands (the Web UI didn't answer)"
    if not any(answer_text(key, value) for key, value in answers.items()):
        raise ToolError("Couldn't read the phone's state from %s." % source)
    lines = ["State (read-only) from %s." % source]
    for name, keys in STATE_GROUPS:
        parts = [answer_text(key, answers.get(key)) for key in keys]
        parts = [part for part in parts if part]
        if name == "Device":
            try:
                rotation = probe(phone).get("rotationLocked")
            except ToolError:
                rotation = None
            if isinstance(rotation, bool):
                parts.append("rotation lock %s" % ("on" if rotation else "off"))
        if parts:
            lines.append("%s: %s" % (name, ", ".join(parts)))
    return "\n".join(lines)


# The app's URL scheme (RCAppDelegate.m): remotecompanion://<destination> and remotecompanion://nav/<destination>
DESTINATIONS = {
    "home": "the triggers list",
    "triggers": "the triggers list",
    "add": "a new trigger",
    "new-trigger": "a new trigger",
    "new": "a new trigger",
    "trigger": "one trigger's screen (needs key)",
    "settings": "RemoteCompanion settings",
    "integrations": "Settings > Integrations",
    "ha": "Settings > Integrations > Home Assistant",
    "homeassistant": "Settings > Integrations > Home Assistant",
    "km": "Settings > Integrations > Keyboard Maestro",
    "keyboardmaestro": "Settings > Integrations > Keyboard Maestro",
    "mqtt": "Settings > Integrations > MQTT",
    "advanced": "Settings > Advanced",
    "excluded": "Settings > Advanced > Excluded Apps",
    "excludedapps": "Settings > Advanced > Excluded Apps",
    "testkit": "Settings > Test Kit",
    "webui": "Settings > Web UI",
    "scroll": "the screen in front, scrolled",
}


def t_rc_deeplink(args):
    phone = phone_for(args.get("phone"))
    url = str(args.get("url") or "").strip()
    if url:
        if not url.lower().startswith("remotecompanion://"):
            raise ToolError("url must start with remotecompanion://. Known destinations: %s."
                            % ", ".join(sorted(DESTINATIONS)))
        parts = urlsplit(url)
        destination = (parts.hostname or "").lower()
        if destination in ("nav", ""):
            destination = parts.path.strip("/").split("/")[0].lower()
        if destination not in DESTINATIONS and destination != "":
            raise ToolError("Unknown destination '%s'. Known: %s." % (destination, ", ".join(sorted(DESTINATIONS))))
    else:
        destination = str(args.get("destination") or "").strip().lower()
        if not destination:
            raise ToolError("Give a destination (one of: %s) or a full remotecompanion:// url."
                            % ", ".join(sorted(DESTINATIONS)))
        if destination not in DESTINATIONS:
            raise ToolError("Unknown destination '%s'. Known: %s." % (destination, ", ".join(sorted(DESTINATIONS))))
        query = []
        if args.get("key"):
            query.append(("key", str(args["key"])))
        if args.get("to"):
            where = str(args["to"]).lower()
            if where not in ("top", "bottom"):
                raise ToolError("to must be top or bottom (or use offset for a number of points).")
            query.append(("to", where))
        if args.get("offset") is not None:
            query.append(("offset", str(int(args["offset"]))))
        url = "remotecompanion://" + destination + ("?" + urlencode(query) if query else "")
    if destination == "trigger" and "key=" not in url:
        raise ToolError("remotecompanion://trigger needs key=<trigger id> (rc_trigger action=list shows them).")
    reply = run(phone, "open " + url)
    _STATE.pop(phone, None)
    ssh(phone, "sleep 0.4", timeout=10)
    lines = ["Opened %s (%s)." % (url, DESTINATIONS.get(destination, "RemoteCompanion")),
             "RemoteCompanion is now in front: the screen has changed."]
    if reply.strip():
        lines.append(reply.strip())
    return "\n".join(lines)


def _yes(value):
    return "yes" if value else "no"


def trigger_key(args):
    key = str(args.get("id") or "").strip()
    if not key:
        raise ToolError("This needs a trigger id: the key rc_trigger action=list shows.")
    return key


def scrub_entries(entries, key):
    """The list without that trigger, and how many entries went. favoriteTriggers holds keys;
    notificationTriggers holds objects with the key under triggerKey (or id/key)."""
    if not isinstance(entries, list):
        return entries, 0
    kept, removed = [], 0
    for item in entries:
        hit = (item == key) if isinstance(item, str) else (
            isinstance(item, dict) and any(item.get(field) == key for field in ("triggerKey", "id", "key")))
        if hit:
            removed += 1
        else:
            kept.append(item)
    return kept, removed


def t_rc_trigger(args):
    action = str(args.get("action") or "").strip().lower()
    phone = phone_for(args.get("phone"))
    if action == "list":
        reply = web(phone, "/api/triggers")
        rows = reply.get("triggers") if isinstance(reply, dict) else None
        if not isinstance(rows, list):
            raise ToolError("The phone's Web UI sent no trigger list.")
        lines = sorted("%s — %s" % (row.get("id"), row.get("name") or "")
                       for row in rows if isinstance(row, dict) and row.get("id"))
        return "%d triggers:\n%s" % (len(lines), "\n".join(lines)) if lines else "No triggers on this phone."
    if action == "get":
        key = trigger_key(args)
        config = web_config(phone)
        triggers = web_triggers(config)
        trigger = triggers.get(key)
        if not isinstance(trigger, dict):
            raise ToolError("No trigger with the key '%s'. Ids on the phone: %s."
                            % (key, ", ".join(sorted(triggers)) or "none"))
        actions = trigger.get("actions") if isinstance(trigger.get("actions"), list) else []
        return ("key: %s\nactions: %d\nenabled: %s\n\n%s"
                % (key, len(actions), _yes(trigger.get("enabled")),
                   json.dumps(trigger, indent=1, sort_keys=True)))
    if action in ("run", "stop"):
        key = trigger_key(args)
        reply = run(phone, ("trigger:" if action == "run" else "stop trigger ") + key)
        _STATE.pop(phone, None)
        return reply or ("Ran %s." % key if action == "run" else "Stopped %s." % key)
    if action == "save":
        return trigger_save(phone, args)
    if action == "delete":
        return trigger_delete(phone, args)
    if action == "enable":
        return trigger_enable(phone, args)
    raise ToolError("action must be list, get, run, stop, save, delete or enable (got '%s')." % (action or "nothing"))


def trigger_save(phone, args):
    key = trigger_key(args)
    raw = args.get("trigger")
    if raw is None:
        raise ToolError('save needs trigger: the trigger as a JSON object, or a JSON string holding one.')
    if isinstance(raw, str):
        try:
            trigger = json.loads(raw)
        except ValueError as e:
            raise ToolError("trigger isn't valid JSON: %s" % e)
    else:
        trigger = raw
    if not isinstance(trigger, dict):
        raise ToolError("A trigger is a JSON object with name, enabled, actions and so on.")
    actions = trigger.get("actions")
    if not isinstance(actions, list) or not actions:
        raise ToolError("A trigger needs a non-empty actions array.")
    problems, warnings = sequence_check(actions, strict=False)
    if problems:
        raise ToolError("The trigger's actions have problems:\n%s" % "\n".join("- " + p for p in problems))
    enabled = trigger.get("enabled")
    if enabled is not None and not isinstance(enabled, (bool, int)):
        raise ToolError("enabled must be true/false or 1/0.")
    create = bool(args.get("create"))
    if create and enabled is None:
        raise ToolError("A new trigger needs enabled: true or false (1 or 0).")
    config = web_config(phone)
    triggers = web_triggers(config)
    exists = key in triggers
    if exists and create:
        raise ToolError("A trigger with the key '%s' already exists. Save without create to replace it." % key)
    if not exists and not create:
        raise ToolError("No trigger with the key '%s'. Pass create true to add it." % key)
    trouble = producer_trouble(phone, key, trigger)
    if trouble and not args.get("force"):
        raise ToolError("%s\nNothing was written. If you know the key is right (an add-on installed later, a "
                        "key another tool fires), call again with force true." % trouble)
    before = triggers.get(key) if isinstance(triggers.get(key), dict) else None
    backup = save_backup(config)
    triggers[key] = trigger
    web(phone, "/api/config", json.dumps(config))
    after_config = web_config(phone)
    after = web_triggers(after_config).get(key)
    if not isinstance(after, dict):
        raise ToolError("The phone didn't keep the trigger. The config before the write is at %s." % backup)
    if after.get("actions") != actions:
        raise ToolError("The phone's actions don't match what was sent. The config before the write is at %s." % backup)
    if enabled is not None and bool(after.get("enabled")) != bool(enabled):
        raise ToolError("The phone's enabled flag doesn't match what was sent. The config before the write is at %s."
                        % backup)
    lines = ["%s %s" % ("Added" if before is None else "Changed", key)]
    if before is None:
        lines.append("Actions: %d, enabled: %s" % (len(actions), _yes(after.get("enabled"))))
    else:
        changes = []
        if bool(before.get("enabled")) != bool(after.get("enabled")):
            changes.append("enabled %s -> %s" % (_yes(before.get("enabled")), _yes(after.get("enabled"))))
        old = before.get("actions") if isinstance(before.get("actions"), list) else []
        if old != actions:
            changes.append("actions %d -> %d" % (len(old), len(actions)))
        if (before.get("name") or "") != (after.get("name") or ""):
            changes.append("name '%s' -> '%s'" % (before.get("name") or "", after.get("name") or ""))
        lines.append("Changes: " + (", ".join(changes) or "none"))
    if warnings:
        lines.append("Warnings:\n" + "\n".join("- " + w for w in warnings))
    if trouble:
        lines.append("Warning: %s (saved because force was true.)" % trouble)
    lines.append("Backup of the config before the write: %s" % backup)
    lines.append("Read back from the phone: the actions and the enabled flag match.")
    return "\n".join(lines)


def trigger_delete(phone, args):
    key = trigger_key(args)
    config = web_config(phone)
    triggers = web_triggers(config)
    if key not in triggers:
        raise ToolError("No trigger with the key '%s'. Nothing to delete. Ids on the phone: %s."
                        % (key, ", ".join(sorted(triggers)) or "none"))
    backup = save_backup(config)
    del triggers[key]
    scrubbed = []
    for field in ("favoriteTriggers", "notificationTriggers"):
        if field in config:
            config[field], removed = scrub_entries(config[field], key)
            scrubbed.append("%s %d" % (field, removed))
    web(phone, "/api/config", json.dumps(config))
    after_config = web_config(phone)
    if key in web_triggers(after_config):
        raise ToolError("The phone still has the trigger. The config before the write is at %s." % backup)
    return ("Deleted %s.\nScrubbed from: %s\nBackup of the config before the write: %s\nRead back from the "
            "phone: the trigger is gone." % (key, ", ".join(scrubbed) or "nothing else", backup))


def trigger_enable(phone, args):
    key = trigger_key(args)
    if not isinstance(args.get("enabled"), bool):
        raise ToolError("enable needs enabled: true or false.")
    enabled = bool(args["enabled"])
    config = web_config(phone)
    triggers = web_triggers(config)
    if not isinstance(triggers.get(key), dict):
        raise ToolError("No trigger with the key '%s'. Ids on the phone: %s."
                        % (key, ", ".join(sorted(triggers)) or "none"))
    backup = save_backup(config)
    trigger = dict(triggers[key])
    trigger["enabled"] = 1 if enabled else 0  # actions are left exactly as they were
    triggers[key] = trigger
    web(phone, "/api/config", json.dumps(config))
    after = web_triggers(web_config(phone)).get(key)
    if not isinstance(after, dict) or bool(after.get("enabled")) != enabled:
        raise ToolError("The phone's enabled flag doesn't match. The config before the write is at %s." % backup)
    return ("%s is now %s.\nBackup of the config before the write: %s\nRead back from the phone: it matches."
            % (key, "on" if enabled else "off", backup))


def t_rc_config(args):
    action = str(args.get("action") or "").strip().lower()
    phone = phone_for(args.get("phone"))
    if action == "get":
        config = web_config(phone)
        if args.get("full"):
            text = json.dumps(config, indent=1, sort_keys=True)
            return ("The whole config, %d characters (large: every trigger, and the integration tokens). "
                    "Trigger actions are easier to read with rc_trigger action=get.\n%s" % (len(text), text))
        triggers = web_triggers(config)
        enabled = [key for key, trigger in triggers.items() if isinstance(trigger, dict) and trigger.get("enabled")]
        lines = ["Config: %d top-level keys, %d triggers (%d enabled)." % (len(config), len(triggers), len(enabled)),
                 "Keys: %s" % ", ".join(sorted(config)),
                 "Trigger ids: %s" % (", ".join(sorted(triggers)) or "none")]
        if "webUIEnabled" in config:
            lines.append("Web UI: %s" % ("on" if config.get("webUIEnabled") else "off"))
        return "\n".join(lines)
    if action == "backup":
        path = save_backup(web_config(phone))
        return "Saved the config to %s (mode 0600). Nothing on the phone changed." % path
    if action == "restore":
        path = str(args.get("path") or "").strip()
        if not path:
            raise ToolError("restore needs path: the backup file to put back (rc_config action=backup makes one).")
        path = os.path.expanduser(path)
        try:
            with open(path, "r", encoding="utf-8") as f:
                incoming = json.load(f)
        except (OSError, ValueError) as e:
            raise ToolError("Can't read the backup %s: %s" % (path, e))
        if not isinstance(incoming, dict) or not isinstance(incoming.get("triggers"), dict):
            raise ToolError("%s isn't a RemoteCompanion config: it has no triggers object." % path)
        backup = save_backup(web_config(phone))
        web(phone, "/api/config", json.dumps(incoming))
        after = web_config(phone)
        missing = [key for key in incoming["triggers"] if key not in web_triggers(after)]
        if missing:
            raise ToolError("The phone didn't keep %d trigger(s) (%s). The config before the restore is at %s."
                            % (len(missing), ", ".join(missing[:5]), backup))
        return ("Restored %d triggers from %s.\nThe config before the restore: %s\nRead back from the phone: the "
                "triggers are there." % (len(incoming["triggers"]), path, backup))
    raise ToolError("action must be get, backup or restore (got '%s')." % (action or "nothing"))


def t_rc_sequence(args):
    action = str(args.get("action") or "validate").strip().lower()
    if action != "validate":
        raise ToolError("action must be validate.")
    raw = args.get("sequence")
    if raw is None:
        raise ToolError("validate needs sequence: a JSON array of actions, or a JSON string holding one.")
    if isinstance(raw, str):
        try:
            sequence = json.loads(raw)
        except ValueError as e:
            raise ToolError("sequence isn't valid JSON: %s" % e)
    else:
        sequence = raw
    problems, warnings = sequence_check(sequence, strict=True)
    if problems:
        raise ToolError("Problems:\n%s" % "\n".join("- " + p for p in problems))
    lines = ["OK: %d actions" % len(sequence)]
    if warnings:
        lines.append("Warnings:\n" + "\n".join("- " + w for w in warnings))
    return "\n".join(lines)


NUM = {"type": "number"}
PHONE = {"type": "string", "description": "Which phone (a name from list_phones). Default: the first."}
LOOK = {"type": "boolean", "description": "Return a screenshot once the screen has settled (default true)."}
GRID = {"type": ["number", "boolean"], "description": "Grid line spacing in points on the screenshot (default 100; 0 for none; true is 100)."}

TOOLS = [
    ("list_phones", t_list_phones, "The phones this server can reach.", {}, []),
    ("status", t_status,
     "What the phone is doing: screen on or off, locked or unlocked, the app in front, its RemoteCompanion "
     "version, and the battery. Check it first, or when a screenshot looks wrong.", {}, []),
    ("look", t_look,
     "A screenshot of the phone with a grid labelled in screen points: see the screen and pick where to touch. "
     "Actions return one after they finish, so call look on its own only to start or after waiting.",
     {"scale": {"type": "number", "description": "Picture size as a share of the screen (default 0.5, 0.2 to 1)."},
      "grid": GRID, "settle": {"type": "boolean", "description": "Wait for the screen to stop changing (default true)."}}, []),
    ("read_text", t_read_text,
     "The text on the screen, read with text recognition: one line per piece of text, 'x,y WxH  text' in screen "
     "points. Waits for the screen to stop changing first, so the positions match what is there when the next "
     "touch lands. Cheaper than look when the words are what you need; it can't see icons or pictures.",
     {"fast": {"type": "boolean", "description": "A quicker, rougher read."},
      "settle": {"type": "boolean", "description": "Wait for the screen to stop changing before reading (default true)."}}, []),
    ("gesture", t_gesture,
     "One touch or gesture, in screen points. kind picks it: tap at x,y; hold at x,y for seconds (default 1); "
     "swipe from x1,y1 to x2,y2 (scroll down by swiping up; starting exactly on a screen edge makes it an edge "
     "swipe: from the bottom edge up goes home, from the left edge goes back; faster swipes fling further); "
     "drag from x1,y1 to x2,y2, letting go slowly so the content stops where it is put (sliders, moving items, "
     "scrolling an exact distance); two_finger_swipe from x1,y1 to x2,y2 (e.g. to pan a map); pinch with two "
     "fingers around x,y, where scale above 1 zooms in (e.g. 2) and below 1 zooms out (e.g. 0.5). Returns a "
     "screenshot once the screen settles, unless look is false.",
     {"kind": {"type": "string", "enum": GESTURE_KINDS,
               "description": "tap, hold, swipe, drag, two_finger_swipe or pinch."},
      "x": NUM, "y": NUM, "x1": NUM, "y1": NUM, "x2": NUM, "y2": NUM,
      "scale": {"type": "number", "description": "pinch: above 1 zooms in, below 1 zooms out."},
      "seconds": {"type": "number",
                  "description": "hold, swipe, drag, two_finger_swipe and pinch: duration in seconds (defaults: "
                                 "hold 1, swipe 0.3, drag 0.62, two_finger_swipe 0.4, pinch 0.6)."},
      "look": LOOK, "grid": GRID}, ["kind"]),
    ("tap_text", t_tap_text,
     "Taps text on the screen (a button, row or link with this text), found with text recognition; case doesn't "
     "matter. More precise than a point. Home screen icon labels can't be tapped: use open_app.",
     {"text": {"type": "string"}, "look": LOOK, "grid": GRID}, ["text"]),
    ("wait_text", t_wait_text,
     "Waits until text shows on the screen (text recognition, case doesn't matter), then until the screen "
     "stops moving, so the next touch lands where it should.",
     {"text": {"type": "string"}, "seconds": {"type": "number", "description": "Give up after (default 10, at most 120)."},
      "look": {"type": "boolean", "description": "Also return a screenshot when found (default false)."}}, ["text"]),
    ("type", t_type, "Types text into the field being edited (tap the field first). Letters, numbers and common symbols.",
     {"text": {"type": "string"}, "look": LOOK, "grid": GRID}, ["text"]),
    ("open_app", t_open_app, "Opens an app by name (e.g. settings, safari) or bundle ID.",
     {"app": {"type": "string"}, "look": LOOK, "grid": GRID}, ["app"]),
    ("home", t_home, "Goes to the home screen.", {"look": LOOK, "grid": GRID}, []),
    ("wake", t_wake,
     "Turns the screen on and unlocks the phone: without a passcode, or with one the person entered in "
     "RemoteCompanion's Test Kit on the phone (never sent to you). Use it when the screenshot is black or shows "
     "the lock screen.", {"look": LOOK, "grid": GRID}, []),
    ("rc_command", t_rc_command,
     "Runs any RemoteCompanion command and returns its reply. Most things have one, and it is faster and "
     "steadier than touching the screen. For any is-X-on/off question call rc_state first; prefer explicit "
     "setters (wifi on/off, bt on/off, airplane on/off, low power on/off, dnd on/off, focus on <name>|off, "
     "rotate lock/unlock) over toggles. Common commands: play, pause, next, volume 30, brightness 50, wifi "
     "on|off, bt on|off, airplane on|off, low power on|off, cellular on|off, dnd on|off, focus on <name>, "
     "focus off, appearance dark|light, lock, unlock, home, switcher, open <app>, uiopen <bundleId>, "
     "screenshot, flashlight toggle, autolock never|2m|status, rotate lock|unlock|status, timer 10m, "
     'shortcut:"Name", notify "Title" "Body", trigger:<id>, stop trigger <id>, list-triggers, running, '
     "backup config, screen ocr, screen tap \"Text\", gesture tap X Y, ha toggle, km trigger <name>, "
     "mqtt pub <topic> <payload>, http-request <url|json>. An empty reply means the command may not exist: "
     "use rc_help to check the spelling.",
     {"command": {"type": "string"},
      "timeout": {"type": "number", "description": "Seconds (default 60, at most 120)."}}, ["command"]),
    ("rc_help", t_rc_help,
     "Every RemoteCompanion command, offline: the categories and the 15 most useful commands, or the "
     "commands matching your words (e.g. rc_help wifi, rc_help focus, rc_help gesture). Use it before "
     "guessing a command's spelling or form. Touches no phone.",
     {"query": {"type": "string", "description": "Words to search for (command, description or category)."}}, []),
    ("rc_state", t_rc_state,
     "The phone's state in one read-only call: wifi, bluetooth, cellular, airplane, location, battery, low "
     "power, orientation, appearance, autolock, flashlight, ringer, DND, focus, lock, playing, volume. Reads "
     "the phone's own Web UI (/api/answers), falling back to a few rc-client status commands and saying which "
     "it used. Call it before setting anything, so you set what you mean instead of toggling.",
     {}, []),
    ("rc_trigger", t_rc_trigger,
     "Reads and changes RemoteCompanion triggers. action=list (id — name), get (one trigger's JSON), run or "
     "stop (fires or stops it now), save (write a trigger, adding it only with create true; backs the config "
     "up first and reads it back to check), delete (also scrubs favorites and notification entries), enable "
     "(sets only the enabled flag). save refuses a key no built-in or add-on produces unless force is true.",
     {"action": {"type": "string", "enum": ["list", "get", "run", "stop", "save", "delete", "enable"]},
      "id": {"type": "string", "description": "The trigger's key (rc_trigger action=list shows them)."},
      "trigger": {"type": ["object", "string"], "description": "save: the trigger as a JSON object or JSON string."},
      "create": {"type": "boolean", "description": "save: add this trigger; without it the key must already exist."},
      "force": {"type": "boolean", "description": "save: write even though no known producer fires this key."},
      "enabled": {"type": "boolean", "description": "enable: true to turn the trigger on, false to turn it off."}},
     ["action"]),
    ("rc_config", t_rc_config,
     "The whole RemoteCompanion config. action=get (a compact summary: keys, trigger count, ids; full true for "
     "everything, which is large), backup (save a copy locally, mode 0600, nothing on the phone changes), "
     "restore (put a backup back; backs up the current config first and reads it back). Writes go through the "
     "phone's own Web UI, over SSH, so they are local and need no API token.",
     {"action": {"type": "string", "enum": ["get", "backup", "restore"]},
      "full": {"type": "boolean", "description": "get: the whole config JSON (large)."},
      "path": {"type": "string", "description": "restore: the backup file to put back."}},
     ["action"]),
    ("rc_sequence", t_rc_sequence,
     "Checks a trigger's actions before you save them: a JSON array (or a JSON string holding one) of command "
     "strings and if/else/lua objects (set_variable too). Reports unknown words, bad numbers and malformed "
     "objects, with the closest command names. Offline: touches no phone.",
     {"action": {"type": "string", "enum": ["validate"], "description": "validate (the only action)."},
      "sequence": {"type": ["array", "string"], "description": "The actions, as a JSON array or a JSON string."}},
     ["action"]),
    ("rc_deeplink", t_rc_deeplink,
     "Opens a RemoteCompanion screen with remotecompanion://: home, triggers, add, trigger (needs key), "
     "settings, integrations, ha, km, mqtt, advanced, excluded, testkit, webui, scroll (to top|bottom or "
     "offset=N). Give destination plus key/to, or a whole url. This brings RemoteCompanion to the front, so "
     "the screen changes: use it when a screenshot or a tap cannot get to that screen.",
     {"destination": {"type": "string", "description": "One of the destinations; see the tool description."},
      "url": {"type": "string", "description": "A full remotecompanion://... url instead of destination."},
      "key": {"type": "string", "description": "trigger: the trigger's key."},
      "to": {"type": "string", "enum": ["top", "bottom"], "description": "scroll: where to scroll to."},
      "offset": {"type": "number", "description": "scroll: points to scroll to instead of top/bottom."}},
     []),
]
HANDLERS = {name: fn for name, fn, _, _, _ in TOOLS}


# ---- MCP over stdio ----

def tool_list():
    out = []
    for name, _, description, props, required in TOOLS:
        props = dict(props)
        if name not in ("list_phones", "rc_help", "rc_sequence"):  # these three never touch a phone
            props["phone"] = PHONE
        out.append({"name": name, "description": description,
                    "inputSchema": {"type": "object", "properties": props, "required": required}})
    return out


def reply(msg_id, result=None, error=None):
    msg = {"jsonrpc": "2.0", "id": msg_id}
    if error is not None:
        msg["error"] = error
    else:
        msg["result"] = result
    sys.stdout.write(json.dumps(msg) + "\n")
    sys.stdout.flush()


def handle(msg):
    method, msg_id, params = msg.get("method"), msg.get("id"), msg.get("params") or {}
    if msg_id is None:
        return  # a notification: nothing to answer
    if method == "initialize":
        reply(msg_id, {"protocolVersion": params.get("protocolVersion", PROTOCOL),
                       "capabilities": {"tools": {}},
                       "serverInfo": {"name": "rc-mcp", "version": VERSION},
                       "instructions": "Use an iPhone running RemoteCompanion. For anything that has a command, "
                                       "use rc_command first: it is faster and steadier than touching the screen. "
                                       "Call rc_help when you are unsure of a command's spelling or form, and "
                                       "rc_state to see what is on or off before setting it. Use look, read_text "
                                       "and tap_text only to verify what happened, or when no command does the "
                                       "job. Check status first: if the screen is off or the phone is locked, "
                                       "call wake."})
    elif method == "ping":
        reply(msg_id, {})
    elif method == "tools/list":
        reply(msg_id, {"tools": tool_list()})
    elif method == "tools/call":
        fn = HANDLERS.get(params.get("name"))
        if not fn:
            reply(msg_id, error={"code": -32602, "message": "Unknown tool: %s" % params.get("name")})
            return
        try:
            result = fn(params.get("arguments") or {})
            content = result["content"] if isinstance(result, dict) else [{"type": "text", "text": result}]
            reply(msg_id, {"content": content, "isError": False})
        except ToolError as e:
            reply(msg_id, {"content": [{"type": "text", "text": str(e)}], "isError": True})
        except KeyError as e:
            reply(msg_id, {"content": [{"type": "text", "text": "Missing argument: %s" % e}], "isError": True})
        except Exception as e:
            reply(msg_id, {"content": [{"type": "text", "text": "%s: %s" % (type(e).__name__, e)}], "isError": True})
    else:
        reply(msg_id, error={"code": -32601, "message": "Method not found: %s" % method})


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except ValueError:
            continue
        handle(msg)


if __name__ == "__main__":
    main()
