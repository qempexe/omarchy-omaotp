import QtQuick

// Every piece of text in Omaotp goes through this. Account names come from
// links you paste, so rich-text auto-detection (which could fetch remote <img> URLs)
// is pinned off here once instead of at every call site.
Text {
    property var ui: null

    textFormat: Text.PlainText
    color: ui ? ui.fg : "white"
    font.family: ui ? ui.fontName : ""
    font.pixelSize: ui ? ui.fs(11) : 11
}
