//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Wayland

// DevOS graphical login (SRS DESK-010, D-03). Runs as the greetd greeter on the
// greeter's own minimal Hyprland (see /usr/lib/devos/devos-greeter):
//   qs -p /usr/share/devos/greeter
// One full-screen layer surface per monitor; the login card is on the first one.
ShellRoot {
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            readonly property bool primary: modelData === Quickshell.screens[0]

            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "#070a11"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "devos-greeter"
            WlrLayershell.keyboardFocus: primary ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            LoginScreen {
                anchors.fill: parent
                showLogin: win.primary
            }
        }
    }
}
