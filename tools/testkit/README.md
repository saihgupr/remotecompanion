# Test kit tools

Two small scripts for driving the on-device test kit from a computer on the same network.
The test kit itself is in the app (Settings > Diagnostics > Test Kit) and the tweak
(`Tweak/RCTestKit.x`, which documents the whole API). These scripts use its JSON API under
`/api/testkit/`, so the **Web UI** setting must be on.

Set `TK_HOST` to the phone's IP address (and `TK_PORT` if it isn't 8080).

## tk

Sends one request and prints the JSON reply.

```sh
export TK_HOST=192.168.1.20
tk info                                    # what this build supports
tk probe                                   # the phone's state, as the tests read it
tk suites                                  # the test suites
tk "suite/run?name=conditions&wait=1"      # run one and wait for the report
tk "suite/run?name=replay&repeat=3"        # start one; follow it with tk report
tk report                                  # the run in progress, or the last one
tk suite/stop                              # stop it
tk replay "vU@0 vD@7 ^D@125 ^U@147"        # press buttons at exact times (v down, ^ up)
tk run "wifi status"                       # any RemoteCompanion command
```

A second argument is sent as a POST body. With `TK_LOG` set to a file, every request and
reply is appended to it as well.

## follow

Streams the test kit's event journal live: button presses as the hardware reports them,
triggers, actions, condition results and test steps, with the time between them.

```sh
follow             # everything
follow trigger     # only events whose type starts with "trigger"
```

The journal records only while the test kit is in use (a run, or a request in the last
10 minutes); following it keeps it on.
