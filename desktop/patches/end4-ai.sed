# DESK-021: DevOS Agent in end-4's AI sidebar. It is the first (default) model; the
# sidebar reaches the local DevOS Agent service with the per-user key from client.json.
# The agent brings its own tools, so the sidebar sends none.
/^    readonly property string apiKeyEnvVarName: "API_KEY"$/a\
\
    // DevOS: where the DevOS Agent service listens, and its per-user key.\
    property var devosAgent: ({ url: "", key: "" })\
    FileView {\
        path: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/devos/agent/client.json"\
        watchChanges: true\
        onFileChanged: reload()\
        onLoaded: { try { root.devosAgent = JSON.parse(text()); } catch (e) {} }\
    }
/^    property var models: Config.options.policies.ai === 2 ? {} : {$/a\
        "devos-agent": aiModelComponent.createObject(this, {\
            "name": "DevOS Agent",\
            "icon": "devos-symbolic",\
            "description": Translation.tr("DevOS | The system agent\\nWorks on your files, projects and the system with the model chosen in DevOS Agent. Risky actions are refused here: run those from the DevOS Agent panel (Super+A), where you can approve them."),\
            "homepage": "https://github.com/DevOS",\
            "endpoint": "http://127.0.0.1/v1/chat/completions",\
            "model": "devos-agent",\
            "requires_key": false,\
            "api_format": "openai",\
        }),
/^            if (model.requires_key) requester.environment\[`\${root.apiKeyEnvVarName}`\] = .*$/a\
            if (currentModelId === "devos-agent") { model.endpoint = root.devosAgent.url + "/v1/chat/completions"; requester.environment[`${root.apiKeyEnvVarName}`] = root.devosAgent.key ?? ""; }
s|root.tools\[model.api_format\]\[root.currentTool\], root.pendingFilePath)|(currentModelId === "devos-agent" ? undefined : root.tools[model.api_format][root.currentTool]), root.pendingFilePath)|
