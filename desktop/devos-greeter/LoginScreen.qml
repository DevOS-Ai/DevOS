import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd

// DevOS login screen in the design of the end-4 lock screen: the wallpaper, a large clock,
// and three Material 3 toolbars at the bottom (user, password, power).
// Authentication goes through greetd (PAM); the password is only passed to
// Greetd.respond() and never stored.
Item {
    id: root

    // Secondary monitors show only the background and clock.
    property bool showLogin: true
    readonly property string lastUserFile: "/var/cache/devos-greeter/last-user"
    property string userName: ""
    property string message: ""
    property bool messageIsError: false
    property bool busy: false
    property string pendingPassword: ""
    property string hostName: ""

    // ------------------------------------------------------------ greetd flow
    function login() {
        if (busy) return;
        const u = userField.text.trim();
        if (u === "") { userField.forceActiveFocus(); return; }
        if (!Greetd.available) { showError("Login service is not available."); return; }
        busy = true;
        message = "";
        pendingPassword = passwordField.text;
        Greetd.createSession(u);
    }
    function showError(text) {
        message = text;
        messageIsError = true;
        busy = false;
        passwordField.text = "";
        pendingPassword = "";
        passwordField.forceActiveFocus();
        shake.restart();
    }

    Connections {
        target: Greetd
        // Greetd is global; only the login card's screen talks to it.
        enabled: root.showLogin
        function onAuthMessage(text, error, responseRequired, echoResponse) {
            if (error) { showError(text); return; }
            if (responseRequired) {
                // Password prompt (hidden input). Visible prompts get the user name.
                Greetd.respond(echoResponse ? userField.text.trim() : root.pendingPassword);
                root.pendingPassword = "";
            } else if (text !== "") {
                root.message = text;
                root.messageIsError = false;
            }
        }
        function onAuthFailure(text) {
            // greetd has already ended this session; the next attempt starts a new one.
            showError("Wrong password. Try again.");
        }
        function onError(text) {
            console.warn("greetd:", text);
            if (root.messageIsError && root.message !== "") return;  // keep the clearer message
            showError("Login failed. Try again.");
        }
        function onReadyToLaunch() {
            lastUser.setText(userField.text.trim());
            root.message = "Starting DevOS…";
            root.messageIsError = false;
            leave.start();
        }
    }

    // Fade to black, then hand over to the session (greetd starts it once the
    // greeter has quit).
    SequentialAnimation {
        id: leave
        NumberAnimation { target: root; property: "opacity"; to: 0; duration: 350; easing.type: Easing.InCubic }
        ScriptAction { script: Greetd.launch(["devos-session"], [], true) }
    }
    opacity: 0
    Component.onCompleted: { opacity = 1; entered = true; }
    Behavior on opacity { enabled: !leave.running; NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }

    // ------------------------------------------------- user name, host name
    FileView {
        id: lastUser
        path: root.lastUserFile
        onLoaded: { const t = text().trim(); if (t !== "") userField.text = t; root.focusInitial(); }
        // Nobody has logged in yet: fall back to the first regular user.
        onLoadFailed: passwd.path = "/etc/passwd"
    }
    FileView {
        id: passwd
        // First regular user (uid 1000-59999) when no one has logged in yet.
        onLoaded: {
            for (const line of text().split("\n")) {
                const f = line.split(":");
                const uid = parseInt(f[2]);
                if (uid >= 1000 && uid < 60000 && !(f[6] || "").endsWith("nologin")) {
                    if (userField.text === "") userField.text = f[0];
                    break;
                }
            }
            root.focusInitial();
        }
    }
    FileView { path: "/etc/hostname"; onLoaded: root.hostName = text().trim() }
    function focusInitial() {
        if (userField.text !== "") passwordField.forceActiveFocus(); else userField.forceActiveFocus();
    }

    // --------------------------------------------------------------- visuals
    Image {
        id: wallpaper
        anchors.fill: parent
        source: "file:///usr/share/backgrounds/devos/devos.jpg"
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
    }
    // Keeps the clock and toolbars readable on any wallpaper.
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.alpha(Theme.m3scrim, 0.30) }
            GradientStop { position: 0.45; color: Theme.alpha(Theme.m3scrim, 0.0) }
            GradientStop { position: 1.0; color: Theme.alpha(Theme.m3scrim, 0.45) }
        }
    }

    SystemClock { id: clock; precision: SystemClock.Minutes }

    // Large clock, as on the end-4 lock screen and desktop.
    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: parent.height * 0.13
        spacing: 0
        opacity: root.entered ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: Qt.formatTime(clock.date, "HH:mm")
            color: Theme.m3onSurface
            font.family: Theme.display
            font.pixelSize: Math.min(root.height * 0.17, 180)
            font.weight: Font.DemiBold
            font.letterSpacing: -2
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: Qt.formatDate(clock.date, "dddd, d MMMM")
            color: Theme.m3onSurfaceVariant
            font.family: Theme.body
            font.pixelSize: 22
            font.weight: Font.Medium
        }
    }

    // ---------------------------------------------- toolbars (end-4 lock screen)
    property bool entered: false

    component Island: Rectangle {
        default property alias content: islandRow.data
        property bool shown: false
        implicitHeight: 56
        implicitWidth: islandRow.implicitWidth + 16
        radius: height / 2
        color: Theme.m3surfaceContainer
        scale: shown ? 1 : 0.9
        opacity: shown ? 1 : 0
        Behavior on scale { NumberAnimation { duration: 500; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.expressiveDefault } }
        Behavior on opacity { NumberAnimation { duration: 300 } }
        layer.enabled: true
        layer.effect: DropShadow { radius: 18; samples: 25; verticalOffset: 3; color: Theme.alpha(Theme.m3scrim, 0.35) }
        RowLayout {
            id: islandRow
            anchors.fill: parent
            anchors.margins: 8
            spacing: 4
        }
    }
    component IconButton: Rectangle {
        id: ib
        property string icon: ""
        property string tip: ""
        signal clicked()
        Layout.preferredWidth: 40
        Layout.preferredHeight: 40
        radius: 20
        color: ibMouse.pressed ? Theme.pressed(Theme.m3surfaceContainer, Theme.m3onSurface)
             : ibMouse.containsMouse ? Theme.hover(Theme.m3surfaceContainer, Theme.m3onSurface) : "transparent"
        MIcon { anchors.centerIn: parent; name: ib.icon; size: 22; color: Theme.m3onSurfaceVariant }
        MouseArea { id: ibMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: ib.clicked() }
    }

    Item {
        visible: root.showLogin
        anchors.fill: parent

        // Center: password, with the confirm button
        Island {
            shown: root.entered
            id: mainIsland
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 24
            Rectangle {
                id: passwordBox
                Layout.preferredWidth: 300
                Layout.fillHeight: true
                radius: height / 2
                color: Theme.m3surfaceContainerHigh
                border.width: passwordField.activeFocus ? 2 : 0
                border.color: root.messageIsError && root.message !== "" ? Theme.m3error : Theme.m3primary
                TextInput {
                    id: passwordField
                    anchors.fill: parent
                    anchors.leftMargin: 18
                    anchors.rightMargin: 18
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: TextInput.Password
                    passwordCharacter: "●"
                    color: Theme.m3onSurface
                    font.family: Theme.body
                    font.pixelSize: 15
                    clip: true
                    enabled: !root.busy
                    KeyNavigation.tab: userField
                    onAccepted: root.login()
                    onTextEdited: if (root.messageIsError) root.message = ""
                    Text {
                        visible: passwordField.text === ""
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.message !== "" ? root.message : "Enter password"
                        color: root.messageIsError && root.message !== "" ? Theme.m3error : Theme.m3onSurfaceVariant
                        font.family: Theme.body
                        font.pixelSize: 15
                    }
                }
                SequentialAnimation {
                    id: shake
                    NumberAnimation { target: mainIsland; property: "anchors.horizontalCenterOffset"; to: -10; duration: 50 }
                    NumberAnimation { target: mainIsland; property: "anchors.horizontalCenterOffset"; to: 10; duration: 70 }
                    NumberAnimation { target: mainIsland; property: "anchors.horizontalCenterOffset"; to: 0; duration: 60 }
                }
            }
            Rectangle {
                id: confirm
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                radius: 20
                color: confirmMouse.containsMouse ? Theme.hover(Theme.m3primary, Theme.m3onPrimary) : Theme.m3primary
                opacity: root.busy ? 0.6 : 1
                MIcon {
                    anchors.centerIn: parent
                    name: root.busy ? "hourglass_top" : "arrow_right_alt"
                    size: 24
                    color: Theme.m3onPrimary
                }
                MouseArea { id: confirmMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: root.login() }
            }
        }

        // Left: who is signing in, and the keyboard layout
        Island {
            shown: root.entered
            anchors.right: mainIsland.left
            anchors.rightMargin: 10
            anchors.verticalCenter: mainIsland.verticalCenter
            Rectangle {
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                Layout.leftMargin: 2
                radius: 20
                color: Theme.m3primaryContainer
                Text {
                    anchors.centerIn: parent
                    visible: avatar.status !== Image.Ready
                    text: userField.text !== "" ? userField.text[0].toUpperCase() : "›_"
                    color: Theme.m3onPrimaryContainer
                    font.family: Theme.display
                    font.pixelSize: 17
                    font.weight: Font.DemiBold
                }
                Image {
                    id: avatar
                    anchors.fill: parent
                    visible: false
                    fillMode: Image.PreserveAspectCrop
                    sourceSize: Qt.size(96, 96)
                    source: userField.text.trim() !== "" ? "file:///var/lib/AccountsService/icons/" + userField.text.trim() : ""
                }
                Rectangle { id: avatarMask; anchors.fill: parent; radius: 20; visible: false }
                OpacityMask { anchors.fill: parent; visible: avatar.status === Image.Ready; source: avatar; maskSource: avatarMask }
            }
            TextInput {
                id: userField
                Layout.preferredWidth: Math.max(80, contentWidth + 4)
                Layout.maximumWidth: 200
                Layout.leftMargin: 6
                Layout.rightMargin: 4
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.m3onSurface
                font.family: Theme.body
                font.pixelSize: 15
                font.weight: Font.Medium
                clip: true
                enabled: !root.busy
                KeyNavigation.tab: passwordField
                onAccepted: passwordField.forceActiveFocus()
                Text { visible: userField.text === ""; anchors.verticalCenter: parent.verticalCenter
                       text: "User"; color: Theme.m3onSurfaceVariant; font.family: Theme.body; font.pixelSize: 15 }
            }
            Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 24; color: Theme.m3outlineVariant }
            MIcon { Layout.leftMargin: 8; name: "keyboard_alt"; size: 20; color: Theme.m3onSurfaceVariant }
            Text { Layout.rightMargin: 12; text: "us"; color: Theme.m3onSurfaceVariant; font.family: Theme.body; font.pixelSize: 14 }
        }

        // Right: power
        Island {
            shown: root.entered
            anchors.left: mainIsland.right
            anchors.leftMargin: 10
            anchors.verticalCenter: mainIsland.verticalCenter
            IconButton { icon: "bedtime"; onClicked: { power.command = ["systemctl", "suspend"]; power.running = true; } }
            IconButton { icon: "restart_alt"; onClicked: { power.command = ["systemctl", "reboot"]; power.running = true; } }
            IconButton { icon: "power_settings_new"; onClicked: { power.command = ["systemctl", "poweroff"]; power.running = true; } }
        }

        // DevOS and the host, top-left (where end-4's bar would be)
        RowLayout {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.margins: 22
            spacing: 10
            opacity: root.entered ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 600 } }
            Rectangle {
                width: 32; height: 32; radius: Theme.radiusSmall
                color: Theme.m3primaryContainer
                Text { anchors.centerIn: parent; text: "›_"; color: Theme.m3onPrimaryContainer
                       font.family: Theme.mono; font.pixelSize: 13; font.weight: Font.Bold }
            }
            Text { text: "DevOS"; color: Theme.m3onSurface; font.family: Theme.display; font.pixelSize: 17; font.weight: Font.DemiBold }
            Text { text: root.hostName; color: Theme.m3onSurfaceVariant; font.family: Theme.body; font.pixelSize: 14; Layout.leftMargin: 4 }
        }
    }

    Process { id: power }
}
