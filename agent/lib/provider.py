"""devos-agent setup-provider / set-option: model providers and settings of DevOS Agent.

Used by the DevOS Agent panel; every provider the engine supports can be connected.

    printf '%s' "$KEY" | devos-agent setup-provider SLUG --key-env ENV [--model M] [--default]
    devos-agent setup-provider custom --base-url http://localhost:11434/v1 --model qwen3 --default
    devos-agent setup-provider SLUG --model M --default          # switch the default model only
    devos-agent setup-provider --remove-key ENV                  # disconnect a provider
    devos-agent set-option approvals.mode manual                 # allow-listed settings only

Keys arrive on stdin (never on the command line), are checked against the provider when
DevOS knows how, and are written to the agent's private .env (0600). The agent service
restarts so the engine picks them up. Prints one JSON line: {"ok": true, ...} or
{"ok": false, "error": "..."}.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

SLUG = re.compile(r"^[a-z0-9][a-z0-9._-]{1,63}$")
ENV = re.compile(r"^[A-Z][A-Z0-9_]{2,63}$")
# Keys that live in .env but are not provider keys must never be touched from the panel.
PROTECTED_ENV = re.compile(r"^(API_SERVER_|HERMES_)")

# Providers DevOS can check before saving (others are checked by the engine on first use).
CHECKS = {
    "gemini": ("https://generativelanguage.googleapis.com/v1beta/models", "goog"),
    "openrouter": ("https://openrouter.ai/api/v1/key", "bearer"),
    "openai-api": ("https://api.openai.com/v1/models", "bearer"),
    "anthropic": ("https://api.anthropic.com/v1/models", "anthropic"),
    "deepseek": ("https://api.deepseek.com/models", "bearer"),
    "xai": ("https://api.x.ai/v1/models", "bearer"),
}
# Key variables the engine reads but its catalog does not always name.
DEFAULT_KEY_ENV = {"openrouter": "OPENROUTER_API_KEY", "gemini": "GEMINI_API_KEY",
                   "anthropic": "ANTHROPIC_API_KEY", "openai-api": "OPENAI_API_KEY"}
# Settings the panel may change.
OPTIONS = {
    "approvals.mode": {"smart", "manual"},
    "agent.reasoning_effort": {"none", "minimal", "low", "medium", "high", "xhigh"},
}


def out(**fields) -> None:
    print(json.dumps(fields))
    sys.exit(0 if fields.get("ok") else 1)


def check(slug: str, key: str, base_url: str | None) -> str | None:
    if slug == "custom":
        url, auth = (base_url or "").rstrip("/") + "/models", "bearer"
    elif slug in CHECKS:
        url, auth = CHECKS[slug]
    else:
        return None
    req = urllib.request.Request(url, headers={"User-Agent": "DevOS-Agent"})
    if auth == "goog":
        req.add_header("x-goog-api-key", key)
    elif auth == "anthropic":
        req.add_header("x-api-key", key)
        req.add_header("anthropic-version", "2023-06-01")
    elif key:
        req.add_header("Authorization", f"Bearer {key}")
    try:
        with urllib.request.urlopen(req, timeout=20):
            return None
    except urllib.error.HTTPError as e:
        return "the provider rejected this key" if e.code in (400, 401, 403) else f"provider answered HTTP {e.code}"
    except (urllib.error.URLError, TimeoutError, OSError) as e:
        return f"cannot reach {url.split('/')[2] if '//' in url else url} ({getattr(e, 'reason', e)})"


def env_path() -> Path:
    return Path(os.environ["HERMES_HOME"]) / ".env"


def set_env(name: str, value: str | None) -> None:
    path = env_path()
    lines = [l for l in path.read_text().splitlines() if not l.startswith(name + "=")] if path.exists() else []
    if value is not None:
        lines.append(f"{name}={value}")
    tmp = path.with_suffix(".tmp")
    tmp.write_text("\n".join(lines) + "\n")
    os.chmod(tmp, 0o600)
    tmp.replace(path)


def engine(*args: str) -> None:
    p = subprocess.run(["/usr/bin/devos-agent", *args], capture_output=True, text=True, timeout=120)
    if p.returncode != 0:
        out(ok=False, error=(p.stderr or p.stdout).strip()[-500:] or f"devos-agent {args[0]} failed")


def restart() -> None:
    # The engine reads keys at start; harmless when the service is not running.
    subprocess.run(["systemctl", "--user", "try-restart", "devos-agent.service"], capture_output=True, timeout=60)


def setup_provider(argv: list[str]) -> None:
    ap = argparse.ArgumentParser(prog="devos-agent setup-provider")
    ap.add_argument("provider", nargs="?")
    ap.add_argument("--key-env")
    ap.add_argument("--model")
    ap.add_argument("--base-url")
    ap.add_argument("--default", action="store_true", help="make it the default provider and model")
    ap.add_argument("--no-check", action="store_true")
    ap.add_argument("--remove-key", metavar="ENV")
    a = ap.parse_args(argv)

    if a.remove_key:
        if not ENV.fullmatch(a.remove_key) or PROTECTED_ENV.match(a.remove_key):
            out(ok=False, error="not a provider key variable")
        set_env(a.remove_key, None)
        restart()
        out(ok=True, removed=a.remove_key)

    slug = (a.provider or "").strip()
    if not SLUG.fullmatch(slug):
        out(ok=False, error="unknown provider")
    key = "" if sys.stdin.isatty() else sys.stdin.read().strip()
    key_env = a.key_env or DEFAULT_KEY_ENV.get(slug, "")
    if key:
        if not ENV.fullmatch(key_env) or PROTECTED_ENV.match(key_env):
            out(ok=False, error="this provider does not take an API key here")
        if "\n" in key or len(key) > 4096:
            out(ok=False, error="that does not look like an API key")
    if slug == "custom" and not a.base_url:
        out(ok=False, error="a custom or local model needs its server address")
    if a.base_url and not re.match(r"^https?://[^\s]+$", a.base_url):
        out(ok=False, error="the server address must start with http:// or https://")
    if not a.no_check and (key or slug == "custom"):
        err = check(slug, key, a.base_url)
        if err:
            out(ok=False, error=err)

    if key:
        set_env(key_env, key)
    if a.default:
        engine("config", "set", "model.provider", slug)
        if a.model:
            engine("config", "set", "model.default", a.model.strip())
        if slug == "custom" or a.base_url:
            engine("config", "set", "model.base_url", a.base_url or "")
    restart()
    out(ok=True, provider=slug, model=a.model or "", default=a.default)


def set_option(argv: list[str]) -> None:
    if len(argv) != 2 or argv[0] not in OPTIONS or argv[1] not in OPTIONS[argv[0]]:
        out(ok=False, error="unsupported setting")
    engine("config", "set", argv[0], argv[1])
    out(ok=True, key=argv[0], value=argv[1])


def main() -> None:
    cmd, argv = sys.argv[1], sys.argv[2:]
    if cmd == "setup-provider":
        setup_provider(argv)
    elif cmd == "set-option":
        set_option(argv)
    else:
        out(ok=False, error=f"unknown command {cmd}")


if __name__ == "__main__":
    main()
