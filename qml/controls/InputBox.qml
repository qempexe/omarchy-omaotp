import QtQuick

// A text field in its box, with a placeholder. The typing itself is PasteInput:
// no native text field, and the clipboard is read only on Ctrl+V, capped.
Rectangle {
    id: box

    property var ui: null
    property alias key: input.key
    property alias text: input.text
    property alias masked: input.masked
    property alias maximumLength: input.maximumLength
    property string placeholder: ""
    signal edited()
    signal accepted()

    function clear() { input.text = "" }
    function focusField() { input.forceActiveFocus() }

    implicitHeight: ui.px(32)
    radius: ui.r(1.5)
    color: ui.tint(0.05)
    border.width: 1
    border.color: input.activeFocus ? ui.tint(0.28) : ui.tint(0.08)
    clip: true

    PasteInput {
        id: input
        service: box.ui ? box.ui.service : null
        anchors.fill: parent
        anchors.leftMargin: ui.px(10)
        anchors.rightMargin: ui.px(10)
        color: ui.fg
        font.family: ui.fontName
        font.pixelSize: ui.fs(12)
        onTextEdited: box.edited()
        onAccepted: box.accepted()

        Txt {
            ui: box.ui
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            elide: Text.ElideRight
            visible: input.text === ""
            text: box.placeholder
            opacity: 0.4
            font.pixelSize: ui.fs(12)
        }
    }
}
