import QtQuick
import QtQuick.Layouts

// Skills of DevOS Agent: reusable procedures it loads when a task needs them, including the
// ones it writes itself after finishing complex work. "Use" starts a task with a skill.
Item {
    id: root
    required property var client
    signal useSkill(string name)
    property string filter: ""
    Component.onCompleted: client.loadSkills()

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            Text { text: "Skills"; color: Theme.text; font.pixelSize: 14; font.weight: Font.DemiBold }
            Text { text: root.client.skills.count + " installed"; color: Theme.faint; font.pixelSize: 11 }
            Item { Layout.fillWidth: true }
            DButton { label: "Refresh"; small: true; variant: "ghost"; onClicked: root.client.loadSkills() }
        }
        Text {
            Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Theme.muted; font.pixelSize: 12
            text: "The agent picks the right skill on its own and saves new ones from work it finishes. "
                  + "Ask it to “make a skill for …” to teach it a workflow."
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
                       text: "Search skills"; color: Theme.faint; font.pixelSize: 13 }
            }
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 6
            model: root.client.skills
            section.property: "category"
            section.delegate: Text {
                required property string section
                text: section.replace(/-/g, " ")
                color: Theme.teal; font.pixelSize: 11; font.weight: Font.DemiBold
                topPadding: 8; bottomPadding: 2
                font.capitalization: Font.AllUppercase
            }
            delegate: Rectangle {
                id: sk
                required property string name
                required property string description
                required property string category
                readonly property bool match: root.filter === "" || name.toLowerCase().includes(root.filter)
                                              || description.toLowerCase().includes(root.filter)
                visible: match
                width: list.width
                height: match ? skRow.implicitHeight + 16 : 0
                radius: Theme.radiusSmall
                color: hov.containsMouse ? Theme.layer2 : Theme.surface
                border.color: Theme.border
                MouseArea { id: hov; anchors.fill: parent; hoverEnabled: true }
                RowLayout {
                    id: skRow
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 12; anchors.rightMargin: 8
                    spacing: 8
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Text { text: sk.name; color: Theme.text; font.family: Theme.mono; font.pixelSize: 12
                               font.weight: Font.DemiBold; elide: Text.ElideRight; Layout.fillWidth: true }
                        Text { text: sk.description; color: Theme.muted; font.pixelSize: 11; wrapMode: Text.WordWrap
                               maximumLineCount: 2; elide: Text.ElideRight; Layout.fillWidth: true }
                    }
                    DButton { label: "Use"; small: true; variant: "ghost"; onClicked: root.useSkill(sk.name) }
                }
            }
        }
    }
}
