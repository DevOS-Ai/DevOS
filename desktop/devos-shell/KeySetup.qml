import QtQuick
import QtQuick.Layouts

// Model provider setup for DevOS Agent, with the data notice (SRS AI-003..005, FB-004).
// The key goes to `devos-agent setup-provider` on stdin; it is checked against the provider
// and kept in the agent's private settings (~/.local/share/devos/agent/.env, mode 0600).
ColumnLayout {
    id: root
    required property var client
    spacing: 12
    property string message: ""
    property bool working: false
    property string choice: "gemini"
    signal moreProviders()
    // Panel names -> engine provider slug and key variable.
    readonly property var engineIds: ({ gemini: ["gemini", "GEMINI_API_KEY"], openrouter: ["openrouter", "OPENROUTER_API_KEY"],
                                        openai: ["openai-api", "OPENAI_API_KEY"], local: ["custom", ""] })

    readonly property var providers: ({
        gemini: { name: "Gemini", hint: "Paste your Google AI Studio API key", link: "aistudio.google.com",
                  model: "gemini-2.5-flash", who: "Google" },
        openrouter: { name: "OpenRouter", hint: "Paste your OpenRouter API key (sk-or-…)", link: "openrouter.ai/keys",
                      model: "google/gemini-2.5-flash", who: "OpenRouter and the model's provider" },
        openai: { name: "OpenAI", hint: "Paste your OpenAI API key", link: "platform.openai.com/api-keys",
                  model: "gpt-5-mini", who: "OpenAI" },
        local: { name: "Local model", hint: "", link: "Ollama, LM Studio or any OpenAI-compatible server",
                 model: "qwen3", who: "nobody: the model runs on this computer" }
    })
    readonly property var p: providers[choice]

    Text {
        text: "Connect a model"
        color: Theme.text
        font.family: Theme.display
        font.pixelSize: 22
        font.weight: Font.Bold
    }
    Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        color: Theme.muted
        font.pixelSize: 13
        lineHeight: 1.3
        text: "DevOS Agent thinks with a language model you choose. Your key stays on this computer, "
            + "in the agent's private settings, readable only by you."
    }

    // Provider choice
    Flow {
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: ["gemini", "openrouter", "openai", "local"]
            Rectangle {
                required property string modelData
                width: lbl.implicitWidth + 22; height: 30; radius: 9
                color: root.choice === modelData ? Theme.surfaceHigh : Theme.surface
                border.color: root.choice === modelData ? Theme.teal : Theme.border
                Text { id: lbl; anchors.centerIn: parent; text: root.providers[parent.modelData].name
                       color: root.choice === parent.modelData ? Theme.text : Theme.muted
                       font.pixelSize: 12; font.weight: Font.DemiBold }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: { root.choice = parent.modelData; root.message = ""; modelInput.text = ""; } }
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: notice.implicitHeight + 24
        radius: 10
        color: Qt.rgba(0.98, 0.75, 0.14, 0.08)
        border.color: Qt.rgba(0.98, 0.75, 0.14, 0.3)
        Text {
            id: notice
            anchors.fill: parent
            anchors.margins: 12
            wrapMode: Text.WordWrap
            color: Theme.text
            font.pixelSize: 12
            lineHeight: 1.3
            text: root.choice === "local"
                ? "Nothing leaves this computer: messages, files and command output go only to your local model server."
                : "What is sent to " + root.p.who + ": your messages, and the file contents, command output and "
                  + "screenshots the agent reads while working on them. Nothing is sent until you send a message "
                  + "or a scheduled task runs. The provider's terms for your account apply."
        }
    }

    // API key (or the local server address)
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 40
        radius: 10
        color: Theme.surface
        border.color: keyInput.activeFocus ? Theme.teal : Theme.border
        TextInput {
            id: keyInput
            anchors.fill: parent
            anchors.margins: 12
            verticalAlignment: TextInput.AlignVCenter
            echoMode: root.choice === "local" ? TextInput.Normal : TextInput.Password
            color: Theme.text
            font.family: Theme.mono
            font.pixelSize: 13
            clip: true
            focus: true
            Text {
                visible: keyInput.text === ""
                anchors.verticalCenter: parent.verticalCenter
                text: root.choice === "local" ? "Server address, e.g. http://localhost:11434/v1" : root.p.hint
                color: Theme.faint
                font.pixelSize: 13
            }
            onAccepted: save.clicked()
        }
    }
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 36
        radius: 10
        color: Theme.surface
        border.color: modelInput.activeFocus ? Theme.teal : Theme.border
        TextInput {
            id: modelInput
            anchors.fill: parent
            anchors.margins: 11
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.text
            font.family: Theme.mono
            font.pixelSize: 12
            clip: true
            Text {
                visible: modelInput.text === ""
                anchors.verticalCenter: parent.verticalCenter
                text: "Model (default: " + root.p.model + ")"
                color: Theme.faint
                font.pixelSize: 12
            }
            onAccepted: save.clicked()
        }
    }
    RowLayout {
        DButton {
            id: save
            label: root.working ? "Testing…" : "Save and test"
            variant: "primary"
            onClicked: {
                if (root.working || keyInput.text.trim() === "") return;
                root.working = true;
                root.message = "";
                const local = root.choice === "local";
                const id = root.engineIds[root.choice];
                root.client.connectProvider(id[0], local ? "" : keyInput.text.trim(), id[1],
                                            modelInput.text.trim() || root.p.model, local ? keyInput.text.trim() : "", true, (ok, err) => {
                    root.working = false;
                    if (ok) keyInput.text = "";
                    root.message = ok ? "" : err;
                });
            }
        }
        Text {
            text: root.choice === "local" ? root.p.link : "Get a key at " + root.p.link
            color: Theme.faint
            font.pixelSize: 12
            Layout.leftMargin: 8
            Layout.fillWidth: true
            elide: Text.ElideRight
        }
    }
    DButton {
        label: "More providers: Anthropic, DeepSeek, xAI, Mistral, Hugging Face, NVIDIA… (" + Math.max(root.client.providers.count, 50) + ")"
        variant: "ghost"; small: true
        onClicked: root.moreProviders()
    }
    Text {
        visible: root.message !== ""
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: root.message
        color: Theme.danger
        font.pixelSize: 12
    }
}
