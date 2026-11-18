import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

// The DevOS Agent panel (SRS §20): a layer-shell sidebar on the right.
// Conversation with the agent (live tool steps, thinking, subagents, approvals), and its
// history, schedules, skills, memory and settings (providers, approvals, abilities).
PanelWindow {
    id: win
    required property var client
    property bool open: false
    // chat | history | jobs | skills | memory | settings
    property string view: "chat"
    property bool pickerOpen: false
    readonly property bool showHistory: view === "history"
    readonly property bool showJobs: view === "jobs"
    function go(v) {
        view = v;
        pickerOpen = false;
        if (v === "history") client.loadConversations();
        else if (v === "jobs") client.loadJobs();
        else if (v === "chat") input.forceActiveFocus();
    }

    visible: open
    anchors { top: true; right: true; bottom: true }
    margins { top: 8; right: 8; bottom: 8 }
    implicitWidth: 560
    exclusiveZone: 0
    color: "transparent"
    WlrLayershell.namespace: "devos-ai"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    onOpenChanged: if (open) { client.ensureConnected(); input.forceActiveFocus(); }

    // Put text in the input box (e.g. the focused window as context) and focus it.
    function prefill(text) {
        input.text = text;
        input.cursorPosition = input.text.length;
        input.forceActiveFocus();
    }

    function denyPending() {
        for (let i = client.items.count - 1; i >= 0; i--) {
            const it = client.items.get(i);
            if (it.kind === "approval" && !it.resolved) { client.respond(it.approvalId, "deny"); return true; }
        }
        return false;
    }

    Rectangle {
        anchors.fill: parent
        radius: 18
        color: Theme.bg
        border.color: Theme.border

        FocusScope {
            anchors.fill: parent
            focus: true
            // Esc denies a pending approval, otherwise closes the panel (UX-001).
            Keys.onEscapePressed: {
                if (win.pickerOpen) { win.pickerOpen = false; return; }
                if (!win.denyPending()) win.open = false;
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                // ---------------------------------------------------- header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Rectangle {
                        width: 30; height: 30; radius: 9
                        color: "#0e1521"
                        border.width: 1.5
                        border.color: Theme.teal
                        Text {
                            anchors.centerIn: parent
                            text: "›_"
                            color: Theme.teal
                            font.family: Theme.mono
                            font.pixelSize: 13
                            font.weight: Font.Bold
                        }
                    }
                    ColumnLayout {
                        spacing: 0
                        Text {
                            text: "DevOS Agent"
                            color: Theme.text
                            font.family: Theme.display
                            font.pixelSize: 17
                            font.weight: Font.Bold
                        }
                        Text {
                            text: (win.client.providerName(win.client.activeProvider) || "No model")
                                  + (win.client.activeModel ? " · " + win.client.activeModel : "")
                                  + (win.client.effort ? " · " + win.client.effort : "") + "  ▾"
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: { win.pickerOpen = !win.pickerOpen; if (win.pickerOpen) win.client.loadProviders(); } }
                            color: Theme.faint
                            font.pixelSize: 11
                        }
                    }
                    Item { Layout.fillWidth: true }
                    // Status (SRS §20.3) and the external-provider indicator (PRIV-012)
                    Rectangle {
                        implicitHeight: 24
                        implicitWidth: statusRow.implicitWidth + 16
                        radius: 12
                        color: Theme.surface
                        border.color: Theme.border
                        RowLayout {
                            id: statusRow
                            anchors.centerIn: parent
                            spacing: 6
                            Rectangle {
                                width: 7; height: 7; radius: 4
                                color: ({ off: Theme.faint, idle: Theme.success, thinking: Theme.violet,
                                          running: Theme.teal, waiting: Theme.warning, error: Theme.danger })[win.client.status]
                                SequentialAnimation on opacity {
                                    running: win.client.status === "thinking" || win.client.status === "running"
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 0.3; duration: 500 }
                                    NumberAnimation { to: 1; duration: 500 }
                                }
                            }
                            Text {
                                text: ({ off: "off", idle: "ready", thinking: "working", running: "running a tool",
                                         waiting: "needs approval", error: "error" })[win.client.status]
                                color: Theme.muted
                                font.pixelSize: 11
                            }
                        }
                    }
                    DButton { label: "New"; variant: "ghost"; small: true
                              onClicked: { win.client.newConversation(); win.go("chat"); } }
                    DButton { label: "✕"; variant: "ghost"; small: true; onClicked: win.open = false }
                }

                // ---------------------------------------------------- navigation
                Row {
                    Layout.fillWidth: true
                    spacing: 4
                    Repeater {
                        model: [{ v: "chat", l: "Chat" }, { v: "history", l: "History" }, { v: "jobs", l: "Schedules" },
                                { v: "skills", l: "Skills" }, { v: "memory", l: "Memory" }, { v: "settings", l: "Settings" }]
                        Rectangle {
                            required property var modelData
                            width: navTxt.implicitWidth + 20; height: 28; radius: 8
                            color: win.view === modelData.v ? Theme.surfaceHigh : navHov.containsMouse ? Theme.surface : "transparent"
                            border.color: win.view === modelData.v ? Theme.teal : "transparent"
                            Text { id: navTxt; anchors.centerIn: parent; text: parent.modelData.l
                                   color: win.view === parent.modelData.v ? Theme.text : Theme.muted
                                   font.pixelSize: 12; font.weight: Font.DemiBold }
                            MouseArea { id: navHov; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: win.go(parent.modelData.v) }
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

                // ------------------------------------------------------ body
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Text {
                        visible: !win.client.connected
                        anchors.centerIn: parent
                        width: parent.width - 40
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: "Starting DevOS Agent…\nIf this persists: systemctl --user restart devos-agent"
                        color: Theme.muted
                        font.pixelSize: 13
                    }

                    KeySetup {
                        visible: win.client.connected && win.client.keyStatus === "missing" && win.view === "chat"
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        client: win.client
                        onMoreProviders: win.go("settings")
                    }

                    ListView {
                        id: history
                        visible: win.client.connected && win.client.keyStatus !== "missing" && win.view === "history"
                        anchors.fill: parent
                        clip: true
                        spacing: 6
                        model: win.client.conversations
                        delegate: Rectangle {
                            required property string id
                            required property string title
                            required property string mode
                            required property string workspace
                            width: history.width
                            height: 52
                            radius: 10
                            color: hov.containsMouse ? Theme.surfaceHigh : Theme.surface
                            MouseArea {
                                id: hov
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: { win.client.openConversation(parent.id); win.go("chat"); }
                            }
                            ColumnLayout {
                                anchors.left: parent.left
                                anchors.right: del.left
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 12
                                spacing: 2
                                Text { text: title; color: Theme.text; font.pixelSize: 13; elide: Text.ElideRight
                                       Layout.fillWidth: true }
                                Text { text: mode + (workspace ? " · " + workspace : ""); color: Theme.faint
                                       font.pixelSize: 11; elide: Text.ElideMiddle; Layout.fillWidth: true }
                            }
                            DButton { id: del; anchors.right: parent.right; anchors.rightMargin: 10
                                      anchors.verticalCenter: parent.verticalCenter
                                      label: "Delete"; variant: "danger"; small: true
                                      onClicked: win.client.deleteConversation(parent.id) }
                        }
                    }

                    JobsView {
                        visible: win.client.connected && win.client.keyStatus !== "missing" && win.view === "jobs"
                        anchors.fill: parent
                        client: win.client
                    }
                    Loader {
                        active: win.view === "skills"
                        visible: active && win.client.connected
                        anchors.fill: parent
                        sourceComponent: SkillsView {
                            client: win.client
                            onUseSkill: name => { win.go("chat"); win.prefill("Use the " + name + " skill to "); }
                        }
                    }
                    Loader {
                        active: win.view === "memory"
                        visible: active
                        anchors.fill: parent
                        sourceComponent: MemoryView { client: win.client }
                    }
                    Loader {
                        active: win.view === "settings"
                        visible: active && win.client.connected
                        anchors.fill: parent
                        sourceComponent: SettingsView { client: win.client }
                    }

                    ListView {
                        id: chat
                        visible: win.client.connected && win.client.keyStatus !== "missing" && win.view === "chat"
                        anchors.fill: parent
                        clip: true
                        spacing: 0   // rows carry their own bottom gap; collapsed rows take none
                        model: win.client.items
                        delegate: ChatItem { client: win.client }
                        onCountChanged: Qt.callLater(() => chat.positionViewAtEnd())
                        onContentHeightChanged: if (atYEnd || moving === false) Qt.callLater(() => chat.positionViewAtEnd())

                        Text {
                            visible: chat.count === 0
                            anchors.centerIn: parent
                            width: parent.width - 60
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            text: "Ask a question or give DevOS Agent a task: on your projects, your files or the system itself, "
                                  + "now or on a schedule (\"every morning at 9…\"). Anything risky waits for your approval."
                            color: Theme.faint
                            font.pixelSize: 13
                            lineHeight: 1.3
                        }
                    }
                }

                // ---------------------------------------------------- footer
                ColumnLayout {
                    visible: win.client.connected && win.client.keyStatus !== "missing" && win.view === "chat"
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: Math.min(Math.max(input.implicitHeight + 24, 48), 160)
                        radius: 14
                        color: Theme.surface
                        border.color: input.activeFocus ? Theme.teal : Theme.border
                        Flickable {
                            id: inputFlick
                            anchors.left: parent.left
                            anchors.right: sendBtn.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.margins: 12
                            contentHeight: input.implicitHeight
                            clip: true
                            TextEdit {
                                id: input
                                width: inputFlick.width
                                wrapMode: TextEdit.Wrap
                                color: Theme.text
                                font.pixelSize: 14
                                focus: true
                                Text { visible: input.text === "" && !input.preeditText
                                       text: "Ask DevOS Agent or give it a task…"
                                       color: Theme.faint; font.pixelSize: 14 }
                                // Enter sends, Shift+Enter inserts a newline.
                                Keys.onReturnPressed: event => {
                                    if (event.modifiers & Qt.ShiftModifier) { event.accepted = false; return; }
                                    if (win.client.runningTask === "") { win.client.send(input.text); input.text = ""; }
                                }
                            }
                        }
                        DButton {
                            id: sendBtn
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 8
                            small: true
                            label: win.client.runningTask !== "" ? "Stop" : "Send"
                            variant: win.client.runningTask !== "" ? "danger" : "primary"
                            onClicked: {
                                if (win.client.runningTask !== "") { win.client.cancel(); return; }
                                win.client.send(input.text);
                                input.text = "";
                            }
                        }
                    }
                }
            }
        }

        // ------------------------------------------------ model picker (header chip)
        Rectangle {
            id: picker
            visible: win.pickerOpen
            z: 10
            anchors.top: parent.top
            anchors.topMargin: 58
            anchors.left: parent.left
            anchors.leftMargin: 16
            width: parent.width - 32
            height: Math.min(pickCol.implicitHeight + 24, parent.height - 90)
            radius: 14
            color: Theme.surface
            border.color: Theme.teal

            Flickable {
                anchors.fill: parent
                anchors.margins: 12
                contentHeight: pickCol.implicitHeight
                clip: true
                ColumnLayout {
                    id: pickCol
                    width: parent.width
                    spacing: 8

                    Text { text: "Model for this conversation"; color: Theme.text; font.pixelSize: 13; font.weight: Font.DemiBold }
                    Rectangle {
                        Layout.fillWidth: true; implicitHeight: 30; radius: 8
                        color: win.client.runProvider === "" ? Theme.surfaceHigh : "transparent"
                        border.color: win.client.runProvider === "" ? Theme.teal : Theme.border
                        Text { anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: 10
                               text: "Default · " + win.client.providerName(win.client.provider) + " · " + win.client.model
                               color: Theme.text; font.pixelSize: 12; elide: Text.ElideRight; width: parent.width - 20 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: { win.client.useModel("", ""); win.pickerOpen = false; } }
                    }

                    Repeater {
                        model: win.client.providers
                        ColumnLayout {
                            id: prov
                            required property string slug
                            required property string name
                            required property bool connected
                            required property string models
                            required property string featured
                            readonly property var list: {
                                let f = [], m = [];
                                try { f = JSON.parse(featured); m = JSON.parse(models); } catch (e) {}
                                return (f.length ? f : m).slice(0, 10);
                            }
                            visible: connected && list.length > 0
                            Layout.fillWidth: true
                            spacing: 4
                            Text { text: prov.name; color: Theme.teal; font.pixelSize: 11; font.weight: Font.DemiBold }
                            Flow {
                                Layout.fillWidth: true
                                spacing: 5
                                Repeater {
                                    model: prov.list
                                    Rectangle {
                                        required property string modelData
                                        readonly property bool chosen: win.client.runProvider === prov.slug && win.client.runModel === modelData
                                        width: mt.implicitWidth + 16; height: 24; radius: 12
                                        color: chosen ? Theme.surfaceHigh : "transparent"
                                        border.color: chosen ? Theme.teal : Theme.border
                                        Text { id: mt; anchors.centerIn: parent; text: parent.modelData
                                               color: Theme.text; font.family: Theme.mono; font.pixelSize: 10 }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                    onClicked: { win.client.useModel(prov.slug, parent.modelData); win.pickerOpen = false; } }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }
                    Text { text: "Reasoning"; color: Theme.text; font.pixelSize: 12; font.weight: Font.DemiBold }
                    Row {
                        spacing: 5
                        Repeater {
                            model: [{ v: "", l: "Default" }, { v: "none", l: "Off" }, { v: "low", l: "Low" },
                                    { v: "medium", l: "Medium" }, { v: "high", l: "High" }]
                            Rectangle {
                                required property var modelData
                                width: et.implicitWidth + 18; height: 24; radius: 12
                                color: win.client.effort === modelData.v ? Theme.surfaceHigh : "transparent"
                                border.color: win.client.effort === modelData.v ? Theme.violet : Theme.border
                                Text { id: et; anchors.centerIn: parent; text: parent.modelData.l; color: Theme.text; font.pixelSize: 11 }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            onClicked: win.client.effort = parent.modelData.v }
                            }
                        }
                    }
                    DButton { label: "Connect more providers…"; small: true; variant: "ghost"; onClicked: win.go("settings") }
                }
            }
        }
    }
}
