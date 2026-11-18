"""DevOS system tools MCP server (devos mcp): protocol, annotations, validation, audit."""

import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from devos import mcp
from devos.audit import AuditLog


def exchange(*messages, audit=None):
    out = io.StringIO()
    inp = io.StringIO("\n".join(json.dumps(m) for m in messages) + "\n")
    mcp.Server(out=out, audit=audit).serve(inp)
    return [json.loads(line) for line in out.getvalue().splitlines()]


class McpProtocolTest(unittest.TestCase):
    def test_initialize_echoes_known_version(self):
        r = exchange({"jsonrpc": "2.0", "id": 1, "method": "initialize",
                      "params": {"protocolVersion": "2025-06-18", "capabilities": {}}})[0]["result"]
        self.assertEqual(r["protocolVersion"], "2025-06-18")
        self.assertIn("tools", r["capabilities"])
        self.assertEqual(r["serverInfo"]["name"], "devos")

    def test_unknown_version_gets_latest(self):
        r = exchange({"jsonrpc": "2.0", "id": 1, "method": "initialize",
                      "params": {"protocolVersion": "1999-01-01"}})[0]["result"]
        self.assertEqual(r["protocolVersion"], mcp.PROTOCOL_VERSIONS[0])

    def test_notifications_get_no_reply(self):
        self.assertEqual(exchange({"jsonrpc": "2.0", "method": "notifications/initialized"}), [])

    def test_unknown_method(self):
        r = exchange({"jsonrpc": "2.0", "id": 7, "method": "resources/list"})[0]
        self.assertEqual(r["error"]["code"], -32601)

    def test_parse_error(self):
        out = io.StringIO()
        mcp.Server(out=out).serve(io.StringIO("not json\n"))
        self.assertEqual(json.loads(out.getvalue())["error"]["code"], -32700)

    def test_only_inspection_tools_are_read_only(self):
        tools = exchange({"jsonrpc": "2.0", "id": 2, "method": "tools/list"})[0]["result"]["tools"]
        ro = {t["name"] for t in tools if t["annotations"]["readOnlyHint"]}
        self.assertEqual(ro, {"desktop_state", "list_apps", "system_status", "wifi_networks",
                              "packages_search", "packages_installed"})
        # Everything that changes the desktop or system must be approved by the user.
        for name in ("packages_change", "launch_app", "window_action", "set_volume", "wifi_connect"):
            self.assertNotIn(name, ro)
        for t in tools:
            self.assertEqual(t["inputSchema"]["type"], "object")


class McpToolTest(unittest.TestCase):
    def call(self, name, args, audit=None):
        return exchange({"jsonrpc": "2.0", "id": 3, "method": "tools/call",
                         "params": {"name": name, "arguments": args}}, audit=audit)[0]["result"]

    def test_unknown_tool(self):
        self.assertTrue(self.call("rm_rf", {})["isError"])

    def test_package_names_validated_before_pkexec(self):
        with mock.patch("subprocess.run") as run:
            for bad in (["Bad Name"], ["../x"], [], ["a"] * 51):
                r = self.call("packages_change", {"action": "install", "packages": bad})
                self.assertTrue(r["isError"], bad)
            r = self.call("packages_change", {"action": "upgrade", "packages": ["vim"]})
            self.assertTrue(r["isError"])
            run.assert_not_called()

    def test_package_change_uses_pkexec_helper(self):
        done = mock.Mock(returncode=0, stdout="ok", stderr="")
        with mock.patch("os.access", return_value=True), mock.patch("subprocess.run", return_value=done) as run:
            r = self.call("packages_change", {"action": "install", "packages": ["htop"]})
        self.assertFalse(r["isError"])
        self.assertEqual(run.call_args[0][0], ["pkexec", mcp.PKG_HELPER, "install", "htop"])

    def test_missing_argument_is_a_tool_error(self):
        self.assertTrue(self.call("launch_app", {})["isError"])

    def test_calls_are_audited_without_secrets(self):
        with tempfile.TemporaryDirectory() as d:
            audit = AuditLog(Path(d))
            with mock.patch("devos.mcp._run", return_value="ok"):
                self.call("wifi_connect", {"ssid": "home", "password": "hunter22"}, audit=audit)
            rec = audit.tail(1)[0]
            self.assertEqual(rec["tool"], "wifi_connect")
            self.assertNotIn("hunter22", json.dumps(rec))


if __name__ == "__main__":
    unittest.main()
