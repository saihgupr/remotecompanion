# Add-ons

**Add-on API, version 1.**

An add-on lets another app or tweak offer its own actions, conditions, triggers, banners and
settings in RemoteCompanion, without RemoteCompanion needing any change. It's a single JSON file
that ships in the app's or tweak's package.

The file only describes what to do; it never runs code inside SpringBoard, so a mistake in an
add-on can't crash it. Anything more involved belongs in the add-on's own tool or tweak, which the
file calls on with `exec` or `notify`.

This page is the reference: every key and every rule. If you're new to add-ons, start with the
guide, [ADDONS-GUIDE.md](ADDONS-GUIDE.md). It walks through a first add-on, explains how a tweak
and RemoteCompanion talk to each other, and has recipes for the usual patterns.

- [Install](#install)
- [Example](#example)
- [Rules that apply everywhere](#rules-that-apply-everywhere)
- [Add-on](#add-on) · [Actions](#actions) · [Options](#options) · [Input](#input) · [Steps](#steps)
- [Variables](#variables-and-templates) · [Banners](#banners) · [Conditions](#conditions)
- [Events and triggers](#events-and-triggers) · [Settings](#settings)
- [Running an action](#running-an-action) · [Commands](#commands) · [Limits](#limits)
- [Validation](#validation) · [Versioning](#versioning) · [Security](#security)

## Install

| | |
|---|---|
| Rootless | `/var/jb/Library/RemoteCompanion/AddOns/<id>.json` |
| Rootful | `/Library/RemoteCompanion/AddOns/<id>.json` |

A package puts its file in one of these folders. RemoteCompanion reads every `.json` file there
when it starts, and it watches the folders and the files in them, so it reads them again about
half a second after a file is added, removed or edited. That means installing, upgrading or
removing an add-on never needs a respring, and its events and triggers start or stop straight
away. Nothing is checked on a timer. You can also ask for a fresh read with `addons reload`.

Files are read in alphabetical order, the rootless folder first. If two files use the same `id`,
the first one wins and the second is reported as a problem.

In the app, each add-on gets a row in Settings > Integrations, in an Add-ons section below
RemoteCompanion's own integrations. Its page has a switch that turns it off without uninstalling
it (it then offers nothing, and its events stop), its settings, what it adds, a switch for each of
its actions' banners, and where its file is. Below the add-ons, rows list any add-ons whose app or
tweak isn't installed, and any file with a problem, with the reason.

## Example

The [`examples/`](examples) folder has files you can try without any other tweak:
`hello.json` (`hello greet goodbye` shows a toast), `uptime.json` (the guide's first add-on) and
`cookbook.json` (every pattern in the guide).

Here's a fuller one, for an imaginary night light tweak:

```json
{
  "api": 1,
  "id": "nightlight",
  "name": "Night Light",
  "requires": ["/Library/MobileSubstrate/DynamicLibraries/NightLight.dylib"],
  "actions": [
    {
      "command": "light",
      "name": "Night Light",
      "icon": "lightbulb.fill",
      "options": [
        { "id": "mode", "title": "Mode", "choices": [
          { "word": "toggle", "label": "Toggle", "value": "Toggle" },
          { "word": "on",     "label": "On",     "value": "On" },
          { "word": "off",    "label": "Off",    "value": "Off" } ] },
        { "id": "color", "title": "Color", "skipWhen": { "mode": "off" }, "choices": [
          { "word": "warm", "label": "Warm" },
          { "word": "cool", "label": "Cool" } ] },
        { "id": "brightness", "title": "Brightness", "skipWhen": { "mode": "off" }, "choices": [
          { "word": "low",  "label": "Low" },
          { "word": "high", "label": "High" } ] }
      ],
      "run": [
        { "defaults": { "domain": "com.example.nightlight", "key": "color", "value": "{color}" } },
        { "defaults": { "domain": "com.example.nightlight", "key": "brightness", "value": "{brightness}" } },
        { "notify": "com.example.nightlight/toggle", "if": { "var": "mode", "unset": true } },
        { "notify": "com.example.nightlight/toggle", "if": { "var": "mode", "is": "Toggle" } },
        { "notify": "com.example.nightlight/on",     "if": { "var": "mode", "is": "On" } },
        { "notify": "com.example.nightlight/off",    "if": { "var": "mode", "is": "Off" } }
      ],
      "banner": {
        "title": "Night Light", "icon": "lightbulb.fill",
        "await": "com.example.nightlight/state",
        "states": { "1": "On", "0": "Off" }
      }
    }
  ],
  "conditions": [
    { "id": "lit", "name": "Night Light On", "type": "choice",
      "notifyState": "com.example.nightlight/state", "choices": { "1": "Yes", "0": "No" } }
  ],
  "events": [
    { "notify": "com.example.nightlight/state",
      "trigger": { "id": "power", "name": "Night Light", "icon": "lightbulb.fill",
                   "states": { "1": "Turned On", "0": "Turned Off" } } }
  ]
}
```

Running `nightlight light on warm` turns the light on with Mode set to On and Color set to Warm.
Running plain `nightlight light` chooses nothing, so the light toggles and the color and
brightness stay as they are.

## Rules that apply everywhere

- **The file is one JSON object.** Keys RemoteCompanion doesn't know are ignored when it loads the
  file, so an add-on written for a newer RemoteCompanion still loads on an older one where it can.
  `addons validate` lists them as warnings. The one exception is a step: a step with an unknown key
  is a problem.
- **Kinds are strict.** A value of the wrong kind, such as text where a number belongs, makes the
  whole file a problem. A file with a problem isn't loaded at all, and the app shows why.
- **Words are lowercase.** That goes for an action's `command` and a choice's `word`. Typed
  commands are matched without regard to case.
- **Icons are SF Symbol names**, such as `"mic.circle.fill"`. Many symbols are newer than iOS 14,
  the oldest iOS RemoteCompanion runs on. When a phone doesn't have a symbol, RemoteCompanion draws
  an older stand-in if it has one; otherwise it uses the add-on's icon, then its own puzzle piece,
  and a banner shows no icon. The Mac checker warns about symbols that need a newer iOS. The icon
  of an add-on, action, condition or trigger can also be an image file (see [Add-on](#add-on));
  banners only use symbols.
- **Text is shown as written.** There's no markup.
- **Paths are absolute.** That applies to `requires` and `exec`. For the jailbreak's own files,
  start the path with `{jbroot}` (`"{jbroot}/usr/bin/tool"`). It means `/var/jb` on rootless and
  nothing on rootful, so one file works on both. In `requires`, a path that doesn't start with
  `/var/` is also tried with `/var/jb` in front. `exec` uses its path exactly as written, and
  `addons validate` warns about an `exec` path that starts with `/var/jb/`.

## Add-on

These are the keys at the top of the file.

| Key | | Kind | Meaning |
|---|---|---|---|
| `api` | | whole number ≥ 1 | The API version the file is written for. Default 1. A file for a newer API than the app has is a problem ("needs add-on API N"). |
| `id` | required | text | The command word: lowercase letters, digits and `-`. `addons` is reserved. Built-in commands are tried first, so an action whose command a built-in one would take (with an id like `spotify` or `camera`) could never run; the file is a problem that names the built-in command. |
| `name` | required | text | Shown in the app and in banners. |
| `icon` | | text | The add-on's icon: an SF Symbol, **or an image file** (a name ending in `.png`, `.jpg` or `.jpeg`, found beside the JSON file, or an absolute path). It's also the icon of everything in the add-on that has no `icon` of its own. An image is cut to a rounded square, so give it a square picture of at least 120 px, under 512 KB. A missing or oversized image falls back to the puzzle piece (`addons validate` warns). Default: a puzzle piece. |
| `requires` | | list of paths | The add-on is offered only when at least one of these paths exists; otherwise it's listed as not installed. Leave it out to always offer the add-on. |
| `actions` | required | list, not empty | See [Actions](#actions). |
| `conditions` | | list | See [Conditions](#conditions). |
| `events` | | list | See [Events and triggers](#events-and-triggers). |
| `settings` | | list | See [Settings](#settings). |

## Actions

Each action is something people can add to a trigger. In the action list it appears as
"Add-on: Name", and inside the add-on's own list as just its name.

| Key | | Kind | Meaning |
|---|---|---|---|
| `command` | required | text | The words that follow the add-on's id, lowercase, one or more (`"light"`, `"limit set"`). Unique within the add-on. When commands share a start (`charge limit` and `charge limit level`), the **longest** one that fits the typed words runs. |
| `name` | required | text | The action's name. |
| `icon` | | text | An SF Symbol or an image file, as for the add-on. Default: the add-on's icon. |
| `options` | | list | See [Options](#options). |
| `input` | | object | See [Input](#input). |
| `run` | required | list, not empty | See [Steps](#steps). |
| `banner` | | object | See [Banners](#banners). Each action with a banner gets its own switch, on the add-on's page and in Settings > Banners. |

## Options

An option offers a fixed set of choices. When someone adds the action, the app shows its options,
each starting on **Keep Current**, which means no choice. Picking a choice adds its `word` to the
command.

```json
{ "id": "color", "title": "Color", "choices": [ { "word": "warm", "label": "Warm", "value": "Warm" } ],
  "skipWhen": { "other-option-id": "word" } }
```

| Key | | Meaning |
|---|---|---|
| `id` | required | Lowercase letters, digits and `_`, starting with a letter. It names the variable `{id}`. Unique within the action. It can't be `input`, `state`, `jbroot`, `exit` or `word1`, `word2` and so on. |
| `title` | | Shown for the option. Default: the id. |
| `choices` | required, not empty | Each is `{ "word", "label", "value" }`. `word` is one word of lowercase letters, digits, `-` and `.`, and it must be **unique across all of the action's options**, since it's what identifies the choice in a command. `label` is what's shown (default: the word), and `value` is what `{id}` becomes (default: the word). |
| `skipWhen` | | `{ "<other option id>": "<word>" }`. While that other option has that choice, this option is left out: hidden in the app, and ignored in a command typed by hand. The other option must exist. |

When the action runs, RemoteCompanion reads the words after the action's own, in order. Each word
that is a choice's word sets that option's variable, with at most one choice per option. The first
word that isn't a choice word, or a second word for an option that's already set, starts the
[input](#input). So does `--`, which is dropped. An option that was never chosen has **no value**,
and any step that uses it is skipped (see [Variables](#variables-and-templates)).

## Input

`"input": { "title": "Stop At (%)", "placeholder": "80", "number": true }`

An input adds a text field. Whatever the person types is added to the command after the option
words, and the steps get it as `{input}`. All three keys are optional. `number` only switches to a
number keyboard; it doesn't check what's typed. If the field is left empty, `{input}` has no value.

Typed text stays text even when it contains a choice's word, so `myapp say turn it on` gives
`{input}` = `turn it on`. When the text *starts* with a choice's word, the app and the Web UI put
`--` in front of it (`myapp say -- on my way`), and anyone typing the command by hand should do
the same.

## Steps

`run` is the list of steps, which run in order, one at a time. Each step is an object with exactly
**one kind** key, plus any modifiers that kind allows.

| Kind | Value | Does |
|---|---|---|
| `notify` | text | Posts a Darwin notification with that name. With `"state": <number>`, it sets the notification's state first (and keeps it registered so the state stays set). |
| `defaults` | object | Writes or reads a preference. See [below](#defaults). |
| `exec` | list of text | Runs a program **without a shell**. The first entry is its full path (or one starting `{jbroot}/`), and the rest are its arguments. See [below](#exec). |
| `url` | text | Opens a URL (`scheme://...`). |
| `command` | text | Runs a RemoteCompanion command. Add-on commands can run other add-on commands, up to 4 deep. |
| `delay` | number | Waits that many seconds, between 0 and 5. |

If the trigger run that the action belongs to is stopped, by Stop or by a new firing of a trigger
set to Restart, the action stops too: a `delay` ends at once and no further steps run.

### Modifiers

Any step can have these:

- `"if": { "var": "name", ... }` runs the step only when the variable passes every test you give.
  `"is": "value"` means it has that value, `"isNot": "value"` that it doesn't, and `"unset": true`
  that it has no value. `"above": 40` and `"below": 40` compare it as a number; the limit can be
  text with variables in it, so `"below": "{limit}"` works. A variable that isn't a number fails
  both `above` and `below`.
- `"ifOptions": true` runs the step only when at least one option was chosen.
- `"stopOnError": true` (for `exec` and `command` steps) stops the action at this step if it
  fails. An `exec` fails when the program exits with anything other than 0, can't start, or is
  stopped. A `command` fails when no command takes it, or its reply starts with `Error`; a command
  that replies with nothing hasn't failed. The action's reply gets an error line, and its banner
  shows the `failed` text (see [Banners](#banners)).

`state` only goes with `notify`, and `root` and `as` only go with `exec`.

### `exec`

The program runs as mobile; add `"root": true` to run it as root through RemoteCompanion's
`rc-root` helper. Its `PATH` includes the jailbreak's tool folders, and each argument is filled
from variables.

Normally the program's output (both standard output and standard error) is added to the action's
reply. With `"as": "name"`, its standard output goes into the variable `{name}` instead, for later
steps and the banner, with its non-empty lines joined by ` · `. Standard error is then left out of
the reply and only shows in `addons trace`. An `as` name is a letter or `_`, followed by letters,
digits, `_`, `-` and `.`.

The step ends when the program exits. If it starts a helper and leaves it running, the helper is
left alone. After 10 seconds the program, and everything it started, is stopped; for a root
program `rc-root` does the stopping, and the exit status is 137.

After every `exec` step, `{exit}` holds its exit status: `0` for success, or `-1` if it couldn't
start or was stopped. Later steps and the banner can use it, for example
`"if": { "var": "exit", "isNot": "0" }`.

### `defaults`

`{ "domain", "key", "value", "type", "toggle", "read", "as", "labels" }`

- By default it writes `value` to the preference, filled from variables. `type` can be `"string"`
  (the default), `"bool"` (from `1`, `true`, `yes` or `on`) or `"int"`. A number or boolean given
  as JSON is written as it is when there's no `type`.
- `"toggle": true` flips a boolean preference instead of writing a value. Add `as` to keep the new
  value in a variable.
- `"read": true` reads the preference into the variable named by `as`, which is required for a
  read. A boolean is read as its label: On or Off, or whatever `labels` says
  (`{ "true": "...", "false": "..." }`).
- The domain `com.apple.springboard` is SpringBoard's own preferences. Any other domain is written
  through the preferences system, as mobile, and synchronised.

## Variables and templates

Text in `notify`, `url`, `command`, `exec` and `defaults.value` steps, and in banner subtitles, can
include variables written as `{name}`. A condition's `exec` and the paths in `requires` can only
use `{jbroot}`.

| Variable | Set by |
|---|---|
| `{<option id>}` | An option's chosen choice: its `value`. |
| `{word1}`, `{word2}`... | The command's input words, in order. |
| `{input}` | The same words joined with spaces. |
| `{<as>}` | A `defaults` step with `as`, or an `exec` step with `as` (its output). |
| `{state}` | In an event or `await` banner: the text for the notification's state. |
| `{jbroot}` | Always: the jailbreak's root folder, `/var/jb` on rootless and empty on rootful. |
| `{exit}` | The exit status of the last `exec` step (`-1` when it couldn't start or was stopped). |

**A step that uses a variable with no value is skipped.** That's how Keep Current leaves a setting
alone. In an action banner's subtitle, a variable with no value falls back to the action's name;
in an event or `await` banner, it means no banner shows.

Only braces around a variable name count as a variable. A name is a letter or `_`, followed by
letters, digits, `_`, `-` and `.`. Braces around anything else are kept as they are, so `{}`, an
awk program (`{print $1}`) or JSON (`{"on": 1}`) can go into a step unchanged, and so can a `{`
that's never closed. Variables can't be nested.

## Banners

A banner is the short pop-up that shows after an action runs, or when an event arrives.

```json
"banner": true
"banner": { "title": "Charging", "subtitle": "{state}", "icon": "bolt.fill", "hold": 2 }
"banner": { "await": "com.example/state", "states": { "1": "Recording", "0": "Not Recording" }, "timeout": 8 }
```

| Key | Meaning |
|---|---|
| `title` | Default: the add-on's name. In an action's banner that doesn't `await`, it's filled from variables like the subtitle (a variable with no value falls back to the add-on's name). |
| `subtitle` | Filled from variables. Default: the action's name; for a state banner, the state's text. |
| `icon` | An SF Symbol. Default: the action's icon. |
| `hold` | Seconds shown. Default 2. |
| `await` | A notification name (filled from variables). The banner waits for that notification and shows the text for its **state**, or shows **nothing** if the `timeout` passes first. It starts listening before the steps run, so a quick reply isn't missed. |
| `states` | `{ "<state number>": "text" }`, for `await` and event banners. A state with no entry shows nothing. Without `states`, the number itself is shown. |
| `timeout` | Seconds to wait for `await`, 1 to 30. Default 8. |
| `failed` | Shown as the subtitle, with a warning icon, when a step with `stopOnError` fails. It's filled from variables, for example `"Couldn't connect ({exit})"`. Default: Failed. An `await` banner stops waiting when this happens. |

`"banner": true` gives a banner with every default: the add-on's name over the action's name,
with the action's icon. `"banner": false` is the same as leaving the banner out.

Whether an action's banner actually shows is up to the person using it: each one has a switch on
the add-on's page and in Settings > Banners, on by default. An event tied to an action with
`"action"` shares that action's switch.

## Conditions

Conditions let people check an add-on's state in an If, a Wait Until or a trigger's conditions.
They're listed as "Add-on: Name".

```json
{ "id": "temperature", "name": "Battery Temperature", "type": "number",
  "exec": ["{jbroot}/usr/bin/tool", "get", "temperature"], "root": false }
{ "id": "guard", "name": "Heat Guard", "type": "choice",
  "notifyState": "com.example/guard", "choices": { "0": "Normal", "1": "Hot" } }
```

| Key | | Meaning |
|---|---|---|
| `id`, `name` | required | The condition's id (unique in the add-on) and its name. |
| `icon` | | An SF Symbol or an image file, as for the add-on. Default: the add-on's icon. |
| `type` | required | `number` or `choice`. |
| `exec` | one of these | A program, as in a step. The value is its trimmed standard output; standard error is left out. A non-zero exit makes the value unknown, so the condition is false, and so does output that isn't a number for a `number` condition. `"root": true` runs it as root. |
| `notifyState` | | A notification name; the value is its current state number. |
| `choices` | required for `choice` | `{ "<raw value>": "label" }`. The raw value (from `exec` or `notifyState`) is turned into the label, and the label is what the condition is compared with. |
| `cache` | | How many seconds a value is reused, from 0 to 3600. Default 0, which reads it every time the condition is checked. While a Wait Until waits on a `notifyState` condition, each new notification clears its cached value. |

A `number` condition is compared with "above" and "below" a number, the way the built-in ones such
as battery level are. A `choice` condition is equal or not equal to one of its labels, ignoring
case. Each condition's key is `addon:<id>:<condition id>`.

**Mind the battery.** A condition is read every time it's checked, and a Wait Until checks twice a
second for as long as it waits. A `notifyState` condition costs next to nothing to read, and a Wait
Until on one is woken by the notification instead of checking (with a check every 30 seconds as
well, just in case). An `exec` condition starts its program on every check, so keep that program
quick and give the condition a `cache` when the value doesn't need to be up to the second
(`"cache": 5`).

## Events and triggers

An event watches for a Darwin notification that a tweak posts on its own. It can show a banner,
become a trigger, or both.

```json
{ "notify": "com.example/limit", "action": "light",
  "banner": { "subtitle": "Stopped: {state}", "states": { "1": "Maximum Length" } },
  "trigger": { "id": "limit", "name": "Limit", "icon": "exclamationmark.circle", "states": false } }
```

| Key | | Meaning |
|---|---|---|
| `notify` | required | The notification name. |
| `banner` | one of these | Shown when the notification arrives. See [Banners](#banners) (`await` doesn't apply here). |
| `trigger` | | Makes the event something people can add a trigger for. |
| `action` | | One of this add-on's action commands. The event's banner then shares that action's banner switch. |

A **trigger** is `{ "id", "name", "icon", "states" }`. Its `id` is lowercase letters, digits, `-`
and `.`, unique in the add-on, and its `icon` is a symbol or an image file (default: the add-on's
icon). When the notification arrives, RemoteCompanion runs the action lists of these triggers, if
the person has added them:

- the trigger itself, with the key `addon_<add-on id>_<trigger id>`, named "Add-on: Name";
- the trigger for the state that arrived, with the key
  `addon_<add-on id>_<trigger id>_<state number>`, named "Add-on: Name (state text)".

The state texts come from the trigger's `states` (`{ "1": "Started" }`), or failing that from the
banner's `states`. `"states": false` offers only the first kind. Both run on every arrival, and
triggers follow the usual rules, such as RemoteCompanion's master switch and excluded apps.

## Settings

Settings are controls on the add-on's page in the app (Settings > Integrations). Each one is tied
to a preference, so people can set the tweak up without leaving RemoteCompanion.

```json
"settings": [
  { "id": "enabled", "title": "Enabled", "type": "switch",
    "domain": "com.example.mytweak", "key": "enabled", "default": true,
    "notify": "com.example.mytweak/changed" },
  { "id": "limit", "title": "Charge Limit", "type": "number", "min": 50, "max": 100, "step": 5, "unit": "%",
    "domain": "com.example.mytweak", "key": "limit", "default": 80 },
  { "id": "mode", "title": "Mode", "type": "choice", "default": "auto",
    "choices": [ { "value": "auto", "label": "Automatic" }, { "value": "manual", "label": "Manual" } ],
    "domain": "com.example.mytweak", "key": "mode" }
]
```

| Key | | Meaning |
|---|---|---|
| `id` | required | Lowercase letters, digits and `_`, starting with a letter; unique in the add-on. |
| `title` | required | The row's name. |
| `type` | required | `switch` (a boolean), `choice` (one of `choices`), `number` (a stepper) or `text` (one line). |
| `domain`, `key` | required | The preference. `com.apple.springboard` is SpringBoard's own preferences; any other domain is written through the preferences system as mobile, the same way a `defaults` step writes it. |
| `default` | | What shows while the preference isn't set: `true` or `false`, a choice's `value`, a number or text. It isn't written until someone changes the setting. |
| `note` | | A line shown under the title. |
| `notify` | | Posted after every change, so the tweak knows to reread its settings. |
| `choices` | required for `choice` | `[ { "value", "label" } ]`. `value` (text or a number) is what's written, and `label` is what's shown. Values must be unique. |
| `min`, `max`, `step`, `unit` | | For `number`: the allowed range (a value outside it is refused), the stepper's step (default 1), and a unit shown after the value. Whole numbers are written as whole numbers. |

RemoteCompanion reads and writes these preferences itself, in SpringBoard. The add-on's tweak only
reads them, and listens for `notify` if it wants to know about changes. Settings are also available
as commands: `addons settings <id>` gives the current values as JSON, and
`addons set <id> <setting> <value>` changes one. A switch takes `on` or `off`, and a choice takes
its value or its label.

## Running an action

When an action runs, this is what happens, in order:

1. The command arrives as `<add-on id> <action words> [choice words] [input words]`.
2. Built-in commands are tried first. Then RemoteCompanion finds the add-on with that id, and its
   longest action command that matches. If no action matches, the reply is an error followed by
   the add-on's list of actions.
3. The choice words set their options' variables, and the input (from the first other word, or
   after `--`) becomes `{word1}`, `{word2}`... and `{input}`.
4. If the banner has `await`, it starts listening.
5. The steps run in order. A step is skipped if its `if` doesn't hold or it uses a variable with no
   value.
6. A banner without `await` shows. The reply is the output of the `exec` and `command` steps, or
   "Add-on: Action" if there wasn't any.

An action runs to the end even if one of its steps fails, unless that step has `stopOnError`. An
`exec` step whose program can't start adds an error line to the reply.

## Commands

These commands help you see and manage add-ons. You can run them with `rc-client "..."` on the
phone, or from anywhere RemoteCompanion takes commands.

- `addons` lists the loaded add-ons, the ones that are switched off, the ones not installed, and
  any problems.
- `addons reload` reads the folders again right away.
- `addons settings <id>` shows an add-on's setting values as JSON, and
  `addons set <id> <setting> <value>` changes one. See [Settings](#settings).
- `addons disable <id>` and `addons enable <id>` turn an add-on off and on again, just like its
  switch in the app. While it's off, it offers no actions, conditions or triggers, and its events
  stop.
- `addons validate <file>` checks one file and prints `OK` with any warnings, or the problem.
- `addons trace <add-on command>` runs the command for real and reports what happened: the
  variables it started with, each step as it was filled in, whether each step ran (with an
  `exec`'s exit status, time and output) or why it was skipped, and finally the banner and the
  reply. For example: `addons trace nightlight light on warm`.
- `addons parse <add-on command>` shows how a command is read, as JSON, without running it: its
  add-on, action, the choices it makes (option id: word) and its input. The app and the Web UI
  read commands with `rc_addon_commands.js` (installed next to `rc_webui.html`), which follows the
  same rules.
- `addons check addon:<id>:<condition> [expected]` shows a condition's value, and whether it
  matches `expected` (for `number`, something like `ABOVE 40`; for `choice`, a label).
- `GET /api/addons` (the Web UI's API) returns the loaded add-ons as JSON, along with the problems.
- `GET /api/addons/icon?id=<add-on id>[&file=<icon>]` returns the image an add-on's icon names
  (`file` picks one of its other icons). Only images the add-on itself lists are served.

Each time the add-ons change, RemoteCompanion also writes what loaded to
`/var/mobile/Documents/rc_addons.json` (with `api`, `addons`, `disabled`, `absent` and `problems`)
and posts `com.saihgupr.remotecompanion.addons-changed`. The app reads that file, so it offers
exactly the add-ons that passed these checks.

## Limits

| | |
|---|---|
| `exec` run time | 10 s, then stopped (a `root` program by `rc-root`, along with what it started). Output kept: 64 KB. |
| Condition `cache` | 0 to 3600 s. |
| `delay` | 5 s at most. |
| Command nesting | 4 deep. |
| `await` timeout | 1 to 30 s. |
| Choice words and commands | Lowercase letters, digits, `-` and `.`. |

## Validation

`addons validate <file>` applies all the rules on this page, and the same checks decide whether a
file loads. They cover the `api`, the `id`, names and the kind of every value, unique commands,
option ids and choice words, `skipWhen` targets, the shape of steps, banners, conditions, events,
triggers and settings, and the `action` an event names.

[`addon.schema.json`](addon.schema.json) describes the format for editors; point your editor's
JSON schema setting at it to get suggestions and error underlines as you type. A schema can't
check the cross-references between keys, but `addons validate` can.

**On the Mac**, [`tools/addon-lint.py`](tools/addon-lint.py) runs the same checks with the same
wording, so a file that passes there also loads on the phone. It only needs Python 3:

```sh
python3 tools/addon-lint.py layout/Library/RemoteCompanion/AddOns/mytweak.json
```

With `--strict`, warnings fail too (exit status 2), which is handy in a Makefile:

```make
before-package::
	python3 /path/to/addon-lint.py --strict layout/Library/RemoteCompanion/AddOns/*.json
```

## Versioning

`api` is a whole number. Within one version, changes only ever **add** things: new optional keys,
or new step kinds that older builds report as a problem only when a file uses them. Anything that
changes what an existing key means gets a new version. A file written for a version the app
doesn't know isn't loaded, and the reason says which version it needs.

## Security

An add-on is trusted the way an installed tweak is, because its file sits in a folder that only
root can write to. It can run programs as mobile, or as root with `"root": true`, post
notifications and write preferences. It has no shell, no code in SpringBoard and no network access
of its own. Anyone who can send RemoteCompanion commands (through the Web UI, MQTT or Home
Assistant) can run an add-on's actions, just as they can run any other command.
