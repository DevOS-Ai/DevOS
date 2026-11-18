import QtQuick
import QtQuick.Layouts

// Material 3 button in the end-4 style: pill shape, state layers on hover and press,
// optional leading icon. Activates on click, or on Enter/Space while focused (SRS UX-001).
//   variant: primary (filled) | secondary (tonal) | ghost (text) | danger (error tonal)
Rectangle {
    id: b
    property string label: ""
    property string icon: ""
    property string variant: "secondary"
    property bool small: false
    signal clicked()

    readonly property color base: variant === "primary" ? Theme.m3primary
        : variant === "danger" ? Theme.m3errorContainer
        : variant === "ghost" ? Theme.alpha(Theme.m3surfaceContainerHigh, 0)
        : Theme.m3secondaryContainer
    readonly property color onBase: variant === "primary" ? Theme.m3onPrimary
        : variant === "danger" ? Theme.m3onErrorContainer
        : variant === "ghost" ? Theme.m3primary
        : Theme.m3onSecondaryContainer

    activeFocusOnTab: true
    implicitHeight: small ? 30 : 38
    implicitWidth: row.implicitWidth + (small ? 22 : 30)
    radius: Theme.radiusFull
    color: mouse.pressed ? Theme.pressed(base, onBase) : mouse.containsMouse ? Theme.hover(base, onBase) : base
    border.width: activeFocus ? 2 : 0
    border.color: Theme.m3onSurface
    scale: mouse.pressed ? 0.97 : 1
    Behavior on color { ColorAnimation { duration: Theme.durationFast } }
    Behavior on scale { NumberAnimation { duration: Theme.durationFast; easing.type: Easing.OutBack } }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 6
        MIcon {
            visible: b.icon !== ""
            name: b.icon
            size: b.small ? 16 : 18
            color: b.onBase
        }
        Text {
            visible: b.label !== ""
            text: b.label
            color: b.onBase
            font.family: Theme.body
            font.pixelSize: b.small ? 12 : 13
            font.weight: Font.Medium
        }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: b.clicked()
    }
    Keys.onReturnPressed: b.clicked()
    Keys.onEnterPressed: b.clicked()
    Keys.onSpacePressed: b.clicked()
}
