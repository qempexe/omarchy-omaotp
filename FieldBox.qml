import QtQuick
import Quickshell.Io

// Minimal themed text field (no dependency on QtQuick.Controls or shell styles).
//
// The editor is NOT a TextInput. A TextInput connects to the clipboard in its
// constructor and re-reads foreign clipboard data on every clipboard change,
// unbounded, with no way to turn that off. This field draws a plain Text and
// handles keys itself, so no clipboard connection ever exists. Paste (Ctrl+V /
// Shift+Insert) is the only way in: one fixed `wl-paste | head -c` call, capped
// at `pasteMaxBytes`, first line only.
// Not supported (by design): IME composition, copy/cut, mouse selection.
//
// `text` is one-way: set it from outside (a binding is fine). The field mirrors it
// and emits `edited(value)` only for real user input, so a binding can never loop.
Rectangle {
    id: box

    property string text: ""
    property string placeholderText: ""
    property color foreground: "#e8dcc8"
    property color accent: "#d4a35a"
    property string fontFamily: ""
    property int pixelSize: 12
    property int maxLength: 256            // max characters stored
    property int pasteMaxBytes: 1024       // byte cap for the clipboard read
    property bool secret: false            // show bullets instead of the characters
    readonly property string display: secret ? new Array(input.text.length + 1).join("\u2022") : input.text
    readonly property bool focused: input.activeFocus

    signal accepted()
    signal edited(string value)            // user typed or pasted

    function forceFocus() { input.forceActiveFocus() }
    function clear() { input.text = ""; input.cursorPosition = 0 }

    implicitHeight: 34
    radius: 8
    color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.08)
    border.width: 1
    border.color: focused ? accent : Qt.rgba(foreground.r, foreground.g, foreground.b, 0.18)

    // Follow outside changes (the setting changed elsewhere, a swatch was clicked)
    // but never our own edit mid-typing: the cleaned-up value that comes back
    // would eat characters such as a trailing space.
    property bool editing: false
    function mirror() {
        if (editing || input.text === box.text) return
        input.text = box.text
        input.cursorPosition = Math.min(input.cursorPosition, input.text.length)
        input.selectAll = false
    }
    onTextChanged: mirror()
    Component.onCompleted: { input.text = box.text; input.cursorPosition = input.text.length }

    function report() {
        editing = true
        edited(input.text)
        editing = false
    }

    // ---- bounded paste ---------------------------------------------------------
    property var pasteTarget: null
    function requestPaste() {
        if (pasteProc.running) return
        pasteProc.running = true
    }
    Process {
        id: pasteProc
        running: false
        // Fixed command, no user input. timeout ends a stalled clipboard read;
        // head -c stops wl-paste early, so a huge clipboard is never fully read.
        command: ["sh", "-c", "timeout 2 wl-paste --no-newline 2>/dev/null | head -c " + Math.max(1, Math.round(box.pasteMaxBytes))]
        stdout: StdioCollector {
            id: pasteOut
            onStreamFinished: {
                var t = String(pasteOut.text || "").split(/\r?\n/)[0]
                input.insert(input.cursorPosition, t)
            }
        }
    }

    // ---- the editor ------------------------------------------------------------
    Item {
        id: input
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        clip: true
        activeFocusOnTab: true

        property string text: ""
        property int cursorPosition: 0
        property bool selectAll: false

        function clampCursor() {
            cursorPosition = Math.max(0, Math.min(text.length, cursorPosition))
        }

        // Insert plain text at `pos` (replaces everything after select-all).
        function insert(pos, str) {
            var t = String(str === null || str === undefined ? "" : str)
                .replace(/[\u0000-\u001f\u007f]/g, "")
            if (t === "") return
            var base = text
            if (selectAll) { base = ""; pos = 0; selectAll = false }
            var room = box.maxLength - base.length
            if (room <= 0) return
            t = t.substring(0, room)
            pos = Math.max(0, Math.min(base.length, pos))
            text = base.substring(0, pos) + t + base.substring(pos)
            cursorPosition = pos + t.length
            box.report()
        }

        function removeBack() {
            if (selectAll) { text = ""; cursorPosition = 0; selectAll = false; box.report(); return }
            if (cursorPosition <= 0) return
            text = text.substring(0, cursorPosition - 1) + text.substring(cursorPosition)
            cursorPosition -= 1
            box.report()
        }

        function removeForward() {
            if (selectAll) { removeBack(); return }
            if (cursorPosition >= text.length) return
            text = text.substring(0, cursorPosition) + text.substring(cursorPosition + 1)
            box.report()
        }

        onActiveFocusChanged: {
            if (activeFocus) { cursorPosition = text.length; blink.restart() }
            else selectAll = false
        }

        FontMetrics {
            id: fm
            font.family: box.fontFamily
            font.pixelSize: box.pixelSize
        }

        Rectangle {          // select-all highlight
            visible: input.selectAll && input.text !== ""
            x: 0
            width: shown.implicitWidth
            height: shown.implicitHeight
            anchors.verticalCenter: parent.verticalCenter
            color: Qt.rgba(box.accent.r, box.accent.g, box.accent.b, 0.35)
        }

        Text {
            id: shown
            anchors.verticalCenter: parent.verticalCenter
            text: box.display
            color: box.foreground
            font.family: box.fontFamily
            font.pixelSize: box.pixelSize
            textFormat: Text.PlainText
        }

        Rectangle {          // caret
            visible: input.activeFocus && blink.on
            width: 1
            height: shown.implicitHeight
            anchors.verticalCenter: parent.verticalCenter
            x: fm.advanceWidth(box.display.substring(0, input.cursorPosition))
            color: box.foreground
        }

        Timer {
            id: blink
            property bool on: true
            interval: 530
            repeat: true
            running: input.activeFocus
            onTriggered: on = !on
            onRunningChanged: if (running) on = true
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton      // middle / right: ignored, nothing pastes
            cursorShape: Qt.IBeamCursor
            onPressed: function(mouse) {
                input.forceActiveFocus()
                input.selectAll = false
                var best = input.text.length
                for (var i = 0; i <= input.text.length; i++) {
                    if (fm.advanceWidth(box.display.substring(0, i)) >= mouse.x) { best = i; break }
                }
                input.cursorPosition = best
                blink.on = true
            }
        }

        Keys.onPressed: function(event) {
            var mods = event.modifiers
            var ctrl = (mods & Qt.ControlModifier) !== 0
            blink.on = true
            if (event.matches(StandardKey.Paste)
                    || (event.key === Qt.Key_Insert && (mods & Qt.ShiftModifier))) {
                event.accepted = true
                box.requestPaste()
                return
            }
            if (ctrl && event.key === Qt.Key_A) { input.selectAll = input.text !== ""; event.accepted = true; return }
            switch (event.key) {
            case Qt.Key_Return:
            case Qt.Key_Enter:
                box.accepted(); event.accepted = true; return
            case Qt.Key_Backspace: removeBack(); event.accepted = true; return
            case Qt.Key_Delete: removeForward(); event.accepted = true; return
            case Qt.Key_Left: selectAll = false; cursorPosition -= 1; clampCursor(); event.accepted = true; return
            case Qt.Key_Right: selectAll = false; cursorPosition += 1; clampCursor(); event.accepted = true; return
            case Qt.Key_Home: selectAll = false; cursorPosition = 0; event.accepted = true; return
            case Qt.Key_End: selectAll = false; cursorPosition = text.length; event.accepted = true; return
            default: break
            }
            // Printable characters only; leave shortcuts (Esc, Alt+arrows...) to the popup.
            if (!ctrl && !(mods & Qt.AltModifier) && !(mods & Qt.MetaModifier)
                    && event.text.length > 0 && event.text.charCodeAt(0) >= 32
                    && event.text.charCodeAt(0) !== 127) {
                insert(cursorPosition, event.text)
                event.accepted = true
            }
        }
    }

    Text {
        anchors.fill: input
        verticalAlignment: Text.AlignVCenter
        visible: input.text.length === 0 && !input.activeFocus
        text: box.placeholderText
        color: Qt.rgba(box.foreground.r, box.foreground.g, box.foreground.b, 0.45)
        font.pixelSize: box.pixelSize
        font.family: box.fontFamily
        elide: Text.ElideRight
        textFormat: Text.PlainText
    }
}
