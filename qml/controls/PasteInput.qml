import QtQuick

// A single-line text field that is NOT a TextInput.
//
// Qt's TextInput carries its own clipboard handling (it watches the clipboard and
// reads foreign text through Qt's Wayland receiver, which has no total byte or time
// limit). Intercepting its paste keys does not remove that, so this field is built
// from a plain Text instead: typing, Backspace, Delete, the arrow keys, Home and End
// are handled here, and nothing in this item ever touches the clipboard.
//
// Ctrl+V and Shift+Insert ask the Service for a capped read (see Service.requestPaste)
// and the text comes back through Service.pasted, addressed by `key`.
//
// Not supported, by design: selecting text with the mouse, cut and copy, undo, and
// input-method (IME) composition.
Item {
    id: field

    property string key: ""            // identifies this field in Service.pasted
    property var service: null         // the Service that performs the capped read

    property string text: ""
    property int maximumLength: 32767
    property color color: "white"
    property alias font: display.font
    property int cursorPosition: 0
    property bool masked: false        // a password: drawn as dots, never as the text itself
    readonly property string _shown: masked ? "\u2022".repeat(text.length) : text

    signal textEdited()                // the user changed the text (typing, deleting, paste)
    signal editingFinished()           // Return / Enter, or the field lost focus
    signal accepted()                  // Return / Enter only

    activeFocusOnTab: true
    clip: true                         // text longer than the box is cut at its edge

    // ---- internal state -------------------------------------------------------
    property bool _ready: false
    property bool _internal: false     // true while this item itself is changing `text`
    property bool _blink: true
    property real _scroll: 0           // how far the text is shifted left to keep the cursor in view
    property real _cursorX: 0

    function _setText(t, pos) {
        _internal = true
        text = t
        _internal = false
        cursorPosition = pos
        _reveal()
    }

    // Insert `str` at `position`, trimmed to what still fits under maximumLength.
    function insert(position, str) {
        let s = String(str === null || str === undefined ? "" : str)
        const room = maximumLength - text.length
        if (room <= 0 || s === "") return
        s = s.slice(0, room)
        const p = Math.max(0, Math.min(text.length, position))
        _setText(text.slice(0, p) + s + text.slice(p), p + s.length)
        textEdited()
    }

    // Remove text[from, to).
    function _erase(from, to) {
        const a = Math.max(0, from)
        const b = Math.min(text.length, to)
        if (b <= a) return
        _setText(text.slice(0, a) + text.slice(b), a)
        textEdited()
    }

    // Keep the cursor inside the visible part of the box, and place the caret.
    function _reveal() {
        if (!_ready) return
        prefixM.text = _shown.substring(0, cursorPosition)
        fullM.text = _shown
        const cx = prefixM.advanceWidth
        const full = fullM.advanceWidth
        const w = width
        let s = _scroll
        if (cx - s > w - 2) s = cx - w + 2
        if (cx - s < 0) s = cx
        s = Math.min(s, Math.max(0, full - w + 2))
        _scroll = Math.max(0, s)
        _cursorX = cx - _scroll
    }

    onTextChanged: {
        if (!_internal) cursorPosition = text.length     // set from outside: cursor goes to the end
        _reveal()
    }
    onCursorPositionChanged: { _blink = true; _reveal() }
    onWidthChanged: _reveal()
    onActiveFocusChanged: {
        _blink = true
        if (!activeFocus) editingFinished()
    }
    Component.onCompleted: { _ready = true; _reveal() }

    // ---- keyboard ---------------------------------------------------------------
    Keys.onPressed: function(event) {
        if (event.matches(StandardKey.Paste)) {          // Ctrl+V and Shift+Insert
            event.accepted = true
            if (field.service) field.service.requestPaste(field.key)
            return
        }
        switch (event.key) {
        case Qt.Key_Backspace:
            field._erase(field.cursorPosition - 1, field.cursorPosition)
            event.accepted = true
            return
        case Qt.Key_Delete:
            field._erase(field.cursorPosition, field.cursorPosition + 1)
            event.accepted = true
            return
        case Qt.Key_Left:
            field.cursorPosition = Math.max(0, field.cursorPosition - 1)
            event.accepted = true
            return
        case Qt.Key_Right:
            field.cursorPosition = Math.min(field.text.length, field.cursorPosition + 1)
            event.accepted = true
            return
        case Qt.Key_Home:
            field.cursorPosition = 0
            event.accepted = true
            return
        case Qt.Key_End:
            field.cursorPosition = field.text.length
            event.accepted = true
            return
        case Qt.Key_Return:
        case Qt.Key_Enter:
            field.accepted()
            field.editingFinished()      // not accepted: parents may still react to Return
            return
        }
        // Printable text. Ctrl / Meta combinations are shortcuts, not characters.
        const held = (event.modifiers & Qt.ControlModifier) || (event.modifiers & Qt.MetaModifier)
        if (!held && event.text.length > 0) {
            const c = event.text.charCodeAt(0)
            if (c >= 32 && c !== 127) {
                field.insert(field.cursorPosition, event.text)
                event.accepted = true
            }
        }
        // Everything else (Escape, Up, Down, Tab ...) is left for the parents.
    }

    // ---- drawing ----------------------------------------------------------------
    Text {
        id: display
        textFormat: Text.PlainText
        text: field._shown
        color: field.color
        wrapMode: Text.NoWrap
        x: -field._scroll
        anchors.verticalCenter: parent.verticalCenter
    }

    Rectangle {
        id: caret
        width: 1
        height: display.height
        x: field._cursorX
        y: (field.height - height) / 2
        color: field.color
        visible: field.activeFocus && field._blink
    }

    Timer {
        interval: 530
        repeat: true
        running: field.activeFocus
        onTriggered: field._blink = !field._blink
    }

    // Measuring only; nothing is drawn.
    TextMetrics { id: prefixM; font: display.font }
    TextMetrics { id: fullM; font: display.font }

    Connections {
        target: display
        function onFontChanged() { Qt.callLater(() => { field._reveal() }) }
    }

    // ---- mouse: click to focus and place the cursor ---------------------------------
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.IBeamCursor
        onPressed: function(mouse) {
            field.forceActiveFocus()
            const p = display.positionAt(mouse.x + field._scroll, display.height / 2)
            field.cursorPosition = Math.max(0, Math.min(field.text.length, p))
        }
    }

    // ---- result of the capped clipboard read ------------------------------------------
    Connections {
        target: field.service
        ignoreUnknownSignals: true
        function onPasted(k, text) {
            if (k !== field.key) return
            const line = String(text === null || text === undefined ? "" : text).split(/\r?\n/)[0]
            field.insert(field.cursorPosition, line)   // maximumLength still applies
        }
    }
}
