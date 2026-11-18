import QtQuick
import Quickshell
import Quickshell.Io

// Client of the DevOS Agent service (SRS §14, §20): the local HTTP API on 127.0.0.1 with the
// per-user key from ~/.local/share/devos/agent/client.json. Runs stream their progress as
// Server-Sent Events: text, tool steps, approval requests, completion.
// Presentation only: the agent and the DevOS system tools decide what needs approval.
//
// Same public surface as the former devosd client, so the panel, approval cards, status pill
// and Welcome work unchanged: items, status, send(), respond(), cancel(), conversations.
Item {
    id: client

    readonly property string home: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/devos/agent"
    property string baseUrl: ""
    property string apiKey: ""
    property bool connected: false
    property string keyStatus: "unknown"       // ok | missing  (model provider configured?)
    property string provider: ""
    property string model: ""
    property bool providerBusy: false
    property string runningTask: ""            // current run id
    property bool toolRunning: false
    property string convId: ""                 // agent session id
    property int approvalCount: 0
    property string lastError: ""
    // off | idle | thinking | running | waiting | error   (SRS §20.3)
    readonly property string status: !connected || keyStatus === "missing" ? "off"
        : approvalCount > 0 ? "waiting"
        : toolRunning ? "running"
        : runningTask !== "" ? "thinking"
        : lastError !== "" ? "error" : "idle"
    // Kept for the panel's mode switch; DevOS Agent always works as an agent.
    property string mode: "agent"
    property string workspace: ""

    property ListModel items: ListModel {}
    property ListModel conversations: ListModel {}
    property ListModel jobs: ListModel {}
    // Every model provider the engine supports (52+), with connection state and models.
    property ListModel providers: ListModel {}
    property ListModel skills: ListModel {}
    property ListModel toolsets: ListModel {}
    // Per-conversation choice from the model picker; empty = the default model.
    property string runProvider: ""
    property string runModel: ""
    property string effort: ""                 // "" = default | none | low | medium | high
    property string approvalsMode: "smart"
    readonly property string activeProvider: runProvider || provider
    readonly property string activeModel: runModel || model
    function providerName(slug) {
        for (let i = 0; i < providers.count; i++) if (providers.get(i).slug === slug) return providers.get(i).name;
        return ({ gemini: "Gemini", openrouter: "OpenRouter", "openai-api": "OpenAI", anthropic: "Anthropic", custom: "Local model" })[slug] || slug;
    }

    // ------------------------------------------------------------ connection
    FileView {
        id: clientInfo
        path: client.home + "/client.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const c = JSON.parse(text());
                client.baseUrl = c.url;
                client.apiKey = c.key;
                client.ping();
            } catch (e) { client.connected = false; }
        }
        onLoadFailed: { client.connected = false; retry.start(); }
    }
    // Model provider and key status from the agent's own files (no secrets are kept here).
    FileView {
        id: configFile
        path: client.home + "/config.yaml"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: client._readConfig()
    }
    FileView {
        id: envFile
        path: client.home + "/.env"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: client._readConfig()
    }
    Timer { id: retry; interval: 3000; onTriggered: { clientInfo.reload(); } }
    Timer { id: pingTimer; interval: 15000; repeat: true; running: true; onTriggered: client.ping() }

    function _readConfig() {
        const cfg = configFile.loaded ? configFile.text() : "";
        const m = cfg.match(/^model:\s*\n((?:[ \t]+.*\n?)*)/m);
        const block = m ? m[1] : "";
        const get = k => { const r = block.match(new RegExp("^\\s+" + k + ":\\s*['\"]?([^'\"\\n#]+)", "m")); return r ? r[1].trim() : ""; };
        provider = get("provider");
        model = get("default");
        const ap = cfg.match(/^approvals:\s*\n(?:[ \t]+.*\n?)*?[ \t]+mode:\s*([a-z]+)/m);
        approvalsMode = ap ? ap[1] : "smart";
        const env = envFile.loaded ? envFile.text() : "";
        const keyVar = { gemini: "GEMINI_API_KEY", openrouter: "OPENROUTER_API_KEY", "openai-api": "OPENAI_API_KEY" }[provider];
        const hasKey = keyVar ? new RegExp("^(" + keyVar + (provider === "gemini" ? "|GOOGLE_API_KEY" : "") + ")=.+", "m").test(env) : provider !== "";
        keyStatus = hasKey ? "ok" : "missing";
    }

    function ensureConnected() { if (!connected) clientInfo.reload(); else ping(); }

    function ping() {
        if (baseUrl === "") return;
        request("GET", "/health", null, (ok, r) => {
            const was = connected;
            connected = ok;
            if (!ok) retry.start();
            else if (!was) loadProviders();
        });
    }

    // ------------------------------------------------------------ providers, models
    function loadProviders(cb) {
        request("GET", "/api/model/options", null, (ok, r) => {
            if (!ok || !r) { if (cb) cb(false); return; }
            providers.clear();
            const list = (r.providers || []).slice().sort((a, b) =>
                (b.is_current - a.is_current) || (b.authenticated - a.authenticated) || a.name.localeCompare(b.name));
            for (const p of list) providers.append({
                slug: p.slug, name: p.slug === "custom" ? "Custom or local server (OpenAI-compatible)" : (p.name || p.slug), current: !!p.is_current, connected: !!p.authenticated,
                authType: p.auth_type || "", keyEnv: p.key_env || "", warning: p.warning || "",
                models: JSON.stringify(p.models || []), featured: JSON.stringify(p.featured_models || []),
                total: p.total_models || 0, custom: !!p.is_user_defined });
            const cur = list.find(p => p.is_current);
            if (cur) keyStatus = cur.authenticated ? "ok" : "missing";
            if (cb) cb(true);
        });
    }
    // Choose the model for this conversation (the picker in the panel header).
    function useModel(slug, modelId) { runProvider = slug; runModel = modelId; }
    // Helper commands (devos-agent setup-provider / set-option), one at a time.
    property var _helperQueue: []
    property var _helperCb: null
    Process {
        id: helper
        stdinEnabled: true
        stdout: StdioCollector {
            onStreamFinished: {
                let r = { ok: false, error: "the agent helper failed" };
                try { r = JSON.parse(text.trim().split("\n").pop()); } catch (e) {}
                const cb = client._helperCb;
                client._helperCb = null;
                configFile.reload(); envFile.reload();
                if (cb) cb(r.ok, r.error || "");
                // The service restarts after a key change; refresh once it is back.
                refreshAfter.restart();
                client._nextHelper();
            }
        }
    }
    Timer { id: refreshAfter; interval: 4000; onTriggered: client.loadProviders() }
    function runHelper(argv, input, cb) {
        _helperQueue.push({ argv: argv, input: input || "", cb: cb });
        if (!helper.running) _nextHelper();
    }
    function _nextHelper() {
        if (helper.running || _helperQueue.length === 0) return;
        const job = _helperQueue.shift();
        _helperCb = job.cb;
        helper.command = ["devos-agent"].concat(job.argv);
        helper.running = true;
        helper.write(job.input);
        helper.stdinEnabled = false;   // EOF: the helper reads the key until end of input
        helper.stdinEnabled = true;
    }
    function connectProvider(slug, key, keyEnv, modelId, baseUrlArg, makeDefault, cb) {
        const argv = ["setup-provider", slug];
        if (keyEnv) argv.push("--key-env", keyEnv);
        if (modelId) argv.push("--model", modelId);
        if (baseUrlArg) argv.push("--base-url", baseUrlArg);
        if (makeDefault) argv.push("--default");
        runHelper(argv, key, cb);
    }
    function disconnectProvider(keyEnv, cb) { runHelper(["setup-provider", "--remove-key", keyEnv], "", cb); }
    function setDefaultModel(slug, modelId, cb) {
        runHelper(["setup-provider", slug, "--model", modelId, "--default"], "", (ok, err) => {
            if (ok) { runProvider = ""; runModel = ""; }
            if (cb) cb(ok, err);
        });
    }
    function setOption(key, value, cb) { runHelper(["set-option", key, value], "", cb); }

    // ------------------------------------------------------------ skills, abilities
    function loadSkills() {
        request("GET", "/v1/skills", null, (ok, r) => {
            skills.clear();
            if (ok && r) (r.data || []).forEach(k => skills.append(
                { name: k.name, description: k.description || "", category: k.category || "other" }));
        });
    }
    function loadToolsets() {
        request("GET", "/v1/toolsets", null, (ok, r) => {
            toolsets.clear();
            if (ok && r) (r.data || []).forEach(t => toolsets.append({
                name: t.name, label: (t.label || t.name).replace(/^[^A-Za-z0-9]+\s*/, ""),
                description: t.description || "", active: !!t.enabled, configured: t.configured !== false,
                count: (t.tools || []).length }));
        });
    }

    function request(method, path, body, cb) {
        const xhr = new XMLHttpRequest();
        xhr.open(method, baseUrl + path);
        xhr.setRequestHeader("Authorization", "Bearer " + apiKey);
        if (body !== null) xhr.setRequestHeader("Content-Type", "application/json");
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            let data = null;
            try { data = xhr.responseText ? JSON.parse(xhr.responseText) : null; } catch (e) {}
            const ok = xhr.status >= 200 && xhr.status < 300;
            if (cb) cb(ok, data, ok ? "" : (data && (data.error && (data.error.message || data.error))) || ("HTTP " + xhr.status));
        };
        xhr.send(body !== null ? JSON.stringify(body) : null);
    }

    // ------------------------------------------------------------ items
    function _blank() {
        return { kind: "", text: "", tool: "", detail: "", state: "", rid: "", approvalId: "", diff: "",
                 reason: "", undoable: true, resolved: false, allowSession: false, task: "", files: "",
                 approvalKind: "" };
    }
    function _add(fields) {
        const o = _blank();
        for (const k in fields) o[k] = fields[k];
        items.append(o);
    }
    function _appendModelText(t) {
        const n = items.count;
        if (n > 0 && items.get(n - 1).kind === "model" && items.get(n - 1).state === "streaming")
            items.setProperty(n - 1, "text", items.get(n - 1).text + t);
        else
            _add({ kind: "model", text: t, state: "streaming" });
    }
    function _closeModelText() {
        const n = items.count;
        if (n > 0 && items.get(n - 1).kind === "model") items.setProperty(n - 1, "state", "done");
    }
    // Tool names from the DevOS system tools arrive prefixed (mcp_devos_*): show them plainly.
    function _toolName(t) { return (t || "").replace(/^mcp_devos_/, "").replace(/^mcp_[a-z0-9]+_/, ""); }
    function _preview(p) {
        let v = p.preview;
        if (v === undefined || v === null) return "";
        if (typeof v !== "string") v = JSON.stringify(v);
        return v.length > 400 ? v.slice(0, 400) + "…" : v;
    }

    // ------------------------------------------------------------ runs
    property var _xhr: null
    property int _seen: 0
    property string _buf: ""
    property bool _streamed: false

    function _onEvent(e) {
        switch (e.event) {
        case "message.delta":
            if (e.delta) { _streamed = true; _appendModelText(e.delta); }
            break;
        case "message.interim":
            if (e.text && !e.already_streamed) { _appendModelText(e.text); _closeModelText(); }
            break;
        case "tool.started":
            _closeModelText();
            toolRunning = true;
            _add({ kind: "tool", rid: e.tool_call_id || ("t" + items.count), tool: _toolName(e.tool),
                   detail: _preview(e), state: "running" });
            break;
        case "tool.completed":
        case "tool.failed": {
            toolRunning = false;
            const st = e.error || e.event === "tool.failed" ? "failed" : "done";
            for (let i = items.count - 1; i >= 0; i--) {
                const it = items.get(i);
                if (it.kind === "tool" && it.state === "running" && it.tool === _toolName(e.tool)) {
                    items.setProperty(i, "state", st);
                    if (st === "failed") items.setProperty(i, "reason", _preview(e));
                    break;
                }
            }
            break;
        }
        case "reasoning.available":
            if (e.text) {
                _closeModelText();
                _add({ kind: "thinking", text: e.text, state: "done" });
            }
            break;
        case "subagent.start":
            _closeModelText();
            _add({ kind: "subagent", rid: e.subagent_id || ("s" + items.count), text: e.goal || e.preview || "Subtask",
                   detail: e.model || "", state: "running" });
            break;
        case "subagent.complete":
            for (let i = items.count - 1; i >= 0; i--) {
                const it = items.get(i);
                if (it.kind === "subagent" && (it.rid === e.subagent_id || it.state === "running")) {
                    items.setProperty(i, "state", e.status === "failed" || e.status === "error" ? "failed" : "done");
                    items.setProperty(i, "reason", e.summary || "");
                    if (e.tool_count !== undefined) items.setProperty(i, "detail",
                        (it.detail ? it.detail + " · " : "") + e.tool_count + " tool calls"
                        + (e.duration_seconds ? " · " + Math.round(e.duration_seconds) + " s" : ""));
                    break;
                }
            }
            break;
        case "approval.request": {
            _closeModelText();
            const choices = e.choices || ["once", "session", "deny"];
            _add({ kind: "approval", approvalId: runningTask, approvalKind: "command",
                   tool: _toolName(e.tool_name || e.tool || (e.command ? "terminal" : "")),
                   detail: e.command || _preview(e), reason: e.description || "",
                   undoable: false, allowSession: choices.indexOf("session") >= 0 });
            approvalCount++;
            break;
        }
        case "approval.responded":
            _resolveApprovals();
            break;
        case "run.completed":
            _closeModelText();
            if (!_streamed && e.output) _add({ kind: "model", text: e.output, state: "done" });
            _finishRun();
            loadConversations();
            break;
        case "run.failed":
            _closeModelText();
            lastError = e.error || "The agent stopped with an error.";
            if (/credentials|api key|authentication|provider/i.test(lastError)) keyStatus = "missing";
            _add({ kind: "error", text: lastError });
            _finishRun();
            break;
        case "run.cancelled":
        case "run.interrupted":
            _closeModelText();
            _add({ kind: "info", text: "Stopped." });
            _finishRun();
            break;
        }
    }
    function _resolveApprovals() {
        for (let i = 0; i < items.count; i++)
            if (items.get(i).kind === "approval" && !items.get(i).resolved) items.setProperty(i, "resolved", true);
        approvalCount = 0;
    }
    function _finishRun() {
        _resolveApprovals();
        runningTask = "";
        toolRunning = false;
        if (_xhr) { const x = _xhr; _xhr = null; x.abort(); }
    }

    // Parse the SSE stream incrementally (Qt delivers partial responseText while LOADING).
    function _pump(x) {
        const t = x.responseText;
        if (!t || t.length <= _seen) return;
        _buf += t.slice(_seen);
        _seen = t.length;
        let cut;
        while ((cut = _buf.indexOf("\n\n")) >= 0) {
            const frame = _buf.slice(0, cut);
            _buf = _buf.slice(cut + 2);
            let data = "";
            for (const line of frame.split("\n"))
                if (line.startsWith("data:")) data += line.slice(5).trim();
            if (data === "") continue;
            try { _onEvent(JSON.parse(data)); } catch (err) { console.warn("devos-agent event:", err); }
        }
    }

    function _subscribe(runId) {
        const x = new XMLHttpRequest();
        _xhr = x;
        _seen = 0;
        _buf = "";
        x.open("GET", baseUrl + "/v1/runs/" + runId + "/events");
        x.setRequestHeader("Authorization", "Bearer " + apiKey);
        x.setRequestHeader("Accept", "text/event-stream");
        x.onreadystatechange = () => {
            if (x !== _xhr) return;
            if (x.readyState === XMLHttpRequest.LOADING || x.readyState === XMLHttpRequest.DONE) _pump(x);
            if (x.readyState === XMLHttpRequest.DONE && runningTask === runId) {
                // Stream ended without a terminal event: ask for the final status once.
                request("GET", "/v1/runs/" + runId, null, (ok, r) => {
                    if (runningTask !== runId) return;
                    if (ok && r && r.status === "completed" && r.output && !_streamed) _add({ kind: "model", text: r.output, state: "done" });
                    else if (!ok || (r && r.status !== "completed")) _add({ kind: "error", text: "Lost the connection to the agent." });
                    _finishRun();
                });
            }
        };
        x.send();
    }

    // ------------------------------------------------------------ actions
    function send(text) {
        text = text.trim();
        if (text === "" || runningTask !== "") return;
        lastError = "";
        _add({ kind: "user", text: text });
        const start = () => {
            const body = { input: text, session_id: convId };
            if (runProvider !== "") body.provider = runProvider;
            if (runModel !== "") body.model = runModel;
            if (effort !== "") body.model_options = { reasoning: effort === "none" ? { enabled: false } : { effort: effort } };
            request("POST", "/v1/runs", body, (ok, r, err) => {
                if (!ok || !r || !r.run_id) { lastError = err; _add({ kind: "error", text: err || "The agent did not answer." }); return; }
                runningTask = r.run_id;
                _streamed = false;
                _subscribe(r.run_id);
            });
        };
        if (convId !== "") { start(); return; }
        request("POST", "/api/sessions", { title: text.slice(0, 60) }, (ok, r, err) => {
            if (!ok || !r || !r.session) { lastError = err; _add({ kind: "error", text: err || "The agent is not running." }); return; }
            convId = r.session.id;
            start();
        });
    }
    // decision: once | session | always | deny
    function respond(runId, decision) {
        request("POST", "/v1/runs/" + runId + "/approval", { choice: decision }, (ok, r, err) => {
            if (!ok) { _add({ kind: "error", text: err }); return; }
            _resolveApprovals();
        });
    }
    function cancel() {
        if (runningTask !== "") request("POST", "/v1/runs/" + runningTask + "/stop", {}, null);
    }
    function undo(task, force) {
        _add({ kind: "info", text: "Ask the agent to revert the change; it keeps track of what it did." });
    }
    function setMode(m) { mode = "agent"; }
    function newConversation() {
        if (runningTask !== "") return;
        convId = "";
        items.clear();
        approvalCount = 0;
        lastError = "";
    }
    function loadConversations() {
        request("GET", "/api/sessions?limit=50&source=api_server", null, (ok, r) => {
            conversations.clear();
            if (!ok || !r) return;
            (r.data || []).forEach(s => conversations.append({
                id: s.id, title: s.title || "Untitled", mode: "agent",
                workspace: s.last_active ? new Date(s.last_active * 1000).toLocaleString(Qt.locale(), "d MMM, HH:mm") : "" }));
        });
    }
    function openConversation(id) {
        request("GET", "/api/sessions/" + id + "/messages", null, (ok, r) => {
            if (!ok || !r) return;
            items.clear();
            convId = id;
            (r.data || []).forEach(m => {
                const c = typeof m.content === "string" ? m.content
                    : Array.isArray(m.content) ? m.content.map(p => p.text || "").join("") : "";
                if (m.role === "user" && c) _add({ kind: "user", text: c });
                else if (m.role === "assistant" && c) _add({ kind: "model", text: c, state: "done" });
                else if (m.role === "tool" && m.tool_name) _add({ kind: "tool", tool: _toolName(m.tool_name), state: "done" });
            });
        });
    }
    function deleteConversation(id) {
        request("DELETE", "/api/sessions/" + id, null, () => {
            if (id === convId) newConversation();
            loadConversations();
        });
    }

    // ------------------------------------------------------------ schedules
    function loadJobs() {
        request("GET", "/api/jobs", null, (ok, r) => {
            jobs.clear();
            if (!ok || !r) return;
            (r.jobs || []).forEach(j => jobs.append({
                id: j.id, name: j.name || "", prompt: j.prompt || "", schedule: j.schedule_display || "",
                active: j.enabled !== false, state: j.state || "", nextRun: j.next_run_at || "",
                lastRun: j.last_run_at || "", lastStatus: j.last_status || "", lastError: j.last_error || "" }));
        });
    }
    function createJob(name, prompt, schedule, cb) {
        request("POST", "/api/jobs", { name: name, prompt: prompt, schedule: schedule }, (ok, r, err) => {
            if (ok) loadJobs();
            if (cb) cb(ok, err);
        });
    }
    function jobAction(id, action) {   // pause | resume | run | delete
        const done = () => loadJobs();
        if (action === "delete") request("DELETE", "/api/jobs/" + id, null, done);
        else request("POST", "/api/jobs/" + id + "/" + action, {}, done);
    }

    function setKey(key, cb) { connectProvider("gemini", key, "GEMINI_API_KEY", "", "", true, cb); }

    function shortHome(p) {
        const h = Quickshell.env("HOME");
        return p === h ? "~" : p.startsWith(h + "/") ? "~" + p.slice(h.length) : p;
    }

    Component.onCompleted: clientInfo.reload()
}
