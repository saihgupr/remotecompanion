#!/usr/bin/env python3
"""addon-lint: checks RemoteCompanion add-on files on the Mac, before they're packaged.

    python3 tools/addon-lint.py path/to/addon.json [more.json ...] [--strict]

It applies the same checks, with the same wording, as `addons validate <file>` on the phone
(Tweak/RCAddOns.m, rcao_check_addOn and rcao_warnings), so a file that passes here loads there.
Keep the two in step when either changes. Prints "OK: ..." with any warnings, or "Problem: ...".
Exit status: 0 OK, 1 a file has a problem, 2 warnings only with --strict.

Needs only Python 3 (no packages). Run it from a Makefile, e.g. in a Theos project:

    before-package::
    	python3 /path/to/addon-lint.py --strict layout/Library/RemoteCompanion/AddOns/*.json
"""
import json
import os
import re
import sys

API_VERSION = 1           # kRCAOAPIVersion

# BUILTINS (tools/addon-builtins.py writes this)
BUILTIN_PREFIXES = ['airplay connect ', 'anc ', 'app nav ', 'appearance ', 'audiohandoff ', 'audiomix ', 'blacklist', 'bluetooth connect ', 'bluetooth disconnect ', 'brightness ', 'bt connect ', 'bt disconnect ', 'bt-connect ', 'bt-disconnect ', 'button ', 'button triggers ', 'camera ', 'clear run history ', 'debug-call ', 'debug-class ', 'debug-classes ', 'delay ', 'delete run history ', 'dnd ', 'exec ', 'flash ', 'flash on', 'flashlight ', 'flashlight on', 'focus ', 'gesture ', 'gps ', 'gps-', 'ha ', 'haptics ', 'hold ', 'key ', 'kill ', 'km ', 'location ', 'location services ', 'location-', 'locationservices ', 'locationservices-', 'lock toggle ', 'lock-toggle ', 'low power ', 'low power mode ', 'lpm ', 'lua ', 'lua_eval ', 'mqtt ', 'mute ', 'nav ', 'nfc scanner ', 'notify ', 'open ', 'open camera ', 'paste ', 'play playlist ', 'playlist ', 'proximity ', 'quickactions ', 'ringer ', 'root ', 'rotate ', 'run history ', 'run history all ', 'screenrecord ', 'sd ', 'set-vol ', 'shortcut ', 'shortcut-direct ', 'shortcut:', 'shuffle playlist ', 'snapper ', 'spotify ', 'spotify album ', 'spotify artist ', 'spotify play ', 'spotify playlist ', 'springcut ', 'ssh-run ', 'stop run ', 'stop trigger ', 'sudo ', 'suffle playlist ', 'swipe ', 'tap ', 'taptest ', 'testkit ', 'testkit passcode/set', 'toast ', 'trigger ', 'trigger:', 'type ', 'uiopen ', 'unlock ', 'url ', 'var ', 'vibration ', 'vol down ', 'vol up ', 'volume', 'volume ', 'volume down ', 'volume up ', 'webui ']
BUILTIN_COMMANDS = ['accessibility shortcut', 'airplane off', 'airplane on', 'airplane status', 'airplane toggle', 'airplay list', 'app switcher', 'battery status', 'bluetooth list', 'bluetooth off', 'bluetooth on', 'bluetooth status', 'bluetooth toggle', 'bt list', 'bt off', 'bt on', 'bt status', 'bt toggle', 'button triggers', 'carplay status', 'cell off', 'cell on', 'cell status', 'cell toggle', 'cellular off', 'cellular on', 'cellular status', 'cellular toggle', 'clear run history', 'control center', 'delete current song', 'delete song', 'flash off', 'flash on', 'flashlight off', 'flashlight on', 'flashlight status', 'flashlight toggle', 'kill current', 'kill current app', 'kill foreground', 'kill front', 'kill front app', 'last app', 'location services', 'lock status', 'lock toggle', 'nfc scanner', 'open camera', 'open control center', 'orientation lock', 'orientation status', 'player status', 'previous app', 'queue album', 'queue artist', 'run history', 'run history all', 'shortcuts list', 'shuffle all songs', 'sneakycam photo', 'sneakycam record', 'sneakycam startstopvideo', 'sneakycam takephoto', 'sneakycam video', 'suffle all songs', 'torch off', 'vol down', 'vol up', 'volume down', 'volume up', 'wi status', 'wifi off', 'wifi on', 'wifi status', 'wifi toggle']
# END BUILTINS
MAX_ICON_BYTES = 512 * 1024
OLDEST_IOS = (14, 0)      # the oldest iOS RemoteCompanion runs on
# macOS's own table of SF Symbols and the release that added each (checked only when it's there)
SYMBOL_TABLE = "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/name_availability.plist"


# --- helpers that mirror the Objective-C ones -------------------------------------------------

def is_string(v):
    """rcao_is_string: text that isn't empty"""
    return isinstance(v, str) and len(v) > 0


def is_number(v):
    """isKindOfClass:[NSNumber class]: a JSON number or true/false"""
    return isinstance(v, (int, float))


def is_dict(v):
    return isinstance(v, dict)


def is_list(v):
    return isinstance(v, list)


def word_list(text):
    """rcao_word_list"""
    return (bool(text) and re.fullmatch(r"[a-z0-9\-. ]+", text) is not None
            and not text.startswith(" ") and not text.endswith(" ") and "  " not in text)


def is_word(v):
    """rcao_is_word"""
    return is_string(v) and re.fullmatch(r"[a-z0-9\-.]+", v) is not None


def is_option_id(v):
    """rcao_is_option_id"""
    if not is_string(v) or re.fullmatch(r"[a-z0-9_]+", v) is None or not v[0].islower():
        return False
    if v in ("input", "state", "jbroot", "exit"):
        return False
    if v.startswith("word") and len(v) > 4 and v[4:].isdigit():
        return False
    return True


def fmt(v):
    """How %@ prints a value"""
    if v is None:
        return "(null)"
    if v is True:
        return "1"
    if v is False:
        return "0"
    if isinstance(v, float) and v.is_integer():
        return str(int(v))
    if isinstance(v, (dict, list)):
        return json.dumps(v)
    return str(v)


def boolv(v):
    """boolValue"""
    if isinstance(v, str):
        return v[:1].lower() in ("y", "t") or v[:1] in "123456789" and v[:1] != ""
    return bool(v)


def is_var_name(name):
    """rcao_is_var_name: what {name} must look like to be a variable (anything else is plain text)"""
    return isinstance(name, str) and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_.-]*", name) is not None


def template_names(template):
    """rcao_template_names: the variable names a template uses"""
    names = []
    if not isinstance(template, str):
        return names
    i = 0
    while True:
        start = template.find("{", i)
        if start < 0:
            break
        end = template.find("}", start + 1)
        if end < 0:
            break
        if is_var_name(template[start + 1:end]):
            names.append(template[start + 1:end])
        i = end + 1
    return names


def builtin_taking(addon_id, command):
    """rcao_builtin_taking: (the built-in command that takes "<id> <command>", whether it's a whole one)"""
    full = "%s %s" % (addon_id, command)
    for prefix in BUILTIN_PREFIXES:
        if (full + " ").startswith(prefix):
            return prefix.strip(), False
    if full in BUILTIN_COMMANDS:
        return full, True
    return None, False


# --- normalising (rcao_normalize) ------------------------------------------------------------

def normalize(addon):
    """"banner": true is a banner with every default, "banner": false is none"""
    for key in ("actions", "events"):
        for item in addon.get(key) if is_list(addon.get(key)) else []:
            if is_dict(item) and isinstance(item.get("banner"), bool):
                if item["banner"]:
                    item["banner"] = {}
                else:
                    del item["banner"]


# --- checks (rcao_check_step, rcao_check_banner, rcao_check_addOn) ----------------------------

KINDS = ["notify", "defaults", "exec", "url", "command", "delay"]
MODIFIERS = ["state", "root", "as", "ifOptions", "if", "stopOnError"]


def check_step(s):
    if not is_dict(s):
        return "a step isn't an object"
    kind = None
    for key in s:
        if key in KINDS:
            if kind:
                return "a step has both %s and %s" % (kind, key)
            kind = key
        elif key not in MODIFIERS:
            return "unknown step key '%s'" % key
    if not kind:
        return "a step has no kind"
    for flag in ("root", "ifOptions", "stopOnError"):
        if flag in s and not is_number(s[flag]):
            return "%s must be true or false" % flag
    if "state" in s and not is_number(s["state"]):
        return "state must be a number"
    if is_dict(s.get("if")) and "unset" in s["if"] and not is_number(s["if"]["unset"]):
        return "if's unset must be true or false"
    d = s.get("defaults")
    if is_dict(d):
        for flag in ("read", "toggle"):
            if flag in d and not is_number(d[flag]):
                return "defaults %s must be true or false" % flag
        if "labels" in d and not is_dict(d["labels"]):
            return "defaults labels must be an object"
        if "type" in d and d["type"] not in ("string", "bool", "int"):
            return "defaults type must be string, bool or int"
    if "if" in s:
        c = s["if"]
        if not is_dict(c) or not is_string(c.get("var")) or ("is" not in c and "isNot" not in c and not boolv(c.get("unset", False))
                                                            and "above" not in c and "below" not in c):
            return "if needs var and is, isNot, unset, above or below"
    for key in ("above", "below"):
        limit = s["if"].get(key) if is_dict(s.get("if")) else None
        if is_dict(s.get("if")) and key in s["if"] and not is_number(limit) and not is_string(limit):
            return "if's %s must be a number (or text that fills to one)" % key
    if "state" in s and kind != "notify":
        return "state only goes with notify"
    if "root" in s and kind != "exec":
        return "root only goes with exec"
    if "stopOnError" in s and kind not in ("exec", "command"):
        return "stopOnError only goes with exec or command"
    if "as" in s and (kind != "exec" or not is_string(s["as"])):
        return "as (a name for the output) only goes with exec"
    for name_given, name in (("as" in s, s.get("as")), (is_dict(d) and "as" in d, d.get("as") if is_dict(d) else None)):
        if name_given and not is_var_name(name):
            return "as '%s' must be a letter or _, then letters, digits, _, - and ." % fmt(name)
    for reserved in ("jbroot", "exit"):
        if s.get("as") == reserved or (is_dict(d) and d.get("as") == reserved):
            return "as can't be %s (that name is RemoteCompanion's)" % reserved
    value = s[kind]
    if kind == "exec":
        if not is_list(value) or len(value) == 0:
            return "exec needs a list"
        if any(not isinstance(a, str) for a in value):
            return "exec arguments must be strings"
        if not value[0].startswith("/") and not value[0].startswith("{jbroot}/"):
            return "exec needs a full path (or one starting {jbroot}/)"
    elif kind == "defaults":
        if not is_dict(value) or not is_string(value.get("domain")) or not is_string(value.get("key")):
            return "defaults needs domain and key"
        if boolv(value.get("read", False)) and not is_string(value.get("as")):
            return "defaults read needs as"
        if not boolv(value.get("toggle", False)) and not boolv(value.get("read", False)) and "value" not in value:
            return "defaults needs value, toggle or read"
    elif kind == "delay":
        if not is_number(value):
            return "delay needs a number"
    elif not is_string(value):
        return "%s needs text" % kind
    return None


def check_banner(banner, where):
    if not is_dict(banner):
        return "%s: banner isn't an object" % where
    for key in ("title", "subtitle", "icon", "await", "failed"):
        if key in banner and not is_string(banner[key]):
            return "%s: banner %s must be text" % (where, key)
    for key in ("hold", "timeout"):
        if key in banner and not is_number(banner[key]):
            return "%s: banner %s must be a number" % (where, key)
    if "states" in banner:
        if not is_dict(banner["states"]):
            return "%s: banner states must be an object" % where
        if any(not isinstance(v, str) for v in banner["states"].values()):
            return "%s: banner states must map to text" % where
    return None


def check_addon(a):
    pid = a.get("id")
    if not is_string(pid) or not word_list(pid) or " " in pid or "." in pid:
        return "id must be lowercase letters, digits and -"
    if pid == "addons":
        return "id '%s' is reserved" % pid
    if "api" in a:
        api = a["api"]
        if not is_number(api) or int(api) < 1:
            return "api must be a whole number from 1"
        if int(api) > API_VERSION:
            return "needs add-on API %s; this RemoteCompanion has %d" % (fmt(api), API_VERSION)
    if not is_string(a.get("name")):
        return "name is missing"
    if "icon" in a and not is_string(a["icon"]):
        return "icon must be text"
    if "requires" in a:
        if not is_list(a["requires"]) or any(not is_string(p) for p in a["requires"]):
            return "requires must be a list of paths"
    actions = a.get("actions")
    if not is_list(actions) or len(actions) == 0:
        return "actions are missing"
    commands = set()
    for action in actions:
        if not is_dict(action):
            return "an action isn't an object"
        command = action.get("command")
        if not is_string(command) or not word_list(command):
            return "an action's command must be lowercase words"
        if command in commands:
            return "two actions are '%s'" % command
        commands.add(command)
        taken, whole = builtin_taking(pid, command)
        has_details = (is_list(action.get("options")) and len(action["options"]) > 0) or "input" in action
        if taken and (not whole or not has_details):
            return ("action '%s': '%s %s' is taken by the built-in command '%s' and would never run (choose another id or command)"
                    % (command, pid, command, taken))
        if not is_string(action.get("name")):
            return "action '%s' has no name" % command
        if "icon" in action and not is_string(action["icon"]):
            return "action '%s': icon must be text" % command
        run = action.get("run")
        if not is_list(run) or len(run) == 0:
            return "action '%s' has no steps" % command
        for step in run:
            problem = check_step(step)
            if problem:
                return "action '%s': %s" % (command, problem)
        if "banner" in action:
            problem = check_banner(action["banner"], "action '%s'" % command)
            if problem:
                return problem
        if "input" in action:
            inp = action["input"]
            if not is_dict(inp):
                return "action '%s': input isn't an object" % command
            for key in ("title", "placeholder"):
                if key in inp and not isinstance(inp[key], str):
                    return "action '%s': input %s must be text" % (command, key)
            if "number" in inp and not is_number(inp["number"]):
                return "action '%s': input number must be true or false" % command
        option_ids, words = set(), set()
        options = action["options"] if "options" in action else []
        if not is_list(options):
            return "action '%s': options must be a list" % command
        for option in options:
            if not is_dict(option) or not is_list(option.get("choices")) or len(option["choices"]) == 0:
                return "action '%s' has an option without id or choices" % command
            if not is_option_id(option.get("id")):
                return ("action '%s': option id '%s' must be lowercase letters, digits and _ (not input, state, jbroot, exit or wordN)"
                        % (command, fmt(option.get("id"))))
            if option["id"] in option_ids:
                return "action '%s': two options are '%s'" % (command, option["id"])
            if "title" in option and not isinstance(option["title"], str):
                return "action '%s': option '%s' title must be text" % (command, option["id"])
            option_ids.add(option["id"])
            for choice in option["choices"]:
                if not is_dict(choice) or not is_string(choice.get("word")):
                    return "action '%s' has a choice without a word" % command
                if not is_word(choice["word"]):
                    return "action '%s': choice word '%s' must be one lowercase word" % (command, choice["word"])
                if choice["word"] in words:
                    return "action '%s': the word '%s' is used by two choices" % (command, choice["word"])
                words.add(choice["word"])
                if "label" in choice and not isinstance(choice["label"], str):
                    return "action '%s': a choice's label must be text" % command
        for option in options:
            if "skipWhen" not in option:
                continue
            skip = option["skipWhen"]
            if not is_dict(skip):
                return "action '%s': skipWhen must be an object" % command
            for other in skip:
                if other not in option_ids or other == option["id"]:
                    return "action '%s': skipWhen names '%s', which isn't another option" % (command, other)
    if "conditions" in a and not is_list(a["conditions"]):
        return "conditions must be a list"
    if "events" in a and not is_list(a["events"]):
        return "events must be a list"
    condition_ids = set()
    for c in a.get("conditions") or []:
        if not is_dict(c) or not is_string(c.get("id")) or not is_string(c.get("name")):
            return "a condition needs id and name"
        cid = c["id"]
        if cid in condition_ids:
            return "two conditions are '%s'" % cid
        condition_ids.add(cid)
        if "root" in c and not is_number(c["root"]):
            return "condition '%s': root must be true or false" % cid
        if "icon" in c and not is_string(c["icon"]):
            return "condition '%s': icon must be text" % cid
        if c.get("type") not in ("number", "choice"):
            return "condition '%s': type must be number or choice" % cid
        if "exec" not in c and not is_string(c.get("notifyState")):
            return "condition '%s' needs exec or notifyState" % cid
        if "exec" in c and check_step({"exec": c["exec"]}):
            return "condition '%s': exec needs a list starting with a full path" % cid
        for arg in c["exec"] if is_list(c.get("exec")) else []:
            if any(n != "jbroot" for n in template_names(arg)):
                return "condition '%s': exec can only use {jbroot}" % cid
        if "cache" in c and (not is_number(c["cache"]) or c["cache"] < 0):
            return "condition '%s': cache must be a number of seconds" % cid
        if c["type"] == "choice":
            choices = c.get("choices")
            if not is_dict(choices) or len(choices) == 0:
                return "condition '%s': a choice needs choices (value: label)" % cid
            if any(not isinstance(v, str) for v in choices.values()):
                return "condition '%s': choices must map to text" % cid
    trigger_ids = set()
    for e in a.get("events") or []:
        if not is_dict(e) or not is_string(e.get("notify")):
            return "an event needs notify"
        has_banner = "banner" in e
        trigger = e.get("trigger")
        if has_banner:
            problem = check_banner(e["banner"], "event '%s'" % e["notify"])
            if problem:
                return problem
        if "trigger" in e:
            if not is_dict(trigger) or not is_string(trigger.get("id")) or not is_string(trigger.get("name")):
                return "an event's trigger needs id and name"
            if "icon" in trigger and not is_string(trigger["icon"]):
                return "a trigger's icon must be text"
            if not is_word(trigger["id"]):
                return "trigger id '%s' must be lowercase letters, digits, - and ." % trigger["id"]
            if trigger["id"] in trigger_ids:
                return "two triggers are '%s'" % trigger["id"]
            trigger_ids.add(trigger["id"])
            states = trigger.get("states")
            if "states" in trigger and not (is_number(states) and states == 0) and not is_dict(states):
                return "a trigger's states must be an object or false"
        if not has_banner and "trigger" not in e:
            return "an event needs a banner or a trigger"
        if "action" in e and (not is_string(e["action"]) or e["action"] not in commands):
            return "event '%s': action '%s' isn't one of the actions" % (e["notify"], fmt(e["action"]))
    return check_settings(a.get("settings"), "settings" in a)


def check_settings(settings, given):
    """rcao_check_settings"""
    if not given:
        return None
    if not is_list(settings):
        return "settings must be a list"
    ids = set()
    for setting in settings:
        if not is_dict(setting):
            return "a setting isn't an object"
        if not is_option_id(setting.get("id")):
            return "setting id '%s' must be lowercase letters, digits and _, starting with a letter" % fmt(setting.get("id"))
        sid = setting["id"]
        if sid in ids:
            return "two settings are '%s'" % sid
        ids.add(sid)
        if not is_string(setting.get("title")):
            return "setting '%s' has no title" % sid
        kind = setting.get("type")
        if kind not in ("switch", "choice", "number", "text"):
            return "setting '%s': type must be switch, choice, number or text" % sid
        if not is_string(setting.get("domain")) or not is_string(setting.get("key")):
            return "setting '%s' needs domain and key" % sid
        for key in ("note", "notify", "unit"):
            if key in setting and not is_string(setting[key]):
                return "setting '%s': %s must be text" % (sid, key)
        for key in ("min", "max", "step"):
            if key in setting and not is_number(setting[key]):
                return "setting '%s': %s must be a number" % (sid, key)
        has_default = "default" in setting
        given_default = setting.get("default")
        if kind == "switch" and has_default and not isinstance(given_default, bool):
            return "setting '%s': a switch's default must be true or false" % sid
        if kind == "text" and has_default and not isinstance(given_default, str):
            return "setting '%s': a text's default must be text" % sid
        if kind == "number":
            if has_default and not is_number(given_default):
                return "setting '%s': a number's default must be a number" % sid
            if "min" in setting and "max" in setting and setting["min"] > setting["max"]:
                return "setting '%s': min is above max" % sid
            if "step" in setting and setting["step"] <= 0:
                return "setting '%s': step must be above 0" % sid
        if kind == "choice":
            choices = setting.get("choices")
            if not is_list(choices) or len(choices) == 0:
                return "setting '%s': a choice needs choices" % sid
            values = set()
            found = not has_default
            for choice in choices:
                if not is_dict(choice) or not is_string(choice.get("label")) or not (isinstance(choice.get("value"), str) or is_number(choice.get("value"))):
                    return "setting '%s': each choice needs a value (text or number) and a label" % sid
                value = fmt(choice["value"])
                if value in values:
                    return "setting '%s': two choices have the value '%s'" % (sid, value)
                values.add(value)
                if has_default and value == fmt(given_default):
                    found = True
            if not found:
                return "setting '%s': the default isn't one of the choices' values" % sid
    return None


# --- warnings (rcao_warnings) ----------------------------------------------------------------

def icons(a):
    out = []
    for icon in [a.get("icon")] + [x.get("icon") for x in a.get("actions") or [] if is_dict(x)] \
            + [x.get("icon") for x in a.get("conditions") or [] if is_dict(x)] \
            + [x["trigger"].get("icon") for x in a.get("events") or [] if is_dict(x) and is_dict(x.get("trigger"))]:
        if is_string(icon):
            out.append(icon)
    return out


def warnings_for(a, folder):
    warnings = []

    def check(obj, known, where):
        if not is_dict(obj):
            return
        for key in obj:
            if key not in known:
                warnings.append("%s: unknown key '%s' is ignored" % (where, key))

    check(a, ["$schema", "api", "id", "name", "icon", "requires", "actions", "conditions", "events", "settings"], "add-on")
    for setting in a.get("settings") or []:
        where = "setting '%s'" % setting["id"]
        check(setting, ["id", "title", "type", "domain", "key", "default", "note", "notify", "choices", "min", "max", "step", "unit"], where)
        for choice in setting.get("choices") or []:
            check(choice, ["value", "label"], where + " choice")
    for action in a["actions"]:
        where = "action '%s'" % action["command"]
        check(action, ["command", "name", "icon", "options", "input", "run", "banner"], where)
        check(action.get("banner"), ["title", "subtitle", "icon", "hold", "await", "states", "timeout", "failed"], where + " banner")
        check(action.get("input"), ["title", "placeholder", "number"], where + " input")
        for option in action.get("options") or []:
            check(option, ["id", "title", "choices", "skipWhen"], where + " option")
            for choice in option["choices"]:
                check(choice, ["word", "label", "value"], where + " choice")
    for c in a.get("conditions") or []:
        check(c, ["id", "name", "icon", "type", "exec", "root", "notifyState", "choices", "cache"], "condition")
    for e in a.get("events") or []:
        check(e, ["notify", "action", "banner", "trigger"], "event")
        check(e.get("banner"), ["title", "subtitle", "icon", "hold", "states"], "event banner")
        check(e.get("trigger"), ["id", "name", "icon", "states"], "event trigger")

    # An exec path under /var/jb only exists on rootless: one warning per path, with how often it's used
    jb_uses = {}
    execs = [step.get("exec") for action in a["actions"] for step in action["run"]]
    execs += [c.get("exec") for c in a.get("conditions") or []]
    for exec_list in execs:
        if is_list(exec_list) and exec_list and isinstance(exec_list[0], str) and exec_list[0].startswith("/var/jb/"):
            jb_uses[exec_list[0]] = jb_uses.get(exec_list[0], 0) + 1
    for path, uses in jb_uses.items():
        warnings.append("exec path %s only works on rootless; write {jbroot}%s (%d place%s)" % (path, path[7:], uses, "" if uses == 1 else "s"))

    for action in a["actions"]:
        taken, whole = builtin_taking(a["id"], action["command"])
        if taken and whole:
            warnings.append("action '%s': with nothing after it, '%s' runs the built-in command instead" % (action["command"], taken))

    for icon in icons(a):
        if os.path.splitext(icon)[1].lower() not in (".png", ".jpg", ".jpeg"):
            continue
        if icon.startswith("/"):
            continue   # a path on the phone; can't be checked here
        path = os.path.join(folder, icon)
        if not os.path.exists(path):
            warnings.append("icon: no image at %s" % path)
        elif os.path.getsize(path) > MAX_ICON_BYTES:
            warnings.append("icon: %s is over 512 KB and isn't used" % icon)
    return warnings


# --- SF Symbols (Mac only) ---

def symbol_warnings(a):
    """Icons that aren't SF Symbols, or need a newer iOS than RemoteCompanion's oldest: there the
    add-on's icon (or the puzzle piece) shows instead"""
    try:
        import plistlib
        with open(SYMBOL_TABLE, "rb") as f:
            table = plistlib.load(f)
    except (OSError, ValueError):
        return []
    releases = {year: tuple(int(x) for x in r["iOS"].split(".")) for year, r in table["year_to_release"].items() if "iOS" in r}
    names = icons(a) + [x["banner"]["icon"] for x in a["actions"] if is_dict(x.get("banner")) and is_string(x["banner"].get("icon"))]
    out, seen = [], set()
    for name in names:
        if name in seen or os.path.splitext(name)[1].lower() in (".png", ".jpg", ".jpeg"):
            continue
        seen.add(name)
        year = table["symbols"].get(name)
        if year is None:
            out.append("(Mac) icon '%s' isn't an SF Symbol, so it shows nothing" % name)
        elif releases.get(year, (0,)) > OLDEST_IOS:
            out.append("(Mac) icon '%s' needs iOS %s; older iOS shows the add-on's icon instead"
                       % (name, ".".join(str(x) for x in releases[year])))
    return out


# --- files -----------------------------------------------------------------------------------

def lint(path):
    """(problem or None, warnings, the add-on)"""
    duplicates = []

    def pairs(items):
        seen = {}
        for key, value in items:
            if key in seen:
                duplicates.append(key)
            seen[key] = value
        return seen

    try:
        with open(path, "rb") as f:
            data = json.loads(f.read().decode("utf-8"), object_pairs_hook=pairs)
    except OSError as error:
        return "can't be read (%s)" % error.strerror, [], None
    except (ValueError, UnicodeDecodeError) as error:
        return "not valid JSON (%s)" % error, [], None
    if not is_dict(data):
        return "not a JSON object", [], None
    normalize(data)
    problem = check_addon(data)
    if problem:
        return problem, [], data
    warnings = warnings_for(data, os.path.dirname(os.path.abspath(path)))
    # Only here ("(Mac)"): JSON allows a key twice and keeps the last one, which is easy to miss;
    # and symbols that older iOS versions don't have
    warnings += ["(Mac) duplicate key '%s' (the last one is used)" % key for key in duplicates]
    warnings += symbol_warnings(data)
    return None, warnings, data


def main(argv):
    strict = "--strict" in argv
    files = [a for a in argv if a != "--strict"]
    if not files:
        print(__doc__.strip())
        return 1
    status = 0
    for path in files:
        if len(files) > 1:
            print("== %s" % path)
        problem, warnings, data = lint(path)
        if problem:
            print("Problem: %s" % problem)
            status = 1
            continue
        n = len(data["actions"])
        print("OK: %s (%s), %d action%s" % (data["name"], data["id"], n, "" if n == 1 else "s"))
        for warning in warnings:
            print("Warning: %s" % warning)
        if warnings and strict and status == 0:
            status = 2
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
