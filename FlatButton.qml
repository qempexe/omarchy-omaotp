import QtQuick

// Themed button. Flat by default; `outlined` gives the rounded pill look
// (used for tabs, toggles and chips). `dotColor` adds a small colour dot.
Rectangle {
    id: btn

    property string text: ""
    property bool selected: false
    property bool bold: false
    property bool outlined: false
    property color dotColor: "transparent"
    property color foreground: "#e8dcc8"
    property color accent: "#d4a35a"
    property string fontFamily: ""
    property int pixelSize: 12
    property int hPad: 12

    signal clicked()

    implicitHeight: 30
    implicitWidth: row.implicitWidth + hPad * 2
    radius: 6
    opacity: enabled ? 1 : 0.4
    // New chips: a soft tint, and an accent outline when selected.
    color: selected ? Qt.rgba(accent.r, accent.g, accent.b, 0.2)
         : Qt.rgba(foreground.r, foreground.g, foreground.b, area.containsMouse ? 0.14 : (outlined ? 0.06 : 0))
    border.width: selected ? 1 : 0
    border.color: accent

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Math.round(btn.pixelSize * 0.55)

        Rectangle {
            visible: btn.dotColor.a > 0
            anchors.verticalCenter: parent.verticalCenter
            width: Math.round(btn.pixelSize * 0.7)
            height: width
            radius: width / 2
            color: btn.dotColor
        }
        Text {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            text: btn.text
            color: btn.foreground
            font.family: btn.fontFamily
            font.pixelSize: btn.pixelSize
            font.weight: (btn.bold || btn.selected) ? Font.DemiBold : Font.Normal
            textFormat: Text.PlainText
        }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }
}
