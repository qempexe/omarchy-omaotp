import QtQuick
import Quickshell

// The docked window, hanging off the bar

// BarWidget.qml talks to this file through a small contract:
// opened, open(), close(), closeForPopoutSwitch(), plus the properties it injects.
Item {
    id: root

    visible: false

    property var bar: null
    property var anchorItem: null
    property var hostWidget: null
    property var ui: null          // shared UiState, injected by BarWidget.qml

    readonly property bool opened: popup.visible
    readonly property bool popoutSwitchClosing: false
    // True for a moment after a click outside closed the popup. That same click may
    // land on the bar button, and BarWidget must not treat it as "open again".
    property bool justClosedByGrab: false

    function open() {
        if (popup.visible) return
        root.locate()
        popup.visible = true
    }
    function close() { popup.visible = false }
    function toggle() { if (popup.visible) root.close(); else root.open() }
    function closeForPopoutSwitch() { root.close() }

    function stepTab(d) {
        if (!root.ui) return
        const names = ["accounts", "settings"]
        const i = names.indexOf(root.ui.tabName)
        root.ui.tabName = names[(Math.max(0, i) + d + names.length) % names.length]
    }

    // ---- placement: never overlap the bar -----------------------------------------
    // Worked out each time the popup is about to open, because the bar's position is
    // not known yet when this file is first loaded. The popup is anchored to the outer
    // edge of the bar's own window (not to the widget, which sits inside the bar's
    // padding), and the gap is transparent padding inside the popup window.
    readonly property bool vertical: {
        const b = root.bar
        if (!b) return false
        try {
            if (b.vertical === true || b.isVertical === true) return true
            if (b.orientation !== undefined && b.orientation === Qt.Vertical) return true
        } catch (e) { }
        return false
    }
    property bool barAtTop: true              // horizontal bar: top edge (else bottom)
    property bool barAtLeft: true             // vertical bar: left edge (else right)
    property bool useRect: false              // anchor to the bar window's edge
    property var anchorWin: null
    property real rectX: 0
    property real rectY: 0
    property real rectW: 1
    property real rectH: 1
    property real extra: 0                    // extra clearance when only the widget is known
    property real maxHeight: 620
    readonly property int gap: 0              // free space between the bar and the panel (0 = flush)
    readonly property real padTop: (!vertical && barAtTop) ? gap + extra : 0
    readonly property real padBottom: (!vertical && !barAtTop) ? gap + extra : 0
    readonly property real padLeft: (vertical && barAtLeft) ? gap + extra : 0
    readonly property real padRight: (vertical && !barAtLeft) ? gap + extra : 0

    function sideFromText(v) {
        const t = String(v === undefined || v === null ? "" : v).toLowerCase()
        if (t.indexOf("top") >= 0) return "top"
        if (t.indexOf("bottom") >= 0) return "bottom"
        if (t.indexOf("left") >= 0) return "left"
        if (t.indexOf("right") >= 0) return "right"
        return ""
    }

    function locate() {
        const item = root.anchorItem
        if (!item) return
        const scr = item.screen
        const sw = scr ? scr.width : 1920
        const sh = scr ? scr.height : 1080
        let side = ""
        let qsWin = null
        let win = null

        // 1. the bar window knows which edges it is attached to
        try { qsWin = item.QsWindow.window } catch (e0) { qsWin = null }
        try { win = qsWin ? qsWin : item.Window.window } catch (e1) { win = null }
        try {
            const an = win ? win.anchors : null
            if (an) {
                if (root.vertical) {
                    if (an.left && !an.right) side = "left"
                    else if (an.right && !an.left) side = "right"
                } else {
                    if (an.top && !an.bottom) side = "top"
                    else if (an.bottom && !an.top) side = "bottom"
                }
            }
        } catch (e2) { side = "" }

        // 2. the shell's bar object may say it outright
        if (side === "" && root.bar) {
            const names = ["position", "barPosition", "edge", "side", "location", "placement", "barSide"]
            for (let i = 0; i < names.length && side === ""; i++) {
                let got = ""
                try { got = root.sideFromText(root.bar[names[i]]) } catch (e3) { got = "" }
                if ((root.vertical && (got === "left" || got === "right"))
                        || (!root.vertical && (got === "top" || got === "bottom")))
                    side = got
            }
        }

        // 3. last resort: which half of the screen (only meaningful when the bar
        //    window is as big as the screen)
        const pos = item.mapToItem(null, 0, 0)
        if (side === "") {
            if (root.vertical) side = pos.x < sw / 2 ? "left" : "right"
            else side = pos.y < sh / 2 ? "top" : "bottom"
        }
        root.barAtTop = side === "top"
        root.barAtLeft = side === "left"

        // Anchor rectangle on the bar window's outer edge (window coordinates).
        const ww = (win && win.width > 0) ? win.width : 0
        const wh = (win && win.height > 0) ? win.height : 0
        const small = root.vertical ? (ww > 0 && ww < sw * 0.5) : (wh > 0 && wh < sh * 0.5)
        root.useRect = !!qsWin && small
        root.anchorWin = qsWin
        if (root.useRect) {
            if (root.vertical) {
                root.rectW = 1
                root.rectH = Math.max(1, item.height)
                root.rectY = pos.y
                root.rectX = side === "left" ? Math.max(0, ww - 1) : 0
            } else {
                root.rectW = Math.max(1, item.width)
                root.rectH = 1
                root.rectX = pos.x
                root.rectY = side === "top" ? Math.max(0, wh - 1) : 0
            }
            root.extra = 0
        } else {
            root.extra = 6                    // only the widget is known: allow a little for bar padding
        }

        // Tallest the panel may be and still fit between the bar and the far edge.
        const thick = (!root.vertical && wh > 0 && wh < sh * 0.5) ? wh : 40
        const room = root.vertical ? sh - 40 : sh - thick - root.gap - root.extra - 16
        root.maxHeight = Math.max(300, Math.min(1100, room))
    }

    // ---- click outside to close -----------------------------------------------------
    // Hyprland's focus grab reports any click outside the popup. It is created at
    // runtime so a shell without that module simply keeps the X button and Esc.
    property var grab: null

    Timer { id: grabTimer; interval: 500; onTriggered: root.justClosedByGrab = false }

    Component.onCompleted: {
        try {
            const g = Qt.createQmlObject(
                'import Quickshell.Hyprland\nHyprlandFocusGrab { }', root, "OmaotpFocusGrab")
            g.windows = [popup]
            g.cleared.connect(() => {
                root.justClosedByGrab = true
                grabTimer.restart()
                popup.visible = false
            })
            root.grab = g
        } catch (e) {
            root.grab = null
        }
    }

    PopupWindow {
        id: popup

        visible: false
        color: "transparent"
        implicitWidth: (root.ui ? root.ui.cfgSafe.windowWidth : 460) + root.padLeft + root.padRight
        implicitHeight: Math.min(root.maxHeight, root.ui ? root.ui.cfgSafe.windowHeight : 560) + root.padTop + root.padBottom

        anchor.item: root.useRect ? null : root.anchorItem
        anchor.window: root.useRect ? root.anchorWin : null
        anchor.rect.x: root.rectX
        anchor.rect.y: root.rectY
        anchor.rect.width: root.rectW
        anchor.rect.height: root.rectH
        // The panel opens on the side of the anchor facing away from the bar.
        anchor.edges: root.vertical ? (root.barAtLeft ? Edges.Right : Edges.Left)
                                    : (root.barAtTop ? Edges.Bottom : Edges.Top)
        anchor.gravity: root.vertical ? (root.barAtLeft ? Edges.Right : Edges.Left)
                                      : (root.barAtTop ? Edges.Bottom : Edges.Top)
        // Only slide along the bar, never across it, so the panel can't be pushed onto the bar.
        anchor.adjustment: root.vertical ? PopupAdjustment.SlideY : PopupAdjustment.SlideX

        onVisibleChanged: {
            if (root.grab) Qt.callLater(() => { root.grab.active = popup.visible })
        }

        Shortcut {
            sequence: "Escape"
            context: Qt.WindowShortcut
            onActivated: {
                if (!viewLoader.item || !viewLoader.item.stepBack()) root.close()
            }
        }
        Shortcut {
            sequence: "Alt+Right"
            context: Qt.WindowShortcut
            onActivated: root.stepTab(1)
        }
        Shortcut {
            sequence: "Alt+Left"
            context: Qt.WindowShortcut
            onActivated: root.stepTab(-1)
        }

        Item {
            anchors.fill: parent
            anchors.topMargin: root.padTop
            anchors.bottomMargin: root.padBottom
            anchors.leftMargin: root.padLeft
            anchors.rightMargin: root.padRight

            Loader {
                id: viewLoader
                anchors.fill: parent
                active: root.ui !== null
                sourceComponent: Component { OtpView { ui: root.ui } }
            }
        }
    }
}
