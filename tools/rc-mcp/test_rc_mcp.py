#!/usr/bin/env python3
"""Offline checks for rc-mcp: starts the server, speaks MCP over its stdin, and checks the tools and
rc_help. No phone is contacted: no RC_PHONES is set, and nothing here asks for device state.

Run it with:  python3 test_rc_mcp.py
"""

import json
import os
import select
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.join(HERE, "rc_mcp.py")
TIMEOUT = 20

NEW_TOOLS = ["rc_help", "rc_state", "rc_trigger", "rc_config", "rc_sequence", "rc_deeplink"]


class Server:
    """The server as a subprocess, one JSON message per line"""

    def __init__(self):
        env = dict(os.environ)
        for name in ("RC_PHONES", "RC_SSH_KEY", "RC_SSH_USER", "RC_SSH_PORT"):
            env.pop(name, None)
        self.proc = subprocess.Popen([sys.executable, SERVER], stdin=subprocess.PIPE,
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                     bufsize=0, env=env)
        self.next_id = 0

    def send(self, method, params=None):
        self.next_id += 1
        message = {"jsonrpc": "2.0", "id": self.next_id, "method": method}
        if params is not None:
            message["params"] = params
        self.proc.stdin.write((json.dumps(message) + "\n").encode("utf-8"))
        self.proc.stdin.flush()
        return self.read()

    def read(self):
        ready, _, _ = select.select([self.proc.stdout], [], [], TIMEOUT)
        if not ready:
            raise AssertionError("the server didn't answer within %d s" % TIMEOUT)
        line = self.proc.stdout.readline()
        if not line:
            raise AssertionError("the server closed its output: %s" % self.proc.stderr.read().decode("utf-8", "replace"))
        return json.loads(line.decode("utf-8"))

    def tool(self, name, arguments=None):
        reply = self.send("tools/call", {"name": name, "arguments": arguments or {}})
        result = reply.get("result") or {}
        text = "\n".join(part.get("text", "") for part in result.get("content") or [] if part.get("type") == "text")
        return text, bool(result.get("isError"))

    def close(self):
        try:
            self.proc.stdin.close()
        except OSError:
            pass
        try:
            self.proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.proc.kill()
            self.proc.wait()


def main():
    server = Server()
    checks = 0
    try:
        # 1. It speaks MCP, and its instructions say commands first
        info = (server.send("initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                                           "clientInfo": {"name": "test_rc_mcp", "version": "1"}})
                .get("result") or {})
        assert info.get("serverInfo", {}).get("name") == "rc-mcp", "initialize didn't name the server"
        instructions = info.get("instructions") or ""
        assert "rc_command" in instructions, "the instructions should say to use rc_command"
        assert "rc_help" in instructions, "the instructions should say to call rc_help when unsure"
        checks += 1

        # 2. tools/list has the new tools, with the schemas they need
        tools = (server.send("tools/list", {}).get("result") or {}).get("tools") or []
        by_name = {tool["name"]: tool for tool in tools}
        missing = [name for name in NEW_TOOLS if name not in by_name]
        assert not missing, "tools/list is missing %s" % ", ".join(missing)
        for name in NEW_TOOLS:
            assert by_name[name].get("description"), "%s has no description" % name
        assert "phone" not in by_name["rc_help"]["inputSchema"]["properties"], "rc_help shouldn't take a phone"
        assert "phone" not in by_name["rc_sequence"]["inputSchema"]["properties"], "rc_sequence shouldn't take a phone"
        assert by_name["rc_command"]["inputSchema"]["required"] == ["command"], "rc_command should require command"
        assert "enum" in by_name["rc_trigger"]["inputSchema"]["properties"]["action"], "rc_trigger action needs an enum"
        checks += 1

        # 3. rc_help with no query: categories and the useful explicit setters, offline
        text, failed = server.tool("rc_help")
        assert not failed, "rc_help failed: %s" % text
        for expected in ("by category", "Most useful", "wifi on", "wifi off", "airplane on",
                         "low power on", "dnd on", "focus on <name>", "appearance dark"):
            assert expected in text, "rc_help should mention %r:\n%s" % (expected, text)
        checks += 1

        # 4. rc_help with words finds the command and its example
        text, failed = server.tool("rc_help", {"query": "wifi"})
        assert not failed, "rc_help wifi failed: %s" % text
        assert "wifi on" in text, "rc_help wifi should show wifi on:\n%s" % text
        assert "e.g." in text, "rc_help should show examples:\n%s" % text
        checks += 1

        # 5. An unknown word gets the closest commands instead of silence
        text, failed = server.tool("rc_help", {"query": "wiffi"})
        assert not failed, "rc_help wiffi failed: %s" % text
        assert "Closest" in text, "rc_help should suggest the closest commands:\n%s" % text
        checks += 1

        # 6. rc_sequence checks a sequence offline: good is OK, a typo names the closest command
        text, failed = server.tool("rc_sequence", {"action": "validate",
                                                   "sequence": ["play", "delay 2", "volume 30"]})
        assert not failed, "a good sequence failed: %s" % text
        assert text.startswith("OK: 3 actions"), "good sequence should be OK:\n%s" % text
        text, failed = server.tool("rc_sequence", {"action": "validate",
                                                   "sequence": ["wifi onn", {"type": "if"}]})
        assert failed, "a bad sequence should be an error:\n%s" % text
        assert "conditionKey" in text, "a bare if should need conditionKey:\n%s" % text
        assert "wifi on" in text, "a typo should suggest the closest command:\n%s" % text
        checks += 1

        # 7. The server doesn't need a phone for help, and it stops cleanly
        text, failed = server.tool("rc_help", {"query": "trigger"})
        assert not failed and "trigger:" in text, "rc_help trigger should show trigger:<id>:\n%s" % text
        checks += 1

        # 8. The command index is clean: one row per command, and every row filled in
        with open(os.path.join(HERE, "rc_commands.json"), "r", encoding="utf-8") as f:
            rows = json.load(f)
        names = [row.get("command") for row in rows]
        assert all(names), "every row in rc_commands.json needs a command"
        duplicates = sorted({name for name in names if names.count(name) > 1})
        assert not duplicates, "duplicate command keys in rc_commands.json: %s" % ", ".join(duplicates)
        for row in rows:
            for field in ("description", "category", "example"):
                assert row.get(field), "%s has no %s" % (row.get("command"), field)
        checks += 1
    finally:
        server.close()
    print("ok: %d checks passed" % checks)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except AssertionError as e:
        print("FAIL: %s" % e)
        sys.exit(1)
