import QtQuick
import QtQuick.Layouts
import Quickshell

// DevOS Agent settings (SRS AGENT-025): every model provider the engine supports, with
// connect / default / disconnect; approvals; reasoning; and what the agent can do.
Flickable {
    id: root
    required property var client
    property string filter: ""
    property string open_: ""          // slug of the expanded provider card
    property string message: ""
    property bool busy: false

    contentHeight: col.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    Component.onCompleted: { client.loadProviders(); client.loadToolsets(); }

    function models(json) { try { return JSON.parse(json); } catch (e) { return []; } }
    function oauth(t) { return t && t !== "api_key" && t !== ""; }

    ColumnLayout {
        id: col
        width: root.width
        spacing: 12

        // ------------------------------------------------------------ providers
        RowLayout {
            Layout.fillWidth: true
            Text { text: "Model providers"; color: Theme.text; font.pixelSize: 14; font.weight: Font.DemiBold }
            Text { text: root.client.providers.count + " available"; color: Theme.faint; font.pixelSize: 11 }
            Item { Layout.fillWidth: true }
            DButton { label: "Refresh"; small: true; variant: "ghost"; onClicked: root.client.loadProviders() }
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 34; radius: Theme.radiusSmall
            color: Theme.layer1
            border.color: search.activeFocus ? Theme.teal : Theme.border
            TextInput {
                id: search
                anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.text; font.pixelSize: 13; clip: true
                onTextEdited: root.filter = text.toLowerCase()
                Text { visible: !search.text; anchors.verticalCenter: parent.verticalCenter
                       text: "Search providers: Anthropic, OpenAI, Gemini, DeepSeek, Ollama…"
                       color: Theme.faint; font.pixelSize: 13 }
            }
        }

        Repeater {
            model: root.client.providers
            delegate: Rectangle {
                id: card
                required property string slug
                required property string name
                required property bool current
                required property bool connected
                required property string authType
                required property string keyEnv
                required property string warning
                required property string models
                required property string featured
                required property int total
                readonly property bool expanded: root.open_ === slug
                readonly property var modelList: root.models(featured).length ? root.models(featured) : root.models(models)
                visible: root.filter === "" || name.toLowerCase().includes(root.filter) || slug.includes(root.filter)
                Layout.fillWidth: true
                implicitHeight: visible ? cardCol.implicitHeight + 20 : 0
                radius: Theme.radiusSmall
                color: expanded ? Theme.layer2 : Theme.surface
                border.color: current ? Theme.teal : connected ? Theme.alpha(Theme.success, 0.45) : Theme.border

                ColumnLayout {
                    id: cardCol
                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                    anchors.margins: 10
                    spacing: 8

                    Item {
                        Layout.fillWidth: true
                        implicitHeight: head.implicitHeight
                        RowLayout {
                            id: head
                            anchors.left: parent.left; anchors.right: parent.right
                            spacing: 8
                            Rectangle { width: 8; height: 8; radius: 4
                                        color: card.connected ? Theme.success : Theme.faint }
                            Text { text: card.name; color: Theme.text; font.pixelSize: 13; font.weight: Font.DemiBold }
                            Text { visible: card.current; text: "default"; color: Theme.teal; font.pixelSize: 11 }
                            Text { visible: card.total > 0; text: card.total + " models"; color: Theme.faint; font.pixelSize: 11 }
                            Item { Layout.fillWidth: true }
                            Text { text: card.expanded ? "▾" : "▸"; color: Theme.muted; font.pixelSize: 12 }
                        }
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: { root.open_ = card.expanded ? "" : card.slug; root.message = ""; }
                        }
                    }

                    // ---- expanded: connect / default / disconnect
                    ColumnLayout {
                        visible: card.expanded
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            visible: root.oauth(card.authType)
                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                            color: Theme.muted; font.pixelSize: 12
                            text: "This provider signs in through its own login (" + card.authType.replace(/_/g, " ")
                                  + "). Open a terminal sign-in, then come back and press Refresh."
                        }
                        DButton {
                            visible: root.oauth(card.authType) && !card.connected
                            label: "Sign in…"; small: true
                            // The engine's interactive model/provider setup, in a terminal.
                            onClicked: Quickshell.execDetached(["kitty", "--title", "DevOS Agent sign-in",
                                                                "devos-agent", "model"])
                        }

                        Rectangle {
                            visible: !root.oauth(card.authType)
                            Layout.fillWidth: true; implicitHeight: 34; radius: Theme.radiusSmall
                            color: Theme.bg; border.color: keyIn.activeFocus ? Theme.teal : Theme.border
                            TextInput {
                                id: keyIn
                                anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10
                                verticalAlignment: TextInput.AlignVCenter
                                echoMode: card.slug === "custom" ? TextInput.Normal : TextInput.Password
                                color: Theme.text; font.family: Theme.mono; font.pixelSize: 12; clip: true
                                Text { visible: !keyIn.text; anchors.verticalCenter: parent.verticalCenter
                                       color: Theme.faint; font.pixelSize: 12
                                       text: card.slug === "custom" ? "Server address, e.g. http://localhost:11434/v1"
                                             : card.connected ? "Key saved · paste a new one to replace it"
                                             : "API key" + (card.keyEnv ? " (" + card.keyEnv + ")" : "") }
                            }
                        }
                        Rectangle {
                            Layout.fillWidth: true; implicitHeight: 34; radius: Theme.radiusSmall
                            color: Theme.bg; border.color: modelIn.activeFocus ? Theme.teal : Theme.border
                            TextInput {
                                id: modelIn
                                anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10
                                verticalAlignment: TextInput.AlignVCenter
                                color: Theme.text; font.family: Theme.mono; font.pixelSize: 12; clip: true
                                Text { visible: !modelIn.text; anchors.verticalCenter: parent.verticalCenter
                                       color: Theme.faint; font.pixelSize: 12
                                       text: "Model" + (card.modelList.length ? " (e.g. " + card.modelList[0] + ")" : "") }
                            }
                        }
                        Flow {
                            visible: card.modelList.length > 0
                            Layout.fillWidth: true
                            spacing: 5
                            Repeater {
                                model: card.modelList.slice(0, 12)
                                Rectangle {
                                    required property string modelData
                                    width: mtxt.implicitWidth + 14; height: 22; radius: Theme.radiusSmall
                                    color: modelIn.text === modelData ? Theme.surface : "transparent"
                                    border.color: modelIn.text === modelData ? Theme.teal : Theme.border
                                    Text { id: mtxt; anchors.centerIn: parent; text: parent.modelData
                                           color: Theme.muted; font.family: Theme.mono; font.pixelSize: 10 }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                onClicked: modelIn.text = parent.modelData }
                                }
                            }
                        }
                        RowLayout {
                            spacing: 6
                            DButton {
                                visible: !root.oauth(card.authType)
                                label: root.busy ? "Checking…" : card.connected ? "Save" : "Connect"
                                small: true
                                onClicked: {
                                    if (root.busy) return;
                                    const local = card.slug === "custom";
                                    const value = keyIn.text.trim();
                                    if (!value && !card.connected) { root.message = local ? "Enter the server address." : "Paste the API key."; return; }
                                    root.busy = true; root.message = "";
                                    root.client.connectProvider(card.slug, local ? "" : value, card.keyEnv, modelIn.text.trim(),
                                                                local ? value : "", root.client.keyStatus !== "ok" || card.current || local, (ok, err) => {
                                        root.busy = false;
                                        root.message = ok ? card.name + " connected." : err;
                                        if (ok) keyIn.text = "";
                                    });
                                }
                            }
                            DButton {
                                visible: card.connected && !card.current
                                label: "Make default"; small: true; variant: "ghost"
                                onClicked: {
                                    const m = modelIn.text.trim() || (card.modelList[0] || "");
                                    if (!m) { root.message = "Choose a model first."; return; }
                                    root.client.setDefaultModel(card.slug, m, (ok, err) =>
                                        root.message = ok ? card.name + " · " + m + " is now the default." : err);
                                }
                            }
                            DButton {
                                visible: card.connected && modelIn.text.trim() !== ""
                                label: "Use in this chat"; small: true; variant: "ghost"
                                onClicked: { root.client.useModel(card.slug, modelIn.text.trim());
                                             root.message = "This conversation now uses " + modelIn.text.trim() + "."; }
                            }
                            DButton {
                                visible: card.connected && card.keyEnv !== "" && !root.oauth(card.authType)
                                label: "Disconnect"; small: true; variant: "danger"
                                onClicked: root.client.disconnectProvider(card.keyEnv, (ok, err) =>
                                    root.message = ok ? card.name + " disconnected." : err)
                            }
                        }
                        Text {
                            visible: root.message !== ""
                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                            text: root.message; font.pixelSize: 12
                            color: /connected|default|uses|disconnected/.test(root.message) ? Theme.success : Theme.danger
                        }
                    }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border; Layout.topMargin: 6 }

        // ------------------------------------------------------------ approvals
        Text { text: "Approvals"; color: Theme.text; font.pixelSize: 14; font.weight: Font.DemiBold }
        Text {
            Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Theme.muted; font.pixelSize: 12
            text: "System tools that change something always ask. For terminal commands: Smart asks only for risky ones "
                  + "(a safety model screens them); Always asks for every flagged command."
        }
        Row {
            spacing: 6
            Repeater {
                model: [{ v: "smart", l: "Smart" }, { v: "manual", l: "Always ask" }]
                Rectangle {
                    required property var modelData
                    width: atxt.implicitWidth + 24; height: 28; radius: Theme.radiusSmall
                    color: root.client.approvalsMode === modelData.v ? Theme.layer2 : Theme.surface
                    border.color: root.client.approvalsMode === modelData.v ? Theme.teal : Theme.border
                    Text { id: atxt; anchors.centerIn: parent; text: parent.modelData.l; color: Theme.text; font.pixelSize: 12 }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: root.client.setOption("approvals.mode", parent.modelData.v, null) }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border; Layout.topMargin: 6 }

        // ------------------------------------------------------------ abilities
        Text { text: "What DevOS Agent can do"; color: Theme.text; font.pixelSize: 14; font.weight: Font.DemiBold }
        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 6
            rowSpacing: 6
            Repeater {
                model: root.client.toolsets
                Rectangle {
                    required property string label
                    required property string description
                    required property bool active
                    required property bool configured
                    required property int count
                    Layout.fillWidth: true
                    implicitHeight: tcol.implicitHeight + 14
                    radius: Theme.radiusSmall
                    color: Theme.layer1
                    border.color: Theme.border
                    opacity: active ? 1 : 0.5
                    ColumnLayout {
                        id: tcol
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                        anchors.margins: 7; anchors.leftMargin: 10
                        spacing: 1
                        RowLayout {
                            Text { text: label; color: Theme.text; font.pixelSize: 12; font.weight: Font.DemiBold
                                   elide: Text.ElideRight; Layout.fillWidth: true }
                            Text { text: !active ? "off" : !configured ? "needs setup" : count + ""
                                   color: !configured ? Theme.warning : Theme.faint; font.pixelSize: 10 }
                        }
                        Text { text: description; color: Theme.faint; font.pixelSize: 10; elide: Text.ElideRight
                               Layout.fillWidth: true }
                    }
                }
            }
        }
        Item { implicitHeight: 8 }
    }
}
