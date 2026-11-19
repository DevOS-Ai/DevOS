//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Wayland

// DevOS graphical installer (SRS §7.1). Runs in the live ISO's Hyprland session:
//   qs -p /usr/share/devos-installer/ui
// A full-screen layer surface on the bottom layer, so a terminal opened from the
// installer floats above it.
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
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.namespace: "devos-installer"
            WlrLayershell.keyboardFocus: primary ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

            Installer {
                anchors.fill: parent
                showUi: win.primary
            }
        }
    }
}
