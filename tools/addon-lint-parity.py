#!/usr/bin/env python3
"""addon-lint-parity: checks that tools/addon-lint.py and the phone agree.

    python3 tools/addon-lint-parity.py <user@phone> [ssh options, e.g. -i ~/.ssh/key]

It writes about 80 add-on files (examples/cookbook.json, and that file broken in one way each),
copies them to the phone, and compares `addons validate` there with addon-lint.py here, line for
line. Run it after changing the checks on either side. The phone needs a RemoteCompanion build
with the same checks installed, and `rc-client` (part of RemoteCompanion).

Every file goes through SpringBoard's loader, so the run stops at once if a reply goes missing or
SpringBoard restarts (a check that throws instead of reporting a problem). The files are removed
from the phone afterwards. Exit status: 0 when all agree, 1 otherwise.
"""
import copy
import importlib.util
import json
import os
import shlex
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REMOTE = "/var/mobile/Documents/rc-lint-parity"

spec = importlib.util.spec_from_file_location("addon_lint", os.path.join(HERE, "addon-lint.py"))
lint = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lint)


def action(d, command):
    return next(a for a in d["actions"] if a["command"] == command)


def step(d, command, i=0):
    return action(d, command)["run"][i]


def whole_builtin(d, details):
    """Makes the first action a whole built-in command ("<word> <word>", not under a built-in prefix)"""
    for command in lint.BUILTIN_COMMANDS:
        parts = command.split(" ")
        if len(parts) == 2 and lint.builtin_taking(parts[0], parts[1])[1] and lint.word_list(parts[0]) and "." not in parts[0]:
            d["id"] = parts[0]
            a = action(d, "say")
            a["command"] = parts[1]
            if not details:
                a.pop("input", None)
            return
    raise SystemExit("no two-word built-in command to test with")


# Each case changes a copy of examples/cookbook.json (plus an event with an action and a banner)
CASES = {
    "valid": lambda d: None,
    # the add-on
    "id_upper": lambda d: d.update(id="Cook"),
    "id_dot": lambda d: d.update(id="cook.book"),
    "id_reserved": lambda d: d.update(id="addons"),
    "api_2": lambda d: d.update(api=2),
    "api_zero": lambda d: d.update(api=0),
    "api_text": lambda d: d.update(api="1"),
    "name_missing": lambda d: d.pop("name"),
    "icon_num": lambda d: d.update(icon=5),
    "requires_text": lambda d: d.update(requires="/x"),
    "actions_empty": lambda d: d.update(actions=[]),
    "action_not_obj": lambda d: d["actions"].append("x"),
    "conditions_text": lambda d: d.update(conditions="x"),
    "events_num": lambda d: d.update(events=5),
    # actions
    "command_upper": lambda d: action(d, "say").update(command="Say"),
    "command_dup": lambda d: action(d, "say").update(command="switch"),
    "action_noname": lambda d: action(d, "say").pop("name"),
    "run_empty": lambda d: action(d, "say").update(run=[]),
    "banner_text": lambda d: action(d, "say").update(banner="x"),
    "banner_hold_text": lambda d: action(d, "say").update(banner={"hold": "2"}),
    "banner_states_num": lambda d: action(d, "say").update(banner={"states": {"1": 2}}),
    "banner_failed_num": lambda d: action(d, "find")["banner"].update(failed=3),
    "banner_false": lambda d: action(d, "find").update(banner=False),
    "banner_true": lambda d: action(d, "say").update(banner=True),
    "input_text": lambda d: action(d, "say").update(input="x"),
    "input_number_text": lambda d: action(d, "say").update(input={"number": "yes"}),
    # steps
    "step_two_kinds": lambda d: action(d, "say")["run"].append({"notify": "a", "url": "b"}),
    "step_unknown_key": lambda d: action(d, "say")["run"].append({"notify": "a", "bogus": 1}),
    "step_no_kind": lambda d: action(d, "say")["run"].append({"state": 1}),
    "root_list": lambda d: step(d, "whoami").update(root=[]),
    "ifoptions_text": lambda d: step(d, "say").update(ifOptions="yes"),
    "stoponerror_text": lambda d: step(d, "find").update(stopOnError="yes"),
    "stoponerror_on_notify": lambda d: step(d, "state").update(stopOnError=True),
    "state_text": lambda d: step(d, "state").update(state="x"),
    "unset_list": lambda d: step(d, "switch").update({"if": {"var": "mode", "unset": []}}),
    "if_no_var": lambda d: step(d, "say").update({"if": {"is": "x"}}),
    "if_no_test": lambda d: step(d, "say").update({"if": {"var": "x"}}),
    "if_above_list": lambda d: step(d, "minute", 1)["if"].update(above=[]),
    "if_below_only": lambda d: step(d, "say").update({"if": {"var": "input", "below": "{input}"}}),
    "read_list": lambda d: action(d, "say")["run"].append({"defaults": {"domain": "a", "key": "b", "read": [], "as": "x"}}),
    "labels_text": lambda d: action(d, "say")["run"].append({"defaults": {"domain": "a", "key": "b", "toggle": True, "labels": "x"}}),
    "type_bad": lambda d: action(d, "say")["run"].append({"defaults": {"domain": "a", "key": "b", "value": "1", "type": 5}}),
    "state_on_exec": lambda d: step(d, "whoami").update(state=1),
    "root_on_notify": lambda d: step(d, "state").update(root=True),
    "as_on_notify": lambda d: step(d, "state").update(**{"as": "x"}),
    "as_jbroot": lambda d: step(d, "whoami").update(**{"as": "jbroot"}),
    "as_exit": lambda d: step(d, "whoami").update(**{"as": "exit"}),
    "exec_relative": lambda d: step(d, "whoami").update(exec=["id", "-un"]),
    "exec_number_arg": lambda d: step(d, "whoami").update(exec=["/usr/bin/id", 1]),
    "defaults_no_domain": lambda d: action(d, "say")["run"].append({"defaults": {"key": "b", "value": 1}}),
    "defaults_read_no_as": lambda d: action(d, "say")["run"].append({"defaults": {"domain": "a", "key": "b", "read": True}}),
    "defaults_nothing": lambda d: action(d, "say")["run"].append({"defaults": {"domain": "a", "key": "b"}}),
    "delay_text": lambda d: action(d, "say")["run"].append({"delay": "1"}),
    "url_empty": lambda d: action(d, "say")["run"].append({"url": ""}),
    # options and choices
    "options_obj": lambda d: action(d, "switch").update(options={}),
    "option_no_choices": lambda d: action(d, "switch")["options"][0].update(choices=[]),
    "option_id_jbroot": lambda d: action(d, "switch")["options"][0].update(id="jbroot"),
    "option_id_exit": lambda d: action(d, "switch")["options"][0].update(id="exit"),
    "option_id_word2": lambda d: action(d, "switch")["options"][0].update(id="word2"),
    "option_title_num": lambda d: action(d, "switch")["options"][0].update(title=3),
    "choice_word_dup": lambda d: action(d, "switch")["options"][0]["choices"][1].update(word="on"),
    "choice_word_bad": lambda d: action(d, "switch")["options"][0]["choices"][1].update(word="Off"),
    "choice_label_num": lambda d: action(d, "switch")["options"][0]["choices"][1].update(label=0),
    "skipwhen_self": lambda d: action(d, "switch")["options"][0].update(skipWhen={"mode": "on"}),
    # conditions
    "condition_dup": lambda d: d["conditions"].append(dict(d["conditions"][0])),
    "condition_root_text": lambda d: d["conditions"][1].update(root="yes"),
    "condition_type_bad": lambda d: d["conditions"][1].update(type="text"),
    "condition_no_source": lambda d: d["conditions"][0].pop("notifyState"),
    "condition_exec_var": lambda d: d["conditions"][1].update(exec=["/bin/date", "{input}"]),
    "condition_cache_neg": lambda d: d["conditions"][1].update(cache=-1),
    "condition_choices_num": lambda d: d["conditions"][0].update(choices={"1": 1}),
    # events
    "event_no_notify": lambda d: d["events"][1].pop("notify"),
    "event_nothing": lambda d: [d["events"][1].pop(k) for k in ("banner", "trigger")],
    "trigger_id_bad": lambda d: d["events"][1]["trigger"].update(id="Ev"),
    "trigger_states_true": lambda d: d["events"][1]["trigger"].update(states=True),
    "event_action_bad": lambda d: d["events"][1].update(action="nope"),
    # variable names, literal braces and built-in commands
    "as_bad_name": lambda d: step(d, "whoami").update(**{"as": "my var"}),
    "as_defaults_bad": lambda d: action(d, "switch")["run"][2]["defaults"].update(**{"as": "1x"}),
    "braces_literal": lambda d: step(d, "whoami").update(exec=["{jbroot}/usr/bin/awk", "{print $1}", "{}", "/dev/null"]),
    "builtin_id": lambda d: d.update(id="spotify"),
    "builtin_whole_bare": lambda d: whole_builtin(d, details=False),
    "builtin_whole_details": lambda d: whole_builtin(d, details=True),
    # settings
    "settings_text": lambda d: d.update(settings="x"),
    "setting_not_obj": lambda d: d["settings"].append(3),
    "setting_bad_id": lambda d: d["settings"][0].update(id="Enabled"),
    "setting_dup": lambda d: d["settings"].append(dict(d["settings"][0])),
    "setting_no_title": lambda d: d["settings"][0].pop("title"),
    "setting_bad_type": lambda d: d["settings"][0].update(type="slider"),
    "setting_no_key": lambda d: d["settings"][0].pop("key"),
    "setting_note_num": lambda d: d["settings"][0].update(note=5),
    "setting_min_text": lambda d: d["settings"][2].update(min="0"),
    "setting_switch_default": lambda d: d["settings"][0].update(default="yes"),
    "setting_text_default": lambda d: d["settings"][3].update(default=5),
    "setting_number_default": lambda d: d["settings"][2].update(default="50"),
    "setting_min_above_max": lambda d: d["settings"][2].update(min=200),
    "setting_step_zero": lambda d: d["settings"][2].update(step=0),
    "setting_no_choices": lambda d: d["settings"][1].update(choices=[]),
    "setting_choice_no_label": lambda d: d["settings"][1]["choices"][0].pop("label"),
    "setting_choice_dup": lambda d: d["settings"][1]["choices"][1].update(value="slow"),
    "setting_choice_default": lambda d: d["settings"][1].update(default="warp"),
    "setting_choice_number": lambda d: d["settings"][1]["choices"][0].update(value=1),
    "setting_null_default": lambda d: d["settings"][0].update(default=None),
    "warn_setting_key": lambda d: d["settings"][0].update(colour="red"),
    # warnings
    "warn_unknown_key": lambda d: d.update(colour="red"),
    "warn_jb_path": lambda d: step(d, "whoami").update(exec=["/var/jb/usr/bin/id", "-un"]),
}


def parse_commands(catalog):
    """Commands to read: each installed action bare, with each choice, with input that starts with a
    choice word, with "--", with a second word for the same option, and with odd spacing and case"""
    commands = []
    for addOn in catalog:
        for a in addOn.get("actions", []):
            base = "%s %s" % (addOn["id"], a["command"])
            commands.append(base)
            words = [c["word"] for o in a.get("options", []) for c in o.get("choices", [])]
            for word in words[:4]:
                commands.append("%s %s" % (base, word))
            if words:
                commands.append("%s %s %s typed text" % (base, words[0], words[-1]))
                commands.append("%s -- %s text" % (base, words[0]))
                commands.append("%s %s -- %s" % (base, words[0], words[0]))
                commands.append("  %s   %s  " % (base.upper(), words[0].upper()))
            commands.append("%s some typed text" % base)
    commands.append("nosuchaddon run")
    return commands


def main(argv):
    if not argv:
        print(__doc__.strip())
        return 1
    destination, ssh_options = argv[0], argv[1:]
    control = os.path.join(tempfile.gettempdir(), "rc-lint-parity-%d" % os.getpid())
    ssh = ["ssh", "-o", "BatchMode=yes", "-o", "ControlMaster=auto", "-o", "ControlPath=" + control,
           "-o", "ControlPersist=60"] + ssh_options + [destination]

    def remote(command):
        return subprocess.run(ssh + [command], capture_output=True, text=True).stdout

    with open(os.path.join(HERE, "..", "examples", "cookbook.json")) as f:
        base = json.load(f)
    base["events"].append({"notify": "com.example.cookbook/other", "action": "state",
                           "banner": {"states": {"1": "On"}}, "trigger": {"id": "other", "name": "Other", "states": False}})

    with tempfile.TemporaryDirectory() as folder:
        for name, change in CASES.items():
            d = copy.deepcopy(base)
            change(d)
            with open(os.path.join(folder, name + ".json"), "w") as f:
                json.dump(d, f, indent=1)
        remote("rm -rf %s && mkdir -p %s" % (REMOTE, REMOTE))
        files = [os.path.join(folder, name + ".json") for name in CASES]
        subprocess.run(["scp", "-q", "-o", "BatchMode=yes", "-o", "ControlPath=" + control] + ssh_options
                       + files + ["%s:%s/" % (destination, REMOTE)], check=True)

        # The pid is read here: not every phone has awk
        pid_command = "ps -axo pid,comm | grep 'SpringBoard.app/SpringBoard$'"

        def pid_of(text):
            parts = text.split()
            return parts[0] if parts else ""

        springboard = pid_of(remote(pid_command))
        same = different = 0
        stopped = None
        for name in CASES:
            reply = remote("rc-client %s; echo; %s" % (shlex.quote("addons validate %s/%s.json" % (REMOTE, name)), pid_command))
            lines = reply.rstrip("\n").split("\n")
            phone, now = "\n".join(lines[:-1]).strip(), pid_of(lines[-1])
            if not phone or now != springboard:
                stopped = name
                break
            problem, warnings, data = lint.lint(os.path.join(folder, name + ".json"))
            if problem:
                mac = "Problem: %s" % problem
            else:
                n = len(data["actions"])
                # "(Mac)" warnings come from the Mac's own checks (SF Symbols, duplicate keys)
                mac = "\n".join(["OK: %s (%s), %d action%s" % (data["name"], data["id"], n, "" if n == 1 else "s")]
                                + ["Warning: %s" % w for w in warnings if not w.startswith("(Mac)")])
            if phone == mac:
                same += 1
                print("same  %-24s %s" % (name, mac.split("\n")[-1]))
            else:
                different += 1
                print("DIFF  %s\n   phone: %s\n   mac:   %s" % (name, phone.replace("\n", " | "), mac.replace("\n", " | ")))
        # How commands read: the tweak ("addons parse") against rc_addon_commands.js (run here with
        # macOS's JavaScript for Automation), with the add-ons installed on the phone
        catalog = json.loads(remote("cat /var/mobile/Documents/rc_addons.json") or "{}").get("addons", [])
        commands = parse_commands(catalog)
        script = os.path.join(HERE, "..", "Tweak", "layout", "Library", "Application Support", "RemoteCompanion", "rc_addon_commands.js")
        with open(script) as f:
            js = f.read()
        js_input = os.path.join(folder, "parse.json")
        with open(js_input, "w") as f:
            json.dump({"addons": catalog, "commands": commands}, f)
        jxa = js + """
            ObjC.import('Foundation');
            var input = JSON.parse($.NSString.stringWithContentsOfFileEncodingError(%s, $.NSUTF8StringEncoding, null).js);
            JSON.stringify(input.commands.map(function (c) {
              var m = RCAddOnCommands.match(input.addons, c);
              if (!m) return {};
              var addOn = input.addons[m.addOn], action = addOn.actions[m.action];
              var split = RCAddOnCommands.split(action, m.rest);
              var out = { addon: addOn.id, action: action.command, choices: split.choices };
              if (split.input !== null) out.input = split.input;
              return out;
            }));""" % json.dumps(js_input)
        js_results = json.loads(subprocess.run(["osascript", "-l", "JavaScript", "-e", jxa], capture_output=True, text=True, check=True).stdout)
        for command, js_result in zip(commands, js_results):
            tweak = remote("rc-client %s" % shlex.quote("addons parse " + command)).strip()
            tweak_result = json.loads(tweak) if tweak.startswith("{") else {"error": tweak}
            if tweak_result == js_result:
                same += 1
                print("same  parse %-40s %s" % (command, json.dumps(js_result, sort_keys=True)))
            else:
                different += 1
                print("DIFF  parse %s\n   phone: %s\n   js:    %s" % (command, json.dumps(tweak_result, sort_keys=True), json.dumps(js_result, sort_keys=True)))
        remote("rm -rf %s" % REMOTE)
        subprocess.run(ssh[:1] + ["-o", "ControlPath=" + control, "-O", "exit", destination], capture_output=True)

    if stopped:
        print("STOPPED at %s: no reply, or SpringBoard restarted (pid %s)" % (stopped, springboard))
        return 1
    print("%d same, %d different" % (same, different))
    return 0 if different == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
