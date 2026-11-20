#!/usr/bin/env python3
"""Deliver an annotated iOS screenshot and optional prompt text to an editor on macOS.

Reads a single JSON object from stdin and prints a single JSON result line to stdout:
    {"ok": true, "detail": "..."}
    {"ok": false, "error": "..."}
"""
import base64
import glob
import http.client
import json
import os
import subprocess
import sys
import time
import urllib.parse

MAX_ANNOTATE_FILES = 50
MAX_INFO_BYTES = 64 * 1024
MAX_RESPONSE_BYTES = 16 * 1024 * 1024
DEFAULT_TMP_DIR = "/tmp/rc-annotate"


def _prune_old_screenshots(tmp_dir, max_files=MAX_ANNOTATE_FILES):
    """Keep only the newest `max_files` PNG screenshots in `tmp_dir`."""
    try:
        entries = []
        for name in os.listdir(tmp_dir):
            if name.startswith("rc-annotate-") and name.endswith(".png"):
                full = os.path.join(tmp_dir, name)
                try:
                    entries.append((os.path.getmtime(full), full))
                except OSError:
                    pass
        if len(entries) <= max_files:
            return
        entries.sort(key=lambda item: item[0])
        for _, full in entries[: len(entries) - max_files]:
            try:
                os.remove(full)
            except OSError:
                pass
    except OSError:
        pass


def _save_png(image_b64, tmp_dir=DEFAULT_TMP_DIR):
    """Decode `image_b64` and write a timestamped PNG file inside `tmp_dir`."""
    if not isinstance(image_b64, str) or not image_b64.strip():
        raise ValueError("Missing screenshot image data")
    raw = base64.b64decode(image_b64, validate=True)
    if not raw:
        raise ValueError("Empty screenshot image data")
    os.makedirs(tmp_dir, mode=0o700, exist_ok=True)
    try:
        os.chmod(tmp_dir, 0o700)
    except OSError:
        pass
    epoch_ms = int(time.time() * 1000)
    path = os.path.join(tmp_dir, f"rc-annotate-{epoch_ms}.png")
    counter = 0
    while os.path.exists(path):
        counter += 1
        path = os.path.join(tmp_dir, f"rc-annotate-{epoch_ms}-{counter}.png")
    with open(path, "wb") as f:
        f.write(raw)
    _prune_old_screenshots(tmp_dir)
    return path


def _opencode_registration_paths():
    """Return OpenCode service registration JSON candidate paths in priority order."""
    home = os.path.expanduser("~")
    xdg_state = os.environ.get("XDG_STATE_HOME", "").strip()
    state_dir = os.path.join(xdg_state, "opencode") if xdg_state else os.path.join(home, ".local", "state", "opencode")

    opencode_cfg = os.environ.get("OPENCODE_CONFIG_DIR", "").strip()
    xdg_cfg = os.environ.get("XDG_CONFIG_HOME", "").strip()

    paths = [os.path.join(state_dir, "service.json")]
    if state_dir != os.path.join(home, ".local", "state", "opencode"):
        paths.append(os.path.join(home, ".local", "state", "opencode", "service.json"))

    state_globs = sorted(glob.glob(os.path.join(state_dir, "service-*.json")))
    default_state_dir = os.path.join(home, ".local", "state", "opencode")
    if state_dir != default_state_dir:
        state_globs.extend(sorted(glob.glob(os.path.join(default_state_dir, "service-*.json"))))
    paths.extend(state_globs)

    if opencode_cfg:
        paths.append(os.path.join(opencode_cfg, "service.json"))
    if xdg_cfg:
        paths.append(os.path.join(xdg_cfg, "opencode", "service.json"))
    paths.append(os.path.join(home, ".config", "opencode", "service.json"))

    seen = set()
    ordered = []
    for p in paths:
        norm = os.path.abspath(p)
        if norm not in seen:
            seen.add(norm)
            ordered.append(p)
    return ordered


def _parse_loopback_service(candidate):
    """Validate and normalize a service registration dict into (host, port, headers, pid)."""
    if not isinstance(candidate, dict):
        return None
    raw_url = candidate.get("url")
    raw_port = candidate.get("port")
    if not raw_url and not raw_port:
        return None

    if raw_url:
        parsed = urllib.parse.urlsplit(str(raw_url).split()[0])
    else:
        hostname = str(candidate.get("hostname") or "127.0.0.1")
        parsed = urllib.parse.urlsplit(f"http://{hostname}:{raw_port}")

    if parsed.scheme != "http" or not parsed.port:
        return None

    host = (parsed.hostname or "").lower()
    if host in ("localhost", "127.0.0.1", "0.0.0.0"):
        connect_host = "127.0.0.1"
    elif host in ("::1", "::"):
        connect_host = "::1"
    else:
        return None

    headers = {"Content-Type": "application/json"}
    password = (
        candidate.get("password")
        or os.environ.get("OPENCODE_PASSWORD")
        or os.environ.get("OPENCODE_SERVER_PASSWORD")
    )
    if isinstance(password, str) and password.strip():
        token = base64.b64encode(("opencode:" + password.strip()).encode("utf-8")).decode("ascii")
        headers["Authorization"] = "Basic " + token

    return {
        "host": connect_host,
        "port": int(parsed.port),
        "headers": headers,
        "pid": candidate.get("pid"),
    }


def _http_json(service, method, path, body=None, timeout=5.0, max_bytes=MAX_RESPONSE_BYTES):
    """Send one HTTP/1.1 JSON request to a loopback OpenCode service."""
    conn = http.client.HTTPConnection(service["host"], service["port"], timeout=timeout)
    try:
        encoded = None if body is None else json.dumps(body).encode("utf-8")
        conn.request(method, path, encoded, service["headers"])
        resp = conn.getresponse()
        data = resp.read(max_bytes + 1)
        if len(data) > max_bytes:
            raise RuntimeError("OpenCode response too large")
        parsed = None
        if data:
            try:
                parsed = json.loads(data.decode("utf-8"))
            except ValueError:
                parsed = data.decode("utf-8", errors="replace")
        return resp.status, parsed
    finally:
        conn.close()


def _discover_opencode_service(reg_paths=None):
    """Find the first live loopback OpenCode service whose /api/info verifies."""
    paths = reg_paths if reg_paths is not None else _opencode_registration_paths()
    for path in paths:
        try:
            with open(path, "r", encoding="utf-8") as f:
                candidate = json.load(f)
        except (OSError, ValueError):
            continue

        svc = _parse_loopback_service(candidate)
        if not svc:
            continue

        try:
            status, info = _http_json(svc, "GET", "/api/info", timeout=2.0, max_bytes=MAX_INFO_BYTES)
        except Exception:
            continue

        if status != 200 or not isinstance(info, dict):
            continue

        info_obj = info.get("data") if isinstance(info.get("data"), dict) and "pid" not in info else info
        if svc["pid"] is not None and info_obj.get("pid") != svc["pid"]:
            continue

        return svc
    return None


def _session_directory(session):
    """Extract a session's working directory across OpenCode V1 and V2 formats."""
    loc = session.get("location")
    if isinstance(loc, dict) and loc.get("directory"):
        return str(loc["directory"])
    if session.get("directory"):
        return str(session["directory"])
    return ""


def _extract_sessions(payload):
    """Normalize session list responses (either top-level array or {"data": [...]})."""
    if isinstance(payload, list):
        return payload
    if isinstance(payload, dict) and isinstance(payload.get("data"), list):
        return payload["data"]
    return []


def _is_open_root_session(session):
    """Return True for non-archived root sessions."""
    if not isinstance(session, dict) or not session.get("id"):
        return False
    if session.get("parentID") is not None:
        return False
    time_obj = session.get("time")
    if isinstance(time_obj, dict) and time_obj.get("archived") is not None:
        return False
    return True


def _pick_opencode_session(svc, project_dir):
    """Resolve the target OpenCode session (last viewed, optionally filtered by project_dir)."""
    norm_project = ""
    if isinstance(project_dir, str) and project_dir.strip():
        norm_project = os.path.realpath(os.path.expanduser(project_dir.strip()))

    query = "/api/session?parentID=null&limit=100"
    if norm_project:
        query_with_dir = query + "&directory=" + urllib.parse.quote(norm_project, safe="")
    else:
        query_with_dir = query

    status, resp = _http_json(svc, "GET", query_with_dir, timeout=5.0)
    if status < 200 or status >= 300:
        raise RuntimeError(f"OpenCode session lookup failed: HTTP {status}")

    sessions = [s for s in _extract_sessions(resp) if _is_open_root_session(s)]

    if norm_project:
        # Verify directory match client-side and fall back to unfiltered query if server didn't match.
        filtered = [
            s for s in sessions
            if _session_directory(s) and os.path.realpath(_session_directory(s)) == norm_project
        ]
        if not filtered:
            status_all, resp_all = _http_json(svc, "GET", query, timeout=5.0)
            if 200 <= status_all < 300:
                all_sessions = [s for s in _extract_sessions(resp_all) if _is_open_root_session(s)]
                filtered = [
                    s for s in all_sessions
                    if _session_directory(s) and os.path.realpath(_session_directory(s)) == norm_project
                ]
        sessions = filtered

    if not sessions:
        suffix = " for project" if norm_project else ""
        raise RuntimeError(f"No open OpenCode session{suffix}")

    def sort_key(s):
        t = s.get("time") if isinstance(s.get("time"), dict) else {}
        viewed = t.get("viewed") or 0
        updated = t.get("updated") or 0
        try:
            viewed_num = int(viewed)
        except (TypeError, ValueError):
            viewed_num = 0
        try:
            updated_num = int(updated)
        except (TypeError, ValueError):
            updated_num = 0
        return (1 if viewed_num > 0 else 0, viewed_num, updated_num)

    sessions.sort(key=sort_key, reverse=True)
    return sessions[0]


def _extract_api_error(resp, status):
    """Extract a short error message from a failed OpenCode API response."""
    if isinstance(resp, dict):
        err = resp.get("error") if isinstance(resp.get("error"), dict) else resp
        msg = err.get("message") or err.get("error")
        if isinstance(msg, str) and msg.strip():
            return f"OpenCode said: {msg.strip().splitlines()[0][:200]}"
    elif isinstance(resp, str) and resp.strip():
        return f"OpenCode said: {resp.strip().splitlines()[0][:200]}"
    return f"OpenCode API failed: HTTP {status}"


def _open_session_in_background(session_id, run_cmd=None):
    """Ask OpenCode Desktop to show a session in a background tab.

    The alfred-tabs GUI plugin treats ?background=1 as "open a tab, do not
    select it". `open -g` keeps macOS from bringing the app to the front.
    Best effort: the prompt is already queued, so a missing tab must not fail
    the send.
    """
    if run_cmd is None:
        run_cmd = _default_run_cmd
    url = f"opencode://session/{urllib.parse.quote(session_id, safe='')}?background=1"
    try:
        run_cmd(["/usr/bin/open", "-g", url], None, None)
        return True
    except Exception:
        return False


def _deliver_opencode_api(svc, png_path, image_b64, text, delivery, project_dir, run_cmd=None):
    """Deliver screenshot + text directly to an OpenCode V2 session."""
    session = _pick_opencode_session(svc, project_dir)
    session_id = session["id"]
    clean_text = text.strip() if isinstance(text, str) else ""
    prompt_text = clean_text if clean_text else "See attached annotated screenshot."
    body = {
        "text": prompt_text,
        "files": [
            {
                "uri": "data:image/png;base64," + image_b64,
                "name": os.path.basename(png_path),
                "description": "Annotated iOS screenshot",
            }
        ],
        "delivery": delivery if delivery in ("queue", "steer") else "queue",
    }
    encoded_id = urllib.parse.quote(session_id, safe="")
    status, resp = _http_json(svc, "POST", f"/api/session/{encoded_id}/prompt", body=body, timeout=10.0)
    if status < 200 or status >= 300:
        raise RuntimeError(_extract_api_error(resp, status))
    _open_session_in_background(session_id, run_cmd=run_cmd)
    title = str(session.get("title") or "").strip() or session_id
    return title


def _escape_applescript(value):
    """Escape backslashes and double quotes for an AppleScript string literal."""
    return str(value).replace("\\", "\\\\").replace('"', '\\"')


def _default_run_cmd(args, input_bytes=None, env=None):
    """Run a subprocess and return (returncode, stdout, stderr)."""
    proc_env = os.environ.copy()
    if env:
        proc_env.update(env)
    proc = subprocess.run(
        args,
        input=input_bytes,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=proc_env,
    )
    return (
        proc.returncode,
        proc.stdout.decode("utf-8", errors="replace"),
        proc.stderr.decode("utf-8", errors="replace"),
    )


def _is_accessibility_error(stderr):
    """Return True if AppleScript failed due to macOS Accessibility permissions."""
    low = (stderr or "").lower()
    return (
        "1002" in low
        or "not allowed to send keystrokes" in low
        or "not allowed assistive access" in low
    )


def _run_osascript(script, run_cmd):
    """Run an AppleScript snippet and map Accessibility errors cleanly."""
    rc, _, stderr = run_cmd(["/usr/bin/osascript", "-e", script], None, None)
    if rc != 0:
        if _is_accessibility_error(stderr):
            raise RuntimeError("Enable Accessibility for sshd-keygen-wrapper on Mac")
        detail = (stderr or "").strip().splitlines()
        msg = detail[-1][:200] if detail else f"osascript failed ({rc})"
        raise RuntimeError(msg)


def _activate_target_app(bundle_id, app_name, run_cmd):
    """Activate the target macOS application and return a display label for it."""
    bid = bundle_id.strip() if isinstance(bundle_id, str) else ""
    name = app_name.strip() if isinstance(app_name, str) else ""
    if bid:
        try:
            _run_osascript(f'tell application id "{_escape_applescript(bid)}" to activate', run_cmd)
            return name or bid
        except RuntimeError as err:
            if "Accessibility" in str(err) or not name:
                raise
    if name:
        _run_osascript(f'tell application "{_escape_applescript(name)}" to activate', run_cmd)
        return name
    raise RuntimeError("Missing target application")


def _antigravity_registration_paths():
    """Return RemoteCompanion Antigravity Bridge registration JSON paths."""
    home = os.path.expanduser("~")
    xdg_state = os.environ.get("XDG_STATE_HOME", "").strip()
    dirs = []
    if xdg_state:
        dirs.append(os.path.join(xdg_state, "rc-antigravity"))
    dirs.append(os.path.join(home, ".local", "state", "rc-antigravity"))

    paths = []
    seen = set()
    for d in dirs:
        for p in sorted(glob.glob(os.path.join(d, "window-*.json"))):
            norm = os.path.abspath(p)
            if norm not in seen:
                seen.add(norm)
                paths.append(p)
    return paths


def _discover_antigravity_windows(reg_paths=None):
    """Discover all live Antigravity IDE bridge instances whose /info verifies."""
    paths = reg_paths if reg_paths is not None else _antigravity_registration_paths()
    windows = []
    for path in paths:
        try:
            with open(path, "r", encoding="utf-8") as f:
                candidate = json.load(f)
        except (OSError, ValueError):
            continue

        svc = _parse_loopback_service(candidate)
        if not svc:
            continue

        try:
            status, info = _http_json(svc, "GET", "/info", timeout=1.5, max_bytes=MAX_INFO_BYTES)
        except Exception:
            continue

        if status != 200 or not isinstance(info, dict) or info.get("ok") is not True:
            continue
        if svc["pid"] is not None and info.get("pid") != svc["pid"]:
            continue

        try:
            last_focused = int(info.get("lastFocusedAt") or 0)
        except (TypeError, ValueError):
            last_focused = 0

        windows.append(
            {
                "service": svc,
                "pid": info.get("pid"),
                "workspaceName": str(info.get("workspaceName") or "").strip(),
                "workspaceFolders": [
                    str(p)
                    for p in (info.get("workspaceFolders") or [])
                    if isinstance(p, str) and p.strip()
                ],
                "windowFocused": bool(info.get("windowFocused")),
                "lastFocusedAt": last_focused,
            }
        )
    return windows


def _open_folder_with_app(bundle_id, app_name, folder_path, run_cmd):
    """Open `folder_path` using macOS `open` with the target bundle ID or app name."""
    bid = bundle_id.strip() if isinstance(bundle_id, str) else ""
    name = app_name.strip() if isinstance(app_name, str) else ""
    if not bid and not name:
        raise RuntimeError("Missing target application")

    rc = 1
    stderr = ""
    if bid:
        rc, _, stderr = run_cmd(["/usr/bin/open", "-b", bid, folder_path], None, None)
        if rc != 0 and name:
            rc, _, stderr = run_cmd(["/usr/bin/open", "-a", name, folder_path], None, None)
    else:
        rc, _, stderr = run_cmd(["/usr/bin/open", "-a", name, folder_path], None, None)

    if rc != 0:
        err_text = (stderr or "").strip()
        msg = err_text.splitlines()[-1][:200] if err_text else "Failed to open project folder"
        raise RuntimeError(msg)


def _pick_antigravity_window(project_dir, bundle_id, app_name, reg_paths, run_cmd, sleep_fn):
    """Resolve the target Antigravity IDE window, opening `project_dir` if needed."""
    def sort_key(win):
        return (1 if win["windowFocused"] else 0, win["lastFocusedAt"])

    has_project = isinstance(project_dir, str) and bool(project_dir.strip())
    if has_project:
        expanded = os.path.expanduser(project_dir.strip())
        if not os.path.isdir(expanded):
            raise RuntimeError(f"Project folder not found: {expanded}")
        norm_project = os.path.realpath(expanded)

        def find_matching(win_list):
            matched_wins = []
            for win in win_list:
                for folder in win["workspaceFolders"]:
                    try:
                        if os.path.realpath(os.path.expanduser(folder)) == norm_project:
                            matched_wins.append(win)
                            break
                    except OSError:
                        pass
            return matched_wins

        windows = _discover_antigravity_windows(reg_paths)
        matched = find_matching(windows)
        if not matched:
            _open_folder_with_app(bundle_id, app_name, expanded, run_cmd)
            for _ in range(20):
                sleep_fn(0.25)
                windows = _discover_antigravity_windows(reg_paths)
                matched = find_matching(windows)
                if matched:
                    break

        if not matched:
            if not windows:
                raise RuntimeError("Antigravity Bridge extension isn't active (reload Antigravity IDE window)")
            label = os.path.basename(norm_project) or norm_project
            raise RuntimeError(f"No Antigravity IDE window found for {label}")

        matched.sort(key=sort_key, reverse=True)
        return matched[0]

    windows = _discover_antigravity_windows(reg_paths)
    if not windows:
        raise RuntimeError("Antigravity Bridge extension isn't active (reload Antigravity IDE window)")
    windows.sort(key=sort_key, reverse=True)
    return windows[0]


def _paste_png_from_clipboard(png_path, image_paste_delay_ms, run_cmd, sleep_fn):
    """Put `png_path` on the macOS clipboard as PNG, paste via Cmd+V, and wait."""
    escaped_path = _escape_applescript(png_path)
    _run_osascript(
        f'set the clipboard to (read POSIX file "{escaped_path}" as «class PNGf»)',
        run_cmd,
    )
    _run_osascript(
        'tell application "System Events" to keystroke "v" using command down',
        run_cmd,
    )

    try:
        delay_ms = int(image_paste_delay_ms)
    except (TypeError, ValueError):
        delay_ms = 450
    delay_ms = max(150, min(2000, delay_ms))
    sleep_fn(delay_ms / 1000.0)


def _send_submit_key(submit_key, run_cmd, sleep_fn):
    """Send Return (or Cmd+Return) via System Events after a short delay."""
    sleep_fn(0.15)
    if submit_key == "cmd+return":
        _run_osascript(
            'tell application "System Events" to key code 36 using command down',
            run_cmd,
        )
    else:
        _run_osascript(
            'tell application "System Events" to key code 36',
            run_cmd,
        )


def _deliver_antigravity_ext(
    png_path,
    text,
    bundle_id,
    app_name,
    auto_send,
    image_paste_delay_ms,
    submit_key,
    project_dir,
    reg_paths,
    run_cmd,
    sleep_fn,
):
    """Deliver screenshot + text to Antigravity IDE via the companion bridge extension."""
    win = _pick_antigravity_window(project_dir, bundle_id, app_name, reg_paths, run_cmd, sleep_fn)
    svc = win["service"]

    if win["workspaceFolders"]:
        _open_folder_with_app(bundle_id, app_name, win["workspaceFolders"][0], run_cmd)
    _activate_target_app(bundle_id, app_name, run_cmd)
    sleep_fn(0.2)

    status, prep = _http_json(svc, "POST", "/prepare", body={}, timeout=5.0)
    if status != 200 or not isinstance(prep, dict) or not prep.get("ok") or not prep.get("isFocused"):
        err = (prep.get("error") if isinstance(prep, dict) else None) or "Couldn't focus Antigravity Agent chat panel"
        raise RuntimeError(str(err))

    _paste_png_from_clipboard(png_path, image_paste_delay_ms, run_cmd, sleep_fn)

    clean_text = text.strip() if isinstance(text, str) else ""
    status, pop = _http_json(
        svc,
        "POST",
        "/populate",
        body={"text": clean_text, "autoSend": bool(auto_send)},
        timeout=5.0,
    )
    if status != 200 or not isinstance(pop, dict) or not pop.get("ok"):
        err = (pop.get("error") if isinstance(pop, dict) else None) or "Failed to populate Antigravity Agent chat"
        raise RuntimeError(str(err))

    if auto_send and not pop.get("sent"):
        if not pop.get("isFocused"):
            raise RuntimeError("Antigravity Agent chat lost focus before send")
        _send_submit_key(submit_key, run_cmd, sleep_fn)

    return str(pop.get("workspaceName") or prep.get("workspaceName") or win.get("workspaceName") or "Antigravity IDE")


def _deliver_clipboard_paste(
    png_path,
    text,
    bundle_id,
    app_name,
    auto_send,
    image_paste_delay_ms,
    submit_key,
    run_cmd=_default_run_cmd,
    sleep_fn=time.sleep,
):
    """Activate the target editor, paste the PNG and text, and optionally submit."""
    display_target = _activate_target_app(bundle_id, app_name, run_cmd)
    sleep_fn(0.25)

    _paste_png_from_clipboard(png_path, image_paste_delay_ms, run_cmd, sleep_fn)

    clean_text = text.strip() if isinstance(text, str) else ""
    if clean_text:
        rc, _, stderr = run_cmd(
            ["/usr/bin/pbcopy"],
            clean_text.encode("utf-8"),
            {"LC_ALL": "en_US.UTF-8", "LANG": "en_US.UTF-8"},
        )
        if rc != 0:
            raise RuntimeError((stderr or "pbcopy failed").strip()[:200])
        _run_osascript(
            'tell application "System Events" to keystroke "v" using command down',
            run_cmd,
        )

    if auto_send:
        _send_submit_key(submit_key, run_cmd, sleep_fn)

    return display_target


def deliver(
    payload,
    reg_paths=None,
    antigravity_reg_paths=None,
    tmp_dir=DEFAULT_TMP_DIR,
    run_cmd=_default_run_cmd,
    sleep_fn=time.sleep,
):
    """Execute delivery for a parsed JSON payload dict and return result dict."""
    try:
        if not isinstance(payload, dict):
            return {"ok": False, "error": "Invalid JSON payload"}

        image_b64 = payload.get("image_b64") or ""
        png_path = _save_png(image_b64, tmp_dir=tmp_dir)

        strategy = str(payload.get("strategy") or "clipboard_paste")
        auto_send = bool(payload.get("auto_send", True))
        text = payload.get("text") or ""

        if strategy not in ("opencode_api", "antigravity_ext", "clipboard_paste"):
            return {"ok": False, "error": f"Unsupported delivery strategy: {strategy}"}

        if strategy == "opencode_api" and auto_send:
            svc = _discover_opencode_service(reg_paths=reg_paths)
            if not svc:
                return {"ok": False, "error": "OpenCode isn't running"}
            detail = _deliver_opencode_api(
                svc=svc,
                png_path=png_path,
                image_b64=image_b64,
                text=text,
                delivery=payload.get("delivery") or "queue",
                project_dir=payload.get("project_dir") or "",
                run_cmd=run_cmd,
            )
            return {"ok": True, "detail": detail}

        if strategy == "antigravity_ext":
            detail = _deliver_antigravity_ext(
                png_path=png_path,
                text=text,
                bundle_id=payload.get("bundle_id") or "",
                app_name=payload.get("app_name") or "",
                auto_send=auto_send,
                image_paste_delay_ms=payload.get("image_paste_delay_ms", 450),
                submit_key=payload.get("submit_key") or "return",
                project_dir=payload.get("project_dir") or "",
                reg_paths=antigravity_reg_paths,
                run_cmd=run_cmd,
                sleep_fn=sleep_fn,
            )
            return {"ok": True, "detail": detail}

        detail = _deliver_clipboard_paste(
            png_path=png_path,
            text=text,
            bundle_id=payload.get("bundle_id") or "",
            app_name=payload.get("app_name") or "",
            auto_send=auto_send,
            image_paste_delay_ms=payload.get("image_paste_delay_ms", 450),
            submit_key=payload.get("submit_key") or "return",
            run_cmd=run_cmd,
            sleep_fn=sleep_fn,
        )
        return {"ok": True, "detail": detail}
    except Exception as exc:
        msg = str(exc).strip() or exc.__class__.__name__
        return {"ok": False, "error": msg}


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception as exc:
        print(json.dumps({"ok": False, "error": f"Invalid input JSON: {exc}"}), flush=True)
        return 1
    result = deliver(payload)
    print(json.dumps(result), flush=True)
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main())
