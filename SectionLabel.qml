import QtQuick

// Small, dim, sentence-case heading ("Theme", "Display"…).
Text {
    property color foreground: "#e8dcc8"
    property string fontFamily: ""
    property int pixelSize: 12

    color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.6)
    font.family: fontFamily
    font.pixelSize: pixelSize
    textFormat: Text.PlainText
}
