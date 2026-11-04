#!/usr/bin/env python3
"""rc-mcp: an MCP server that lets an assistant see and use a jailbroken iPhone running
RemoteCompanion. It reads the screen as text (rc-screen), acts on it (press, tap, hold, swipe,
type), and runs any RemoteCompanion command, over SSH.

No dependencies beyond Python 3.8+. Speaks MCP over stdio (one JSON message per line).

Settings (environment variables):
  RC_PHONES    phones by name, "name=host,name=host" (e.g. "15=192.168.1.20,8=192.168.1.21");
               the first is the default
  RC_SSH_USER  SSH user on the phone (default: mobile)
  RC_SSH_KEY   SSH private key (default: SSH's own choice)
  RC_SSH_PORT  SSH port (default: 22)
  RC_WEB_PORT  Web UI port, for the log (default: 8080)
"""

import json
import os
import shlex
import subprocess
import sys
import urllib.request

VERSION = "1.0.0"
PROTOCOL = "2025-06-18"


def phones():
    spec = os.environ.get("RC_PHONES", "").strip()
    out = {}
    for part in spec.split(","):
        if "=" in part:
            name, host = part.split("=", 1)
            out[name.strip()] = host.strip()
        elif part.strip():
            out[part.strip()] = part.strip()
    return out


def host_for(name):
    known = phones()
    if not known:
        raise ToolError("No phone set up. Set RC_PHONES, e.g. RC_PHONES=\"15=192.168.1.20\".")
    if not name:
        return next(iter(known.values()))
    if name in known:
        return known[name]
    raise ToolError("Unknown phone '%s'. Phones: %s" % (name, ", ".join(known)))


class ToolError(Exception):
    pass


def ssh(host, command, timeout=60):
    """Runs a shell command on the phone; returns (exit status, stdout, stderr)."""
    args = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8",
            # One connection kept open between calls, so each call is quick
            "-o", "ControlMaster=auto", "-o", "ControlPersist=120",
            "-o", "ControlPath=" + os.path.join(os.path.expanduser("~"), ".ssh", "rc-mcp-%C")]
    key = os.environ.get("RC_SSH_KEY")
    if key:
        args += ["-i", os.path.expanduser(key), "-o", "IdentitiesOnly=yes"]
    port = os.environ.get("RC_SSH_PORT")
    if port:
        args += ["-p", port]
    args += ["%s@%s" % (os.environ.get("RC_SSH_USER", "mobile"), host), command]
    try:
        p = subprocess.run(args, stdin=subprocess.DEVNULL, capture_output=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        raise ToolError("The phone didn't answer within %d s." % timeout)
    out = p.stdout.decode("utf-8", "replace").rstrip("\n")
    err = p.stderr.decode("utf-8", "replace").rstrip("\n")
    if p.returncode == 255:
        raise ToolError("Couldn't reach the phone over SSH: %s" % (err or "no answer"))
    return p.returncode, out, err


def screen_cmd(*words):
    return " ".join(["rc-screen"] + [shlex.quote(str(w)) for w in words])


def rc_cmd(command):
    return "rc-client " + shlex.quote(command)


def run(host, command, timeout=60, ok_codes=(0,)):
    code, out, err = ssh(host, command, timeout)
    text = "\n".join(t for t in (out, err) if t)
    if code not in ok_codes or text.startswith("Error"):
        raise ToolError(text or "Failed (exit %d)" % code)
    return text


def with_screen(host, text, args):
    if args.get("show_screen"):
        # A moment for the screen to change before reading it
        _, screen, _ = ssh(host, "sleep 0.8; " + screen_cmd())
        text += "\n\nScreen now:\n" + screen
    return text


def point_or_target(args, verb):
    """For tap and hold: the element (by text or #N) or x and y."""
    if args.get("target"):
        return None
    if args.get("x") is None or args.get("y") is None:
        raise ToolError("Give a target (text or #N from the screen list), or x and y.")
    return float(args["x"]), float(args["y"])


# ---- tools ----

PHONE = {"type": "string", "description": "Which phone (a name from list_phones). Default: the first."}
SHOW = {"type": "boolean", "description": "Also return the screen once it has settled (saves a separate screen call)."}
TARGET = {"type": "string", "description": "The element: text from its label or value (exact label first, then contains), or #N, its number in the screen list."}


def t_list_phones(args):
    known = phones()
    if not known:
        return "No phones set up (RC_PHONES)."
    return "\n".join("%s%s: %s" % (name, " (default)" if i == 0 else "", host) for i, (name, host) in enumerate(known.items()))


def t_screen(args):
    host = host_for(args.get("phone"))
    words = ["--json"] if args.get("json") else []
    return run(host, screen_cmd(*words))


def t_find(args):
    host = host_for(args.get("phone"))
    code, out, err = ssh(host, screen_cmd("find", args["text"]))
    return out or "Nothing on screen matches '%s'." % args["text"]


def t_press(args):
    host = host_for(args.get("phone"))
    return with_screen(host, run(host, screen_cmd("press", args["target"])), args)


def t_menu(args):
    host = host_for(args.get("phone"))
    return with_screen(host, run(host, screen_cmd("menu", args["target"])), args)


def t_tap(args):
    host = host_for(args.get("phone"))
    point = point_or_target(args, "tap")
    if point is None:
        text = run(host, screen_cmd("tap", args["target"]))
    else:
        text = run(host, rc_cmd("gesture tap %g %g" % point))
    return with_screen(host, text, args)


def t_hold(args):
    host = host_for(args.get("phone"))
    seconds = float(args.get("seconds", 1))
    point = point_or_target(args, "hold")
    if point is None:
        text = run(host, screen_cmd("hold", args["target"], "%g" % seconds))
    else:
        text = run(host, rc_cmd("gesture hold %g %g %g" % (point[0], point[1], seconds)))
    return with_screen(host, text, args)


def t_swipe(args):
    host = host_for(args.get("phone"))
    seconds = float(args.get("seconds", 0.3))
    text = run(host, rc_cmd("gesture swipe %g %g %g %g %g" % (args["x1"], args["y1"], args["x2"], args["y2"], seconds)))
    return with_screen(host, text, args)


def t_scroll_to(args):
    host = host_for(args.get("phone"))
    words = ["scroll-to", args["text"]] + (["up"] if args.get("up") else [])
    code, out, err = ssh(host, screen_cmd(*words), timeout=120)
    if code != 0:
        raise ToolError(err or out or "Not found after scrolling")
    return with_screen(host, out, args)


def t_adjust(args):
    host = host_for(args.get("phone"))
    to = str(args["to"]).strip().lower()
    words = ["adjust", args["target"]] + (to.split() if to.split()[0] in ("up", "down") else [to if to.endswith("%") else to + "%"])
    return with_screen(host, run(host, screen_cmd(*words)), args)


def t_type(args):
    host = host_for(args.get("phone"))
    words = ["type"] + (["--replace"] if args.get("replace") else []) + [args["text"]]
    return with_screen(host, run(host, screen_cmd(*words)), args)


def t_clear(args):
    host = host_for(args.get("phone"))
    return with_screen(host, run(host, screen_cmd("clear")), args)


def t_set_switch(args):
    host = host_for(args.get("phone"))
    return with_screen(host, run(host, screen_cmd("set", args["target"], "on" if args["on"] else "off")), args)


def t_wait(args):
    host = host_for(args.get("phone"))
    seconds = float(args.get("seconds", 10))
    code, out, err = ssh(host, screen_cmd("wait", args["text"], "%g" % seconds), timeout=seconds + 30)
    if code != 0:
        raise ToolError(err or out or "Not found after %g s" % seconds)
    return out


def front_app(host):
    _, out, _ = ssh(host, screen_cmd() + " | head -1")
    return out.strip()


def t_open_app(args):
    host = host_for(args.get("phone"))
    before = front_app(host)
    # An open during a transition (just after home) can be dropped: check it came to the front
    for attempt in range(2):
        run(host, rc_cmd("open " + args["app"]))
        for _ in range(8):
            front = front_app(host)
            if front and front != before and front != "SpringBoard":
                return with_screen(host, "Opened %s (in front: %s)" % (args["app"], front), args)
            ssh(host, "sleep 0.4")
    raise ToolError("Asked to open %s, but %s is still in front. Is the screen on (wake)?" % (args["app"], front_app(host) or "nothing"))


def t_home(args):
    host = host_for(args.get("phone"))
    run(host, rc_cmd("home") + "; sleep 0.8")  # until the home screen animation ends
    return with_screen(host, "Home screen.", args)


def t_wake(args):
    host = host_for(args.get("phone"))
    run(host, rc_cmd("unlock"))
    _, status, _ = ssh(host, "sleep 1.2; " + rc_cmd("lock status"))
    if "unlocked" in status:
        return with_screen(host, "Awake and unlocked.", args)
    return ("The screen is on but the phone is still locked: it needs its passcode, which only the person "
            "holding it should enter.")


def t_command(args):
    host = host_for(args.get("phone"))
    code, out, err = ssh(host, rc_cmd(args["command"]), timeout=float(args.get("timeout", 60)))
    return "\n".join(t for t in (out, err) if t) or "(no output)"


def t_log(args):
    host = host_for(args.get("phone"))
    port = os.environ.get("RC_WEB_PORT", "8080")
    try:
        with urllib.request.urlopen("http://%s:%s/api/logs" % (host, port), timeout=8) as r:
            lines = json.loads(r.read().decode("utf-8", "replace")).get("logs", "").splitlines()
    except Exception as e:
        raise ToolError("Couldn't read the log from the Web UI (is it on?): %s" % e)
    contains = args.get("contains")
    if contains:
        lines = [l for l in lines if contains.lower() in l.lower()]
    count = int(args.get("lines", 40))
    return "\n".join(lines[-count:]) or "(nothing)"


TOOLS = [
    ("list_phones", t_list_phones, "The phones this server can reach.", {}, []),
    ("screen", t_screen,
     "What's on the phone's screen now, as text: the app in front (SpringBoard for the home or lock screen), then "
     "each element on screen with its number, kind (button, text, header, search, key, link, image, adjustable), "
     "label, value (a switch reads 0 or 1) and center point in screen points. Only what's visible: swipe to scroll.",
     {"json": {"type": "boolean", "description": "JSON instead of text."}}, []),
    ("find", t_find, "Elements on screen whose label or value contains the text.",
     {"text": {"type": "string"}}, ["text"]),
    ("press", t_press,
     "Activates an element the way VoiceOver does (no touch). Best for buttons, rows and switches. "
     "After a press that changes screens, use wait before the next press: presses during a transition are lost.",
     {"target": TARGET, "show_screen": SHOW}, ["target"]),
    ("tap", t_tap,
     "A real touch: on an element's center (target), or at x, y in screen points. For what press can't reach "
     "(games, custom views, web content).",
     {"target": TARGET, "x": {"type": "number"}, "y": {"type": "number"}, "show_screen": SHOW}, []),
    ("hold", t_hold, "A real touch held down (long press) on an element or at x, y.",
     {"target": TARGET, "x": {"type": "number"}, "y": {"type": "number"},
      "seconds": {"type": "number", "description": "How long (default 1)."}, "show_screen": SHOW}, []),
    ("swipe", t_swipe,
     "A real swipe from x1,y1 to x2,y2 in screen points. Scroll down a list by swiping up (e.g. from y 700 to 250). "
     "Starting exactly on a screen edge makes it an edge swipe: from the bottom edge up goes home (Face ID phones), "
     "from the left edge goes back. Faster swipes (lower seconds) fling further.",
     {"x1": {"type": "number"}, "y1": {"type": "number"}, "x2": {"type": "number"}, "y2": {"type": "number"},
      "seconds": {"type": "number", "description": "Duration (default 0.3)."}, "show_screen": SHOW},
     ["x1", "y1", "x2", "y2"]),
    ("scroll_to", t_scroll_to,
     "Scrolls the list on screen until an element with this text shows, searching down first (or up), then the "
     "other way. Returns the element. Slow when the text isn't there at all (a long list is searched to its end).",
     {"text": {"type": "string"}, "up": {"type": "boolean", "description": "Search up first."}, "show_screen": SHOW}, ["text"]),
    ("adjust", t_adjust,
     "Moves an adjustable element (slider, stepper, picker; kind 'adjustable' in the screen list) the way "
     "VoiceOver does: to 'up' or 'down' (optionally 'up 3' for steps), or to a percentage like '30%' "
     "(as close as its steps allow).",
     {"target": TARGET, "to": {"type": "string", "description": "up, down, 'up 3', or a percentage like 30%."},
      "show_screen": SHOW}, ["target", "to"]),
    ("type", t_type, "Types text into the field being edited (tap or press a text field first). Any characters.",
     {"text": {"type": "string"}, "replace": {"type": "boolean", "description": "Empty the field first."},
      "show_screen": SHOW}, ["text"]),
    ("clear", t_clear, "Empties the text field being edited.", {"show_screen": SHOW}, []),
    ("set_switch", t_set_switch,
     "Turns a switch (kind 'switch' in the screen list) on or off. Reads it first and presses it only if it needs "
     "to change, then checks the result. Prefer this to press for switches.",
     {"target": TARGET, "on": {"type": "boolean"}, "show_screen": SHOW}, ["target", "on"]),
    ("menu", t_menu, "Opens an element's menu, as a long press would (e.g. an app icon's quick actions).",
     {"target": TARGET, "show_screen": SHOW}, ["target"]),
    ("wait", t_wait, "Waits until text is on screen and the screen has settled. Use after anything that changes screens.",
     {"text": {"type": "string"}, "seconds": {"type": "number", "description": "Give up after (default 10)."}}, ["text"]),
    ("open_app", t_open_app, "Opens an app by name (e.g. settings, safari, photos) or bundle ID.",
     {"app": {"type": "string"}, "show_screen": SHOW}, ["app"]),
    ("home", t_home, "Goes to the home screen.", {"show_screen": SHOW}, []),
    ("wake", t_wake,
     "Turns the screen on and dismisses the lock screen (if the phone has no passcode or is already unlocked). "
     "Use it when the screen list is empty or shows the lock screen; apps don't open while the screen is off.",
     {"show_screen": SHOW}, []),
    ("rc_command", t_command,
     "Runs any RemoteCompanion command and returns its reply (e.g. 'lock status', 'wifi status', 'flashlight toggle', "
     "'gesture list', 'gesture play \"Name\"').",
     {"command": {"type": "string"}, "timeout": {"type": "number"}}, ["command"]),
    ("log", t_log, "The end of RemoteCompanion's log (from the Web UI), for debugging.",
     {"lines": {"type": "integer", "description": "How many lines (default 40)."},
      "contains": {"type": "string", "description": "Only lines containing this."}}, []),
]

HANDLERS = {name: fn for name, fn, _, _, _ in TOOLS}


def tool_list():
    out = []
    for name, _, desc, props, required in TOOLS:
        schema_props = {"phone": PHONE}
        schema_props.update(props)
        out.append({"name": name, "description": desc,
                    "inputSchema": {"type": "object", "properties": schema_props, "required": required}})
    return out


# ---- MCP over stdio ----

def reply(msg_id, result=None, error=None):
    msg = {"jsonrpc": "2.0", "id": msg_id}
    if error is not None:
        msg["error"] = error
    else:
        msg["result"] = result
    sys.stdout.write(json.dumps(msg, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def handle(msg):
    method = msg.get("method")
    msg_id = msg.get("id")
    params = msg.get("params") or {}
    if msg_id is None:
        return  # a notification (initialized, cancelled): nothing to answer
    if method == "initialize":
        reply(msg_id, {"protocolVersion": params.get("protocolVersion", PROTOCOL),
                       "capabilities": {"tools": {}},
                       "serverInfo": {"name": "rc-phone", "version": VERSION},
                       "instructions": "Drive an iPhone running RemoteCompanion. Read the screen with screen, act with "
                                       "press (preferred), tap, hold, swipe, type, then wait for the result before the next "
                                       "step. Coordinates are screen points as the screen list shows them. If the screen list is empty "
                                       "or shows the lock screen, call wake first."})
    elif method == "ping":
        reply(msg_id, {})
    elif method == "tools/list":
        reply(msg_id, {"tools": tool_list()})
    elif method == "tools/call":
        name = params.get("name")
        fn = HANDLERS.get(name)
        if not fn:
            reply(msg_id, error={"code": -32602, "message": "Unknown tool: %s" % name})
            return
        try:
            text = fn(params.get("arguments") or {})
            reply(msg_id, {"content": [{"type": "text", "text": text}], "isError": False})
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
            reply(None, error={"code": -32700, "message": "Parse error"})
            continue
        for m in (msg if isinstance(msg, list) else [msg]):
            handle(m)


if __name__ == "__main__":
    main()
