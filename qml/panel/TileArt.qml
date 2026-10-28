import QtQuick

// The little picture inside a settings tile. One file draws every choice that
// gets a tile (see `control: "tiles"` in js/Schema.js), picked by setting key
// and option. Sizes are fixed on purpose: the Spacing tile must not change
// shape just because the Spacing setting changed.
Item {
    id: art

    property var ui: null
    property string key: ""      // setting key, e.g. "density"
    property string opt: ""      // the option this tile stands for

    implicitWidth: 84
    implicitHeight: 40
    width: implicitWidth
    height: implicitHeight

    readonly property color ink: ui.tint(0.40)
    readonly property color mid: ui.tint(0.22)
    readonly property color faint: ui.tint(0.10)

    // ---- Card style: cardStyle --------------------------------------------------
    Rectangle {
        visible: art.key === "cardStyle"
        anchors.centerIn: parent
        width: 60; height: 34; radius: 6
        color: art.opt === "soft" ? art.faint : "transparent"
        border.width: art.opt === "flat" ? 0 : 1
        border.color: art.opt === "outline" ? art.ink : art.mid
        Column {
            x: 8; y: 7
            spacing: 4
            Rectangle { width: 30; height: 4; radius: 2; color: art.ink }
            Rectangle { width: 42; height: 3; radius: 1.5; color: art.mid }
            Rectangle { width: 20; height: 3; radius: 1.5; color: art.mid }
        }
    }

    // ---- Spacing: density -------------------------------------------------------
    Column {
        visible: art.key === "density"
        anchors.centerIn: parent
        spacing: art.opt === "compact" ? 3 : (art.opt === "spacious" ? 10 : 6)
        Repeater {
            model: 3
            Rectangle { width: 60; height: 5; radius: 2; color: index === 0 ? art.ink : art.mid }
        }
    }

    // ---- Open as: openAs --------------------------------------------------------
    Item {
        anchors.fill: parent
        visible: art.key === "openAs"

        Rectangle { x: 0; y: 0; width: parent.width; height: 6; radius: 2; color: art.mid }   // the bar
        Rectangle {   // bar panel: hangs off the bar
            visible: art.opt === "panel"
            x: parent.width * 0.2; y: 6
            width: parent.width * 0.6; height: 32
            radius: 3; color: art.faint
            border.width: 1; border.color: art.ink
        }
        Rectangle {   // own window: floats on its own, with a title strip
            visible: art.opt === "window"
            x: parent.width * 0.14; y: 14
            width: parent.width * 0.72; height: 25
            radius: 3; color: art.faint
            border.width: 1; border.color: art.ink
            Rectangle { x: 1; y: 1; width: parent.width - 2; height: 5; radius: 2; color: art.mid }
        }
    }
}
