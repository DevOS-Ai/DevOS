import QtQuick
import QtQuick.Layouts

// One row of the conversation: user / model text, the model's thinking, tool activity,
// subagents, approval card (SRS PERM-003), task summary, errors.
Item {
    id: row
    required property var client
    required property int index
    required property string kind
    required property string text
    required property string tool
    required property string detail
    required property string state
    required property string approvalId
    required property string approvalKind
    required property string diff
    required property string reason
    required property bool undoable
    required property bool resolved
    required property bool allowSession
    required property string task
    required property string files
    property int width_: ListView.view ? ListView.view.width : 400

    width: width_
    // Answered approvals collapse: the tool row that follows shows the outcome.
    visible: !(kind === "approval" && resolved)
    implicitHeight: visible && loader.item ? loader.item.implicitHeight + 12 : 0

    Loader {
        id: loader
        width: parent.width
        sourceComponent: row.kind === "user" ? userC
            : row.kind === "model" ? modelC
            : row.kind === "tool" ? toolC
            : row.kind === "approval" ? approvalC
            : row.kind === "summary" ? summaryC
            : row.kind === "thinking" ? thinkingC
            : row.kind === "subagent" ? subagentC : noteC
    }

    Component {
        id: userC
        Item {
            implicitHeight: bubble.height
            Rectangle {
                id: bubble
                anchors.right: parent.right
                width: Math.min(userText.implicitWidth + 28, parent.width * 0.85)
                height: userText.implicitHeight + 20
                radius: Theme.radius
                color: Theme.m3primaryContainer
                border.color: "transparent"
                Text {
                    id: userText
                    anchors.fill: parent
                    anchors.margins: 10
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    text: row.text
                    wrapMode: Text.Wrap
                    color: Theme.m3onPrimaryContainer
                    font.family: Theme.body
                    font.pixelSize: 14
                }
            }
        }
    }

    Component {
        id: modelC
        Text {
            text: row.text + (row.state === "streaming" ? " ▍" : "")
            textFormat: Text.MarkdownText
            wrapMode: Text.Wrap
            color: Theme.text
            linkColor: Theme.m3primary
            font.family: Theme.body
            font.pixelSize: 14
            lineHeight: 1.3
            onLinkActivated: link => Qt.openUrlExternally(link)
        }
    }

    Component {
        id: toolC
        RowLayout {
            spacing: 8
            MIcon {
                Layout.alignment: Qt.AlignTop
                name: row.state === "running" ? "progress_activity" : row.state === "done" ? "check_circle"
                    : row.state === "failed" ? "error" : "block"
                size: 16
                fill: row.state === "running" ? 0 : 1
                color: row.state === "done" ? Theme.success : row.state === "running" ? Theme.m3primary : Theme.danger
                RotationAnimation on rotation {
                    running: row.state === "running"; loops: Animation.Infinite; from: 0; to: 360; duration: 1000
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text {
                    Layout.fillWidth: true
                    text: row.tool + (row.detail ? "  " + row.detail : "")
                    color: row.state === "running" ? Theme.text : Theme.muted
                    font.family: Theme.mono
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
                Text {
                    visible: (row.state === "blocked" || row.state === "failed") && row.reason !== ""
                    Layout.fillWidth: true
                    text: (row.state === "blocked" ? "Blocked: " : "") + row.reason
                    maximumLineCount: 4
                    elide: Text.ElideRight
                    wrapMode: Text.Wrap
                    color: Theme.danger
                    font.pixelSize: 12
                }
            }
        }
    }

    Component {
        id: approvalC
        Rectangle {
            implicitHeight: col.implicitHeight + 28
            radius: Theme.radius
            color: row.resolved ? Theme.surface : Theme.alpha(Theme.m3tertiary, 0.10)
            border.color: row.resolved ? Theme.border : Theme.alpha(Theme.m3tertiary, 0.55)
            opacity: row.resolved ? 0.6 : 1
            ColumnLayout {
                id: col
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 14
                spacing: 8
                RowLayout {
                    spacing: 6
                    MIcon { name: row.resolved ? "verified_user" : "gpp_maybe"; size: 18; fill: 1
                            color: row.resolved ? Theme.muted : Theme.m3tertiary }
                    Text {
                        text: row.resolved ? "Approval answered"
                            : row.approvalKind === "continue" ? "Continue the task?" : "Approval needed · " + row.tool
                        color: row.resolved ? Theme.muted : Theme.m3tertiary
                        font.family: Theme.body
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }
                }
                Rectangle {
                    visible: row.detail !== ""
                    Layout.fillWidth: true
                    implicitHeight: cmd.implicitHeight + 16
                    radius: 8
                    color: Theme.m3surfaceContainerLowest
                    Text {
                        id: cmd
                        anchors.fill: parent
                        anchors.margins: 8
                        text: row.detail
                        wrapMode: Text.WrapAnywhere
                        color: Theme.text
                        font.family: Theme.mono
                        font.pixelSize: 12
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: row.reason
                    wrapMode: Text.Wrap
                    color: Theme.muted
                    font.pixelSize: 12
                }
                // Diff preview (UX-003)
                Rectangle {
                    visible: row.diff !== "" && !row.resolved
                    Layout.fillWidth: true
                    implicitHeight: Math.min(diffCol.implicitHeight + 16, 260)
                    radius: 8
                    color: Theme.m3surfaceContainerLowest
                    clip: true
                    Flickable {
                        anchors.fill: parent
                        anchors.margins: 8
                        contentHeight: diffCol.implicitHeight
                        Column {
                            id: diffCol
                            width: parent.width
                            Repeater {
                                model: row.diff.split("\n").slice(0, 400)
                                Text {
                                    required property string modelData
                                    width: diffCol.width
                                    text: modelData
                                    elide: Text.ElideRight
                                    font.family: Theme.mono
                                    font.pixelSize: 11
                                    color: modelData.startsWith("+++") || modelData.startsWith("---") ? Theme.faint
                                         : modelData.startsWith("+") ? Theme.success
                                         : modelData.startsWith("-") ? Theme.danger
                                         : modelData.startsWith("@@") ? Theme.violet : Theme.muted
                                }
                            }
                        }
                    }
                }
                Text {
                    visible: !row.undoable && !row.resolved
                    text: "This change cannot be undone."
                    color: Theme.danger
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
                RowLayout {
                    visible: !row.resolved
                    spacing: 8
                    DButton {
                        label: row.approvalKind === "continue" ? "Continue" : "Approve once"
                        icon: "check"
                        variant: "primary"
                        small: true
                        onClicked: row.client.respond(row.approvalId, "once")
                    }
                    DButton {
                        visible: row.allowSession
                        label: "Approve for session"
                        icon: "done_all"
                        small: true
                        onClicked: row.client.respond(row.approvalId, "session")
                    }
                    DButton {
                        label: row.approvalKind === "continue" ? "Stop" : "Deny"
                        icon: "block"
                        variant: "danger"
                        small: true
                        onClicked: row.client.respond(row.approvalId, "deny")
                    }
                }
            }
        }
    }

    Component {
        id: summaryC
        Rectangle {
            implicitHeight: sum.implicitHeight + 24
            radius: Theme.radiusSmall
            color: Theme.layer1
            border.color: Theme.border
            ColumnLayout {
                id: sum
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 12
                spacing: 6
                Text {
                    text: "Task " + row.state
                    color: row.state === "completed" ? Theme.success : Theme.warning
                    font.pixelSize: 12
                    font.weight: Font.Bold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 0.8
                }
                Text {
                    visible: row.files !== ""
                    Layout.fillWidth: true
                    text: "Changed: " + row.files
                    wrapMode: Text.Wrap
                    color: Theme.text
                    font.family: Theme.mono
                    font.pixelSize: 12
                }
                Text {
                    visible: row.detail !== ""
                    Layout.fillWidth: true
                    text: row.detail
                    wrapMode: Text.Wrap
                    color: Theme.faint
                    font.pixelSize: 11
                }
                DButton {
                    visible: row.undoable
                    label: "Undo task"
                    small: true
                    onClicked: row.client.undo(row.task, false)
                }
            }
        }
    }

    // The model's reasoning: one muted line, expands on click.
    Component {
        id: thinkingC
        Rectangle {
            property bool expanded: false
            implicitHeight: thinkCol.implicitHeight + 16
            radius: Theme.radiusSmall
            color: Theme.alpha(Theme.m3tertiary, 0.07)
            border.color: Theme.alpha(Theme.m3tertiary, 0.25)
            ColumnLayout {
                id: thinkCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 8
                anchors.leftMargin: 12
                spacing: 4
                RowLayout {
                    spacing: 5
                    MIcon { name: "lightbulb"; size: 15; color: Theme.m3tertiary }
                    Text { text: "Thinking"; color: Theme.m3tertiary; font.family: Theme.body; font.pixelSize: 12
                           font.weight: Font.DemiBold }
                    MIcon { name: thinkCol.parent.expanded ? "expand_less" : "expand_more"; size: 15; color: Theme.m3tertiary }
                }
                Text {
                    Layout.fillWidth: true
                    text: row.text
                    wrapMode: Text.Wrap
                    color: Theme.muted
                    font.pixelSize: 12
                    lineHeight: 1.2
                    maximumLineCount: parent.parent.expanded ? 400 : 2
                    elide: Text.ElideRight
                }
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: parent.expanded = !parent.expanded }
        }
    }

    // A delegated subtask running in parallel (subagent).
    Component {
        id: subagentC
        Rectangle {
            implicitHeight: subCol.implicitHeight + 16
            radius: Theme.radiusSmall
            color: Theme.layer1
            border.color: row.state === "running" ? Theme.teal : Theme.border
            ColumnLayout {
                id: subCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 8
                anchors.leftMargin: 12
                spacing: 2
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    MIcon {
                        name: "account_tree"
                        size: 16
                        fill: row.state === "done" ? 1 : 0
                        color: row.state === "done" ? Theme.success : row.state === "running" ? Theme.m3primary : Theme.danger
                    }
                    Text { text: "Subagent"; color: Theme.teal; font.pixelSize: 11; font.weight: Font.DemiBold }
                    Text { Layout.fillWidth: true; text: row.text; color: Theme.text; font.pixelSize: 12
                           elide: Text.ElideRight }
                }
                Text { visible: row.detail !== ""; text: row.detail; color: Theme.faint; font.pixelSize: 11
                       Layout.leftMargin: 21 }
                Text { visible: row.reason !== "" && row.state !== "running"; Layout.fillWidth: true
                       Layout.leftMargin: 21; text: row.reason; wrapMode: Text.Wrap; maximumLineCount: 4
                       elide: Text.ElideRight; color: Theme.muted; font.pixelSize: 12 }
            }
        }
    }

    Component {
        id: noteC
        RowLayout {
            Text {
                Layout.fillWidth: true
                text: row.text
                wrapMode: Text.Wrap
                color: row.kind === "error" ? Theme.danger : Theme.muted
                font.pixelSize: 12
            }
            DButton {
                visible: row.state === "conflict"
                label: "Overwrite"
                variant: "danger"
                small: true
                onClicked: row.client.undo(row.task, true)
            }
        }
    }
}
