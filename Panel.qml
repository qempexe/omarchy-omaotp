pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "Otp.js" as Model
import "Settings.js" as Settings

// Popup with two tabs once the vault is open: Accounts (codes, search, add) and Settings.
// While the vault is locked or not created yet, it shows only the password step.
PopupWindow {
    id: root

    // injected by BarWidget
    property var bar: null
    property var barObject: bar
    property bool vertical: false
    property var probeBg: undefined
    property var probeFg: undefined
    property var anchorItem: null
    property var hostWidget: null
    property var widget: null

    readonly property var shellBgColor: (root.bar && root.bar.background !== undefined) ? root.bar.background
                                       : root.probeBg
    readonly property var shellFgColor: (root.bar && root.bar.foreground !== undefined) ? root.bar.foreground
                                       : root.probeFg

    // Hand the shell's bar colour to the widget, so its theme reader can match the
    // installed Omarchy theme by colour when no current/theme folder exists.
    Binding { target: root.widget; property: "shellBg"; value: root.shellBgColor; when: !!root.widget && root.shellBgColor !== undefined }

    property string currentTab: "accounts"
    readonly property string stage: widget ? widget.stage : "checking"
    readonly property var all: widget ? widget.entries : []
    readonly property var cfg: widget ? widget.cfg : Model.normalizeSettings({})

    // The full palette for the current mode. Theme: bar colours (which the shell
    // themes from Omarchy) + Omarchy accent. Custom: user's three colours. Mono:
    // fixed neutral palette.
    readonly property var colors: widget ? widget.colors
                                         : Model.resolveColors({ colorMode: "mono" }, null)
    readonly property bool useBarColors: !!widget && widget.cfg.colorMode === "theme"
        && root.shellBgColor !== undefined && root.shellFgColor !== undefined
    readonly property color fg: useBarColors ? root.shellFgColor : root.colors.text
    readonly property color panelBg: {
        if (useBarColors) { var c = root.shellBgColor; return Qt.rgba(c.r, c.g, c.b, 1) }   // never translucent
        return root.colors.background
    }
    readonly property color accent: {
        if (useBarColors) {
            var o = widget.omarchy
            return (o && Model.isHex(o.accent)) ? Qt.color(o.accent) : root.shellFgColor
        }
        return root.colors.accent
    }
    readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.56)
    readonly property color faint: Qt.rgba(fg.r, fg.g, fg.b, 0.14)
    function tint(a) { return Qt.rgba(fg.r, fg.g, fg.b, a) }
    function accentTint(a) { return Qt.rgba(accent.r, accent.g, accent.b, a) }
    function luma(c) { return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b }
    readonly property color inkOnAccent: luma(accent) > 0.55 ? Qt.rgba(0.07, 0.07, 0.09, 1) : Qt.rgba(0.97, 0.97, 0.98, 1)

    readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
    readonly property int fsMain: Math.max(10, Math.round(Style.font.body * 0.9))
    readonly property int fsSub: Math.max(9, Math.round(Style.font.body * 0.8))
    readonly property int fsCode: Style.font.subtitle
    readonly property real rowHeight: Style.space(48)
    readonly property int visibleRows: 5
    readonly property real listHeight: Math.max(1, Math.min(shown.length, visibleRows)) * rowHeight

    // ---- layout metrics ---------------------------------------------------------
    readonly property real mHeaderTop: Style.space(14)
    readonly property real hHeader: Style.space(60)
    readonly property real mBodyTop: Style.space(12)
    readonly property real hTabs: Style.space(30)
    readonly property real mStackTop: Style.space(12)
    readonly property real mPagePad: Style.space(14)
    readonly property real hSearch: Style.space(34)
    readonly property real vGap: Style.space(10)
    readonly property real hAddButton: Style.space(34)
    readonly property real mBodyBottom: Style.space(10)
    readonly property real hFooter: Style.space(16)
    readonly property real mFooterBottom: Style.space(10)
    readonly property real panelChrome:
        mHeaderTop + hHeader + mBodyTop + mBodyBottom + hFooter + mFooterBottom

    // Padding inside the password card, and the min height its content needs.
    readonly property real authPad: Style.space(14)
    readonly property real authFieldH: Style.space(36)
    readonly property real authLineH: Math.max(1, Math.round(Style.font.body * 0.8)) + Style.space(2)

    // account list state
    property string query: ""
    property bool adding: false
    property string confirmId: ""
    property string dragId: ""
    property int dragFrom: -1
    property int dragTarget: -1
    property real dragStartY: 0
    property real dragOffset: 0

    // what has been typed in the password and add-account fields (the fields themselves are one-way)
    property string authText: ""
    property string uriText: ""
    property string issuerText: ""
    property string accountText: ""
    property string secretText: ""

    // Which custom-colour role the picker edits (a panel-local choice, not a setting).
    property string colorRole: "customBackground"
    readonly property var colorRoles: [
        { key: "customBackground", label: "Background" },
        { key: "customText", label: "Text" },
        { key: "customAccent", label: "Accent" }
    ]

    readonly property var shown: {
        var q = query.toLowerCase()
        var out = []
        for (var i = 0; i < all.length; i++) {
            var e = all[i]
            if (q === "" || e.issuer.toLowerCase().indexOf(q) >= 0 || e.account.toLowerCase().indexOf(q) >= 0)
                out.push(e)
        }
        return out
    }

    readonly property string statusLine: {
        if (!widget) return "Starting\u2026"
        if (widget.errorCode !== "" && stage !== "open") return Model.errorText(widget.errorCode)
        if (stage === "checking") return "Checking vault\u2026"
        if (stage === "setup") return "Create a vault"
        if (stage === "locked") return "Vault locked"
        return "Vault unlocked  \u00b7  " + all.length + (all.length === 1 ? " account" : " accounts")
    }

    function finishDrag() {
        if (dragId !== "" && dragTarget >= 0 && dragTarget < shown.length
                && dragTarget !== dragFrom && widget) {
            widget.moveEntry(dragId, shown[dragTarget].id)
        }
        dragId = ""
        dragFrom = -1
        dragTarget = -1
        dragOffset = 0
    }

    function submitAuth() {
        if (!widget) return
        if (stage === "setup") {
            widget.createVault(authText)
            if (authText.length >= Model.MIN_PASSWORD) { authText = ""; authBox.clear() }
        } else if (stage === "locked") {
            widget.unlock(authText)
            authText = ""
            authBox.clear()
        }
    }

    function submitAdd() {
        if (!widget) return
        var uri = uriText.trim()
        if (Model.isOtpUri(uri)) widget.addUri(uri)
        else widget.addUri(Model.buildUri(issuerText.trim(), accountText.trim(), secretText))
        clearAddForm()
        adding = false
    }

    function clearAddForm() {
        uriText = ""; issuerText = ""; accountText = ""; secretText = ""
        uriBox.clear(); issuerBox.clear(); accountBox.clear(); secretBox.clear()
    }

    function clearInputs() {
        authText = ""
        authBox.clear()
        clearAddForm()
        adding = false
        confirmId = ""
        query = ""
        dragId = ""
    }

    function focusFirst() {
        if (!root.visible) return
        if (stage === "setup" || stage === "locked") authBox.forceFocus()
    }
    onStageChanged: if (visible) Qt.callLater(root.focusFirst)

    function computeHeight() {
        if (stage === "open") {
            if (currentTab === "settings") return Style.space(600)
            var page = hTabs + mStackTop
                     + mPagePad + hSearch + vGap + vGap + hAddButton + mPagePad
            var add = adding ? Style.space(220) : 0
            return panelChrome + page + root.listHeight + add
        }
        if (stage === "setup") {
            var descSetup = authLineH * 4
            var cardSetup = authPad * 2 + descSetup + vGap + authFieldH + vGap + authFieldH
            return panelChrome + cardSetup + Style.space(8)
        }
        if (stage === "locked") {
            var descLocked = authLineH * 2
            var cardLocked = authPad * 2 + descLocked + vGap + authFieldH + vGap + authFieldH
            return panelChrome + cardLocked + Style.space(8)
        }
        return Style.space(190)
    }

    function labelFor(d, value) {
        var i = d.options.indexOf(value)
        return i >= 0 && d.labels ? d.labels[i] : String(value)
    }

    // A small preview dot next to a colour-mode choice, showing what that option's
    // accent looks like. In mono everything (including these dots) is neutral.
    function choiceDot(key, value) {
        if (key !== "colorMode") return "transparent"
        if (root.cfg.colorMode === "mono") return "#aaaaaa"
        if (value === "theme") {
            var o = root.widget ? root.widget.omarchy : null
            return (o && Model.isHex(o.accent)) ? o.accent : "#39d353"
        }
        if (value === "custom") return String(root.cfg.customAccent)
        if (value === "mono") return "#aaaaaa"
        return "transparent"
    }

    // Rows of the Settings tab: a header per group, then each *visible* setting that
    // applies. `ui: "hidden"` rows are skipped entirely (they are saved settings that
    // the palette picker edits, not rows of their own); previously they slipped
    // through and each one added an empty 24px row with its own divider under the
    // Theme row.
    readonly property string modeChoice: root.widget ? root.widget.cfg.colorMode : "theme"
    readonly property var settingRows: buildRows(modeChoice)
    function buildRows(mode) {
        var rows = [], lastGroup = ""
        var schema = Settings.SCHEMA
        for (var i = 0; i < schema.length; i++) {
            var d = schema[i]
            if (d.ui === "hidden") continue
            if (d.showWhen && d.showWhen !== mode) continue
            if (d.group !== lastGroup) { rows.push({ type: "header", label: d.group }); lastGroup = d.group }
            rows.push(d)
        }
        return rows
    }

    readonly property bool opened: visible
    function open() { if (!root.visible) root.toggle() }
    function close() { root.visible = false }
    function openTab(tab) { root.currentTab = tab; root.open() }

    // ---- placement: never overlap the bar -----------------------------------------
    property bool barAtTop: true
    property bool barAtLeft: true
    property bool useRect: false
    property var anchorWin: null
    property real rectX: 0
    property real rectY: 0
    property real rectW: 1
    property real rectH: 1
    property real extra: 0
    property real maxHeight: 620
    readonly property int gap: 0
    readonly property real padTop: (!vertical && barAtTop) ? gap + extra : 0
    readonly property real padBottom: (!vertical && !barAtTop) ? gap + extra : 0
    readonly property real padLeft: (vertical && barAtLeft) ? gap + extra : 0
    readonly property real padRight: (vertical && !barAtLeft) ? gap + extra : 0

    function sideFromText(v) {
        var t = String(v === undefined || v === null ? "" : v).toLowerCase()
        if (t.indexOf("top") >= 0) return "top"
        if (t.indexOf("bottom") >= 0) return "bottom"
        if (t.indexOf("left") >= 0) return "left"
        if (t.indexOf("right") >= 0) return "right"
        return ""
    }

    function locate() {
        var item = root.anchorItem
        if (!item) return
        var scr = item.screen
        var sw = scr ? scr.width : 1920
        var sh = scr ? scr.height : 1080
        var side = ""
        var qsWin = null
        var win = null

        try { qsWin = item.QsWindow.window } catch (e0) { qsWin = null }
        try { win = qsWin ? qsWin : item.Window.window } catch (e1) { win = null }
        try {
            var an = win ? win.anchors : null
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

        if (side === "" && root.barObject) {
            var names = ["position", "barPosition", "edge", "side", "location", "placement", "barSide"]
            for (var i = 0; i < names.length && side === ""; i++) {
                var got = ""
                try { got = root.sideFromText(root.barObject[names[i]]) } catch (e3) { got = "" }
                if ((root.vertical && (got === "left" || got === "right"))
                        || (!root.vertical && (got === "top" || got === "bottom")))
                    side = got
            }
        }

        var pos = item.mapToItem(null, 0, 0)
        if (side === "") {
            if (root.vertical) side = pos.x < sw / 2 ? "left" : "right"
            else side = pos.y < sh / 2 ? "top" : "bottom"
        }
        root.barAtTop = side === "top"
        root.barAtLeft = side === "left"

        var ww = (win && win.width > 0) ? win.width : 0
        var wh = (win && win.height > 0) ? win.height : 0
        var small = root.vertical ? (ww > 0 && ww < sw * 0.5) : (wh > 0 && wh < sh * 0.5)
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
            root.extra = 6
        }

        var thick = (!root.vertical && wh > 0 && wh < sh * 0.5) ? wh : 40
        var room = root.vertical ? sh - 40 : sh - thick - root.gap - root.extra - 16
        root.maxHeight = Math.max(300, Math.min(900, room))
    }

    function toggle() {
        if (!root.visible && Date.now() - root.grabClosedAt < 500) return
        if (!root.visible) root.locate()
        root.visible = !root.visible
    }

    property var grab: null
    property double grabClosedAt: 0

    Component.onCompleted: {
        try {
            var g = Qt.createQmlObject(
                'import Quickshell.Hyprland\nHyprlandFocusGrab { }', root, "OmaotpFocusGrab")
            g.windows = [root]
            g.cleared.connect(function() {
                root.grabClosedAt = Date.now()
                root.visible = false
            })
            root.grab = g
        } catch (e) {
            root.grab = null
        }
    }

    // ---- window geometry -------------------------------------------------------
    visible: false
    color: "transparent"
    readonly property real wantHeight: root.computeHeight()
    implicitWidth: Style.space(440) + root.padLeft + root.padRight
    implicitHeight: Math.min(root.maxHeight, wantHeight) + root.padTop + root.padBottom

    anchor.item: root.useRect ? null : root.anchorItem
    anchor.window: root.useRect ? root.anchorWin : null
    anchor.rect.x: root.rectX
    anchor.rect.y: root.rectY
    anchor.rect.width: root.rectW
    anchor.rect.height: root.rectH
    anchor.edges: root.vertical ? (root.barAtLeft ? Edges.Right : Edges.Left)
                                : (root.barAtTop ? Edges.Bottom : Edges.Top)
    anchor.gravity: root.vertical ? (root.barAtLeft ? Edges.Right : Edges.Left)
                                  : (root.barAtTop ? Edges.Bottom : Edges.Top)
    anchor.adjustment: root.vertical ? PopupAdjustment.SlideY : PopupAdjustment.SlideX

    onVisibleChanged: {
        if (root.grab) Qt.callLater(function() { root.grab.active = root.visible })
        if (root.visible) Qt.callLater(root.focusFirst)
        else root.clearInputs()
    }

    Shortcut {
        sequence: "Escape"
        context: Qt.WindowShortcut
        onActivated: root.visible = false
    }


    Rectangle {
        anchors.fill: parent
        anchors.topMargin: root.padTop
        anchors.bottomMargin: root.padBottom
        anchors.leftMargin: root.padLeft
        anchors.rightMargin: root.padRight
        color: root.panelBg
        border.color: root.tint(0.14)
        border.width: 1
        radius: 12
        clip: true

        Item {
            id: card
            anchors.fill: parent

            // ── header card ──
            Item {
                id: header
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: root.mHeaderTop
                height: root.hHeader

                Rectangle {
                    anchors.fill: parent
                    radius: 10
                    color: root.tint(0.05)
                    border.width: 1
                    border.color: root.tint(0.08)
                }
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: Style.space(34)
                        implicitHeight: Style.space(34)
                        radius: 9
                        color: root.accentTint(0.18)
                        Text {
                            anchors.centerIn: parent
                            text: Model.LOCK_GLYPH
                            color: root.accent
                            font.family: root.fontFamily
                            font.pixelSize: root.fsMain + 3
                            textFormat: Text.PlainText
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 2
                        Text {
                            Layout.fillWidth: true
                            text: "omaotp"
                            color: root.fg
                            font.family: root.fontFamily
                            font.pixelSize: root.fsSub + 2
                            font.weight: Font.DemiBold
                            font.letterSpacing: 1.5
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.statusLine
                            color: root.fg
                            opacity: 0.6
                            font.family: root.fontFamily
                            font.pixelSize: root.fsSub
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                        }
                    }
                    FlatButton {
                        Layout.alignment: Qt.AlignVCenter
                        visible: root.stage === "open"
                        outlined: true
                        implicitHeight: Style.space(26)
                        hPad: Style.space(10)
                        text: "Lock"
                        foreground: root.fg
                        accent: root.accent
                        fontFamily: root.fontFamily
                        pixelSize: root.fsSub
                        onClicked: if (root.widget) root.widget.lock()
                    }
                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 24; implicitHeight: 24; radius: 6
                        color: closeArea.containsMouse ? root.tint(0.16) : root.tint(0.08)
                        Text {
                            anchors.centerIn: parent
                            text: "\u00d7"
                            color: root.fg
                            font.pixelSize: 15
                            textFormat: Text.PlainText
                        }
                        MouseArea {
                            id: closeArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.close()
                        }
                    }
                }
            }

            // ── footer ──
            RowLayout {
                id: footer
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: Style.space(14)
                anchors.rightMargin: Style.space(14)
                anchors.bottomMargin: root.mFooterBottom
                height: root.hFooter
                spacing: 6
                Rectangle {
                    implicitWidth: escLabel.implicitWidth + 10
                    implicitHeight: 16
                    radius: 4
                    color: root.tint(0.08)
                    Text {
                        id: escLabel
                        anchors.centerIn: parent
                        text: "Esc"
                        color: root.fg
                        opacity: 0.75
                        font.family: root.fontFamily
                        font.pixelSize: 8
                        textFormat: Text.PlainText
                    }
                }
                Text {
                    text: "close"
                    color: root.fg
                    opacity: 0.45
                    font.family: root.fontFamily
                    font.pixelSize: 8
                    textFormat: Text.PlainText
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: root.stage !== "open" ? "Encrypted on this machine"
                        : (root.widget && root.widget.errorCode !== "" ? Model.errorText(root.widget.errorCode)
                                                                       : "Codes refresh every 30 s")
                    color: root.stage === "open" && root.widget && root.widget.errorCode !== "" ? "#f85149" : root.fg
                    opacity: root.stage === "open" && root.widget && root.widget.errorCode !== "" ? 1 : 0.45
                    font.family: root.fontFamily
                    font.pixelSize: 8
                    textFormat: Text.PlainText
                }
            }

            Item {
                id: body
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: header.bottom
                anchors.bottom: footer.top
                anchors.leftMargin: Style.space(14)
                anchors.rightMargin: Style.space(14)
                anchors.topMargin: root.mBodyTop
                anchors.bottomMargin: root.mBodyBottom
                clip: true

                // ── password step: create the vault, or unlock it ──
                Rectangle {
                    id: authCard
                    visible: root.stage !== "open"
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    radius: 10
                    color: root.tint(0.035)
                    border.width: 1
                    border.color: root.tint(0.07)

                    ColumnLayout {
                        id: authCol
                        anchors.fill: parent
                        anchors.margins: root.authPad
                        spacing: root.vGap

                        Text {
                            Layout.fillWidth: true
                            text: root.stage === "setup"
                                ? "Choose a master password. It encrypts your secrets. There is no way to recover it, so keep it safe."
                                : root.stage === "locked" ? "Enter your master password to show your codes."
                                : "Checking vault\u2026"
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: root.fsSub
                            wrapMode: Text.Wrap
                            textFormat: Text.PlainText
                        }
                        FieldBox {
                            id: authBox
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.authFieldH
                            visible: root.stage === "setup" || root.stage === "locked"
                            secret: true
                            placeholderText: root.stage === "setup" ? "Master password (8 or more characters)" : "Master password"
                            foreground: root.fg
                            accent: root.accent
                            fontFamily: root.fontFamily
                            pixelSize: root.fsMain
                            onEdited: function (value) { root.authText = value }
                            onAccepted: root.submitAuth()
                        }
                        Loader {
                            Layout.fillWidth: true
                            active: root.widget && root.widget.errorCode !== "" && root.stage !== "open"
                            visible: active
                            sourceComponent: Text {
                                width: parent ? parent.width : 0
                                text: root.widget ? Model.errorText(root.widget.errorCode) : ""
                                color: "#f85149"
                                font.family: root.fontFamily
                                font.pixelSize: root.fsSub
                                wrapMode: Text.Wrap
                                textFormat: Text.PlainText
                            }
                        }
                        FlatButton {
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.authFieldH
                            visible: root.stage === "setup" || root.stage === "locked"
                            outlined: true
                            selected: true
                            text: root.stage === "setup" ? "Create vault" : "Unlock"
                            foreground: root.fg
                            accent: root.accent
                            fontFamily: root.fontFamily
                            pixelSize: root.fsMain
                            onClicked: root.submitAuth()
                        }
                        Item { Layout.fillHeight: true }
                    }
                }

                // ── open vault: tabs and pages ──
                Item {
                    id: openView
                    visible: root.stage === "open"
                    anchors.fill: parent

                    Item {
                        id: tabs
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: root.hTabs

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 1
                            color: root.tint(0.10)
                        }
                        RowLayout {
                            anchors.fill: parent
                            spacing: 0
                            Repeater {
                                model: [
                                    { key: "accounts", label: "Accounts" },
                                    { key: "settings", label: "Settings" }
                                ]
                                delegate: Item {
                                    id: tabItem
                                    required property var modelData
                                    readonly property bool on: root.currentTab === tabItem.modelData.key
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    Layout.fillHeight: true
                                    Text {
                                        anchors.centerIn: parent
                                        anchors.verticalCenterOffset: -1
                                        text: tabItem.modelData.label
                                        color: root.fg
                                        opacity: tabItem.on ? 1.0 : (tabArea.containsMouse ? 0.8 : 0.5)
                                        font.family: root.fontFamily
                                        font.pixelSize: root.fsSub + 1
                                        font.weight: tabItem.on ? Font.DemiBold : Font.Normal
                                        textFormat: Text.PlainText
                                    }
                                    Rectangle {
                                        visible: tabItem.on
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        height: 2
                                        radius: 1
                                        color: root.accent
                                    }
                                    MouseArea {
                                        id: tabArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.currentTab = tabItem.modelData.key
                                    }
                                }
                            }
                        }
                    }

                    StackLayout {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: tabs.bottom
                        anchors.bottom: parent.bottom
                        anchors.topMargin: root.mStackTop
                        currentIndex: root.currentTab === "settings" ? 1 : 0

                        // ACCOUNTS
                        Rectangle {
                            radius: 10
                            color: root.tint(0.035)
                            border.width: 1
                            border.color: root.tint(0.07)
                            clip: true

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: root.mPagePad
                                spacing: root.vGap

                                FieldBox {
                                    id: searchBox
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: root.hSearch
                                    Layout.minimumHeight: root.hSearch
                                    Layout.maximumHeight: root.hSearch
                                    placeholderText: "Search accounts"
                                    foreground: root.fg
                                    accent: root.accent
                                    fontFamily: root.fontFamily
                                    pixelSize: root.fsMain
                                    text: root.query
                                    onEdited: function (value) { root.query = value }
                                }

                                Flickable {
                                    id: listFlick
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: root.listHeight
                                    Layout.minimumHeight: root.listHeight
                                    Layout.maximumHeight: root.listHeight
                                    clip: true
                                    contentWidth: width
                                    contentHeight: listCol.implicitHeight
                                    interactive: root.dragId === ""
                                    boundsBehavior: Flickable.StopAtBounds

                                    Column {
                                        id: listCol
                                        width: listFlick.width

                                        Text {
                                            visible: root.shown.length === 0
                                            width: parent.width
                                            text: root.all.length === 0 ? "No accounts yet. Use Add account below." : "No accounts match."
                                            color: root.dim
                                            font.family: root.fontFamily
                                            font.pixelSize: root.fsSub
                                            horizontalAlignment: Text.AlignHCenter
                                            topPadding: Style.space(14)
                                            bottomPadding: Style.space(14)
                                            textFormat: Text.PlainText
                                        }

                                        Repeater {
                                            model: root.shown

                                            delegate: Rectangle {
                                                id: row
                                                required property var modelData
                                                required property int index
                                                readonly property bool dragging: root.dragId !== "" && root.dragId === row.modelData.id
                                                width: listCol.width
                                                height: root.rowHeight
                                                radius: 8
                                                z: dragging ? 2 : 0
                                                transform: Translate { y: row.dragging ? root.dragOffset : 0 }
                                                color: row.dragging ? root.tint(0.14)
                                                    : rowArea.containsMouse ? root.tint(0.08) : "transparent"

                                                Rectangle {
                                                    anchors.fill: parent
                                                    radius: 8
                                                    color: "transparent"
                                                    border.width: 1
                                                    border.color: root.accent
                                                    visible: root.dragId !== "" && root.dragTarget === row.index && root.dragFrom !== row.index
                                                }

                                                Text {
                                                    anchors.left: parent.left
                                                    anchors.leftMargin: Style.space(4)
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: "\u2261"
                                                    color: root.dim
                                                    font.family: root.fontFamily
                                                    font.pixelSize: root.fsMain
                                                    textFormat: Text.PlainText
                                                }
                                                MouseArea {
                                                    anchors.left: parent.left
                                                    anchors.top: parent.top
                                                    anchors.bottom: parent.bottom
                                                    width: Style.space(18)
                                                    cursorShape: Qt.SizeVerCursor
                                                    onPressed: function (mouse) {
                                                        root.dragId = row.modelData.id
                                                        root.dragFrom = row.index
                                                        root.dragTarget = row.index
                                                        root.dragStartY = mapToItem(listCol, mouse.x, mouse.y).y
                                                        root.dragOffset = 0
                                                        root.confirmId = ""
                                                    }
                                                    onPositionChanged: function (mouse) {
                                                        if (root.dragId === "") return
                                                        var y = mapToItem(listCol, mouse.x, mouse.y).y
                                                        root.dragOffset = y - root.dragStartY
                                                        var t = Math.floor(y / root.rowHeight)
                                                        root.dragTarget = Math.max(0, Math.min(root.shown.length - 1, t))
                                                    }
                                                    onReleased: root.finishDrag()
                                                    onCanceled: root.finishDrag()
                                                }

                                                Rectangle {
                                                    id: tile
                                                    anchors.left: parent.left
                                                    anchors.leftMargin: Style.space(24)
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: Style.space(32)
                                                    height: Style.space(32)
                                                    radius: 7
                                                    color: root.widget ? root.widget.tileColor : root.tint(0.18)
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: Model.issuerGlyph(row.modelData.issuer)
                                                            || Model.tileLetter(row.modelData.issuer, row.modelData.account)
                                                        color: root.fg
                                                        font.family: root.fontFamily
                                                        font.pixelSize: root.fsCode
                                                        font.bold: !Model.issuerGlyph(row.modelData.issuer)
                                                        textFormat: Text.PlainText
                                                    }
                                                }

                                                Column {
                                                    anchors.left: tile.right
                                                    anchors.leftMargin: Style.space(10)
                                                    anchors.right: codeArea.left
                                                    anchors.rightMargin: Style.space(6)
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    Text {
                                                        width: parent.width
                                                        text: row.modelData.issuer || "Account"
                                                        elide: Text.ElideRight
                                                        color: root.fg
                                                        font.family: root.fontFamily
                                                        font.pixelSize: root.fsMain
                                                        font.bold: true
                                                        textFormat: Text.PlainText
                                                    }
                                                    Text {
                                                        width: parent.width
                                                        text: row.modelData.account
                                                        elide: Text.ElideRight
                                                        color: root.dim
                                                        font.family: root.fontFamily
                                                        font.pixelSize: root.fsSub
                                                        textFormat: Text.PlainText
                                                    }
                                                }

                                                Row {
                                                    id: codeArea
                                                    anchors.right: parent.right
                                                    anchors.rightMargin: Style.space(8)
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    spacing: Style.space(8)

                                                    Text {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        visible: root.confirmId !== row.modelData.id
                                                        text: Model.formatCode(row.modelData.code)
                                                        color: root.widget && root.widget.lastCopied === row.modelData.id
                                                            ? root.accent : root.fg
                                                        font.family: root.fontFamily
                                                        font.pixelSize: root.fsCode
                                                        font.bold: true
                                                        font.letterSpacing: 1
                                                        textFormat: Text.PlainText
                                                    }

                                                    Canvas {
                                                        id: rowRing
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        width: Style.space(14)
                                                        height: Style.space(14)
                                                        visible: root.confirmId !== row.modelData.id
                                                        readonly property real secs: root.widget ? root.widget.remainingFor(row.modelData) : 0
                                                        readonly property real frac: secs / row.modelData.period
                                                        onFracChanged: requestPaint()
                                                        onPaint: {
                                                            var ctx = getContext("2d")
                                                            ctx.reset()
                                                            var r = width / 2 - 1.5
                                                            ctx.lineWidth = 2
                                                            ctx.strokeStyle = Qt.alpha(root.fg, 0.18)
                                                            ctx.beginPath()
                                                            ctx.arc(width / 2, height / 2, r, 0, 2 * Math.PI)
                                                            ctx.stroke()
                                                            ctx.strokeStyle = secs <= 5 ? "#f85149" : secs <= 10 ? "#e3b341" : root.accent
                                                            ctx.beginPath()
                                                            ctx.arc(width / 2, height / 2, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * frac)
                                                            ctx.stroke()
                                                        }
                                                    }

                                                    Text {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: root.confirmId === row.modelData.id ? "Remove?" : "\u00d7"
                                                        color: root.confirmId === row.modelData.id ? "#f85149" : root.dim
                                                        font.family: root.fontFamily
                                                        font.pixelSize: root.fsMain
                                                        textFormat: Text.PlainText
                                                        MouseArea {
                                                            anchors.fill: parent
                                                            anchors.margins: -Style.space(5)
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                if (root.confirmId === row.modelData.id) {
                                                                    root.confirmId = ""
                                                                    if (root.widget) root.widget.removeEntry(row.modelData.id)
                                                                } else {
                                                                    root.confirmId = row.modelData.id
                                                                }
                                                            }
                                                        }
                                                    }
                                                }

                                                MouseArea {
                                                    id: rowArea
                                                    anchors.left: tile.left
                                                    anchors.right: codeArea.left
                                                    anchors.top: parent.top
                                                    anchors.bottom: parent.bottom
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (root.widget) {
                                                            root.widget.copyCode(row.modelData.code)
                                                            root.widget.lastCopied = row.modelData.id
                                                        }
                                                        root.confirmId = ""
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                FlatButton {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: root.hAddButton
                                    Layout.minimumHeight: root.hAddButton
                                    Layout.maximumHeight: root.hAddButton
                                    outlined: true
                                    text: root.adding ? "Cancel" : "+ Add account"
                                    foreground: root.fg
                                    accent: root.accent
                                    fontFamily: root.fontFamily
                                    pixelSize: root.fsMain
                                    onClicked: root.adding = !root.adding
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    visible: root.adding
                                    spacing: Style.space(8)

                                    Text {
                                        Layout.fillWidth: true
                                        text: "Paste an otpauth:// link, or fill in issuer, account and secret."
                                        color: root.dim
                                        font.family: root.fontFamily
                                        font.pixelSize: root.fsSub
                                        wrapMode: Text.Wrap
                                        textFormat: Text.PlainText
                                    }
                                    FieldBox {
                                        id: uriBox
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: Style.space(34)
                                        maxLength: 2048
                                        pasteMaxBytes: 2048
                                        placeholderText: "otpauth://totp/... (or leave empty and fill below)"
                                        foreground: root.fg
                                        accent: root.accent
                                        fontFamily: root.fontFamily
                                        pixelSize: root.fsSub
                                        onEdited: function (value) { root.uriText = value }
                                        onAccepted: root.submitAdd()
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        visible: root.uriText === ""
                                        spacing: Style.space(8)
                                        FieldBox {
                                            id: issuerBox
                                            Layout.fillWidth: true
                                            Layout.preferredWidth: 1
                                            Layout.preferredHeight: Style.space(34)
                                            maxLength: 64
                                            placeholderText: "Issuer"
                                            foreground: root.fg
                                            accent: root.accent
                                            fontFamily: root.fontFamily
                                            pixelSize: root.fsSub
                                            onEdited: function (value) { root.issuerText = value }
                                        }
                                        FieldBox {
                                            id: accountBox
                                            Layout.fillWidth: true
                                            Layout.preferredWidth: 1
                                            Layout.preferredHeight: Style.space(34)
                                            maxLength: 128
                                            placeholderText: "Account"
                                            foreground: root.fg
                                            accent: root.accent
                                            fontFamily: root.fontFamily
                                            pixelSize: root.fsSub
                                            onEdited: function (value) { root.accountText = value }
                                        }
                                    }
                                    FieldBox {
                                        id: secretBox
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: Style.space(34)
                                        visible: root.uriText === ""
                                        secret: true
                                        maxLength: 128
                                        placeholderText: "Secret (hidden)"
                                        foreground: root.fg
                                        accent: root.accent
                                        fontFamily: root.fontFamily
                                        pixelSize: root.fsSub
                                        onEdited: function (value) { root.secretText = value }
                                        onAccepted: root.submitAdd()
                                    }
                                    FlatButton {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: Style.space(34)
                                        outlined: true
                                        selected: true
                                        text: "Add"
                                        foreground: root.fg
                                        accent: root.accent
                                        fontFamily: root.fontFamily
                                        pixelSize: root.fsMain
                                        onClicked: root.submitAdd()
                                    }
                                }
                            }
                        }

                        // SETTINGS
                        Flickable {
                            id: settingsFlick
                            contentHeight: settingsCol.implicitHeight + Style.space(24)
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            Rectangle {
                                x: 0; y: 0
                                width: settingsFlick.width
                                height: settingsCol.implicitHeight
                                radius: 10
                                color: root.tint(0.035)
                                border.width: 1
                                border.color: root.tint(0.07)
                            }

                            ColumnLayout {
                                id: settingsCol
                                width: settingsFlick.width
                                spacing: 0

                                Text {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: Style.space(12)
                                    Layout.rightMargin: Style.space(12)
                                    Layout.topMargin: Style.space(12)
                                    Layout.bottomMargin: Style.space(4)
                                    text: root.widget && root.widget.omarchyNote
                                          ? "Saved to ~/.config/omaotp/settings.json. Edit it by hand and it applies live. " + root.widget.omarchyNote
                                          : "Saved to ~/.config/omaotp/settings.json. Edit it by hand and it applies live."
                                    wrapMode: Text.Wrap
                                    color: root.dim
                                    font.family: root.fontFamily
                                    font.pixelSize: root.fsSub
                                    textFormat: Text.PlainText
                                }

                                Repeater {
                                    model: root.opened ? root.settingRows : []
                                    delegate: Item {
                                        id: srow
                                        required property var modelData
                                        Layout.fillWidth: true
                                        readonly property bool isHeader: modelData.type === "header"
                                        readonly property int pad: Style.space(12)
                                        readonly property real innerWidth: width - pad * 2
                                        implicitHeight: content.implicitHeight + (isHeader ? 0 : pad * 2)

                                        Rectangle {
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.bottom: parent.bottom
                                            anchors.leftMargin: srow.pad
                                            anchors.rightMargin: srow.pad
                                            height: 1
                                            visible: !srow.isHeader
                                            color: root.tint(0.07)
                                        }

                                        Component {
                                            id: headerC
                                            Item {
                                                width: srow.innerWidth
                                                height: Style.space(40)
                                                Text {
                                                    anchors.left: parent.left
                                                    anchors.bottom: parent.bottom
                                                    anchors.bottomMargin: Style.space(4)
                                                    text: srow.modelData.label.toUpperCase()
                                                    color: root.accent
                                                    font.family: root.fontFamily
                                                    font.pixelSize: root.fsSub
                                                    font.bold: true
                                                    font.letterSpacing: 1
                                                    textFormat: Text.PlainText
                                                }
                                            }
                                        }

                                        Component {
                                            id: labelsC
                                            Column {
                                                width: srow.innerWidth
                                                spacing: Style.space(2)
                                                Text {
                                                    width: parent.width
                                                    text: srow.modelData.label
                                                    color: root.fg
                                                    font.family: root.fontFamily
                                                    font.pixelSize: root.fsMain
                                                    wrapMode: Text.Wrap
                                                    textFormat: Text.PlainText
                                                }
                                                Text {
                                                    width: parent.width
                                                    text: srow.modelData.description
                                                    color: root.dim
                                                    font.family: root.fontFamily
                                                    font.pixelSize: root.fsSub
                                                    wrapMode: Text.Wrap
                                                    textFormat: Text.PlainText
                                                }
                                            }
                                        }

                                        Component {
                                            id: stepC
                                            Item {
                                                width: srow.innerWidth
                                                height: Math.max(labelBlockStep.height, Style.space(34)) + Style.space(12)
                                                Loader { id: labelBlockStep; sourceComponent: labelsC; width: parent.width - Style.space(210); anchors.verticalCenter: parent.verticalCenter }
                                                Row {
                                                    anchors.right: parent.right
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    spacing: Style.space(6)
                                                    FlatButton {
                                                        text: "\u2212"
                                                        outlined: true
                                                        implicitHeight: Style.space(30)
                                                        hPad: Style.space(12)
                                                        foreground: root.fg
                                                        accent: root.accent
                                                        fontFamily: root.fontFamily
                                                        pixelSize: root.fsMain
                                                        onClicked: root.widget.setValue(srow.modelData.key,
                                                            Model.stepOption(Model.OPTIONS[srow.modelData.key], root.cfg[srow.modelData.key], -1))
                                                    }
                                                    Text {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        width: Style.space(96)
                                                        horizontalAlignment: Text.AlignHCenter
                                                        text: Model.formatSetting(srow.modelData.fmt, root.cfg[srow.modelData.key])
                                                        color: root.fg
                                                        font.family: root.fontFamily
                                                        font.pixelSize: root.fsMain
                                                        textFormat: Text.PlainText
                                                    }
                                                    FlatButton {
                                                        text: "+"
                                                        outlined: true
                                                        implicitHeight: Style.space(30)
                                                        hPad: Style.space(12)
                                                        foreground: root.fg
                                                        accent: root.accent
                                                        fontFamily: root.fontFamily
                                                        pixelSize: root.fsMain
                                                        onClicked: root.widget.setValue(srow.modelData.key,
                                                            Model.stepOption(Model.OPTIONS[srow.modelData.key], root.cfg[srow.modelData.key], 1))
                                                    }
                                                }
                                            }
                                        }

                                        Component {
                                            id: enumC
                                            Column {
                                                width: srow.innerWidth
                                                spacing: Style.space(8)
                                                Loader { sourceComponent: labelsC; width: parent.width }
                                                Flow {
                                                    width: parent.width
                                                    spacing: Style.space(6)
                                                    Repeater {
                                                        model: srow.modelData.options
                                                        delegate: FlatButton {
                                                            id: choice
                                                            required property string modelData
                                                            outlined: true
                                                            selected: root.cfg[srow.modelData.key] === choice.modelData
                                                            implicitHeight: Style.space(30)
                                                            text: root.labelFor(srow.modelData, choice.modelData)
                                                            dotColor: root.choiceDot(srow.modelData.key, choice.modelData)
                                                            foreground: root.fg
                                                            accent: root.accent
                                                            fontFamily: root.fontFamily
                                                            pixelSize: root.fsSub
                                                            onClicked: root.widget.setValue(srow.modelData.key, choice.modelData)
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        // Custom colours: pick a role, then a swatch or a hex code.
                                        Component {
                                            id: paletteC
                                            Column {
                                                width: srow.innerWidth
                                                spacing: Style.space(10)
                                                Loader { sourceComponent: labelsC; width: parent.width }

                                                Flow {
                                                    width: parent.width
                                                    spacing: Style.space(6)
                                                    Repeater {
                                                        model: root.colorRoles
                                                        delegate: FlatButton {
                                                            id: roleBtn
                                                            required property var modelData
                                                            outlined: true
                                                            selected: root.colorRole === roleBtn.modelData.key
                                                            implicitHeight: Style.space(30)
                                                            text: roleBtn.modelData.label
                                                            dotColor: String(root.cfg[roleBtn.modelData.key])
                                                            foreground: root.fg
                                                            accent: root.accent
                                                            fontFamily: root.fontFamily
                                                            pixelSize: root.fsSub
                                                            onClicked: root.colorRole = roleBtn.modelData.key
                                                        }
                                                    }
                                                }

                                                Row {
                                                    width: parent.width
                                                    spacing: Style.space(8)
                                                    Rectangle {
                                                        width: Style.space(32)
                                                        height: Style.space(32)
                                                        radius: Style.space(6)
                                                        color: String(root.cfg[root.colorRole])
                                                        border.width: 1
                                                        border.color: root.faint
                                                    }
                                                    FieldBox {
                                                        id: hexField
                                                        width: parent.width - Style.space(40)
                                                        height: Style.space(32)
                                                        placeholderText: "#rrggbb"
                                                        foreground: root.fg
                                                        accent: root.accent
                                                        fontFamily: root.fontFamily
                                                        pixelSize: root.fsMain
                                                        text: String(root.cfg[root.colorRole] !== undefined ? root.cfg[root.colorRole] : "")
                                                        maxLength: 7
                                                        onEdited: function (value) {
                                                            var v = value.trim()
                                                            if (/^#[0-9a-fA-F]{6}$/.test(v))
                                                                root.widget.setValue(root.colorRole, v.toLowerCase())
                                                        }
                                                    }
                                                }

                                                Flow {
                                                    width: parent.width
                                                    spacing: Style.space(5)
                                                    Repeater {
                                                        model: Settings.PALETTE
                                                        delegate: Rectangle {
                                                            id: swatch
                                                            required property string modelData
                                                            width: Style.space(26)
                                                            height: Style.space(26)
                                                            radius: Style.space(6)
                                                            color: swatch.modelData
                                                            border.width: String(root.cfg[root.colorRole]).toLowerCase() === swatch.modelData ? 2 : 1
                                                            border.color: String(root.cfg[root.colorRole]).toLowerCase() === swatch.modelData
                                                                ? root.accent : root.faint
                                                            MouseArea {
                                                                anchors.fill: parent
                                                                cursorShape: Qt.PointingHandCursor
                                                                onClicked: root.widget.setValue(root.colorRole, swatch.modelData)
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        Component {
                                            id: actionsC
                                            Item {
                                                width: srow.innerWidth
                                                height: Math.max(labelBlockAct.height, Style.space(34)) + Style.space(12)
                                                Loader { id: labelBlockAct; sourceComponent: labelsC; width: parent.width - Style.space(170); anchors.verticalCenter: parent.verticalCenter }
                                                FlatButton {
                                                    anchors.right: parent.right
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    outlined: true
                                                    implicitHeight: Style.space(30)
                                                    text: "Reset all settings"
                                                    foreground: root.fg
                                                    accent: root.accent
                                                    fontFamily: root.fontFamily
                                                    pixelSize: root.fsSub
                                                    onClicked: root.widget.resetAll()
                                                }
                                            }
                                        }

                                        Component {
                                            id: unknownC
                                            Item { width: srow.innerWidth; height: 0 }
                                        }

                                        Loader {
                                            id: content
                                            width: srow.innerWidth
                                            x: srow.pad
                                            y: srow.isHeader ? 0 : srow.pad
                                            sourceComponent: srow.modelData.type === "header" ? headerC
                                                           : srow.modelData.type === "enum" ? enumC
                                                           : srow.modelData.type === "stepper" ? stepC
                                                           : srow.modelData.type === "palette" ? paletteC
                                                           : srow.modelData.type === "actions" ? actionsC
                                                           : unknownC
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
