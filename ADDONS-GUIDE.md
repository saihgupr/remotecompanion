# Writing an add-on

If you make an app or a tweak, an add-on lets people use it from RemoteCompanion. They can add
your actions to their triggers, check your tweak's state in an If or a Wait Until, run actions
when your tweak reports that something happened, and change your settings from RemoteCompanion's
own Settings.

An add-on is a single JSON file that you ship in your package. You don't write any code for
RemoteCompanion, and nothing in RemoteCompanion has to change to support you. The file describes
what your actions do, and RemoteCompanion does the rest.

This guide starts with a small add-on you can try in a few minutes, then explains how your tweak
and RemoteCompanion talk to each other, and ends with recipes for the things most add-ons need.
When you want the exact rules for a key, look it up in the reference, [ADDONS.md](ADDONS.md).

- [How an add-on is put together](#how-an-add-on-is-put-together)
- [Your first add-on](#your-first-add-on)
- [Shipping it with your tweak](#shipping-it-with-your-tweak)
- [Talking to your tweak](#talking-to-your-tweak)
- [Recipes](#recipes)
- [When something goes wrong](#when-something-goes-wrong)
- [Keeping it light on the battery](#keeping-it-light-on-the-battery)

You'll need a jailbroken phone with RemoteCompanion on it (rootless and rootful both work), and
Python 3 on your Mac to run the checker. You only need Theos once you package the file.

## How an add-on is put together

Everything in an add-on hangs off its **id**, a short word like `mytweak`. Each of your
**actions** adds one more word, so an action called `limit` is run with the command
`mytweak limit`. That command is all a trigger stores, which is why the same action works from a
button press, the Web UI, a shortcut or MQTT.

An action is a list of **steps**, run in order. A step does one small thing: it posts a
notification, writes a preference, runs a program, opens a URL, runs another RemoteCompanion
command, or waits a moment. An action can also have **options**, which are fixed choices like On
and Off, and an **input**, which is text the person types. Both end up in **variables** such as
`{mode}` or `{input}` that the steps can use.

Beyond actions, an add-on can offer **conditions**, which are values RemoteCompanion can check,
such as "is the charge limit on?". It can offer **events**, which are notifications your tweak
posts by itself; each one can become a trigger or show a banner. **Banners** are the small pop-ups
that confirm an action ran. And **settings** are switches and other controls that appear on your
add-on's page in RemoteCompanion.

You don't need all of that. The first add-on below has one action with one step.

## Your first add-on

This add-on shows how long the phone has been running. It uses `uptime`, a program every
jailbreak has, so you can try it without writing a tweak first. The file is
[`examples/uptime.json`](examples/uptime.json):

```json
{
  "$schema": "../addon.schema.json",
  "api": 1,
  "id": "uptime",
  "name": "Uptime",
  "icon": "clock",
  "actions": [
    {
      "command": "show",
      "name": "Show Uptime",
      "run": [
        { "exec": ["{jbroot}/usr/bin/uptime"], "as": "up" }
      ],
      "banner": { "subtitle": "{up}", "hold": 4 }
    }
  ]
}
```

The id is `uptime` and the action's command is `show`, so the action runs as `uptime show`. The
`name` and `icon` are what people see in the app; the icon is an SF Symbol name.

The action has a single step. `exec` runs a program directly, without a shell. `{jbroot}` stands
for the jailbreak's folder, which is `/var/jb` on rootless and nothing at all on rootful, so this
one file works on both. Normally a program's output becomes the command's reply, but `"as": "up"`
keeps it in a variable called `{up}` instead, and the banner shows that variable under the
add-on's name for four seconds.

The `$schema` line is optional. It points your editor (VS Code, for example) at the add-on
schema, so the editor can suggest keys and underline mistakes while you type.

### Check it

Before you put a file on a phone, run the checker on your Mac:

```sh
python3 tools/addon-lint.py examples/uptime.json
```

```
OK: Uptime (uptime), 1 action
```

The checker runs the same checks as the phone, word for word. That matters because the phone
skips any file with a problem, so you'd otherwise find out only when your add-on doesn't show up.
Add `--strict` and warnings fail too.

### Put it on your phone

Copy the file into the Add-ons folder as root. The folder is
`/var/jb/Library/RemoteCompanion/AddOns/` on rootless and `/Library/RemoteCompanion/AddOns/` on
rootful:

```sh
ssh root@<phone> mkdir -p /var/jb/Library/RemoteCompanion/AddOns
scp examples/uptime.json root@<phone>:/var/jb/Library/RemoteCompanion/AddOns/
```

You don't need to respring. RemoteCompanion watches that folder and picks up the new file within
a second. If you edit the file and copy it again, the change takes effect just as quickly.

### See it work

Open RemoteCompanion and add an action to any trigger. The action list now has an **Add-ons**
section with **Uptime** in it, and inside that, **Show Uptime**. Your add-on also has its own page
under Settings > Integrations, where people can turn it off, see what it adds, and change its
settings.

You can run it from the phone's command line too:

```sh
rc-client "uptime show"
```

And when you want to see exactly what happened, ask for a trace. It runs the action for real and
reports each step:

```sh
rc-client "addons trace uptime show"
```

```
Uptime: Show Uptime (uptime show)
Variables: jbroot='/var/jb'
1. exec /var/jb/usr/bin/uptime -> exit 0, 0.11 s, output: 12:53:37  up 2 days ...
   {up} = '12:53:37  up 2 days ...'
Banner: Uptime / 12:53:37  up 2 days ...
Reply: Uptime: Show Uptime
```

You'll use `addons trace` a lot. Whenever a step doesn't do what you expect, the trace tells you
whether it ran and, if not, why it was skipped.

## Shipping it with your tweak

When you're ready to ship, put the file in your Theos project's `layout` folder, named after your
add-on's id:

```
layout/Library/RemoteCompanion/AddOns/mytweak.json
```

For a rootless package, Theos moves it under `/var/jb` for you. If your icon is an image instead
of an SF Symbol (`"icon": "mytweak.png"`), put the image next to the JSON file.

Installing your package adds the add-on straight away, upgrading it updates the add-on, and
removing it removes the add-on, all without a respring. Your package doesn't need to depend on
RemoteCompanion; if RemoteCompanion isn't installed, the file simply sits there unused.

If you ship the add-on in a different package from the tweak it controls, add a `requires` list
with a path your tweak installs. RemoteCompanion then offers the add-on only when that path
exists, and lists it as not installed otherwise.

It's worth running the checker as part of your build, so a broken file can never make it into a
package:

```make
before-package::
	python3 /path/to/addon-lint.py --strict layout/Library/RemoteCompanion/AddOns/*.json
```

## Talking to your tweak

RemoteCompanion never runs your code. It reaches your tweak in one of three ways, and you choose
one for each step.

The usual choice is a **notification** (`notify`). It's a Darwin notification that your tweak
listens for, so it arrives instantly and costs almost nothing. If your tweak keeps its settings in
a **preference** domain, a `defaults` step can write them directly, usually followed by a `notify`
so the tweak knows to reread them. And if you ship a command-line tool, or the work needs root,
an `exec` step runs it (with `"root": true` for root). That starts a new process each time, so
save it for the cases that need it.

Your tweak talks back the same way: it posts a notification and attaches a **state**, which is
just a number. That one notification can do three jobs at once. A condition with `notifyState`
reads the state, an event with the same name fires (and can be a trigger, including one per
state), and an action's banner can `await` it to show what the tweak reported.

Here's the tweak's side in Objective-C:

```objc
#include <notify.h>

// Tell RemoteCompanion the new state. Keep the token: the state lasts only while a
// registration for the name is open.
static void MyTweakPublishState(uint64_t state) {
    static int token = NOTIFY_TOKEN_INVALID;
    if (token == NOTIFY_TOKEN_INVALID) notify_register_check("com.example.mytweak/state", &token);
    notify_set_state(token, state);
    notify_post("com.example.mytweak/state");
}

// Listen for what the add-on's steps post ("notify": "com.example.mytweak/on")
__attribute__((constructor)) static void MyTweakListen(void) {
    int on, off;
    notify_register_dispatch("com.example.mytweak/on", &on, dispatch_get_main_queue(), ^(__unused int t) {
        // ... turn it on ...
        MyTweakPublishState(1);
    });
    notify_register_dispatch("com.example.mytweak/off", &off, dispatch_get_main_queue(), ^(__unused int t) {
        // ... turn it off ...
        MyTweakPublishState(0);
    });
}
```

Start every notification name with your bundle id so it can't clash with anyone else's. One thing
to know about states: a state only lasts while some process holds a registration for its name.
A tweak running in SpringBoard or a daemon keeps it for as long as it runs, but if your tweak
lives in an app, the state disappears when the app quits.

## Recipes

Every recipe here comes from [`examples/cookbook.json`](examples/cookbook.json), which works as
it is because it uses its own preference domain and notification names. Install it next to your
own add-on, try each action, and copy what you need.

### Turn something on, off, or toggle it

Most switch-like actions want three behaviours: turn it on, turn it off, or flip it. You get all
three from one option with an On and an Off choice. When someone leaves the option on Keep
Current, it has no value, and that's the signal to toggle:

```json
{
  "command": "switch",
  "name": "Switch",
  "options": [
    { "id": "mode", "title": "Mode", "choices": [
      { "word": "on",  "label": "On",  "value": "1" },
      { "word": "off", "label": "Off", "value": "0" } ] }
  ],
  "run": [
    { "defaults": { "domain": "com.example.cookbook", "key": "enabled", "toggle": true },
      "if": { "var": "mode", "unset": true } },
    { "defaults": { "domain": "com.example.cookbook", "key": "enabled", "value": "{mode}", "type": "bool" } },
    { "defaults": { "domain": "com.example.cookbook", "key": "enabled", "read": true, "as": "now" } },
    { "notify": "com.example.cookbook/changed" }
  ],
  "banner": { "subtitle": "{now}" }
}
```

So `cookbook switch on` writes true, `cookbook switch off` writes false, and plain
`cookbook switch` toggles. The trick is a rule that runs through every add-on: **a step that uses
a variable with no value is skipped.** The second step uses `{mode}`, so it only runs when a
choice was made, and the first step is told to run only when `mode` is unset. The third step reads
the result back as On or Off for the banner, and the last one tells the tweak to reread its
settings. If your tweak keeps its own state instead of a preference, you only need the `notify`.

A choice's `value` can also go straight into a step. For example,
`"exec": ["{jbroot}/usr/bin/mytool", "{mode}"]` passes 1 or 0 to your tool, with no need for a
separate step per choice.

### Show what a program prints

```json
"run": [ { "exec": ["{jbroot}/usr/bin/uptime"], "as": "up" } ],
"banner": { "subtitle": "{up}" }
```

With `as`, the program's output is kept in a variable, with several lines joined by ` · `. Only
standard output goes in; anything the program writes to standard error shows up in
`addons trace` instead, so a stray warning won't end up in your banner. Without `as`, the output
becomes the command's reply, which is what the Web UI and `rc-client` show.

### Ask for text

```json
{
  "command": "say",
  "name": "Show Text",
  "input": { "title": "Text", "placeholder": "Hello" },
  "run": [ { "command": "toast \"{input}\"" } ]
}
```

When someone adds this action, the app asks for the text and saves it as part of the command, so
the trigger ends up running something like `cookbook say Hello there`. Your steps get it as
`{input}`, or word by word as `{word1}`, `{word2}` and so on. Add `"number": true` to the input
for a number keyboard.

Typed text stays text even if it happens to contain one of the action's choice words. If it
starts with one, the app quietly puts `--` in front so it's still read as text. This example
uses a `command` step, which runs any RemoteCompanion command; here it shows a toast.

### Wait for your tweak to confirm

A banner usually just confirms that the action ran. If your tweak reports back, the banner can
show what actually happened instead:

```json
"banner": { "await": "com.example.cookbook/state", "states": { "1": "Ready", "2": "Busy" }, "timeout": 3 }
```

RemoteCompanion starts listening before the steps run, so even a very quick reply is caught. If
nothing arrives before the timeout, no banner shows. In the cookbook, the action posts the state
itself to stand in for a tweak.

### Offer a condition

A condition lets people ask about your tweak in an If or a Wait Until. The cheapest kind reads
your tweak's state notification:

```json
{ "id": "state", "name": "State", "type": "choice",
  "notifyState": "com.example.cookbook/state", "choices": { "1": "Ready", "2": "Busy" } }
```

A condition can also take its value from a program's output. A `number` condition is compared
with "above" and "below", the way battery level is:

```json
{ "id": "hour", "name": "Hour", "type": "number",
  "exec": ["{jbroot}/bin/date", "+%H"], "cache": 60 }
```

Keep in mind that the program runs every time the condition is checked, and a Wait Until checks
twice a second, so give this kind a `cache` to reuse its value for a while. You can see a
condition's current value from the phone with `rc-client "addons check addon:cookbook:hour"`.

### Offer a trigger

When your tweak posts a notification on its own, an event turns it into a trigger people can
hang actions on:

```json
"events": [
  { "notify": "com.example.cookbook/state",
    "trigger": { "id": "state", "name": "State Changed", "states": { "1": "Ready", "2": "Busy" } } }
]
```

The app then offers **State Changed**, which fires every time, plus **State Changed (Ready)** and
**State Changed (Busy)** for each state. Set `"states": false` if you only want the first one. An
event can show a banner instead of a trigger, or both.

### Say when something failed

```json
{
  "command": "connect",
  "name": "Connect",
  "run": [
    { "exec": ["{jbroot}/usr/bin/mytool", "connect"], "stopOnError": true },
    { "notify": "com.example.mytweak/connected" }
  ],
  "banner": { "subtitle": "Connected", "failed": "Couldn't connect (exit {exit})" }
}
```

By default an action runs all its steps, whatever happens. With `stopOnError`, the action stops
as soon as the program exits with anything other than 0, so the `notify` only runs when the
connection worked, and the banner shows the `failed` text instead of the subtitle. Even without
`stopOnError`, `{exit}` holds the last program's exit status, so a later step can check it with
`"if": { "var": "exit", "isNot": "0" }`.

### Compare numbers

```json
{ "exec": ["{jbroot}/usr/bin/mytool", "temperature"], "as": "temp" },
{ "command": "toast \"Hot: {temp}°\"", "if": { "var": "temp", "above": 40 } }
```

`above` and `below` compare numbers, and you can use both for a range. If the value isn't a
number, the step is skipped. The limit can be a variable too, as in `"below": "{input}"`.

### Let people set your tweak up

Settings appear on your add-on's page in Settings > Integrations, and each one is tied to one of
your tweak's preferences:

```json
"settings": [
  { "id": "level", "title": "Level", "type": "number", "min": 0, "max": 100, "step": 10, "unit": "%",
    "domain": "com.example.cookbook", "key": "level", "default": 50,
    "notify": "com.example.cookbook/changed" }
]
```

There are four types: `switch`, `choice`, `number` and `text`. When someone changes a setting,
RemoteCompanion writes the preference and posts your `notify`, and your tweak reads the
preference the way it already does. The cookbook has one of each type.

### Run something as root

```json
{ "exec": ["{jbroot}/usr/bin/id", "-un"], "root": true, "as": "root" }
```

Root steps go through RemoteCompanion's `rc-root` helper. Only use root when the work really
needs it.

### Pick icons that work on older iOS

RemoteCompanion runs on iOS 14 and later, but many SF Symbols only arrived in iOS 15 or later.
If a phone doesn't have one of your icons, RemoteCompanion draws an older stand-in when it knows
one, and otherwise falls back to your add-on's icon, then to its own puzzle piece. You'll get the
best result by choosing symbols that iOS 14 has. On a Mac, the checker tells you which of your
icons need a newer iOS.

### Write less

You can usually leave things out. `"banner": true` gives you a banner with the add-on's name over
the action's name. Options don't need a `title`, and choices don't need a `label`, when the id or
word already reads well. And the add-on's `icon` is used for any action, condition or trigger
that doesn't have its own.

## When something goes wrong

Start on the phone with `rc-client "addons"`, which lists what loaded, what isn't installed and
which files have problems. Then use `addons trace` on the action that misbehaves. Most problems
turn out to be one of these:

| What you see | What's going on |
|---|---|
| Your add-on isn't in the app | The file has a problem, and `addons` (or the checker) tells you what it is. Or it's listed as not installed, because none of its `requires` paths exist. |
| A step doesn't run | `addons trace` says why: an `if` didn't hold, or the step uses a variable with no value (often an option left on Keep Current). Steps after a failed `stopOnError` step don't run either. |
| "Could not run" | The program's path is wrong, or the file isn't executable. Paths are used exactly as written, and there's no shell. |
| It works on rootless but not on rootful | A path is written with `/var/jb/`. Use `{jbroot}/` instead; the checker warns about this. |
| "taken by the built-in command" | RemoteCompanion's own commands are tried first, so ids like `spotify` or `camera` can never be reached. Pick a different id. |
| No banner | Each action's banner can be switched off, on your add-on's page or in Settings > Banners. An `await` banner also shows nothing if no reply arrives in time. |
| A condition is never true | `addons check addon:<id>:<condition>` shows its current value. A program that exits with an error makes the value unknown, which counts as false. A `choice` condition is compared with the labels in `choices`, not the raw values. |
| A trigger never fires | Check that the notification name matches exactly. Triggers also respect RemoteCompanion's master switch and excluded apps. |
| Nothing from your add-on works | Check that it isn't switched off on its page in Settings > Integrations. |

RemoteCompanion's log records every file with a problem and every program that couldn't start or
ran too long, as lines starting with `[AddOns]`. If you set Settings > Advanced Settings > Logging
to Full, it also records each time the add-ons load and each action that runs, with its
variables. The log is at `/var/jb/tmp/remotecommand.log` on rootless and `/tmp/remotecommand.log`
on rootful.

## Keeping it light on the battery

Nothing in an add-on runs on a timer. RemoteCompanion just listens for your notifications and
watches the Add-ons folder, which costs nothing while nothing is happening.

The thing to watch is programs. Every `exec` step starts a new process, so lean on notifications
where you can. A Wait Until on a `notifyState` condition, for example, simply waits for your
notification instead of checking twice a second. When you do need a program, keep it quick
(RemoteCompanion stops it after 10 seconds) and give `exec` conditions a `cache`.
