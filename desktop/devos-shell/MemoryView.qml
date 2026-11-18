import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// What DevOS Agent remembers across conversations: its notes about you (USER.md) and about
// your system and work (MEMORY.md). Both are plain files the agent curates; you can read
// and correct them here. The agent sees edits in its next conversation.
Item {
    id: root
    required property var client
    readonly property string dir: client.home + "/memories"
    property string tab: "user"
    property string status: ""

    FileView { id: userFile; path: root.dir + "/USER.md"; watchChanges: true; onFileChanged: reload()
               onLoaded: if (root.tab === "user" && !editor.activeFocus) editor.text = text() }
    FileView { id: memFile; path: root.dir + "/MEMORY.md"; watchChanges: true; onFileChanged: reload()
               onLoaded: if (root.tab === "memory" && !editor.activeFocus) editor.text = text() }
    readonly property var current: tab === "user" ? userFile : memFile

    function show(t) {
        tab = t;
        status = "";
        editor.text = current.loaded ? current.text() : "";
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            Text { text: "Memory"; color: Theme.text; font.pixelSize: 14; font.weight: Font.DemiBold }
            Item { Layout.fillWidth: true }
            Repeater {
                model: [{ v: "user", l: "About you" }, { v: "memory", l: "System & work" }]
                Rectangle {
                    required property var modelData
                    width: ttxt.implicitWidth + 20; height: 26; radius: 8
                    color: root.tab === modelData.v ? Theme.layer2 : "transparent"
                    border.color: root.tab === modelData.v ? Theme.teal : Theme.border
                    Text { id: ttxt; anchors.centerIn: parent; text: parent.modelData.l; color: Theme.text; font.pixelSize: 11 }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.show(parent.modelData.v) }
                }
            }
        }
        Text {
            Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Theme.muted; font.pixelSize: 12
            text: root.tab === "user"
                ? "Preferences and facts the agent keeps about you. It updates this on its own; fix anything that is wrong."
                : "Notes about this computer, your projects and how things are set up, kept between conversations."
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Theme.radiusSmall
            color: Theme.layer1
            border.color: editor.activeFocus ? Theme.teal : Theme.border
            Flickable {
                id: flick
                anchors.fill: parent
                anchors.margins: 10
                contentHeight: editor.implicitHeight
                clip: true
                TextEdit {
                    id: editor
                    width: flick.width
                    wrapMode: TextEdit.Wrap
                    color: Theme.text
                    font.family: Theme.mono
                    font.pixelSize: 12
                    selectByMouse: true
                    Text { visible: !editor.text
                           text: "Nothing yet. The agent writes here as it learns; you can also add notes yourself."
                           color: Theme.faint; font.pixelSize: 12; width: parent.width; wrapMode: Text.WordWrap }
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Text { text: root.status; color: Theme.success; font.pixelSize: 12; Layout.fillWidth: true }
            DButton { label: "Revert"; small: true; variant: "ghost"
                      onClicked: { root.current.reload(); root.show(root.tab); } }
            DButton {
                label: "Save"; small: true
                onClicked: {
                    Quickshell.execDetached(["mkdir", "-p", root.dir]);
                    root.current.setText(editor.text);
                    root.status = "Saved. The agent uses it from the next conversation.";
                }
            }
        }
    }
}
