#!/usr/bin/env python3
"""Tests for dev_editor_presets.json, RCDevEditorPresetsData.h, and tools/rc-dev-deliver.py."""
import base64
import http.server
import importlib.util
import json
import os
import re
import subprocess
import sys
import tempfile
import threading
import unittest
import urllib.parse

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
DELIVER_PATH = os.path.join(ROOT, "tools", "rc-dev-deliver.py")
PRESETS_PATH = os.path.join(ROOT, "dev_editor_presets.json")
HEADER_PATH = os.path.join(ROOT, "RemoteCompanion", "RCDevEditorPresetsData.h")
WEBUI_PATH = os.path.join(ROOT, "rc_webui.html")

spec = importlib.util.spec_from_file_location("rc_dev_deliver", DELIVER_PATH)
rc_dev_deliver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rc_dev_deliver)

TINY_PNG_B64 = base64.b64encode(
    b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01"
    b"\x08\x06\x00\x00\x00\x1f\x15c4\x00\x00\x00\nIDATx\x9cc\x00\x01\x00"
    b"\x00\x05\x00\x01\r\n-\xb4\x00\x00\x00\x00IEND\xaeB`\x82"
).decode("ascii")


class MockOpenCodeState:
    def __init__(self, pid, password):
        self.pid = pid
        self.password = password
        self.sessions = []
        self.ignore_directory_query = False
        self.requests = []
        self.posted_prompts = []


def start_mock_opencode(state):
    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, format, *args):
            pass

        def _check_auth(self):
            if not state.password:
                return True
            expected = "Basic " + base64.b64encode(("opencode:" + state.password).encode("utf-8")).decode("ascii")
            return self.headers.get("Authorization") == expected

        def _send_json(self, code, payload):
            raw = json.dumps(payload).encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)

        def do_GET(self):
            state.requests.append(("GET", self.path, self.headers.get("Authorization")))
            if not self._check_auth():
                self._send_json(401, {"error": {"message": "Unauthorized"}})
                return
            parsed = urllib.parse.urlsplit(self.path)
            if parsed.path == "/api/info":
                self._send_json(200, {"pid": state.pid, "version": "2.0.0"})
                return
            if parsed.path == "/api/session":
                params = urllib.parse.parse_qs(parsed.query)
                directory = (params.get("directory") or [None])[0]
                if directory and not state.ignore_directory_query:
                    matched = [
                        s for s in state.sessions
                        if ((s.get("location") or {}).get("directory") or s.get("directory")) == directory
                    ]
                else:
                    matched = list(state.sessions)
                self._send_json(200, {"data": matched})
                return
            self._send_json(404, {"error": {"message": "Not Found"}})

        def do_POST(self):
            length = int(self.headers.get("Content-Length") or 0)
            body = json.loads(self.rfile.read(length).decode("utf-8")) if length else {}
            state.requests.append(("POST", self.path, self.headers.get("Authorization")))
            if not self._check_auth():
                self._send_json(401, {"error": {"message": "Unauthorized"}})
                return
            m = re.match(r"^/api/session/([^/]+)/prompt$", self.path)
            if m:
                session_id = urllib.parse.unquote(m.group(1))
                state.posted_prompts.append((session_id, body))
                self._send_json(200, {"data": {"id": "msg_12345"}})
                return
            self._send_json(404, {"error": {"message": "Not Found"}})

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server


class MockAntigravityBridgeState:
    def __init__(self, pid, workspace_name, workspace_folders, focused=True, last_focused_at=1000):
        self.pid = pid
        self.workspace_name = workspace_name
        self.workspace_folders = list(workspace_folders)
        self.window_focused = focused
        self.last_focused_at = last_focused_at
        self.prepare_ok = True
        self.prepare_is_focused = True
        self.prepare_is_visible = True
        self.populate_is_focused = True
        self.populate_sent = False
        self.requests = []
        self.populated_texts = []


def start_mock_antigravity_bridge(state):
    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, format, *args):
            pass

        def _send_json(self, code, payload):
            raw = json.dumps(payload).encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)

        def do_GET(self):
            state.requests.append(("GET", self.path))
            if self.path == "/info":
                self._send_json(
                    200,
                    {
                        "ok": True,
                        "pid": state.pid,
                        "workspaceName": state.workspace_name,
                        "workspaceFolders": state.workspace_folders,
                        "windowFocused": state.window_focused,
                        "lastFocusedAt": state.last_focused_at,
                    },
                )
                return
            self._send_json(404, {"ok": False, "error": "Not found"})

        def do_POST(self):
            length = int(self.headers.get("Content-Length") or 0)
            body = json.loads(self.rfile.read(length).decode("utf-8")) if length else {}
            state.requests.append(("POST", self.path, body))
            if self.path == "/prepare":
                if not state.prepare_ok or not state.prepare_is_focused:
                    self._send_json(
                        200,
                        {
                            "ok": False,
                            "error": "Antigravity Agent chat input did not gain focus",
                            "isVisible": state.prepare_is_visible,
                            "isFocused": state.prepare_is_focused,
                        },
                    )
                    return
                self._send_json(
                    200,
                    {
                        "ok": True,
                        "isVisible": state.prepare_is_visible,
                        "isFocused": state.prepare_is_focused,
                        "workspaceName": state.workspace_name,
                        "workspaceFolders": state.workspace_folders,
                    },
                )
                return
            if self.path == "/populate":
                state.populated_texts.append(body.get("text", ""))
                self._send_json(
                    200,
                    {
                        "ok": True,
                        "isVisible": True,
                        "isFocused": state.populate_is_focused,
                        "sent": bool(state.populate_sent and body.get("autoSend")),
                        "workspaceName": state.workspace_name,
                    },
                )
                return
            self._send_json(404, {"ok": False, "error": "Not found"})

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server


class DevAnnotateTests(unittest.TestCase):
    def test_presets_integrity_and_webui_parity(self):
        with open(PRESETS_PATH, "r", encoding="utf-8") as f:
            presets = json.load(f)
        ids = [p["id"] for p in presets]
        self.assertEqual(ids, ["opencode", "antigravity"])
        for p in presets:
            self.assertIn(p["strategy"], ("opencode_api", "antigravity_ext", "clipboard_paste"))
            self.assertTrue(p["name"].strip())

        with open(WEBUI_PATH, "r", encoding="utf-8") as f:
            webui = f.read()
        for p in presets:
            self.assertIn(f"id:'{p['id']}'", webui)
            self.assertIn(f"name:'{p['name']}'", webui)

    def test_opencode_discovery_stale_pid_and_last_viewed_selection(self):
        state = MockOpenCodeState(pid=4242, password="secret-token")
        state.sessions = [
            {
                "id": "ses_newer_updated",
                "title": "Newer Updated",
                "parentID": None,
                "time": {"updated": 9000, "viewed": 1000},
                "location": {"directory": "/tmp/proj-a"},
            },
            {
                "id": "ses_last_viewed",
                "title": "Last Viewed",
                "parentID": None,
                "time": {"updated": 5000, "viewed": 8000},
                "location": {"directory": "/tmp/proj-b"},
            },
            {
                "id": "ses_archived",
                "title": "Archived",
                "parentID": None,
                "time": {"updated": 9999, "viewed": 9999, "archived": 1234},
                "location": {"directory": "/tmp/proj-c"},
            },
            {
                "id": "ses_child",
                "title": "Child",
                "parentID": "ses_last_viewed",
                "time": {"updated": 9999, "viewed": 9999},
                "location": {"directory": "/tmp/proj-b"},
            },
        ]
        server = start_mock_opencode(state)
        try:
            port = server.server_address[1]
            calls = []

            def fake_run_cmd(args, input_bytes=None, env=None):
                calls.append((args, input_bytes, env))
                return 0, "", ""

            with tempfile.TemporaryDirectory() as tmp:
                stale_reg = os.path.join(tmp, "service.json")
                live_reg = os.path.join(tmp, "service-beta.json")
                with open(stale_reg, "w") as f:
                    json.dump({"url": f"http://127.0.0.1:{port}", "pid": 99999, "password": "secret-token"}, f)
                with open(live_reg, "w") as f:
                    json.dump({"url": f"http://localhost:{port}", "pid": 4242, "password": "secret-token"}, f)

                res = rc_dev_deliver.deliver(
                    {
                        "image_b64": TINY_PNG_B64,
                        "text": "Fix the spacing here",
                        "strategy": "opencode_api",
                        "auto_send": True,
                        "delivery": "queue",
                    },
                    reg_paths=[stale_reg, live_reg],
                    tmp_dir=os.path.join(tmp, "shots"),
                    run_cmd=fake_run_cmd,
                )
                self.assertTrue(res["ok"], res)
                self.assertEqual(res["detail"], "Last Viewed")
                self.assertEqual(
                    calls,
                    [(["/usr/bin/open", "-g", "opencode://session/ses_last_viewed?background=1"], None, None)],
                )
                self.assertEqual(len(state.posted_prompts), 1)
                sid, body = state.posted_prompts[0]
                self.assertEqual(sid, "ses_last_viewed")
                self.assertEqual(body["text"], "Fix the spacing here")
                self.assertEqual(body["delivery"], "queue")
                self.assertTrue(body["files"][0]["uri"].startswith("data:image/png;base64,"))
                self.assertIn(TINY_PNG_B64, body["files"][0]["uri"])
        finally:
            server.shutdown()
            server.server_close()

    def test_opencode_fallback_to_updated_and_project_dir_realpath_fallback(self):
        state = MockOpenCodeState(pid=777, password="pw")
        with tempfile.TemporaryDirectory() as tmp:
            real_proj = os.path.realpath(os.path.join(tmp, "real_project"))
            other_proj = os.path.realpath(os.path.join(tmp, "other_project"))
            os.makedirs(real_proj)
            os.makedirs(other_proj)
            symlink_proj = os.path.join(tmp, "link_project")
            os.symlink(real_proj, symlink_proj)

            state.sessions = [
                {
                    "id": "ses_other",
                    "title": "Other Project",
                    "parentID": None,
                    "time": {"updated": 9500},
                    "location": {"directory": other_proj},
                },
                {
                    "id": "ses_proj_old",
                    "title": "Project Older",
                    "parentID": None,
                    "time": {"updated": 4000},
                    "location": {"directory": real_proj},
                },
                {
                    "id": "ses_proj_new",
                    "title": "Project Newer",
                    "parentID": None,
                    "time": {"updated": 8000},
                    "location": {"directory": real_proj},
                },
            ]
            # Simulate server directory query returning empty so client realpath fallback exercises.
            state.ignore_directory_query = False
            server = start_mock_opencode(state)
            calls = []

            def fake_run_cmd(args, input_bytes=None, env=None):
                calls.append((args, input_bytes, env))
                return 0, "", ""

            try:
                port = server.server_address[1]
                reg = os.path.join(tmp, "service.json")
                with open(reg, "w") as f:
                    json.dump({"url": f"http://127.0.0.1:{port}", "pid": 777, "password": "pw"}, f)

                res = rc_dev_deliver.deliver(
                    {
                        "image_b64": TINY_PNG_B64,
                        "text": "",
                        "strategy": "opencode_api",
                        "auto_send": True,
                        "project_dir": symlink_proj,
                    },
                    reg_paths=[reg],
                    tmp_dir=os.path.join(tmp, "shots"),
                    run_cmd=fake_run_cmd,
                )
                self.assertTrue(res["ok"], res)
                self.assertEqual(res["detail"], "Project Newer")
                self.assertEqual(
                    calls,
                    [(["/usr/bin/open", "-g", "opencode://session/ses_proj_new?background=1"], None, None)],
                )
                sid, body = state.posted_prompts[0]
                self.assertEqual(sid, "ses_proj_new")
                self.assertEqual(body["text"], "See attached annotated screenshot.")
                self.assertEqual(body["delivery"], "queue")
            finally:
                server.shutdown()
                server.server_close()

    def test_opencode_background_tab_failure_does_not_fail_send(self):
        state = MockOpenCodeState(pid=888, password="pw")
        state.sessions = [
            {
                "id": "ses_tab",
                "title": "Tab Target",
                "parentID": None,
                "time": {"updated": 1000},
                "location": {"directory": "/tmp/proj-tab"},
            },
        ]
        server = start_mock_opencode(state)

        def fake_run_cmd(args, input_bytes=None, env=None):
            if args and args[0] == "/usr/bin/open":
                raise RuntimeError("LaunchServices unavailable")
            return 0, "", ""

        try:
            port = server.server_address[1]
            with tempfile.TemporaryDirectory() as tmp:
                reg = os.path.join(tmp, "service.json")
                with open(reg, "w") as f:
                    json.dump({"url": f"http://127.0.0.1:{port}", "pid": 888, "password": "pw"}, f)

                res = rc_dev_deliver.deliver(
                    {"image_b64": TINY_PNG_B64, "text": "note", "strategy": "opencode_api", "auto_send": True},
                    reg_paths=[reg],
                    tmp_dir=os.path.join(tmp, "shots"),
                    run_cmd=fake_run_cmd,
                )
                self.assertTrue(res["ok"], res)
                self.assertEqual(res["detail"], "Tab Target")
                self.assertEqual(len(state.posted_prompts), 1)
        finally:
            server.shutdown()
            server.server_close()

    def test_opencode_not_running_when_pid_mismatch_only(self):
        state = MockOpenCodeState(pid=111, password="pw")
        server = start_mock_opencode(state)
        try:
            port = server.server_address[1]
            with tempfile.TemporaryDirectory() as tmp:
                reg = os.path.join(tmp, "service.json")
                with open(reg, "w") as f:
                    json.dump({"url": f"http://127.0.0.1:{port}", "pid": 222, "password": "pw"}, f)

                res = rc_dev_deliver.deliver(
                    {"image_b64": TINY_PNG_B64, "text": "hi", "strategy": "opencode_api", "auto_send": True},
                    reg_paths=[reg],
                    tmp_dir=os.path.join(tmp, "shots"),
                )
                self.assertFalse(res["ok"])
                self.assertEqual(res["error"], "OpenCode isn't running")
        finally:
            server.shutdown()
            server.server_close()

    def test_opencode_auto_send_false_uses_clipboard_paste(self):
        state = MockOpenCodeState(pid=333, password="pw")
        server = start_mock_opencode(state)
        calls = []

        def fake_run_cmd(args, input_bytes=None, env=None):
            calls.append((args, input_bytes, env))
            return 0, "", ""

        try:
            port = server.server_address[1]
            with tempfile.TemporaryDirectory() as tmp:
                reg = os.path.join(tmp, "service.json")
                with open(reg, "w") as f:
                    json.dump({"url": f"http://127.0.0.1:{port}", "pid": 333, "password": "pw"}, f)

                res = rc_dev_deliver.deliver(
                    {
                        "image_b64": TINY_PNG_B64,
                        "text": "Draft note",
                        "strategy": "opencode_api",
                        "bundle_id": "ai.opencode.desktop",
                        "app_name": "OpenCode",
                        "auto_send": False,
                    },
                    reg_paths=[reg],
                    tmp_dir=os.path.join(tmp, "shots"),
                    run_cmd=fake_run_cmd,
                    sleep_fn=lambda _: None,
                )
                self.assertTrue(res["ok"], res)
                self.assertEqual(res["detail"], "OpenCode")
                self.assertEqual(len(state.posted_prompts), 0)
                # activate, copy png, paste png, pbcopy text, paste text (no return keystroke!)
                self.assertEqual(len(calls), 5)
                self.assertEqual(calls[3][0], ["/usr/bin/pbcopy"])
                self.assertEqual(calls[3][1], b"Draft note")
        finally:
            server.shutdown()
            server.server_close()

    def test_antigravity_ext_prepares_pastes_png_populates_text_via_ipc_and_autosends(self):
        state = MockAntigravityBridgeState(
            pid=5151,
            workspace_name="RemoteCompanion",
            workspace_folders=["/tmp/RemoteCompanion"],
            focused=True,
            last_focused_at=5000,
        )
        server = start_mock_antigravity_bridge(state)
        calls = []

        def fake_run_cmd(args, input_bytes=None, env=None):
            calls.append((args, input_bytes, env))
            return 0, "", ""

        try:
            port = server.server_address[1]
            with tempfile.TemporaryDirectory() as tmp:
                reg = os.path.join(tmp, "window-5151.json")
                with open(reg, "w") as f:
                    json.dump({"url": f"http://127.0.0.1:{port}", "pid": 5151}, f)

                res = rc_dev_deliver.deliver(
                    {
                        "image_b64": TINY_PNG_B64,
                        "text": "Align button padding",
                        "strategy": "antigravity_ext",
                        "bundle_id": "com.google.antigravity-ide",
                        "app_name": "Antigravity IDE",
                        "auto_send": True,
                    },
                    antigravity_reg_paths=[reg],
                    tmp_dir=os.path.join(tmp, "shots"),
                    run_cmd=fake_run_cmd,
                    sleep_fn=lambda _: None,
                )
                self.assertTrue(res["ok"], res)
                self.assertEqual(res["detail"], "RemoteCompanion")
                self.assertEqual(state.populated_texts, ["Align button padding"])
                self.assertEqual([r[0:2] for r in state.requests], [
                    ("GET", "/info"),
                    ("POST", "/prepare"),
                    ("POST", "/populate"),
                ])
                self.assertEqual(state.requests[2][2], {"text": "Align button padding", "autoSend": True})
                # open -b folder, activate, set clipboard png, Cmd+V, Return fallback (never pbcopy!)
                self.assertEqual(len(calls), 5)
                self.assertEqual(calls[0][0], ["/usr/bin/open", "-b", "com.google.antigravity-ide", "/tmp/RemoteCompanion"])
                self.assertIn('tell application id "com.google.antigravity-ide" to activate', calls[1][0][2])
                self.assertIn("«class PNGf»", calls[2][0][2])
                self.assertIn('keystroke "v" using command down', calls[3][0][2])
                self.assertIn("key code 36", calls[4][0][2])
                self.assertFalse(any(c[0][0] == "/usr/bin/pbcopy" for c in calls))
        finally:
            server.shutdown()
            server.server_close()

    def test_antigravity_ext_skips_return_keystroke_when_populate_sent_true(self):
        state = MockAntigravityBridgeState(
            pid=5152,
            workspace_name="RemoteCompanion",
            workspace_folders=["/tmp/RemoteCompanion"],
            focused=True,
            last_focused_at=5000,
        )
        state.populate_sent = True
        server = start_mock_antigravity_bridge(state)
        calls = []

        def fake_run_cmd(args, input_bytes=None, env=None):
            calls.append((args, input_bytes, env))
            return 0, "", ""

        try:
            port = server.server_address[1]
            with tempfile.TemporaryDirectory() as tmp:
                reg = os.path.join(tmp, "window-5152.json")
                with open(reg, "w") as f:
                    json.dump({"url": f"http://127.0.0.1:{port}", "pid": 5152}, f)

                res = rc_dev_deliver.deliver(
                    {
                        "image_b64": TINY_PNG_B64,
                        "text": "Send via triggerSend RPC",
                        "strategy": "antigravity_ext",
                        "bundle_id": "com.google.antigravity-ide",
                        "app_name": "Antigravity IDE",
                        "auto_send": True,
                    },
                    antigravity_reg_paths=[reg],
                    tmp_dir=os.path.join(tmp, "shots"),
                    run_cmd=fake_run_cmd,
                    sleep_fn=lambda _: None,
                )
                self.assertTrue(res["ok"], res)
                self.assertEqual(res["detail"], "RemoteCompanion")
                self.assertEqual(state.populated_texts, ["Send via triggerSend RPC"])
                self.assertEqual(state.requests[2][2], {"text": "Send via triggerSend RPC", "autoSend": True})
                # open -b folder, activate, set clipboard png, Cmd+V (no Return keystroke needed)
                self.assertEqual(len(calls), 4)
                self.assertFalse(any(
                    c[0][0] == "/usr/bin/osascript" and "key code 36" in c[0][2]
                    for c in calls
                ))
        finally:
            server.shutdown()
            server.server_close()

    def test_antigravity_ext_project_dir_filtering_and_open_when_not_running(self):
        with tempfile.TemporaryDirectory() as tmp:
            other_proj = os.path.realpath(os.path.join(tmp, "OtherProject"))
            target_proj = os.path.realpath(os.path.join(tmp, "TargetProject"))
            os.makedirs(other_proj)
            os.makedirs(target_proj)

            other_state = MockAntigravityBridgeState(
                pid=6001,
                workspace_name="OtherProject",
                workspace_folders=[other_proj],
                focused=True,
                last_focused_at=9999,
            )
            target_state = MockAntigravityBridgeState(
                pid=6002,
                workspace_name="TargetProject",
                workspace_folders=[target_proj],
                focused=False,
                last_focused_at=5000,
            )
            other_srv = start_mock_antigravity_bridge(other_state)
            target_srv = start_mock_antigravity_bridge(target_state)
            calls = []
            reg_other = os.path.join(tmp, "window-6001.json")
            reg_target = os.path.join(tmp, "window-6002.json")

            def fake_run_cmd(args, input_bytes=None, env=None):
                calls.append((args, input_bytes, env))
                if args == ["/usr/bin/open", "-b", "com.google.antigravity-ide", target_proj]:
                    with open(reg_target, "w") as f:
                        json.dump({"url": f"http://127.0.0.1:{target_srv.server_address[1]}", "pid": 6002}, f)
                return 0, "", ""

            try:
                with open(reg_other, "w") as f:
                    json.dump({"url": f"http://127.0.0.1:{other_srv.server_address[1]}", "pid": 6001}, f)

                res = rc_dev_deliver.deliver(
                    {
                        "image_b64": TINY_PNG_B64,
                        "text": "Check this panel",
                        "strategy": "antigravity_ext",
                        "bundle_id": "com.google.antigravity-ide",
                        "app_name": "Antigravity IDE",
                        "project_dir": target_proj,
                        "auto_send": False,
                    },
                    antigravity_reg_paths=[reg_other, reg_target],
                    tmp_dir=os.path.join(tmp, "shots"),
                    run_cmd=fake_run_cmd,
                    sleep_fn=lambda _: None,
                )
                self.assertTrue(res["ok"], res)
                self.assertEqual(res["detail"], "TargetProject")
                self.assertEqual(other_state.populated_texts, [])
                self.assertEqual(target_state.populated_texts, ["Check this panel"])
                self.assertIn(
                    ["/usr/bin/open", "-b", "com.google.antigravity-ide", target_proj],
                    [c[0] for c in calls],
                )
                # auto_send is False so no Return keystroke
                self.assertFalse(any(c[0][0] == "/usr/bin/osascript" and "key code 36" in c[0][2] for c in calls))
            finally:
                other_srv.shutdown()
                other_srv.server_close()
                target_srv.shutdown()
                target_srv.server_close()

    def test_antigravity_ext_aborts_paste_when_chat_not_focused(self):
        state = MockAntigravityBridgeState(
            pid=7001,
            workspace_name="RemoteCompanion",
            workspace_folders=["/tmp/RemoteCompanion"],
        )
        state.prepare_is_focused = False
        server = start_mock_antigravity_bridge(state)
        calls = []

        def fake_run_cmd(args, input_bytes=None, env=None):
            calls.append((args, input_bytes, env))
            return 0, "", ""

        try:
            port = server.server_address[1]
            with tempfile.TemporaryDirectory() as tmp:
                reg = os.path.join(tmp, "window-7001.json")
                with open(reg, "w") as f:
                    json.dump({"url": f"http://127.0.0.1:{port}", "pid": 7001}, f)

                res = rc_dev_deliver.deliver(
                    {
                        "image_b64": TINY_PNG_B64,
                        "text": "Should not paste into file",
                        "strategy": "antigravity_ext",
                        "bundle_id": "com.google.antigravity-ide",
                        "app_name": "Antigravity IDE",
                        "auto_send": True,
                    },
                    antigravity_reg_paths=[reg],
                    tmp_dir=os.path.join(tmp, "shots"),
                    run_cmd=fake_run_cmd,
                    sleep_fn=lambda _: None,
                )
                self.assertFalse(res["ok"])
                self.assertIn("did not gain focus", res["error"])
                self.assertEqual(state.populated_texts, [])
                # Zero Cmd+V or Return keystrokes
                self.assertFalse(any(
                    c[0][0] == "/usr/bin/osascript" and ('keystroke "v"' in c[0][2] or "key code 36" in c[0][2])
                    for c in calls
                ))
        finally:
            server.shutdown()
            server.server_close()

    def test_antigravity_missing_project_dir_returns_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            missing = os.path.join(tmp, "does-not-exist")
            res = rc_dev_deliver.deliver(
                {
                    "image_b64": TINY_PNG_B64,
                    "text": "Test",
                    "strategy": "antigravity_ext",
                    "bundle_id": "com.google.antigravity-ide",
                    "app_name": "Antigravity IDE",
                    "project_dir": missing,
                    "auto_send": False,
                },
                tmp_dir=os.path.join(tmp, "shots"),
                run_cmd=lambda *a, **kw: (0, "", ""),
                sleep_fn=lambda _: None,
            )
            self.assertFalse(res["ok"])
            self.assertEqual(res["error"], f"Project folder not found: {missing}")

    def test_clipboard_accessibility_1002_error_mapping(self):
        def fake_run_cmd(args, input_bytes=None, env=None):
            if args[0] == "/usr/bin/osascript" and "System Events" in args[2]:
                return 1, "", "execution error: System Events got an error: osascript is not allowed to send keystrokes. (1002)"
            return 0, "", ""

        with tempfile.TemporaryDirectory() as tmp:
            res = rc_dev_deliver.deliver(
                {
                    "image_b64": TINY_PNG_B64,
                    "text": "Test",
                    "strategy": "clipboard_paste",
                    "bundle_id": "ai.opencode.desktop",
                    "app_name": "OpenCode",
                    "auto_send": True,
                },
                tmp_dir=os.path.join(tmp, "shots"),
                run_cmd=fake_run_cmd,
                sleep_fn=lambda _: None,
            )
            self.assertFalse(res["ok"])
            self.assertEqual(res["error"], "Enable Accessibility for sshd-keygen-wrapper on Mac")

    def test_clipboard_missing_target_app_returns_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            res = rc_dev_deliver.deliver(
                {
                    "image_b64": TINY_PNG_B64,
                    "text": "Test",
                    "strategy": "clipboard_paste",
                    "bundle_id": "",
                    "app_name": "",
                    "auto_send": False,
                },
                tmp_dir=os.path.join(tmp, "shots"),
                run_cmd=lambda *a, **kw: (0, "", ""),
                sleep_fn=lambda _: None,
            )
            self.assertFalse(res["ok"])
            self.assertEqual(res["error"], "Missing target application")

    def test_inline_b64_from_generated_header_runs(self):
        with open(HEADER_PATH, "r", encoding="utf-8") as f:
            header = f.read()
        m = re.search(r'kRCDevDeliverPythonScriptB64\s*=\s*@"([^"]+)"', header)
        self.assertIsNotNone(m)
        b64 = m.group(1)
        cmd = f'import base64; exec(base64.b64decode("{b64}"))'
        proc = subprocess.run(
            [sys.executable, "-c", cmd],
            input=b"{}",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        self.assertEqual(proc.returncode, 1)
        out = json.loads(proc.stdout.decode("utf-8").strip())
        self.assertFalse(out["ok"])
        self.assertIn("Missing screenshot", out["error"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
