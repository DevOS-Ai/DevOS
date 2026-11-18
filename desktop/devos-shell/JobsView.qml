import QtQuick
import QtQuick.Layouts

// Scheduled tasks of DevOS Agent (SRS AGENT-030): the agent runs a prompt on a schedule
// (cron expression or interval). The agent can also create them itself when asked
// ("every morning at 9, summarize…"). Risky commands are never run unattended.
Item {
    id: root
    required property var client
    property bool adding: false
    property string message: ""
    property string schedule: "0 9 * * *"

    readonly property var presets: [
        { label: "Every hour", value: "1h" },
        { label: "Daily 09:00", value: "0 9 * * *" },
        { label: "Weekdays 09:00", value: "0 9 * * 1-5" },
        { label: "Mondays 09:00", value: "0 9 * * 1" },
        { label: "Every 30 min", value: "30m" }
    ]

    function when(iso) {
        if (!iso) return "";
        const d = new Date(iso);
        return isNaN(d) ? iso : d.toLocaleString(Qt.locale(), "ddd d MMM, HH:mm");
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            Text { text: "Scheduled tasks"; color: Theme.text; font.pixelSize: 14; font.weight: Font.DemiBold }
            Item { Layout.fillWidth: true }
            DButton { label: root.adding ? "Cancel" : "New schedule"; small: true
                      variant: root.adding ? "ghost" : "primary"
                      onClicked: { root.adding = !root.adding; root.message = ""; } }
        }

        // -------------------------------------------------------------- new job
        Rectangle {
            visible: root.adding
            Layout.fillWidth: true
            implicitHeight: form.implicitHeight + 24
            radius: 12
            color: Theme.surface
            border.color: Theme.border

            ColumnLayout {
                id: form
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 12
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 34; radius: 9
                    color: Theme.bg
                    border.color: nameIn.activeFocus ? Theme.teal : Theme.border
                    TextInput {
                        id: nameIn
                        anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.text; font.pixelSize: 13; clip: true
                        Text { visible: !nameIn.text; anchors.verticalCenter: parent.verticalCenter
                               text: "Name, e.g. Morning briefing"; color: Theme.faint; font.pixelSize: 13 }
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: Math.max(promptIn.implicitHeight + 16, 70); radius: 9
                    color: Theme.bg
                    border.color: promptIn.activeFocus ? Theme.teal : Theme.border
                    TextEdit {
                        id: promptIn
                        anchors.fill: parent; anchors.margins: 8
                        wrapMode: TextEdit.Wrap
                        color: Theme.text; font.pixelSize: 13
                        Text { visible: !promptIn.text
                               text: "What should the agent do? e.g. Check my git repos in ~/src for unpushed work and notify me."
                               width: parent.width; wrapMode: Text.WordWrap
                               color: Theme.faint; font.pixelSize: 13 }
                    }
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: root.presets
                        Rectangle {
                            required property var modelData
                            width: chip.implicitWidth + 18; height: 26; radius: 13
                            color: root.schedule === modelData.value ? Theme.surfaceHigh : "transparent"
                            border.color: root.schedule === modelData.value ? Theme.teal : Theme.border
                            Text { id: chip; anchors.centerIn: parent; text: parent.modelData.label
                                   color: Theme.muted; font.pixelSize: 11 }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: { root.schedule = parent.modelData.value; schedIn.text = root.schedule; } }
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 34; radius: 9
                        color: Theme.bg
                        border.color: schedIn.activeFocus ? Theme.teal : Theme.border
                        TextInput {
                            id: schedIn
                            anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10
                            verticalAlignment: TextInput.AlignVCenter
                            text: root.schedule
                            onTextEdited: root.schedule = text
                            color: Theme.text; font.family: Theme.mono; font.pixelSize: 12; clip: true
                        }
                    }
                    DButton {
                        label: "Create"; small: true
                        onClicked: {
                            if (!promptIn.text.trim()) { root.message = "Describe what the agent should do."; return; }
                            root.message = "";
                            root.client.createJob(nameIn.text.trim() || promptIn.text.trim().slice(0, 40),
                                                  promptIn.text.trim(), root.schedule.trim(), (ok, err) => {
                                if (ok) { root.adding = false; nameIn.text = ""; promptIn.text = ""; }
                                else root.message = err;
                            });
                        }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: "Cron (minute hour day month weekday) or an interval like 30m, 2h, 1d."
                    color: Theme.faint; font.pixelSize: 11; wrapMode: Text.WordWrap
                }
                Text {
                    visible: root.message !== ""
                    Layout.fillWidth: true
                    text: root.message; color: Theme.danger; font.pixelSize: 12; wrapMode: Text.WordWrap
                }
            }
        }

        // -------------------------------------------------------------- job list
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 6
            model: root.client.jobs

            delegate: Rectangle {
                id: job
                required property string id
                required property string name
                required property string prompt
                required property string schedule
                required property bool active
                required property string nextRun
                required property string lastRun
                required property string lastStatus
                required property string lastError
                width: list.width
                implicitHeight: col.implicitHeight + 20
                radius: 10
                color: Theme.surface
                border.color: Theme.border
                opacity: active ? 1 : 0.6

                ColumnLayout {
                    id: col
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 10
                    spacing: 4
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: job.name || "Task"; color: Theme.text; font.pixelSize: 13; font.weight: Font.DemiBold
                               elide: Text.ElideRight; Layout.fillWidth: true }
                        Text { text: job.schedule; color: Theme.teal; font.family: Theme.mono; font.pixelSize: 11 }
                    }
                    Text { text: job.prompt; color: Theme.muted; font.pixelSize: 12; wrapMode: Text.WordWrap
                           maximumLineCount: 3; elide: Text.ElideRight; Layout.fillWidth: true }
                    Text {
                        Layout.fillWidth: true
                        color: job.lastError ? Theme.danger : Theme.faint
                        font.pixelSize: 11; wrapMode: Text.WordWrap
                        text: (job.active ? (job.nextRun ? "Next: " + root.when(job.nextRun) : "") : "Paused")
                              + (job.lastRun ? "  ·  Last: " + root.when(job.lastRun) + (job.lastStatus ? " (" + job.lastStatus + ")" : "") : "")
                              + (job.lastError ? "\n" + job.lastError : "")
                    }
                    RowLayout {
                        spacing: 6
                        DButton { label: "Run now"; small: true; variant: "ghost"; onClicked: root.client.jobAction(job.id, "run") }
                        DButton { label: job.active ? "Pause" : "Resume"; small: true; variant: "ghost"
                                  onClicked: root.client.jobAction(job.id, job.active ? "pause" : "resume") }
                        DButton { label: "Delete"; small: true; variant: "danger"; onClicked: root.client.jobAction(job.id, "delete") }
                    }
                }
            }

            Text {
                visible: list.count === 0 && !root.adding
                anchors.centerIn: parent
                width: parent.width - 40
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: "No scheduled tasks yet. Create one here, or just ask the agent:\n“Every weekday at 9, check the CI of my projects and tell me what failed.”"
                color: Theme.faint
                font.pixelSize: 13
                lineHeight: 1.3
            }
        }
    }
}
