import QtQuick

// Filter chip: label, optional count, on/off. `tone` colors the active state.
Rectangle {
    id: root

    property var ui: null
    property string label: ""
    property int count: -1
    property bool on: false
    property color tone: ui.accent
    property bool dot: false

    signal clicked()

    implicitWidth: row.implicitWidth + ui.px(16)
    implicitHeight: ui.px(24)
    radius: ui.r(1.5)
    color: on ? Qt.rgba(tone.r, tone.g, tone.b, 0.22) : ui.tint(area.containsMouse ? 0.12 : 0.06)
    border.width: 1
    border.color: on ? tone : ui.tint(0.10)
    Behavior on color { enabled: ui.animations; ColorAnimation { duration: 90 } }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: ui.px(5)

        Rectangle {
            visible: root.dot
            width: ui.px(7); height: ui.px(7); radius: width / 2
            color: root.tone
            anchors.verticalCenter: parent.verticalCenter
        }
        Txt {
            ui: root.ui
            text: root.label
            color: root.on ? ui.onText(root.tone) : ui.fg
            font.pixelSize: ui.fs(11)
            font.weight: root.on ? Font.DemiBold : Font.Normal
            opacity: root.on ? 1.0 : 0.8
        }
        Txt {
            ui: root.ui
            visible: root.count >= 0
            text: String(root.count)
            font.pixelSize: ui.fs(10)
            opacity: 0.5
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
