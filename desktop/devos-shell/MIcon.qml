import QtQuick

// A Material Symbols Rounded icon, as end-4 draws them (same font, fill and weight axes).
//   MIcon { name: "smart_toy"; size: 20; fill: 1 }
Text {
    id: icon
    property string name: ""
    property int size: 20
    property real fill: 0          // 0 = outlined, 1 = filled (animatable)
    property int weight: 400

    text: name
    color: Theme.text
    font.family: Theme.icons
    font.pixelSize: size
    font.variableAxes: ({ "FILL": fill, "wght": weight, "opsz": Math.max(20, Math.min(48, size)), "GRAD": 0 })
    renderType: Text.NativeRendering
    verticalAlignment: Text.AlignVCenter
    horizontalAlignment: Text.AlignHCenter
    Behavior on fill { NumberAnimation { duration: Theme.durationFast; easing.type: Easing.OutCubic } }
}
