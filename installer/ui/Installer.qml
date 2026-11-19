import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io

// DevOS graphical installer (SRS §7.1, INST-001..007), in the design of the login screen
// (end-4 Material You). It only collects settings; devos-install does the work:
//   sudo devos-install --config - --ui
// Settings go to its stdin, so no password is ever written to a disk; the user password
// is hashed (openssl passwd -6) before it leaves this process. Progress comes back as
// "::step", "::progress", "::error" and "::done" lines.
// DEVOS_INSTALLER_DRYRUN=1 runs a simulated installation (UI development, screenshots).
Item {
    id: root

    property bool showUi: true
    readonly property bool dryRun: Quickshell.env("DEVOS_INSTALLER_DRYRUN") === "1"

    // ------------------------------------------------------------------ settings
    property string timezone: "UTC"
    property string locale: "en_US.UTF-8"
    property string keymap: "us"
    property string disk: ""
    property string diskLabel: ""
    property real diskBytes: 0
    property bool encrypt: false
    property string username: ""
    property string hostname: "devos"
    property var profiles: ({ web: false, backend: false, systems: false, ai: false, embedded: false })
    // Secrets stay in memory only; the user password leaves this process hashed.
    property string password: ""
    property string password2: ""
    property string luks: ""
    property string luks2: ""

    // ------------------------------------------------------------------ pages
    readonly property var pages: [
        { title: "Welcome", icon: "waving_hand" },
        { title: "Region", icon: "public" },
        { title: "Network", icon: "wifi" },
        { title: "Disk", icon: "hard_drive" },
        { title: "Account", icon: "person" },
        { title: "Profiles", icon: "deployed_code" },
        { title: "Summary", icon: "checklist" },
        { title: "Install", icon: "download" }
    ]
    property int page: 0
    property int furthest: 0
    readonly property bool installing: page === 7

    // Dry runs can open a page directly (DEVOS_INSTALLER_PAGE=0..7) for screenshots.
    Component.onCompleted: {
        const start = Number(Quickshell.env("DEVOS_INSTALLER_PAGE") || 0);
        if (!dryRun || !(start > 0)) return;
        username = "alex"; password = password2 = "x";
        disk = "/dev/vda"; diskLabel = "Virtual disk"; diskBytes = 64e9;
        furthest = 6;
        if (start >= 7) startInstall(); else page = start;
    }

    function go(i) {
        if (installing) return;
        page = Math.max(0, Math.min(6, i));
        furthest = Math.max(furthest, page);
    }

    readonly property bool usernameOk: /^[a-z_][a-z0-9_-]{0,31}$/.test(username) && username !== "root"
    readonly property bool hostnameOk: /^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/.test(hostname)
    readonly property bool passwordOk: password.length > 0 && password === password2
    readonly property bool luksOk: !encrypt || (luks.length >= 8 && luks === luks2)
    function canLeave(i) {
        if (i === 1) return timezone !== "";
        if (i === 3) return disk !== "" && luksOk;
        if (i === 4) return usernameOk && hostnameOk && passwordOk;
        return true;
    }

    function fmtSize(bytes) {
        const gb = bytes / 1e9;
        return gb >= 1000 ? (gb / 1000).toFixed(1) + " TB" : Math.round(gb) + " GB";
    }
    function chosenProfiles() {
        return Object.keys(profiles).filter(k => profiles[k]);
    }

    // ------------------------------------------------------------------ system data
    property var timezones: []
    property var keymaps: ["us"]
    property var disks: []
    property string netState: "checking"     // connected | disconnected | checking
    property string netName: ""
    property var wifi: []

    Process {
        running: true
        command: ["timedatectl", "list-timezones"]
        stdout: StdioCollector { onStreamFinished: root.timezones = text.trim().split("\n").filter(s => s !== "") }
    }
    Process {
        running: true
        command: ["localectl", "list-keymaps"]
        stdout: StdioCollector {
            onStreamFinished: {
                const k = text.trim().split("\n").filter(s => s !== "");
                if (k.length) root.keymaps = k;
            }
        }
    }
    // The time zone of this network's location, as the text installer did; UTC without one.
    Process {
        id: tzDetect
        running: true
        command: ["curl", "-fsS", "--max-time", "5", "https://ipapi.co/timezone"]
        stdout: StdioCollector {
            onStreamFinished: {
                const tz = text.trim();
                if (/^[A-Za-z_]+(\/[A-Za-z0-9_+-]+)+$/.test(tz)) root.timezone = tz;
            }
        }
    }
    Process {
        id: diskScan
        running: true
        command: ["lsblk", "-J", "-b", "-o", "NAME,PATH,SIZE,MODEL,TYPE,TRAN,RM,MOUNTPOINTS"]
        stdout: StdioCollector {
            onStreamFinished: {
                let list = [];
                try {
                    const mounted = d => (d.mountpoints || []).some(m => m) || (d.children || []).some(mounted);
                    for (const d of JSON.parse(text).blockdevices) {
                        // Whole disks only, never the live medium (it has mounted partitions).
                        if (d.type !== "disk" || mounted(d) || Number(d.size) < 8e9) continue;
                        list.push({ path: d.path, size: Number(d.size), model: (d.model || "").trim() || "Disk",
                                    tran: d.tran || "", removable: d.rm === true || d.rm === "1" });
                    }
                } catch (e) {}
                root.disks = list;
                if (list.length === 1 && root.disk === "") root.pickDisk(list[0]);
            }
        }
    }
    readonly property bool diskScanning: diskScan.running
    function rescanDisks() { diskScan.running = true; }
    function pickDisk(d) { disk = d.path; diskLabel = d.model; diskBytes = d.size; }

    Process {
        id: netCheck
        command: ["nmcli", "-t", "-f", "TYPE,STATE,CONNECTION", "device"]
        stdout: StdioCollector {
            onStreamFinished: {
                let state = "disconnected", name = "";
                for (const l of text.trim().split("\n")) {
                    const f = l.split(":");
                    if (f[1] === "connected" && (f[0] === "ethernet" || f[0] === "wifi")) {
                        state = "connected";
                        name = f[0] === "wifi" ? f.slice(2).join(":") : "Wired connection";
                    }
                }
                root.netState = state;
                root.netName = name;
            }
        }
    }
    Timer { interval: 4000; running: true; repeat: true; triggeredOnStart: true; onTriggered: if (!netCheck.running) netCheck.running = true }

    Process {
        id: wifiScan
        command: ["nmcli", "-t", "-f", "IN-USE,SIGNAL,SECURITY,SSID", "device", "wifi", "list", "--rescan", "auto"]
        stdout: StdioCollector {
            onStreamFinished: {
                const seen = {}, list = [];
                for (const l of text.trim().split("\n")) {
                    const f = l.split(":");
                    if (f.length < 4) continue;
                    const ssid = f.slice(3).join(":").replace(/\\:/g, ":");
                    if (!ssid || seen[ssid]) continue;
                    seen[ssid] = true;
                    list.push({ ssid: ssid, signal: Number(f[1]), secure: f[2] !== "" && f[2] !== "--", active: f[0] === "*" });
                }
                list.sort((a, b) => b.signal - a.signal);
                root.wifi = list;
            }
        }
    }
    readonly property bool wifiScanning: wifiScan.running
    readonly property bool wifiConnecting: wifiConnect.running
    function rescanWifi() { if (!wifiScan.running) wifiScan.running = true; }
    property string wifiTarget: ""
    property string wifiError: ""
    Process {
        id: wifiConnect
        stderr: StdioCollector { id: wifiErr }
        onExited: code => {
            root.wifiError = code === 0 ? "" : (wifiErr.text.trim().split("\n").pop() || "Could not connect.");
            if (code === 0) root.wifiTarget = "";
            netCheck.running = true;
            wifiScan.running = true;
        }
    }
    function connectWifi(ssid, password) {
        wifiError = "";
        wifiConnect.command = password !== ""
            ? ["nmcli", "device", "wifi", "connect", ssid, "password", password]
            : ["nmcli", "device", "wifi", "connect", ssid];
        wifiConnect.running = true;
    }

    Process { id: launcher }
    function openTerminal() { launcher.command = ["kitty"]; launcher.running = true; }

    // ------------------------------------------------------------------ installation
    property int stepNo: 0
    property int stepCount: 5
    property string stepText: "Starting"
    property real stepProgress: 0
    property string detail: ""
    property string error: ""
    property bool finished: false
    // Weight of each devos-install step in the overall progress (disk, packages, setup,
    // boot loader, finish).
    readonly property var weights: [5, 70, 15, 8, 2]
    readonly property real overall: {
        if (finished) return 1;
        let done = 0;
        for (let i = 0; i < stepNo - 1 && i < weights.length; i++) done += weights[i];
        const cur = stepNo > 0 && stepNo <= weights.length ? weights[stepNo - 1] * stepProgress : 0;
        return Math.min(0.99, (done + cur) / 100);
    }
    property var log: []
    function addLog(line) {
        const l = log.slice(-200);
        l.push(line);
        log = l;
    }

    Process {
        id: hasher
        stdinEnabled: true
        command: ["openssl", "passwd", "-6", "-stdin"]
        // Write once the process runs; writes before that are lost.
        onStarted: { write(root.password + "\n"); stdinEnabled = false; }
        stdout: StdioCollector {
            onStreamFinished: {
                const hash = text.trim();
                if (!hash.startsWith("$6$")) { root.fail("Could not prepare the password."); return; }
                root.runInstaller(hash);
            }
        }
    }

    property string pendingConfig: ""
    Process {
        id: installer
        stdinEnabled: true
        onStarted: { write(root.pendingConfig); root.pendingConfig = ""; stdinEnabled = false; }
        stdout: SplitParser {
            onRead: line => {
                if (line.startsWith("::step ")) {
                    const m = line.match(/^::step (\d+) (\d+) (.*)$/);
                    if (m) {
                        root.stepNo = Number(m[1]);
                        root.stepCount = Number(m[2]);
                        root.stepText = m[3];
                        root.stepProgress = 0;
                        root.detail = "";
                    }
                } else if (line.startsWith("::progress ")) {
                    const m = line.match(/^::progress (\d+) ?(.*)$/);
                    if (m) {
                        root.stepProgress = Number(m[1]) / 100;
                        root.detail = m[2];
                    }
                } else if (line.startsWith("::error ")) {
                    root.fail(line.slice(8));
                } else if (line === "::done") {
                    root.finished = true;
                }
                root.addLog(line);
            }
        }
        stderr: SplitParser { onRead: line => root.addLog(line) }
        onExited: code => {
            if (code !== 0 && !root.finished && root.error === "")
                root.fail("The installation stopped unexpectedly (exit code " + code + ").");
        }
    }

    function fail(message) { error = message; }

    function startInstall() {
        page = 7;
        stepNo = 0; stepProgress = 0; stepText = "Starting"; error = ""; finished = false; log = [];
        hasher.stdinEnabled = true;
        hasher.running = true;
    }

    function runInstaller(hash) {
        const cfg = [
            "DISK=" + disk,
            "HOSTNAME=" + hostname,
            "USERNAME=" + username,
            "PASSWORD_HASH=" + hash,
            "TIMEZONE=" + timezone,
            "LOCALE=" + locale,
            "KEYMAP=" + keymap,
            "ENCRYPT=" + (encrypt ? "yes" : "no"),
            "LUKS_PASSWORD=" + (encrypt ? luks : ""),
            "PROFILES=" + chosenProfiles().join(" "),
            "ASSUME_YES=yes"
        ].join("\n") + "\n";
        installer.command = dryRun
            ? ["sh", "-c", "cat >/dev/null; n=1; for s in 'Preparing the disk' 'Installing packages' 'Setting up DevOS' " +
               "'Installing the boot loader' 'Finishing'; do echo \"::step $n 5 $s\"; " +
               "if [ $n = 2 ]; then for p in $(seq 1 100); do echo \"::progress $p package-$p\"; sleep 0.08; done; fi; " +
               "sleep 1.5; n=$((n+1)); done; echo ::done"]
            : ["sudo", "-n", "/usr/bin/devos-install", "--config", "-", "--ui"];
        pendingConfig = cfg;
        installer.stdinEnabled = true;
        installer.running = true;
    }

    Process { id: power }
    function reboot() { power.command = ["systemctl", "reboot"]; power.running = true; }

    // =================================================================== visuals
    Image {
        anchors.fill: parent
        source: Qt.resolvedUrl("background.jpg")
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize.width: 2560
    }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(0.02, 0.03, 0.06, 0.55) }
            GradientStop { position: 1; color: Qt.rgba(0.02, 0.03, 0.06, 0.25) }
        }
    }

    // DevOS mark, top left.
    RowLayout {
        visible: root.showUi
        anchors { left: parent.left; top: parent.top; margins: 22 }
        spacing: 10
        Rectangle {
            implicitWidth: 32; implicitHeight: 32; radius: 10
            color: Theme.m3primaryContainer
            Text { anchors.centerIn: parent; text: "›_"; color: Theme.m3onPrimaryContainer; font.family: Theme.mono; font.pixelSize: 14; font.bold: true }
        }
        Text { text: "DevOS"; color: Theme.m3onSurface; font.family: Theme.display; font.pixelSize: 17; font.weight: Font.DemiBold }
        Text { text: "Installer"; color: Theme.m3onSurfaceVariant; font.family: Theme.body; font.pixelSize: 14; Layout.leftMargin: 2 }
    }

    // Network and terminal, top right.
    RowLayout {
        visible: root.showUi
        anchors { right: parent.right; top: parent.top; margins: 18 }
        spacing: 8
        Chip {
            icon: root.netState === "connected" ? "wifi" : "wifi_off"
            label: root.netState === "connected" ? root.netName : "Offline"
            onClicked: if (!root.installing) root.go(2)
        }
        Chip { icon: "terminal"; label: "Terminal"; onClicked: root.openTerminal() }
    }

    // The card's shadow, drawn separately: rendering the card itself through a layer turns
    // text on transparent buttons black.
    Rectangle {
        visible: root.showUi
        anchors.fill: card
        radius: card.radius
        color: Theme.m3surfaceContainerLow
        opacity: card.opacity
        scale: card.scale
        layer.enabled: true
        layer.effect: DropShadow { radius: 32; samples: 41; verticalOffset: 8; color: Theme.alpha(Theme.m3scrim, 0.45) }
    }

    // The installer card.
    Rectangle {
        id: card
        visible: root.showUi
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 1080)
        height: Math.min(parent.height - 120, 680)
        radius: 28
        color: Theme.m3surfaceContainerLow
        opacity: 0
        scale: 0.96
        Component.onCompleted: { opacity = 1; scale = 1; }
        Behavior on opacity { NumberAnimation { duration: 400 } }
        Behavior on scale { NumberAnimation { duration: 600; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.expressiveDefault } }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 0

            // ---------------------------------------------------- step rail
            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: 220
                radius: 20
                color: Theme.alpha(Theme.m3surfaceContainer, 0.9)
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 4
                    Text {
                        text: "Install DevOS"
                        color: Theme.m3onSurface
                        font.family: Theme.display; font.pixelSize: 18; font.weight: Font.DemiBold
                        Layout.leftMargin: 10; Layout.topMargin: 6; Layout.bottomMargin: 14
                    }
                    Repeater {
                        model: root.pages
                        delegate: Rectangle {
                            id: railItem
                            required property var modelData
                            required property int index
                            readonly property bool current: root.page === index
                            readonly property bool reachable: !root.installing && index <= root.furthest && index < 7
                            Layout.fillWidth: true
                            implicitHeight: 44
                            radius: 22
                            color: current ? Theme.m3secondaryContainer
                                 : railMouse.containsMouse && reachable ? Theme.hover(Theme.m3surfaceContainer, Theme.m3onSurface)
                                 : "transparent"
                            Behavior on color { ColorAnimation { duration: Theme.durationFast } }
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                spacing: 12
                                MIcon {
                                    name: railItem.index < root.page && !railItem.current ? "check_circle" : railItem.modelData.icon
                                    fill: railItem.current ? 1 : 0
                                    size: 20
                                    color: railItem.current ? Theme.m3onSecondaryContainer
                                         : railItem.index < root.page ? Theme.m3primary : Theme.m3onSurfaceVariant
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: railItem.modelData.title
                                    color: railItem.current ? Theme.m3onSecondaryContainer : Theme.m3onSurfaceVariant
                                    font.family: Theme.body; font.pixelSize: 14
                                    font.weight: railItem.current ? Font.DemiBold : Font.Normal
                                }
                            }
                            MouseArea {
                                id: railMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: railItem.reachable ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: if (railItem.reachable) root.go(railItem.index)
                            }
                        }
                    }
                    Item { Layout.fillHeight: true }
                    Text {
                        Layout.fillWidth: true
                        Layout.margins: 10
                        wrapMode: Text.WordWrap
                        text: "Everything installs from this USB stick. No internet needed."
                        color: Theme.m3onSurfaceVariant
                        font.family: Theme.body; font.pixelSize: 12
                        lineHeight: 1.2
                    }
                }
            }

            // ---------------------------------------------------- page area
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Item {
                    id: pageArea
                    anchors { left: parent.left; right: parent.right; top: parent.top; bottom: nav.top }
                    anchors.margins: 28
                    anchors.bottomMargin: 12

                    Page { r: root; index: 0; WelcomePage { r: root } }
                    Page { r: root; index: 1; RegionPage { r: root } }
                    Page { r: root; index: 2; NetworkPage { r: root } }
                    Page { r: root; index: 3; DiskPage { r: root } }
                    Page { r: root; index: 4; AccountPage { r: root } }
                    Page { r: root; index: 5; ProfilesPage { r: root } }
                    Page { r: root; index: 6; SummaryPage { r: root } }
                    Page { r: root; index: 7; InstallPage { r: root } }
                }

                // Back / Next.
                RowLayout {
                    id: nav
                    visible: root.page > 0 && !root.installing
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 20 }
                    height: 44
                    spacing: 10
                    DButton { label: "Back"; icon: "arrow_back"; variant: "ghost"; onClicked: root.go(root.page - 1) }
                    Item { Layout.fillWidth: true }
                    Text {
                        visible: !root.canLeave(root.page)
                        text: root.page === 3 && root.disk === "" ? "Choose a disk"
                            : root.page === 3 ? "Check the encryption passphrase"
                            : root.page === 4 ? "Fill in your account" : ""
                        color: Theme.m3onSurfaceVariant
                        font.family: Theme.body; font.pixelSize: 13
                    }
                    DButton {
                        visible: root.page < 6
                        label: "Next"; icon: "arrow_forward"; variant: "primary"
                        opacity: root.canLeave(root.page) ? 1 : 0.45
                        onClicked: if (root.canLeave(root.page)) root.go(root.page + 1)
                    }
                    DButton {
                        visible: root.page === 6
                        label: "Install DevOS"; icon: "download"; variant: "primary"
                        onClicked: confirmBox.open = true
                    }
                }
            }
        }
    }

    // ======================================================== confirmation dialog
    Rectangle {
        id: confirmBox
        property bool open: false
        anchors.fill: parent
        color: Theme.alpha(Theme.m3scrim, open ? 0.5 : 0)
        visible: color.a > 0.01
        Behavior on color { ColorAnimation { duration: 200 } }
        MouseArea { anchors.fill: parent; onClicked: confirmBox.open = false }
        Rectangle {
            anchors.centerIn: parent
            width: 440
            height: dlg.implicitHeight + 48
            radius: 28
            color: Theme.m3surfaceContainerHigh
            scale: confirmBox.open ? 1 : 0.9
            Behavior on scale { NumberAnimation { duration: 350; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.expressiveDefault } }
            MouseArea { anchors.fill: parent }
            ColumnLayout {
                id: dlg
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
                spacing: 14
                MIcon { name: "warning"; size: 28; color: Theme.m3error; Layout.alignment: Qt.AlignHCenter }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: "Erase this disk?"
                    color: Theme.m3onSurface
                    font.family: Theme.display; font.pixelSize: 22; font.weight: Font.DemiBold
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: "Everything on " + root.diskLabel + " (" + root.disk + ", " + root.fmtSize(root.diskBytes) +
                          ") will be deleted and replaced by DevOS. This can't be undone."
                    color: Theme.m3onSurfaceVariant
                    font.family: Theme.body; font.pixelSize: 14
                    lineHeight: 1.2
                }
                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    Layout.topMargin: 6
                    spacing: 8
                    DButton { label: "Cancel"; variant: "ghost"; onClicked: confirmBox.open = false }
                    DButton { label: "Erase and install"; icon: "delete_forever"; variant: "danger"
                              onClicked: { confirmBox.open = false; root.startInstall(); } }
                }
            }
        }
    }

    // ==================================================================== pieces
    component Page: Item {
        property var r
        id: pg
        required property int index
        default property alias content: holder.data
        anchors.fill: parent
        visible: opacity > 0
        opacity: r.page === index ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 220 } }
        Item {
            id: holder
            anchors.fill: parent
            anchors.topMargin: r.page === pg.index ? 0 : 16
            Behavior on anchors.topMargin { NumberAnimation { duration: 400; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.emphasizedDecel } }
        }
    }

    component Heading: ColumnLayout {
        property string title
        property string subtitle
        Layout.fillWidth: true
        spacing: 6
        Text { text: parent.title; color: Theme.m3onSurface; font.family: Theme.display; font.pixelSize: 28; font.weight: Font.DemiBold }
        Text {
            Layout.fillWidth: true
            visible: text !== ""
            text: parent.subtitle
            wrapMode: Text.WordWrap
            color: Theme.m3onSurfaceVariant
            font.family: Theme.body; font.pixelSize: 14
            lineHeight: 1.2
        }
    }

    component Chip: Rectangle {
        id: chip
        property string icon
        property string label
        signal clicked()
        implicitHeight: 36
        implicitWidth: chipRow.implicitWidth + 24
        radius: 18
        color: chipMouse.containsMouse ? Theme.hover(Theme.m3surfaceContainer, Theme.m3onSurface) : Theme.alpha(Theme.m3surfaceContainer, 0.9)
        RowLayout {
            id: chipRow
            anchors.centerIn: parent
            spacing: 6
            MIcon { name: chip.icon; size: 18; color: Theme.m3onSurfaceVariant }
            Text { text: chip.label; color: Theme.m3onSurface; font.family: Theme.body; font.pixelSize: 13 }
        }
        MouseArea { id: chipMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: chip.clicked() }
    }

    // A text field in the style of the login screen's password pill.
    component Field: Rectangle {
        id: fld
        property alias text: input.text
        property alias input: input
        property string placeholder
        property string icon
        property bool secret: false
        property bool bad: false
        Layout.fillWidth: true
        implicitHeight: 48
        radius: 24
        color: Theme.m3surfaceContainerHigh
        border.width: input.activeFocus ? 2 : 1
        border.color: bad ? Theme.m3error : input.activeFocus ? Theme.m3primary : Theme.m3outlineVariant
        Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            spacing: 10
            MIcon { visible: fld.icon !== ""; name: fld.icon; size: 20; color: Theme.m3onSurfaceVariant }
            TextInput {
                id: input
                Layout.fillWidth: true
                color: Theme.m3onSurface
                font.family: Theme.body; font.pixelSize: 15
                echoMode: fld.secret ? TextInput.Password : TextInput.Normal
                passwordCharacter: "•"
                selectByMouse: true
                clip: true
                activeFocusOnTab: true
                Text {
                    anchors.fill: parent
                    visible: input.text === ""
                    text: fld.placeholder
                    color: Theme.m3onSurfaceVariant
                    font: input.font
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.IBeamCursor; onPressed: mouse => { input.forceActiveFocus(); mouse.accepted = false; } }
    }

    // A selectable row (time zones, languages, Wi-Fi networks, disks).
    component Choice: Rectangle {
        id: ch
        property bool selected: false
        property string icon
        property string title
        property string subtitle
        property string trailing
        signal clicked()
        Layout.fillWidth: true
        width: ListView.view ? ListView.view.width : implicitWidth
        implicitHeight: subtitle !== "" ? 60 : 44
        radius: 16
        color: selected ? Theme.m3secondaryContainer
             : chMouse.containsMouse ? Theme.hover(Theme.m3surfaceContainer, Theme.m3onSurface) : Theme.m3surfaceContainer
        border.width: selected ? 2 : 0
        border.color: Theme.m3primary
        Behavior on color { ColorAnimation { duration: Theme.durationFast } }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            spacing: 12
            MIcon { visible: ch.icon !== ""; name: ch.icon; size: 22; fill: ch.selected ? 1 : 0
                    color: ch.selected ? Theme.m3onSecondaryContainer : Theme.m3onSurfaceVariant }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text { Layout.fillWidth: true; text: ch.title; elide: Text.ElideRight
                       color: ch.selected ? Theme.m3onSecondaryContainer : Theme.m3onSurface
                       font.family: Theme.body; font.pixelSize: 14; font.weight: ch.selected ? Font.DemiBold : Font.Normal }
                Text { Layout.fillWidth: true; visible: ch.subtitle !== ""; text: ch.subtitle; elide: Text.ElideRight
                       color: Theme.m3onSurfaceVariant; font.family: Theme.body; font.pixelSize: 12 }
            }
            Text { visible: ch.trailing !== ""; text: ch.trailing; color: Theme.m3onSurfaceVariant; font.family: Theme.body; font.pixelSize: 13 }
            MIcon { visible: ch.selected; name: "check_circle"; fill: 1; size: 20; color: Theme.m3primary }
        }
        MouseArea { id: chMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ch.clicked() }
    }

    // A filterable list (time zones, keyboard layouts).
    component SearchList: ColumnLayout {
        id: sl
        property var items: []
        property string current
        property string icon
        property string placeholder: "Search"
        signal picked(string value)
        spacing: 10
        Field { id: q; icon: "search"; placeholder: sl.placeholder }
        ListView {
            id: lv
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 4
            boundsBehavior: Flickable.StopAtBounds
            model: {
                const f = q.text.trim().toLowerCase().replace(/ /g, "_");
                return f === "" ? sl.items : sl.items.filter(s => s.toLowerCase().indexOf(f) >= 0);
            }
            delegate: Choice {
                required property string modelData
                icon: sl.icon
                title: modelData.replace(/_/g, " ")
                selected: modelData === sl.current
                onClicked: sl.picked(modelData)
            }
            Component.onCompleted: positionTimer.start()
            Timer { id: positionTimer; interval: 300; onTriggered: { const i = sl.items.indexOf(sl.current); if (i >= 0) lv.positionViewAtIndex(i, ListView.Center); } }
        }
    }

    component Toggle: Rectangle {
        id: tg
        property bool checked: false
        signal toggled()
        implicitWidth: 52
        implicitHeight: 32
        radius: 16
        color: checked ? Theme.m3primary : Theme.m3surfaceContainerHighest
        border.width: checked ? 0 : 2
        border.color: Theme.m3outline
        Behavior on color { ColorAnimation { duration: Theme.durationFast } }
        Rectangle {
            width: tg.checked ? 24 : 16
            height: width
            radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            x: tg.checked ? parent.width - width - 4 : 8
            color: tg.checked ? Theme.m3onPrimary : Theme.m3outline
            Behavior on x { NumberAnimation { duration: 250; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.expressiveFast } }
            Behavior on width { NumberAnimation { duration: 200 } }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tg.toggled() }
    }

    // ===================================================================== pages
    component WelcomePage: ColumnLayout {
        property var r
        anchors.fill: parent
        spacing: 0
        Item { Layout.fillHeight: true }
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 96; implicitHeight: 96; radius: 30
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "#2DD4BF" }
                GradientStop { position: 1; color: "#8B5CF6" }
            }
            Text { anchors.centerIn: parent; text: "›_"; color: "#0b1020"; font.family: Theme.mono; font.pixelSize: 40; font.bold: true }
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 28
            text: "Welcome to DevOS"
            color: Theme.m3onSurface
            font.family: Theme.display; font.pixelSize: 40; font.weight: Font.DemiBold
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 10
            text: "The operating system for developers, with an AI agent built in."
            color: Theme.m3onSurfaceVariant
            font.family: Theme.body; font.pixelSize: 16
        }
        Flow {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 28
            Layout.maximumWidth: 640
            spacing: 10
            Repeater {
                model: [
                    { icon: "desktop_windows", text: "Hyprland desktop" },
                    { icon: "smart_toy", text: "DevOS Agent" },
                    { icon: "code", text: "Developer profiles" },
                    { icon: "lock", text: "Disk encryption" },
                    { icon: "cloud_off", text: "Installs offline" }
                ]
                delegate: Rectangle {
                    required property var modelData
                    implicitHeight: 36
                    implicitWidth: fr.implicitWidth + 26
                    radius: 12
                    color: Theme.m3surfaceContainerHigh
                    RowLayout {
                        id: fr
                        anchors.centerIn: parent
                        spacing: 8
                        MIcon { name: modelData.icon; size: 18; color: Theme.m3primary }
                        Text { text: modelData.text; color: Theme.m3onSurface; font.family: Theme.body; font.pixelSize: 13 }
                    }
                }
            }
        }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 36
            spacing: 12
            DButton { label: "Open a terminal"; icon: "terminal"; onClicked: r.openTerminal() }
            DButton { label: "Install DevOS"; icon: "arrow_forward"; variant: "primary"; onClicked: r.go(1) }
        }
        Item { Layout.fillHeight: true }
    }

    component RegionPage: ColumnLayout {
        property var r
        anchors.fill: parent
        spacing: 18
        Heading { title: "Region"; subtitle: "Your time zone, language and keyboard." }
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 18
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 3
                spacing: 8
                Text { text: "Time zone · " + r.timezone.replace(/_/g, " "); color: Theme.m3onSurfaceVariant; font.family: Theme.body; font.pixelSize: 13 }
                SearchList {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    items: r.timezones
                    current: r.timezone
                    icon: "schedule"
                    placeholder: "Search a city or region"
                    onPicked: v => r.timezone = v
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 2
                spacing: 8
                Text { text: "Language"; color: Theme.m3onSurfaceVariant; font.family: Theme.body; font.pixelSize: 13 }
                ListView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 200
                    clip: true
                    spacing: 4
                    boundsBehavior: Flickable.StopAtBounds
                    model: [
                        ["en_US.UTF-8", "English (US)"], ["en_GB.UTF-8", "English (UK)"], ["de_DE.UTF-8", "Deutsch"],
                        ["fr_FR.UTF-8", "Français"], ["es_ES.UTF-8", "Español"], ["it_IT.UTF-8", "Italiano"],
                        ["pt_BR.UTF-8", "Português (Brasil)"], ["nl_NL.UTF-8", "Nederlands"], ["pl_PL.UTF-8", "Polski"],
                        ["tr_TR.UTF-8", "Türkçe"], ["ru_RU.UTF-8", "Русский"], ["fa_IR", "فارسی"],
                        ["ar_EG.UTF-8", "العربية"], ["hi_IN", "Hindi"], ["zh_CN.UTF-8", "Chinese (Simplified)"],
                        ["ja_JP.UTF-8", "Japanese"], ["ko_KR.UTF-8", "Korean"]
                    ]
                    delegate: Choice {
                        required property var modelData
                        title: modelData[1]
                        trailing: modelData[0].replace(".UTF-8", "")
                        selected: r.locale === modelData[0]
                        onClicked: r.locale = modelData[0]
                    }
                }
                Text { text: "Keyboard (text console and disk passphrase)"; color: Theme.m3onSurfaceVariant; font.family: Theme.body; font.pixelSize: 13; Layout.topMargin: 6 }
                SearchList {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    items: r.keymaps
                    current: r.keymap
                    icon: "keyboard"
                    placeholder: "Search layouts (us, de, fr…)"
                    onPicked: v => r.keymap = v
                }
            }
        }
    }

    component NetworkPage: ColumnLayout {
        property var r
        anchors.fill: parent
        spacing: 18
        Component.onCompleted: r.rescanWifi()
        Heading {
            title: "Network"
            subtitle: "Optional. DevOS installs completely from this USB stick; connect if you want updates right away."
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 72
            radius: 20
            color: r.netState === "connected" ? Theme.m3primaryContainer : Theme.m3surfaceContainer
            RowLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 14
                MIcon { name: r.netState === "connected" ? "wifi" : "wifi_off"; size: 26; fill: 1
                        color: r.netState === "connected" ? Theme.m3onPrimaryContainer : Theme.m3onSurfaceVariant }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text { text: r.netState === "connected" ? "Connected" : "Not connected"
                           color: r.netState === "connected" ? Theme.m3onPrimaryContainer : Theme.m3onSurface
                           font.family: Theme.body; font.pixelSize: 15; font.weight: Font.DemiBold }
                    Text { text: r.netState === "connected" ? r.netName : "You can skip this step."
                           color: r.netState === "connected" ? Theme.m3onPrimaryContainer : Theme.m3onSurfaceVariant
                           font.family: Theme.body; font.pixelSize: 13 }
                }
                DButton { label: "Rescan"; icon: "refresh"; small: true; onClicked: r.rescanWifi() }
            }
        }
        Text {
            visible: r.wifi.length > 0
            text: "Wi-Fi networks"
            color: Theme.m3onSurfaceVariant; font.family: Theme.body; font.pixelSize: 13
        }
        Text {
            visible: r.wifi.length === 0
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: r.wifiScanning ? "Looking for Wi-Fi networks…" : "No Wi-Fi networks found. A network cable works too."
            color: Theme.m3onSurfaceVariant; font.family: Theme.body; font.pixelSize: 13
        }
        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 4
            boundsBehavior: Flickable.StopAtBounds
            model: r.wifi
            delegate: ColumnLayout {
                id: wrow
                required property var modelData
                width: ListView.view.width
                spacing: 6
                Choice {
                    icon: modelData.signal > 66 ? "network_wifi" : modelData.signal > 33 ? "network_wifi_2_bar" : "network_wifi_1_bar"
                    title: wrow.modelData.ssid
                    subtitle: wrow.modelData.active ? "Connected" : wrow.modelData.secure ? "Secured" : "Open"
                    trailing: wrow.modelData.secure ? "🔒" : ""
                    selected: wrow.modelData.active || r.wifiTarget === wrow.modelData.ssid
                    onClicked: {
                        if (wrow.modelData.active) return;
                        if (wrow.modelData.secure) { r.wifiTarget = wrow.modelData.ssid; r.wifiError = ""; }
                        else r.connectWifi(wrow.modelData.ssid, "");
                    }
                }
                RowLayout {
                    visible: r.wifiTarget === wrow.modelData.ssid && !wrow.modelData.active
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    spacing: 8
                    Field { id: wpass; icon: "key"; placeholder: "Wi-Fi password"; secret: true
                            input.onAccepted: r.connectWifi(wrow.modelData.ssid, wpass.text) }
                    DButton { label: r.wifiConnecting ? "Connecting…" : "Connect"; variant: "primary"
                              onClicked: r.connectWifi(wrow.modelData.ssid, wpass.text) }
                }
                Text {
                    visible: r.wifiTarget === wrow.modelData.ssid && r.wifiError !== ""
                    Layout.leftMargin: 16
                    text: r.wifiError
                    color: Theme.m3error; font.family: Theme.body; font.pixelSize: 12
                }
            }
        }
    }

    component DiskPage: ColumnLayout {
        property var r
        anchors.fill: parent
        spacing: 16
        Heading {
            title: "Disk"
            subtitle: "DevOS uses the whole disk. Everything on the disk you choose will be erased."
        }
        Text {
            visible: r.disks.length === 0
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: r.diskScanning ? "Looking for disks…" : "No disk of at least 8 GB was found."
            color: Theme.m3onSurfaceVariant; font.family: Theme.body; font.pixelSize: 14
        }
        ListView {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, 220)
            clip: true
            spacing: 6
            boundsBehavior: Flickable.StopAtBounds
            model: r.disks
            delegate: Choice {
                required property var modelData
                icon: modelData.tran === "usb" || modelData.removable ? "usb" : "hard_drive"
                title: modelData.model
                subtitle: modelData.path + (modelData.tran ? " · " + modelData.tran.toUpperCase() : "")
                          + (modelData.size < 32e9 ? " · small: at least 32 GB is recommended" : "")
                trailing: r.fmtSize(modelData.size)
                selected: r.disk === modelData.path
                onClicked: r.pickDisk(modelData)
            }
        }
        DButton { label: "Rescan disks"; icon: "refresh"; small: true; variant: "ghost"; onClicked: r.rescanDisks() }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: encCol.implicitHeight + 32
            radius: 20
            color: Theme.m3surfaceContainer
            ColumnLayout {
                id: encCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                spacing: 12
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 14
                    MIcon { name: "lock"; size: 24; fill: r.encrypt ? 1 : 0; color: r.encrypt ? Theme.m3primary : Theme.m3onSurfaceVariant }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text { text: "Encrypt the disk"; color: Theme.m3onSurface; font.family: Theme.body; font.pixelSize: 15; font.weight: Font.DemiBold }
                        Text { Layout.fillWidth: true; wrapMode: Text.WordWrap
                               text: "LUKS2. You type the passphrase at every start; without it the data cannot be read."
                               color: Theme.m3onSurfaceVariant; font.family: Theme.body; font.pixelSize: 13 }
                    }
                    Toggle { checked: r.encrypt; onToggled: r.encrypt = !r.encrypt }
                }
                RowLayout {
                    visible: r.encrypt
                    Layout.fillWidth: true
                    spacing: 10
                    Field { id: luksField; icon: "key"; placeholder: "Passphrase (8 characters or more)"; secret: true
                            bad: text !== "" && text.length < 8; input.onTextChanged: r.luks = input.text }
                    Field { id: luks2Field; icon: "key"; placeholder: "Repeat the passphrase"; secret: true
                            bad: text !== "" && text !== luksField.text; input.onTextChanged: r.luks2 = input.text }
                }
            }
        }
        Item { Layout.fillHeight: true }
    }

    component AccountPage: ColumnLayout {
        property var r
        anchors.fill: parent
        spacing: 16
        Heading { title: "Your account"; subtitle: "You use this account to log in and for administrator tasks (sudo)." }
        GridLayout {
            Layout.fillWidth: true
            Layout.maximumWidth: 640
            columns: 2
            columnSpacing: 14
            rowSpacing: 8
            Text { text: "User name"; color: Theme.m3onSurfaceVariant; font.family: Theme.body; font.pixelSize: 13 }
            Text { text: "Computer name"; color: Theme.m3onSurfaceVariant; font.family: Theme.body; font.pixelSize: 13 }
            Field {
                id: userField
                icon: "person"; placeholder: "e.g. alex"
                bad: text !== "" && !r.usernameOk
                input.onTextChanged: {
                    const t = input.text.toLowerCase().replace(/\s/g, "");
                    if (t !== input.text) input.text = t;
                    r.username = t;
                }
            }
            Field {
                icon: "computer"; text: r.hostname
                bad: !r.hostnameOk
                input.onTextChanged: r.hostname = input.text.toLowerCase()
            }
            Text { text: "Password"; color: Theme.m3onSurfaceVariant; font.family: Theme.body; font.pixelSize: 13; Layout.topMargin: 8 }
            Text { text: "Repeat the password"; color: Theme.m3onSurfaceVariant; font.family: Theme.body; font.pixelSize: 13; Layout.topMargin: 8 }
            Field { id: passField; icon: "password"; placeholder: "Password"; secret: true; input.onTextChanged: r.password = input.text }
            Field { id: pass2Field; icon: "password"; placeholder: "Password again"; secret: true
                    bad: text !== "" && text !== passField.text; input.onTextChanged: r.password2 = input.text }
        }
        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: userField.text !== "" && !r.usernameOk ? "User names use lowercase letters, digits, - and _, and start with a letter."
                : !r.hostnameOk ? "Computer names use lowercase letters, digits and -."
                : pass2Field.text !== "" && !r.passwordOk ? "The passwords don't match."
                : ""
            color: Theme.m3error; font.family: Theme.body; font.pixelSize: 13
        }
        Item { Layout.fillHeight: true }
    }

    component ProfilesPage: ColumnLayout {
        property var r
        anchors.fill: parent
        spacing: 16
        Heading {
            title: "Developer profiles"
            subtitle: "Tool sets for your kind of work. All of them are on this USB stick; you can add more later in Welcome."
        }
        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 2
            columnSpacing: 12
            rowSpacing: 12
            Repeater {
                model: [
                    { id: "general", icon: "terminal", name: "General", desc: "Git, compilers, Python, Node.js, Go, Rust, Podman, VS Code, CLI tools", locked: true },
                    { id: "web", icon: "language", name: "Web", desc: "pnpm, Yarn, Deno, Bun, nginx, Chromium, Firefox Developer Edition" },
                    { id: "backend", icon: "dns", name: "Backend", desc: "PostgreSQL, Valkey, MariaDB client, JDK, Maven, Gradle, .NET, PHP, gRPC" },
                    { id: "systems", icon: "memory", name: "Systems", desc: "GCC, LLVM, NASM, QEMU, bpftrace, Meson, mold, cross compilers" },
                    { id: "ai", icon: "psychology", name: "AI", desc: "PyTorch, NumPy, pandas, scikit-learn, Matplotlib, JupyterLab" },
                    { id: "embedded", icon: "developer_board", name: "Embedded", desc: "ARM and AVR toolchains, OpenOCD, dfu-util, serial consoles" }
                ]
                delegate: Rectangle {
                    id: pc
                    required property var modelData
                    readonly property bool on: modelData.locked || r.profiles[modelData.id] === true
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 92
                    radius: 20
                    color: on ? Theme.m3secondaryContainer
                         : pcMouse.containsMouse ? Theme.hover(Theme.m3surfaceContainer, Theme.m3onSurface) : Theme.m3surfaceContainer
                    border.width: on && !modelData.locked ? 2 : 0
                    border.color: Theme.m3primary
                    Behavior on color { ColorAnimation { duration: Theme.durationFast } }
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 14
                        Rectangle {
                            implicitWidth: 44; implicitHeight: 44; radius: 14
                            color: pc.on ? Theme.m3primary : Theme.m3surfaceContainerHighest
                            MIcon { anchors.centerIn: parent; name: pc.modelData.icon; size: 22; fill: 1
                                    color: pc.on ? Theme.m3onPrimary : Theme.m3onSurfaceVariant }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3
                            RowLayout {
                                spacing: 8
                                Text { text: pc.modelData.name; color: Theme.m3onSurface; font.family: Theme.body; font.pixelSize: 15; font.weight: Font.DemiBold }
                                Text { visible: pc.modelData.locked === true; text: "always installed"; color: Theme.m3onSurfaceVariant; font.family: Theme.body; font.pixelSize: 12 }
                            }
                            Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: pc.modelData.desc
                                   color: Theme.m3onSurfaceVariant; font.family: Theme.body; font.pixelSize: 12; lineHeight: 1.15 }
                        }
                        MIcon { name: pc.on ? "check_circle" : "add_circle"; fill: pc.on ? 1 : 0; size: 24
                                color: pc.on ? Theme.m3primary : Theme.m3onSurfaceVariant }
                    }
                    MouseArea {
                        id: pcMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: pc.modelData.locked ? Qt.ArrowCursor : Qt.PointingHandCursor
                        onClicked: {
                            if (pc.modelData.locked) return;
                            const p = Object.assign({}, r.profiles);
                            p[pc.modelData.id] = !p[pc.modelData.id];
                            r.profiles = p;
                        }
                    }
                }
            }
        }
    }

    component SummaryPage: ColumnLayout {
        property var r
        anchors.fill: parent
        spacing: 16
        Heading { title: "Ready to install"; subtitle: "Check your choices. Nothing has changed on this computer yet." }
        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 12
            rowSpacing: 12
            Repeater {
                model: [
                    { icon: "hard_drive", label: "Disk", value: r.diskLabel + " · " + r.fmtSize(r.diskBytes) + " · erased", page: 3 },
                    { icon: "lock", label: "Encryption", value: r.encrypt ? "On (LUKS2)" : "Off", page: 3 },
                    { icon: "person", label: "Account", value: r.username + " on " + r.hostname, page: 4 },
                    { icon: "public", label: "Region", value: r.timezone.replace(/_/g, " ") + " · " + r.locale.replace(".UTF-8", ""), page: 1 },
                    { icon: "keyboard", label: "Keyboard", value: r.keymap, page: 1 },
                    { icon: "deployed_code", label: "Profiles", value: ["General"].concat(r.chosenProfiles().map(p => p.charAt(0).toUpperCase() + p.slice(1))).join(", "), page: 5 }
                ]
                delegate: Rectangle {
                    id: sc
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 76
                    radius: 20
                    color: scMouse.containsMouse ? Theme.hover(Theme.m3surfaceContainer, Theme.m3onSurface) : Theme.m3surfaceContainer
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 14
                        MIcon { name: sc.modelData.icon; size: 24; color: Theme.m3primary }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text { text: sc.modelData.label; color: Theme.m3onSurfaceVariant; font.family: Theme.body; font.pixelSize: 12 }
                            Text { Layout.fillWidth: true; text: sc.modelData.value; elide: Text.ElideRight
                                   color: Theme.m3onSurface; font.family: Theme.body; font.pixelSize: 15; font.weight: Font.Medium }
                        }
                        MIcon { name: "edit"; size: 18; color: Theme.m3onSurfaceVariant; opacity: scMouse.containsMouse ? 1 : 0 }
                    }
                    MouseArea { id: scMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: r.go(sc.modelData.page) }
                }
            }
        }
        Item { Layout.fillHeight: true }
    }

    component InstallPage: ColumnLayout {
        property var r
        anchors.fill: parent
        spacing: 0
        Item { Layout.fillHeight: true }

        // Progress ring.
        Item {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 168
            implicitHeight: 168
            Canvas {
                id: ring
                anchors.fill: parent
                property real value: r.overall
                property color track: Theme.m3surfaceContainerHighest
                property color bar: r.error !== "" ? Theme.m3error : Theme.m3primary
                onValueChanged: requestPaint()
                onBarChanged: requestPaint()
                Behavior on value { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const c = width / 2, r = c - 10;
                    ctx.lineCap = "round";
                    ctx.lineWidth = 12;
                    ctx.strokeStyle = track;
                    ctx.beginPath(); ctx.arc(c, c, r, 0, 2 * Math.PI); ctx.stroke();
                    ctx.strokeStyle = bar;
                    ctx.beginPath(); ctx.arc(c, c, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * Math.max(0.01, value)); ctx.stroke();
                }
            }
            MIcon {
                anchors.centerIn: parent
                visible: r.finished || r.error !== ""
                name: r.error !== "" ? "error" : "check"
                size: 64
                fill: 1
                color: r.error !== "" ? Theme.m3error : Theme.m3primary
            }
            Text {
                anchors.centerIn: parent
                visible: !r.finished && r.error === ""
                text: Math.round(r.overall * 100) + "%"
                color: Theme.m3onSurface
                font.family: Theme.display; font.pixelSize: 36; font.weight: Font.DemiBold
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 28
            text: r.error !== "" ? "The installation failed"
                : r.finished ? "DevOS is installed"
                : r.stepText
            color: Theme.m3onSurface
            font.family: Theme.display; font.pixelSize: 26; font.weight: Font.DemiBold
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 8
            Layout.maximumWidth: 560
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: r.error !== "" ? r.error
                : r.finished ? "Remove the USB stick, then restart to start DevOS."
                : r.detail !== "" ? r.detail
                : "This takes a few minutes. You can keep using the terminal meanwhile."
            color: r.error !== "" ? Theme.m3error : Theme.m3onSurfaceVariant
            font.family: r.detail !== "" && !r.finished && r.error === "" ? Theme.mono : Theme.body
            font.pixelSize: 14
        }

        // Steps.
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 28
            spacing: 8
            Repeater {
                model: ["Disk", "Packages", "Setup", "Boot loader", "Finish"]
                delegate: Rectangle {
                    required property string modelData
                    required property int index
                    readonly property bool done: r.finished || index + 1 < r.stepNo
                    readonly property bool active: !r.finished && index + 1 === r.stepNo
                    implicitHeight: 32
                    implicitWidth: sr.implicitWidth + 22
                    radius: 16
                    color: active ? Theme.m3secondaryContainer : done ? Theme.alpha(Theme.m3primary, 0.14) : Theme.m3surfaceContainer
                    RowLayout {
                        id: sr
                        anchors.centerIn: parent
                        spacing: 6
                        MIcon { visible: !active; name: done ? "check" : "circle"; size: 16
                                color: done ? Theme.m3primary : Theme.m3outline }
                        MIcon { visible: active; name: "progress_activity"; size: 16; color: Theme.m3onSecondaryContainer
                                RotationAnimation on rotation { running: active && r.error === ""; from: 0; to: 360; duration: 1200; loops: Animation.Infinite }
                        }
                        Text { text: modelData; color: active ? Theme.m3onSecondaryContainer : Theme.m3onSurfaceVariant
                               font.family: Theme.body; font.pixelSize: 12 }
                    }
                }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 28
            spacing: 10
            DButton { visible: r.error !== ""; label: "Show details"; icon: "description"; variant: "ghost"
                      onClicked: logView.visible = !logView.visible }
            DButton { visible: r.error !== ""; label: "Open a terminal"; icon: "terminal"; onClicked: r.openTerminal() }
            DButton { visible: r.error !== ""; label: "Back to settings"; icon: "arrow_back"
                      onClicked: { r.error = ""; r.page = 6; } }
            DButton { visible: r.finished; label: "Restart now"; icon: "restart_alt"; variant: "primary"; onClicked: r.reboot() }
        }

        Rectangle {
            id: logView
            visible: false
            Layout.fillWidth: true
            Layout.preferredHeight: 140
            Layout.topMargin: 16
            radius: 16
            color: Theme.m3surfaceContainerLowest
            ListView {
                anchors.fill: parent
                anchors.margins: 12
                clip: true
                model: r.log
                onCountChanged: positionViewAtEnd()
                delegate: Text {
                    required property string modelData
                    width: ListView.view.width
                    text: modelData
                    elide: Text.ElideRight
                    color: Theme.m3onSurfaceVariant
                    font.family: Theme.mono; font.pixelSize: 11
                }
            }
        }
        Item { Layout.fillHeight: true }
    }
}
