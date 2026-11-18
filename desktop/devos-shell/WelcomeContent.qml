import QtQuick
import QtQuick.Layouts

// Welcome content (SRS §7.2). Hosted by Welcome.qml; `host` owns state and actions.
Item {
    id: content
    required property var host
    readonly property var win: host

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 36
        spacing: 18

        RowLayout {
            spacing: 14
            Rectangle {
                width: 52; height: 52; radius: 15
                color: Theme.m3primaryContainer
                border.width: 2
                border.color: Theme.teal
                Text { anchors.centerIn: parent; text: "›_"; color: Theme.teal
                       font.family: Theme.mono; font.pixelSize: 22; font.weight: Font.Bold }
            }
            ColumnLayout {
                spacing: 2
                Text { text: "Welcome to DevOS"; color: Theme.text; font.family: Theme.display
                       font.pixelSize: 28; font.weight: Font.Bold }
                Text { text: "Your development environment is ready. Two optional steps:"; color: Theme.muted
                       font.pixelSize: 14 }
            }
        }

        Text { text: "1 · Developer profiles"; color: Theme.text; font.pixelSize: 16; font.weight: Font.DemiBold }
        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: "The General profile (Git, C/C++, Python, Node/TypeScript, Go, Rust, Neovim, Podman) is installed. Add more:"
            color: Theme.muted
            font.pixelSize: 13
        }
        GridLayout {
            Layout.fillWidth: true
            columns: 2
            rowSpacing: 8
            columnSpacing: 8
            Repeater {
                model: win.profiles
                Rectangle {
                    required property var modelData
                    readonly property bool isInstalled: !!win.installed[modelData.id]
                    readonly property bool isSelected: isInstalled || !!win.selected[modelData.id]
                    Layout.fillWidth: true
                    implicitHeight: 58
                    radius: Theme.radiusSmall
                    color: isSelected ? Theme.m3secondaryContainer : Theme.surface
                    border.color: isSelected ? Theme.m3primary : Theme.border
                    MouseArea {
                        anchors.fill: parent
                        enabled: !parent.isInstalled
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const s = Object.assign({}, win.selected);
                            s[parent.modelData.id] = !s[parent.modelData.id];
                            win.selected = s;
                        }
                    }
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 2
                        Text { text: modelData.title + (isInstalled ? "  ·  installed" : "")
                               color: Theme.text; font.pixelSize: 14; font.weight: Font.DemiBold }
                        Text { text: modelData.desc; color: Theme.faint; font.pixelSize: 12
                               elide: Text.ElideRight; Layout.fillWidth: true }
                    }
                }
            }
        }
        DButton {
            label: "Install selected profiles"
            enabled: Object.keys(win.selected).some(k => win.selected[k] && !win.installed[k])
            opacity: enabled ? 1 : 0.5
            onClicked: win.installSelected()
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

        Text { text: "2 · DevOS Agent"; color: Theme.text; font.pixelSize: 16; font.weight: Font.DemiBold }
        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            // FB-003: AI is optional; DevOS is fully usable without it.
            text: win.client.keyStatus === "missing" || win.client.keyStatus === "unknown"
                ? "DevOS Agent works on your projects, files and the system itself, right away or on a schedule. "
                  + "Connect a model (Gemini, OpenRouter, OpenAI or a local model) to start. Open it any time with Super+A."
                : "DevOS Agent is ready. Open it any time with Super+A; risky actions always wait for your approval."
            color: Theme.muted
            font.pixelSize: 13
        }
        RowLayout {
            spacing: 8
            DButton { label: win.client.keyStatus === "ok" ? "Open DevOS Agent" : "Connect a model"; variant: "primary"; onClicked: { win.openAiPanel(); win.finish(); } }
            DButton { label: "Skip"; onClicked: win.finish() }
        }

        Item { Layout.fillHeight: true }
        RowLayout {
            Text { text: "Reopen this window from the launcher: DevOS Welcome"; color: Theme.faint; font.pixelSize: 12
                   Layout.fillWidth: true }
            DButton { label: "Done"; onClicked: win.finish() }
        }
    }
}
