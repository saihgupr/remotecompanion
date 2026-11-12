#!/usr/bin/env python3
"""rc-mcp: a small MCP server that lets an AI assistant see and use an iPhone running
RemoteCompanion. It looks at the screen with screenshots (with a grid labelled in screen points)
and text recognition, and acts with touches and RemoteCompanion commands, over SSH.

No dependencies beyond Python 3.8 and the ssh command. Speaks MCP over stdio (one JSON message
per line). See README.md next to this file.

Settings (environment variables):
  RC_PHONES    phones by name, "name=host,name=host" (e.g. "15=192.168.1.20,8=192.168.1.21");
               the first is the default
  RC_SSH_USER  SSH user on the phone (default: mobile)
  RC_SSH_KEY   SSH private key (default: SSH's own choice)
  RC_SSH_PORT  SSH port (default: 22)
"""

import json
import os
import shlex
import subprocess
import sys

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
    known = {}
    for part in os.environ.get("RC_PHONES", "").split(","):
        if "=" in part:
            name, host = part.split("=", 1)
            known[name.strip()] = host.strip()
    return known


def host_for(name):
    known = phones()
    if not known:
        raise ToolError("No phones set up: set RC_PHONES, e.g. RC_PHONES=\"15=192.168.1.20\".")
    if not name:
        return next(iter(known.values()))
    if name not in known:
        raise ToolError("Unknown phone '%s'. Known: %s" % (name, ", ".join(known)))
    return known[name]


def ssh(host, command, timeout=60):
    """Runs a shell command on the phone; returns (exit status, stdout, stderr)."""
    args = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8",
            # One connection kept open between calls, so each call is quick
            "-o", "ControlMaster=auto", "-o", "ControlPersist=120",
            "-o", "ControlPath=" + os.path.join(os.path.expanduser("~"), ".ssh", "rc-mcp-%C")]
    if os.environ.get("RC_SSH_KEY"):
        args += ["-i", os.path.expanduser(os.environ["RC_SSH_KEY"]), "-o", "IdentitiesOnly=yes"]
    if os.environ.get("RC_SSH_PORT"):
        args += ["-p", os.environ["RC_SSH_PORT"]]
    args += ["%s@%s" % (os.environ.get("RC_SSH_USER", "mobile"), host), PHONE_PATH + command]
    try:
        p = subprocess.run(args, stdin=subprocess.DEVNULL, capture_output=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        raise ToolError("The phone didn't answer within %d s." % timeout)
    out = p.stdout.decode("utf-8", "replace").rstrip("\n")
    err = p.stderr.decode("utf-8", "replace").rstrip("\n")
    if p.returncode == 255:
        raise ToolError("Couldn't reach the phone over SSH: %s" % (err or "no answer"))
    return p.returncode, out, err


def rc(command):
    """A RemoteCompanion command, as a shell command for the phone"""
    return "rc-client " + shlex.quote(command)


def run(host, command, timeout=60):
    """Runs a RemoteCompanion command; its reply, or ToolError when it failed"""
    code, out, err = ssh(host, rc(command), timeout)
    text = "\n".join(t for t in (out, err) if t)
    if code != 0 or text.startswith("Error"):
        raise ToolError(text or "Failed (exit %d)" % code)
    return text


def quoted(text):
    return '"%s"' % str(text).replace("\n", " ")


# ---- the screen ----

def settle_steps():
    """A shell step that waits until the screen stops changing (a page sliding in, an app opening),
    checked inside SpringBoard: at most 3 s, since a clock or spinner never settles"""
    return rc("screen settle 3") + " >/dev/null"


def capture(host, scale, grid, settle):
    """The screen as a JPEG (base64) at `scale` of its points, with a grid every `grid` points
    when above 0, taken once the screen stops changing when `settle`. Returns (data, width, height)."""
    steps = [settle_steps()] if settle else []
    steps.append(rc("screen capture %s.jpg %g 0.6%s" % (SHOT, scale, (" grid %g" % grid) if grid else "")))
    steps.append("echo; base64 < %s.jpg | tr -d '\\n'; rm -f %s.jpg" % (SHOT, SHOT))
    code, out, err = ssh(host, "; ".join(steps), timeout=40)
    lines = [l for l in out.splitlines() if l.strip()]
    info = next((l for l in lines if l.startswith(SHOT + ".jpg") or l.startswith("Error")), "")
    if code != 0 or not info.startswith(SHOT) or len(lines) < 2:
        raise ToolError("Couldn't take a screenshot: %s" % (info or err or out or "no reply"))
    width, height = (int(v) for v in info.split()[1].split("x"))
    return lines[-1].strip(), width, height


def look(host, args, note=""):
    """A screenshot as MCP content, with how to read positions off it"""
    grid = args.get("grid", 100)
    grid = 100 if grid is True else (0 if grid in (False, None) else float(grid))
    scale = min(max(float(args.get("scale", 0.5)), 0.2), 1.0)
    data, w, h = capture(host, scale, grid, args.get("settle", True))
    text = ("Screenshot %dx%d px of the %.0fx%.0f point screen (1 px = %g points). Give positions in screen points."
            % (w, h, w / scale, h / scale, round(1 / scale, 2)))
    if grid:
        text += " Grid lines every %g points, labelled with their point." % grid
    if note.strip():
        text = note.strip() + "\n" + text
    return {"content": [{"type": "image", "data": data, "mimeType": "image/jpeg"}, {"type": "text", "text": text}]}


def after(host, reply, args, settle=False):
    """After an action: a fresh screenshot unless look is false. `settle`: even without one, wait
    for the screen to stop changing (an app opening), so the next call sees it."""
    if not args.get("look", True):
        if settle:
            ssh(host, settle_steps(), timeout=20)
        return reply
    return look(host, {"grid": args["grid"]} if "grid" in args else {}, reply)


# ---- tools ----

def t_list_phones(args):
    known = phones()
    if not known:
        return "No phones set up (RC_PHONES)."
    return "\n".join("%s%s: %s" % (n, " (default)" if i == 0 else "", h) for i, (n, h) in enumerate(known.items()))


def t_look(args):
    return look(host_for(args.get("phone")), args)


def t_read_text(args):
    host = host_for(args.get("phone"))
    command = rc("screen ocr" + (" fast" if args.get("fast") else ""))
    if args.get("settle", True):
        command = settle_steps() + "; " + command
    code, out, err = ssh(host, command, timeout=40)
    text = "\n".join(t for t in (out, err) if t)
    if code != 0 or text.startswith("Error"):
        raise ToolError(text or "Failed (exit %d)" % code)
    return text


def gesture(args, words, seconds_default):
    host = host_for(args.get("phone"))
    seconds = float(args.get("seconds", seconds_default))
    return after(host, run(host, "gesture " + " ".join(str(w) for w in words) + " %g" % seconds), args)


def t_tap(args):
    host = host_for(args.get("phone"))
    return after(host, run(host, "gesture tap %g %g" % (args["x"], args["y"])), args)


def t_hold(args):
    return gesture(args, ["hold", "%g" % args["x"], "%g" % args["y"]], 1)


def t_swipe(args):
    return gesture(args, ["swipe"] + ["%g" % args[k] for k in ("x1", "y1", "x2", "y2")], 0.3)


def t_drag(args):
    return gesture(args, ["drag"] + ["%g" % args[k] for k in ("x1", "y1", "x2", "y2")], 0.62)


def t_two_finger_swipe(args):
    return gesture(args, ["swipe2"] + ["%g" % args[k] for k in ("x1", "y1", "x2", "y2")], 0.4)


def t_pinch(args):
    return gesture(args, ["pinch", "%g" % args["x"], "%g" % args["y"], "%g" % args["scale"]], 0.6)


def t_tap_text(args):
    host = host_for(args.get("phone"))
    tap = rc("screen tap " + quoted(args["text"]))
    code, out, _ = ssh(host, tap, timeout=30)
    if out.startswith("Error") and "isn't on the screen" in out:
        # It may still be on its way (a screen opening): wait for it a moment, then tap
        code, out, _ = ssh(host, rc("screen wait %s 3" % quoted(args["text"])) + " && " + tap, timeout=40)
        out = out.splitlines()[-1] if out else out
    if code != 0 or out.startswith("Error"):
        raise ToolError(out or "\"%s\" isn't on the screen" % args["text"])
    return after(host, out, args)


def t_wait_text(args):
    host = host_for(args.get("phone"))
    seconds = min(max(float(args.get("seconds", 10)), 0.5), 120)
    reply = run(host, "screen wait %s %g" % (quoted(args["text"]), seconds), timeout=seconds + 20)
    return after(host, reply, args) if args.get("look") else reply


def t_type(args):
    host = host_for(args.get("phone"))
    return after(host, run(host, "type " + str(args["text"])), args)


def t_open_app(args):
    host = host_for(args.get("phone"))
    reply = run(host, "open " + str(args["app"]))
    # A launching app can show the same blank frame twice, which would pass for settled
    ssh(host, "sleep 0.8")
    return after(host, reply, args, settle=True)


def t_home(args):
    host = host_for(args.get("phone"))
    return after(host, run(host, "home"), args, settle=True)


def t_wake(args):
    host = host_for(args.get("phone"))
    run(host, "unlock")
    _, status, _ = ssh(host, "sleep 1.2; " + rc("lock status"))
    if "unlocked" in status.lower():
        return after(host, "Awake and unlocked.", args)
    # The Test Kit can unlock with a passcode the person entered on the phone; the code never
    # leaves the phone, and only a local request (this one, over SSH) can use it
    code, out, _ = ssh(host, rc("testkit unlock"), timeout=20)
    try:
        reply = json.loads(out.strip().splitlines()[-1]) if code == 0 and out.strip() else {}
    except (ValueError, IndexError):
        reply = {}
    if reply.get("unlocked"):
        return after(host, "Awake, and unlocked with the passcode set in the Test Kit.", args)
    return ("The screen is on but the phone is still locked. Only the person holding the phone should enter "
            "its passcode (on the phone, or in Settings > Diagnostics > Test Kit to let assistants unlock it for a while).")


def t_rc_command(args):
    host = host_for(args.get("phone"))
    _, out, err = ssh(host, rc(args["command"]), timeout=float(args.get("timeout", 60)))
    return "\n".join(t for t in (out, err) if t) or "(no output)"


NUM = {"type": "number"}
PHONE = {"type": "string", "description": "Which phone (a name from list_phones). Default: the first."}
LOOK = {"type": "boolean", "description": "Return a screenshot once the screen has settled (default true)."}
GRID = {"type": ["number", "boolean"], "description": "Grid line spacing in points on the screenshot (default 100; 0 for none; true is 100)."}
SECS = lambda d: {"type": "number", "description": "Duration in seconds (default %g)." % d}
LINE = {"x1": NUM, "y1": NUM, "x2": NUM, "y2": NUM}

TOOLS = [
    ("list_phones", t_list_phones, "The phones this server can reach.", {}, []),
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
    ("tap", t_tap, "A tap at x, y in screen points.", {"x": NUM, "y": NUM, "look": LOOK, "grid": GRID}, ["x", "y"]),
    ("hold", t_hold, "A long press at x, y.", {"x": NUM, "y": NUM, "seconds": SECS(1), "look": LOOK, "grid": GRID}, ["x", "y"]),
    ("swipe", t_swipe,
     "A swipe from x1,y1 to x2,y2. Scroll down by swiping up. Starting exactly on a screen edge makes it an edge "
     "swipe: from the bottom edge up goes home, from the left edge goes back. Faster swipes fling further.",
     dict(LINE, seconds=SECS(0.3), look=LOOK, grid=GRID), ["x1", "y1", "x2", "y2"]),
    ("drag", t_drag,
     "A drag from x1,y1 to x2,y2 that lets go slowly, so the content stops where it's put: sliders, moving items, "
     "scrolling an exact distance.", dict(LINE, seconds=SECS(0.62), look=LOOK, grid=GRID), ["x1", "y1", "x2", "y2"]),
    ("two_finger_swipe", t_two_finger_swipe, "A two-finger swipe from x1,y1 to x2,y2 (e.g. to pan a map).",
     dict(LINE, seconds=SECS(0.4), look=LOOK, grid=GRID), ["x1", "y1", "x2", "y2"]),
    ("pinch", t_pinch, "Two fingers around x, y: scale above 1 zooms in (e.g. 2), below 1 zooms out (e.g. 0.5).",
     {"x": NUM, "y": NUM, "scale": NUM, "seconds": SECS(0.6), "look": LOOK, "grid": GRID}, ["x", "y", "scale"]),
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
     "Runs any RemoteCompanion command and returns its reply (e.g. 'flashlight toggle', 'volume 50', "
     "'trigger:<key>'). See SCRIPTING.md for the commands.",
     {"command": {"type": "string"}, "timeout": {"type": "number", "description": "Seconds (default 60)."}}, ["command"]),
]
HANDLERS = {name: fn for name, fn, _, _, _ in TOOLS}


# ---- MCP over stdio ----

def tool_list():
    out = []
    for name, _, description, props, required in TOOLS:
        props = dict(props)
        if name != "list_phones":
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
                       "instructions": "Use an iPhone running RemoteCompanion. See the screen with look (a screenshot "
                                       "with a grid labelled in screen points) or read_text; act with tap_text, tap, "
                                       "swipe, drag, type and the rest. Each action returns a fresh screenshot once "
                                       "the screen settles. If the screenshot is black or shows the lock screen, "
                                       "call wake first."})
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
