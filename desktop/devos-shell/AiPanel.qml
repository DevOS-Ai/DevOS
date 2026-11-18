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
        radius: Theme.radiusLarge
        color: Theme.bg
        border.color: Theme.alpha(Theme.m3outlineVariant, 0.6)

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
                        width: 40; height: 40; radius: Theme.radiusSmall
                        color: Theme.m3primaryContainer
                        Text {
                            anchors.centerIn: parent
                            text: "›_"
                            color: Theme.m3onPrimaryContainer
                            font.family: Theme.mono
                            font.pixelSize: 15
                            font.weight: Font.Bold
                        }
                    }
                    ColumnLayout {
                        spacing: 3
                        Text {
                            text: "DevOS Agent"
                            color: Theme.text
                            font.family: Theme.display
                            font.pixelSize: 19
                            font.weight: Font.Medium
                        }
                        // Model chip: opens the model picker.
                        Rectangle {
                            implicitHeight: 24
                            implicitWidth: chipRow.implicitWidth + 16
                            radius: Theme.radiusFull
                            color: chipMouse.containsMouse || win.pickerOpen ? Theme.layer3 : Theme.layer2
                            Behavior on color { ColorAnimation { duration: Theme.durationFast } }
                            RowLayout {
                                id: chipRow
                                anchors.centerIn: parent
                                spacing: 4
                                MIcon { name: "neurology"; size: 14; color: Theme.m3primary }
                                Text {
                                    text: (win.client.providerName(win.client.activeProvider) || "No model")
                                          + (win.client.activeModel ? " · " + win.client.activeModel : "")
                                          + (win.client.effort ? " · " + win.client.effort : "")
                                    color: Theme.muted
                                    font.family: Theme.body
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                    Layout.maximumWidth: 260
                                }
                                MIcon { name: win.pickerOpen ? "expand_less" : "expand_more"; size: 14; color: Theme.muted }
                            }
                            MouseArea { id: chipMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: { win.pickerOpen = !win.pickerOpen; if (win.pickerOpen) win.client.loadProviders(); } }
                        }
                    }
                    Item { Layout.fillWidth: true }
                    // Status (SRS §20.3) and the external-provider indicator (PRIV-012)
                    Rectangle {
                        implicitHeight: 26
                        implicitWidth: statusRow.implicitWidth + 18
                        radius: Theme.radiusFull
                        color: win.client.status === "waiting" ? Theme.m3tertiaryContainer : Theme.layer2
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
                                color: win.client.status === "waiting" ? Theme.m3onTertiaryContainer : Theme.muted
                                font.family: Theme.body
                                font.pixelSize: 11
                            }
                        }
                    }
                    DButton { icon: "edit_square"; variant: "ghost"; small: true
                              onClicked: { win.client.newConversation(); win.go("chat"); } }
                    DButton { icon: "close"; variant: "ghost"; small: true; onClicked: win.open = false }
                }

                // ---------------------------------------------------- navigation
                Row {
                    Layout.fillWidth: true
                    spacing: 4
                    Repeater {
                        model: [{ v: "chat", l: "Chat", i: "forum" }, { v: "history", l: "History", i: "history" },
                                { v: "jobs", l: "Schedules", i: "event_repeat" }, { v: "skills", l: "Skills", i: "school" },
                                { v: "memory", l: "Memory", i: "psychology" }, { v: "settings", l: "Settings", i: "tune" }]
                        Rectangle {
                            id: tab
                            required property var modelData
                            readonly property bool selected: win.view === modelData.v
                            width: tabRow.implicitWidth + 22; height: 32; radius: Theme.radiusFull
                            color: selected ? Theme.m3secondaryContainer
                                 : navHov.containsMouse ? Theme.hover(Theme.layer0, Theme.m3onSurface) : "transparent"
                            Behavior on color { ColorAnimation { duration: Theme.durationFast } }
                            RowLayout {
                                id: tabRow
                                anchors.centerIn: parent
                                spacing: 5
                                MIcon { name: tab.modelData.i; size: 17; fill: tab.selected ? 1 : 0
                                        color: tab.selected ? Theme.m3onSecondaryContainer : Theme.muted }
                                Text { text: tab.modelData.l; font.family: Theme.body; font.pixelSize: 12
                                       font.weight: tab.selected ? Font.DemiBold : Font.Medium
                                       color: tab.selected ? Theme.m3onSecondaryContainer : Theme.muted }
                            }
                            MouseArea { id: navHov; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: win.go(tab.modelData.v) }
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
                            radius: Theme.radiusSmall
                            color: hov.containsMouse ? Theme.layer2 : Theme.surface
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
                        implicitHeight: Math.min(Math.max(input.implicitHeight + 26, 52), 170)
                        radius: Theme.radiusLarge
                        color: Theme.layer2
                        border.width: input.activeFocus ? 2 : 0
                        border.color: Theme.m3primary
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
                                font.family: Theme.body
                                font.pixelSize: 14
                                focus: true
                                Text { visible: input.text === "" && !input.preeditText
                                       text: "Ask DevOS Agent or give it a task…"
                                       color: Theme.faint; font.family: Theme.body; font.pixelSize: 14 }
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
                            icon: win.client.runningTask !== "" ? "stop" : "arrow_upward"
                            variant: win.client.runningTask !== "" ? "danger" : "primary"
                            implicitWidth: 38
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
            radius: Theme.radius
            color: Theme.layer1
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
                        color: win.client.runProvider === "" ? Theme.layer2 : "transparent"
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
                                        width: mt.implicitWidth + 16; height: 24; radius: Theme.radiusSmall
                                        color: chosen ? Theme.layer2 : "transparent"
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
                                width: et.implicitWidth + 18; height: 24; radius: Theme.radiusSmall
                                color: win.client.effort === modelData.v ? Theme.layer2 : "transparent"
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
