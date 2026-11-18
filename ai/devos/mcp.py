"""DevOS system tools for DevOS Agent, as an MCP server over stdio (SRS §15, AGENT-020).

    devos mcp

DevOS Agent starts this server and offers its tools to the model. Read-only tools carry
the MCP `readOnlyHint`; every other tool changes the desktop or the system, so the agent
asks the user before each call (the server is configured `trust: untrusted`). Package
changes go through devos-pkg-helper and the polkit password prompt, never through sudo.
Every call is written to the DevOS audit log.

Standard library only. Messages are newline-delimited JSON-RPC 2.0 (MCP stdio transport).
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Callable

from devos.audit import AuditLog

SERVER_NAME = "devos"
SERVER_VERSION = "0.1.0"
PROTOCOL_VERSIONS = ("2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05")
PKG_HELPER = "/usr/lib/devos/devos-pkg-helper"
PKG_NAME = re.compile(r"^[a-z0-9@._+-]+$")
OUTPUT_LIMIT = 20000


class ToolError(Exception):
    pass


# ------------------------------------------------------------------ helpers

def _session_env() -> dict:
    """The environment plus the desktop session's variables when they are missing (the agent
    service can start before the compositor exported them)."""
    env = dict(os.environ)
    runtime = Path(env.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}")
    if not env.get("HYPRLAND_INSTANCE_SIGNATURE"):
        instances = sorted((runtime / "hypr").glob("*/.socket.sock"), key=lambda p: p.stat().st_mtime, reverse=True)
        if instances:
            env["HYPRLAND_INSTANCE_SIGNATURE"] = instances[0].parent.name
    if not env.get("WAYLAND_DISPLAY"):
        sockets = sorted(runtime.glob("wayland-[0-9]"), key=lambda p: p.stat().st_mtime, reverse=True)
        if sockets:
            env["WAYLAND_DISPLAY"] = sockets[0].name
    return env


def _run(argv: list[str], timeout: float = 30, input_text: str | None = None) -> str:
    if shutil.which(argv[0]) is None and not os.path.isabs(argv[0]):
        raise ToolError(f"{argv[0]} is not installed")
    try:
        p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout, input=input_text,
                           env=_session_env())
    except subprocess.TimeoutExpired:
        raise ToolError(f"{argv[0]} timed out after {timeout:.0f} s")
    if p.returncode != 0:
        raise ToolError((p.stderr or p.stdout or f"{argv[0]} failed ({p.returncode})").strip()[-2000:])
    return p.stdout


def _hyprctl_json(what: str) -> Any:
    return json.loads(_run(["hyprctl", "-j", what]))


def _dispatch(lua: str) -> str:
    """Run one Hyprland dispatcher (Lua config syntax, Hyprland >= 0.55)."""
    out = _run(["hyprctl", "dispatch", lua]).strip()
    if out and out.lower() != "ok":
        raise ToolError(out)
    return "ok"


def _lua_str(s: str) -> str:
    return json.dumps(s)  # a JSON string is a valid Lua string literal for our inputs


def _window_summary(c: dict) -> dict:
    return {"address": c.get("address"), "class": c.get("class"), "title": c.get("title"),
            "workspace": (c.get("workspace") or {}).get("name"), "floating": c.get("floating"),
            "fullscreen": c.get("fullscreen"), "focused": c.get("focusHistoryID") == 0,
            "pid": c.get("pid")}


def _find_window(ref: str) -> dict:
    """A window by address, or the first whose class or title contains `ref`."""
    clients = _hyprctl_json("clients")
    ref_l = ref.lower()
    for c in clients:
        if c.get("address") == ref:
            return c
    for c in clients:
        if ref_l in (c.get("class") or "").lower() or ref_l in (c.get("title") or "").lower():
            return c
    raise ToolError(f"no open window matches {ref!r}")


# ------------------------------------------------------------------ tools

def t_desktop_state(a: dict) -> Any:
    active = _hyprctl_json("activewindow") or {}
    return {
        "monitors": [{"name": m.get("name"), "size": f"{m.get('width')}x{m.get('height')}",
                      "workspace": (m.get("activeWorkspace") or {}).get("name"), "focused": m.get("focused")}
                     for m in _hyprctl_json("monitors")],
        "workspaces": [{"name": w.get("name"), "windows": w.get("windows"), "monitor": w.get("monitor")}
                       for w in sorted(_hyprctl_json("workspaces"), key=lambda w: w.get("id", 0))],
        "windows": [_window_summary(c) for c in _hyprctl_json("clients")],
        "focused_window": _window_summary(active) if active.get("address") else None,
    }


def t_focus_window(a: dict) -> Any:
    c = _find_window(a["window"])
    _dispatch(f'hl.dsp.focus({{ window = {_lua_str("address:" + c["address"])} }})')
    return {"focused": _window_summary(c)}


def t_switch_workspace(a: dict) -> Any:
    return _dispatch(f'hl.dsp.focus({{ workspace = {_lua_str(str(a["workspace"]))} }})')


def t_move_window(a: dict) -> Any:
    if a.get("window"):
        t_focus_window({"window": a["window"]})
    follow = "true" if a.get("follow", False) else "false"
    return _dispatch(f'hl.dsp.window.move({{ workspace = {_lua_str(str(a["workspace"]))}, follow = {follow} }})')


def t_window_action(a: dict) -> Any:
    if a.get("window"):
        t_focus_window({"window": a["window"]})
    action = a["action"]
    lua = {
        "close": "hl.dsp.window.close()",
        "toggle_fullscreen": 'hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" })',
        "toggle_maximize": 'hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })',
        "toggle_floating": 'hl.dsp.window.float({ action = "toggle" })',
        "pin": "hl.dsp.window.pin()",
    }.get(action)
    if lua is None:
        raise ToolError(f"unknown window action {action!r}")
    return _dispatch(lua)


def t_launch_app(a: dict) -> Any:
    """Start an installed app by desktop entry id or name (through UWSM when available)."""
    app = a["app"].strip()
    entry = _desktop_entry(app)
    if entry is None:
        raise ToolError(f"no installed app matches {app!r} (try list_apps)")
    argv = (["uwsm", "app", "--", entry] if shutil.which("uwsm") else ["gtk-launch", entry.removesuffix(".desktop")])
    subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True, env=_session_env())
    return {"launched": entry}


def _app_dirs() -> list[Path]:
    home = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
    dirs = [home] + [Path(d) for d in os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":") if d]
    return [d / "applications" for d in dirs]


def _apps() -> list[dict]:
    seen, apps = set(), []
    for d in _app_dirs():
        for f in sorted(d.glob("*.desktop")) if d.is_dir() else []:
            if f.name in seen:
                continue
            seen.add(f.name)
            name, hidden, comment = "", False, ""
            try:
                section = ""
                for line in f.read_text(errors="replace").splitlines():
                    if line.startswith("["):
                        section = line.strip()
                    elif section == "[Desktop Entry]":
                        if line.startswith("Name=") and not name:
                            name = line[5:].strip()
                        elif line.startswith("Comment=") and not comment:
                            comment = line[8:].strip()
                        elif line.strip() in ("NoDisplay=true", "Hidden=true"):
                            hidden = True
            except OSError:
                continue
            if name and not hidden:
                apps.append({"id": f.name, "name": name, "comment": comment})
    return apps


def _desktop_entry(app: str) -> str | None:
    apps = _apps()
    app_l = app.lower().removesuffix(".desktop")
    for key in ("id", "name"):
        for x in apps:
            if x[key].lower().removesuffix(".desktop") == app_l:
                return x["id"]
    for x in apps:
        if app_l in x["name"].lower() or app_l in x["id"].lower():
            return x["id"]
    return None


def t_list_apps(a: dict) -> Any:
    q = (a.get("query") or "").lower()
    apps = [x for x in _apps() if not q or q in x["name"].lower() or q in x["id"].lower() or q in x["comment"].lower()]
    return apps[:200]


def t_screenshot(a: dict) -> Any:
    out_dir = Path(os.environ.get("XDG_PICTURES_DIR", Path.home() / "Pictures")) / "Screenshots"
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / time.strftime("devos-agent-%Y%m%d-%H%M%S.png")
    argv = ["grim"]
    if a.get("target") == "focused_window":
        w = _hyprctl_json("activewindow") or {}
        if not w.get("at"):
            raise ToolError("no focused window")
        (x, y), (wd, ht) = w["at"], w["size"]
        argv += ["-g", f"{x},{y} {wd}x{ht}"]
    _run(argv + [str(path)])
    return {"path": str(path), "note": "Read the file with the vision or file tools to see it."}


def t_notify(a: dict) -> Any:
    argv = ["notify-send", "-a", "DevOS Agent", "-i", "dialog-information"]
    if a.get("urgent"):
        argv += ["-u", "critical"]
    _run(argv + [a["title"], a.get("body", "")])
    return "sent"


def t_system_status(a: dict) -> Any:
    def first(cmd: list[str]) -> str:
        try:
            return _run(cmd, timeout=5).strip()
        except ToolError:
            return ""
    mem = {}
    for line in Path("/proc/meminfo").read_text().splitlines():
        k, v = line.split(":", 1)
        if k in ("MemTotal", "MemAvailable", "SwapTotal", "SwapFree"):
            mem[k] = f"{int(v.split()[0]) // 1024} MiB"
    du = shutil.disk_usage("/")
    home = shutil.disk_usage(Path.home())
    battery = {}
    for b in Path("/sys/class/power_supply").glob("BAT*"):
        try:
            battery = {"capacity": (b / "capacity").read_text().strip() + "%", "status": (b / "status").read_text().strip()}
        except OSError:
            pass
    return {
        "os": first(["sh", "-c", ". /etc/os-release && echo \"$PRETTY_NAME\""]),
        "kernel": os.uname().release, "hostname": os.uname().nodename,
        "uptime": first(["uptime", "-p"]), "load": os.getloadavg(),
        "memory": mem,
        "disk_root": f"{du.free // 2**30} GiB free of {du.total // 2**30} GiB",
        "disk_home": f"{home.free // 2**30} GiB free of {home.total // 2**30} GiB",
        "battery": battery or None,
        "network": first(["nmcli", "-t", "-f", "TYPE,STATE,CONNECTION", "device"]),
        "volume": first(["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]),
        "failed_units": first(["systemctl", "--failed", "--no-legend", "--plain"]),
    }


def t_set_volume(a: dict) -> Any:
    if "mute" in a:
        _run(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "1" if a["mute"] else "0"])
    if "percent" in a:
        pct = max(0, min(150, int(a["percent"])))
        _run(["wpctl", "set-volume", "-l", "1.5", "@DEFAULT_AUDIO_SINK@", f"{pct}%"])
    return _run(["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]).strip()


def t_set_brightness(a: dict) -> Any:
    pct = max(1, min(100, int(a["percent"])))
    _run(["brightnessctl", "set", f"{pct}%"])
    return f"{pct}%"


def t_wifi_networks(a: dict) -> Any:
    out = _run(["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "device", "wifi", "list", "--rescan", "auto"])
    nets = []
    for line in out.splitlines():
        parts = re.split(r"(?<!\\):", line)
        if len(parts) >= 4 and parts[1]:
            nets.append({"connected": parts[0] == "*", "ssid": parts[1].replace("\\:", ":"),
                         "signal": parts[2], "security": parts[3]})
    return nets


def t_wifi_connect(a: dict) -> Any:
    argv = ["nmcli", "device", "wifi", "connect", a["ssid"]]
    # The password goes through nmcli's stdin prompt (--ask), never the command line.
    if a.get("password"):
        return _run(["nmcli", "--ask"] + argv[1:], timeout=60, input_text=a["password"] + "\n").strip()
    return _run(argv, timeout=60).strip()


def t_packages_search(a: dict) -> Any:
    q = a["query"].strip()
    if not q or len(q) > 100:
        raise ToolError("empty or too long query")
    out = _run(["pacman", "-Ss", "--", q], timeout=30) if q else ""
    lines = out.splitlines()
    res = []
    for i in range(0, len(lines) - 1, 2):
        head, desc = lines[i], lines[i + 1].strip()
        repo_name, _, rest = head.partition(" ")
        res.append({"package": repo_name, "version": rest.split(" ")[0], "installed": "[installed" in rest,
                    "description": desc})
    return res[:60]


def t_packages_installed(a: dict) -> Any:
    names = a.get("names") or []
    if names:
        return {n: (subprocess.run(["pacman", "-Q", n], capture_output=True, text=True).stdout.strip() or None)
                for n in names[:50]}
    return {"explicit_count": len(_run(["pacman", "-Qeq"]).split()),
            "updates_hint": "Use packages_search or the terminal (checkupdates) for updates."}


def t_packages_change(a: dict) -> Any:
    action = a["action"]
    names = a.get("packages") or []
    if action not in ("install", "remove"):
        raise ToolError("action must be install or remove")
    if not names or len(names) > 50 or not all(PKG_NAME.fullmatch(n) for n in names):
        raise ToolError("invalid package names")
    if not os.access(PKG_HELPER, os.X_OK):
        raise ToolError("devos-pkg-helper is not installed")
    # pkexec shows the polkit password prompt on the desktop (auth_admin every time).
    p = subprocess.run(["pkexec", PKG_HELPER, action, *names], capture_output=True, text=True, timeout=1800)
    if p.returncode in (126, 127):
        raise ToolError("the administrator password was not given; nothing was changed")
    return {"exit_code": p.returncode, "output": (p.stdout + p.stderr)[-OUTPUT_LIMIT:]}


def _s(props: dict, required: list[str] | None = None) -> dict:
    return {"type": "object", "properties": props, "required": required or [], "additionalProperties": False}


STR = {"type": "string"}
WINDOW = {"type": "string", "description": "Window address (from desktop_state) or part of its class/title"}

# name: (description, input schema, read_only, handler)
TOOLS: dict[str, tuple[str, dict, bool, Callable[[dict], Any]]] = {
    "desktop_state": ("Monitors, workspaces and open windows on the Hyprland desktop, and which window has focus.",
                      _s({}), True, t_desktop_state),
    "focus_window": ("Focus an open window.", _s({"window": WINDOW}, ["window"]), False, t_focus_window),
    "switch_workspace": ("Switch to a workspace (number or name).",
                         _s({"workspace": {"type": ["string", "integer"]}}, ["workspace"]), False, t_switch_workspace),
    "move_window": ("Move a window (default: the focused one) to a workspace.",
                    _s({"window": WINDOW, "workspace": {"type": ["string", "integer"]},
                        "follow": {"type": "boolean", "description": "Also switch to that workspace"}},
                       ["workspace"]), False, t_move_window),
    "window_action": ("Close, fullscreen, maximize, float or pin a window (default: the focused one).",
                      _s({"window": WINDOW, "action": {"type": "string", "enum": [
                          "close", "toggle_fullscreen", "toggle_maximize", "toggle_floating", "pin"]}},
                         ["action"]), False, t_window_action),
    "list_apps": ("Installed graphical apps (desktop entries), optionally filtered.",
                  _s({"query": STR}), True, t_list_apps),
    "launch_app": ("Start an installed app by name or desktop entry id.", _s({"app": STR}, ["app"]),
                   False, t_launch_app),
    "screenshot": ("Take a screenshot of the whole screen or the focused window; returns the PNG path.",
                   _s({"target": {"type": "string", "enum": ["screen", "focused_window"]}}), False, t_screenshot),
    "notify": ("Show a desktop notification to the user.",
               _s({"title": STR, "body": STR, "urgent": {"type": "boolean"}}, ["title"]), False, t_notify),
    "system_status": ("OS, kernel, uptime, memory, disk, battery, network, volume and failed services.",
                      _s({}), True, t_system_status),
    "set_volume": ("Set the output volume in percent and/or mute it.",
                   _s({"percent": {"type": "integer"}, "mute": {"type": "boolean"}}), False, t_set_volume),
    "set_brightness": ("Set the screen brightness in percent.", _s({"percent": {"type": "integer"}}, ["percent"]),
                       False, t_set_brightness),
    "wifi_networks": ("Visible Wi-Fi networks and the one in use.", _s({}), True, t_wifi_networks),
    "wifi_connect": ("Connect to a Wi-Fi network.", _s({"ssid": STR, "password": STR}, ["ssid"]), False, t_wifi_connect),
    "packages_search": ("Search the package repositories (pacman -Ss).", _s({"query": STR}, ["query"]),
                        True, t_packages_search),
    "packages_installed": ("Installed versions of the given packages, or a summary.",
                           _s({"names": {"type": "array", "items": STR}}), True, t_packages_installed),
    "packages_change": ("Install or remove system packages. The user confirms and enters the administrator "
                        "password; core system packages cannot be removed.",
                        _s({"action": {"type": "string", "enum": ["install", "remove"]},
                            "packages": {"type": "array", "items": STR}}, ["action", "packages"]),
                        False, t_packages_change),
}


# ------------------------------------------------------------------ MCP server

class Server:
    def __init__(self, out=None, audit: AuditLog | None = None):
        self.out = out or sys.stdout
        self.audit = audit

    def send(self, msg: dict) -> None:
        self.out.write(json.dumps(msg, ensure_ascii=False) + "\n")
        self.out.flush()

    def result(self, mid: Any, result: dict) -> None:
        self.send({"jsonrpc": "2.0", "id": mid, "result": result})

    def error(self, mid: Any, code: int, message: str) -> None:
        self.send({"jsonrpc": "2.0", "id": mid, "error": {"code": code, "message": message}})

    def handle(self, msg: dict) -> None:
        method, mid = msg.get("method"), msg.get("id")
        if method is None:
            return  # a response to nothing we sent
        if mid is None:
            return  # notifications (initialized, cancelled) need no answer
        params = msg.get("params") or {}
        if method == "initialize":
            requested = params.get("protocolVersion")
            self.result(mid, {
                "protocolVersion": requested if requested in PROTOCOL_VERSIONS else PROTOCOL_VERSIONS[0],
                "capabilities": {"tools": {"listChanged": False}},
                "serverInfo": {"name": SERVER_NAME, "title": "DevOS system tools", "version": SERVER_VERSION},
                "instructions": "System-level tools of the DevOS desktop (Hyprland) and OS. Read-only tools run "
                                "freely; the user approves every tool that changes something.",
            })
        elif method == "ping":
            self.result(mid, {})
        elif method == "tools/list":
            self.result(mid, {"tools": [
                {"name": n, "description": d, "inputSchema": s,
                 "annotations": {"readOnlyHint": ro, "destructiveHint": n in ("packages_change", "window_action"),
                                 "openWorldHint": False}}
                for n, (d, s, ro, _) in TOOLS.items()]})
        elif method == "tools/call":
            self.result(mid, self.call(params.get("name", ""), params.get("arguments") or {}))
        else:
            self.error(mid, -32601, f"method not found: {method}")

    def call(self, name: str, args: dict) -> dict:
        tool = TOOLS.get(name)
        if tool is None:
            return {"content": [{"type": "text", "text": f"unknown tool {name}"}], "isError": True}
        started = time.monotonic()
        try:
            value = tool[3](args)
            text = value if isinstance(value, str) else json.dumps(value, ensure_ascii=False, indent=1)
            ok = True
        except ToolError as e:
            text, ok = str(e), False
        except (KeyError, TypeError, ValueError) as e:
            text, ok = f"invalid arguments: {e}", False
        if self.audit is not None:
            try:
                # Arguments minus secrets (Wi-Fi password).
                shown = {k: v for k, v in args.items() if k != "password"}
                self.audit.write("agent.system_tool", tool=name, args=shown, ok=ok,
                                 ms=int((time.monotonic() - started) * 1000))
            except OSError:
                pass
        return {"content": [{"type": "text", "text": text[:OUTPUT_LIMIT]}], "isError": not ok}

    def serve(self, inp=None) -> None:
        for line in inp or sys.stdin:
            line = line.strip()
            if not line:
                continue
            try:
                msg = json.loads(line)
            except json.JSONDecodeError:
                self.error(None, -32700, "parse error")
                continue
            if isinstance(msg, dict):
                self.handle(msg)


def main() -> None:
    try:
        audit = AuditLog()
    except OSError:
        audit = None
    Server(audit=audit).serve()


if __name__ == "__main__":
    main()
