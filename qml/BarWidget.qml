import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "core"
import "js/Otp.js" as Model
import "js/Schema.js" as Schema
import "js/Theme.js" as Theme

// Omaotp: one-time codes (TOTP) in the bar, from an encrypted vault on this
// computer. The vault and the codes are handled by bin/omaotp.py; the master
// password goes to it on stdin, never on a command line.
//
// This file is also the "service" the window talks to (`ui.service`): the vault's
// state and the codes, the helper's job queue, copying, the capped clipboard read,
// the manifest, and the theme's window border.
BarWidget {
    id: root
    moduleName: "io.github.qempexe.omaotp"

    // ---- settings ------------------------------------------------------------------
    // Local overrides (Settings tab, see SettingsStore.qml) win over `omarchy bar set`.
    // Every key read here is declared in manifest.json (tools/gen-manifest.js).
    SettingsStore { id: settingsStore }

    function shellValues() {
        const out = {}
        for (const k of Schema.settingKeys) {
            const v = setting(k, undefined)
            if (v !== undefined && v !== null) out[k] = v
        }
        return out
    }
    readonly property var cfg: Schema.resolve(settingsStore.values, shellValues())
    function setValue(key, value) { settingsStore.set(key, value) }

    // ---- the vault -------------------------------------------------------------------
    property string stage: "checking"     // checking | setup | locked | open
    property var entries: []
    property string password: ""          // only while the vault is open
    property string pendingPassword: ""
    property string errorCode: ""
    property string lastCopied: ""
    property real now: Date.now()
    property int lastWindow: -1

    readonly property string scriptPath: decodeURIComponent(
        String(Qt.resolvedUrl("../bin/omaotp.py")).replace(/^file:\/\//, ""))

    readonly property var current: entries.length > 0 ? entries[0] : null
    function remainingFor(e) { return e ? Model.remaining(e.period, now) : 0 }

    readonly property string statusLine: {
        if (errorCode !== "" && stage !== "open") return Model.errorText(errorCode)
        if (stage === "checking") return "Checking the vault…"
        if (stage === "setup") return "Create a vault"
        if (stage === "locked") return "Vault locked"
        return "Vault open  ·  " + entries.length + (entries.length === 1 ? " account" : " accounts")
    }

    // ---- the helper's job queue ------------------------------------------------------
    // One helper runs at a time. Jobs remember the epoch they were queued in; lock()
    // bumps it, so nothing started before a lock can open the vault again.
    property var jobs: []
    property var job: null
    property int epoch: 0

    function enqueue(args, input, tag) {
        jobs = jobs.concat([{ args: args, input: input, tag: tag, epoch: epoch }])
    }
    function startNextJob() {
        if (helperProc.running || jobs.length === 0) return
        const q = jobs.slice()
        job = q.shift()
        jobs = q
        helperProc.command = ["python3", scriptPath].concat(job.args)
        helperProc.running = true
    }
    function onHelperStarted() {
        if (job && job.input) helperProc.write(job.input)
        if (job) job.input = ""            // the password is not kept in the job
    }
    function parseError(text) {
        try {
            const o = JSON.parse(text)
            return o && o.error && Model.ERRORS[o.error] ? o.error : "request-failed"
        } catch (e) { return "bad-response" }
    }
    function onHelperOutput(text) {
        const finished = job
        job = null
        const tag = finished ? finished.tag : ""
        // A result from before a lock is dropped. "status" carries no secrets.
        if (finished && finished.epoch !== epoch && tag !== "status") return
        if (tag === "status") {
            stage = text.indexOf('"exists": true') >= 0 ? "locked" : "setup"
            return
        }
        if (tag === "init") {
            if (text.indexOf('"ok": true') >= 0) unlockWith(pendingPassword)
            else { errorCode = parseError(text); pendingPassword = ""; stage = "setup" }
            return
        }
        if (tag === "unlock" || tag === "codes") {
            const res = Model.parseEntries(text)
            if (res.error) {
                if (tag === "unlock") {
                    errorCode = res.error
                    pendingPassword = ""
                    stage = res.error === "no-vault" ? "setup" : "locked"
                }
                return
            }
            if (tag === "unlock") {
                password = pendingPassword
                pendingPassword = ""
                stage = "open"
                lastWindow = Math.floor(Date.now() / 1000 / Model.minPeriod(res.entries))
            }
            errorCode = ""
            entries = res.entries
            return
        }
        if (tag === "add" || tag === "remove" || tag === "reorder") {
            if (text.indexOf('"error"') >= 0) { errorCode = parseError(text); return }
            errorCode = ""
            fetchCodes()
        }
    }

    function checkVault() { enqueue(["status"], "", "status") }

    function createVault(pw, again) {
        errorCode = ""
        if (pw.length < Model.MIN_PASSWORD) { errorCode = "short"; return false }
        if (pw !== again) { errorCode = "mismatch"; return false }
        pendingPassword = pw
        enqueue(["init"], pw + "\n", "init")
        return true
    }
    function unlock(pw) {
        errorCode = ""
        if (pw === "") { errorCode = "bad-password"; return }
        unlockWith(pw)
    }
    function unlockWith(pw) {
        pendingPassword = pw
        enqueue(["codes"], pw + "\n", "unlock")
    }
    function fetchCodes() {
        if (password !== "") enqueue(["codes"], password + "\n", "codes")
    }
    function addUri(uri) {
        if (password !== "") enqueue(["add"], password + "\n" + uri + "\n", "add")
    }
    function removeEntry(id) {
        if (password !== "") enqueue(["remove"], password + "\n" + id + "\n", "remove")
    }
    function moveEntry(id, targetId) {
        if (password === "") return
        const ids = entries.map((e) => e.id)
        const from = ids.indexOf(id), to = ids.indexOf(targetId)
        if (from < 0 || to < 0 || from === to) return
        ids.splice(from, 1)
        ids.splice(to, 0, id)
        const byId = {}
        for (const e of entries) byId[e.id] = e
        entries = ids.map((k) => byId[k])
        enqueue(["reorder"], password + "\n" + ids.join(",") + "\n", "reorder")
    }

    function lock() {
        epoch++
        // queued jobs hold the master password: drop them (status checks stay)
        jobs = jobs.filter((j) => j.tag === "status")
        password = ""
        pendingPassword = ""
        entries = []
        errorCode = ""
        lastCopied = ""
        if (stage === "open") stage = "locked"
        autoLock.stop()
        ux.locked()
    }

    // The code is written to the copier's stdin, never placed in its arguments. The
    // clipboard is cleared after `clipboardSeconds` if it still holds that code.
    property string pendingCopy: ""
    function copyCode(entry) {
        if (!entry || !/^\d{6,8}$/.test(entry.code)) return
        pendingCopy = entry.code
        lastCopied = entry.id
        copyProc.running = true
    }
    Process {
        id: copyProc
        stdinEnabled: true
        command: ["sh", "-c",
            'IFS= read -r c || exit 1; ' +
            'h=$(printf %s "$c" | sha256sum); printf %s "$c" | wl-copy -n; unset c; ' +
            '( sleep "$1"; [ "$(wl-paste -n 2>/dev/null | sha256sum)" = "$h" ] && wl-copy --clear ) >/dev/null 2>&1 &',
            "sh", String(root.cfg.clipboardSeconds)]
        onStarted: {
            copyProc.write(root.pendingCopy + "\n")
            root.pendingCopy = ""
        }
    }

    Process {
        id: helperProc
        stdinEnabled: true
        onStarted: root.onHelperStarted()
        stdout: StdioCollector { onStreamFinished: root.onHelperOutput(text.trim()) }
    }
    Timer {
        interval: 40
        repeat: true
        running: root.jobs.length > 0
        onTriggered: root.startNextJob()
    }

    // codes change when the time window does
    Timer {
        interval: 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            root.now = Date.now()
            if (root.stage !== "open" || root.password === "") return
            const w = Math.floor(root.now / 1000 / Model.minPeriod(root.entries))
            if (w !== root.lastWindow) {
                root.lastWindow = w
                root.fetchCodes()
            }
        }
    }

    // locking when the window has been closed for a while, or at once
    readonly property bool shown: panelOpened || windowShown
    onShownChanged: if (!shown && stage === "open" && cfg.lockOnClose) lock()
    Timer {
        id: autoLock
        interval: root.cfg.autoLockMinutes * 60 * 1000
        running: root.stage === "open" && !root.shown
        onTriggered: root.lock()
    }

    // ---- the color file of 1.0 (~/.config/omaotp/color), moved over once -------------
    FileView {
        id: legacyColor
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/omaotp/color"
        onLoaded: {
            const c = Model.parseColorFile(root.readText(legacyColor).slice(0, 32))
            legacyMove.mode = c.mode
            legacyMove.hex = c.hex
            legacyMove.ready = true
            legacyMove.apply()
        }
    }
    QtObject {
        id: legacyMove
        property bool ready: false
        property bool done: false
        property string mode: ""
        property string hex: ""
        function apply() {
            if (done || !ready || !settingsStore.loaded) return
            done = true
            const v = settingsStore.values
            if (v.colorMode === undefined) settingsStore.set("colorMode", mode)
            if (mode === "custom" && v.accentColor === undefined && v.customAccent === undefined) settingsStore.set("accentColor", hex)
        }
    }
    Connections {
        target: settingsStore
        function onLoadedChanged() { legacyMove.apply() }
    }

    Component.onCompleted: checkVault()

    // ---- the plugin's own manifest (the About tab shows its version) ----------------
    property var manifest: null
    FileView {
        id: manifestFile
        path: decodeURIComponent(Qt.resolvedUrl("../manifest.json").toString().replace(/^file:\/\//, ""))
        onLoaded: {
            let m = null
            try { m = JSON.parse(root.readText(manifestFile)) } catch (e) { m = null }
            const v = m && typeof m.version === "string" && /^[0-9A-Za-z.+-]{1,32}$/.test(m.version) ? m.version : ""
            root.manifest = { version: v }
        }
    }
    function readText(fv) {
        try { return String(typeof fv.text === "function" ? fv.text() : fv.text) } catch (e) { return "" }
    }

    // ---- the theme's window border ----------------------------------------------------
    // For the Window borders color scheme and the window outline: the active border's
    // colors and angle, from the theme's hyprland.lua (or .conf, or the line some themes
    // keep in colors.toml). Only #rrggbb values and an angle are taken from these files.
    property var tomlBorder: ({ colors: [], angle: 0 })
    property var luaBorder: ({ colors: [], angle: 0 })
    property var confBorder: ({ colors: [], angle: 0 })
    property bool luaMissing: false
    readonly property var borderColors: luaBorder.colors.length > 0 ? luaBorder.colors
        : (confBorder.colors.length > 0 ? confBorder.colors : tomlBorder.colors)
    readonly property real borderAngle: luaBorder.colors.length > 0 ? luaBorder.angle
        : (confBorder.colors.length > 0 ? confBorder.angle : tomlBorder.angle)
    readonly property string themeDir: {
        try { return Color.currentThemePath ? String(Color.currentThemePath) : "" } catch (e) { return "" }
    }

    FileView {
        id: paletteFile
        path: root.themeDir !== "" ? root.themeDir + "/colors.toml" : ""
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.tomlBorder = Theme.parseBorder(root.readText(paletteFile))
        onLoadFailed: { root.tomlBorder = ({ colors: [], angle: 0 }); root.retryTheme() }
    }
    FileView {
        id: borderLua
        path: root.themeDir !== "" ? root.themeDir + "/hyprland.lua" : ""
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { root.luaMissing = false; root.luaBorder = Theme.parseBorder(root.readText(borderLua)) }
        onLoadFailed: { root.luaBorder = ({ colors: [], angle: 0 }); root.luaMissing = true }
    }
    FileView {
        id: borderConf
        // only looked at when the theme has no hyprland.lua
        path: root.themeDir !== "" && root.luaMissing ? root.themeDir + "/hyprland.conf" : ""
        watchChanges: true
        onFileChanged: reload()
        onPathChanged: if (path === "") root.confBorder = ({ colors: [], angle: 0 })
        onLoaded: root.confBorder = Theme.parseBorder(root.readText(borderConf))
        onLoadFailed: root.confBorder = ({ colors: [], angle: 0 })
    }
    // A theme switch replaces the theme folder, so for a moment the files are gone and
    // the watch can lose track of them: read them again shortly after, a few times at most.
    property int themeTries: 0
    function retryTheme() { if (themeTries < 3) { themeTries++; themeRetry.restart() } }
    Timer {
        id: themeRetry
        interval: 800
        onTriggered: { paletteFile.reload(); borderLua.reload(); borderConf.reload() }
    }
    Connections {
        target: Color
        ignoreUnknownSignals: true
        function onAccentChanged() { root.themeTries = 0; themeRetry.restart() }
        function onBackgroundChanged() { root.themeTries = 0; themeRetry.restart() }
    }

    // ---- clipboard paste (capped, no shell) -------------------------------------------
    // Pasting into a text field never reads the clipboard on the UI thread. wl-paste
    // runs directly (no shell) and its output is read in chunks. Reading stops as soon
    // as 1024 bytes are in, or after 2 seconds, and the process is stopped. The text is
    // then sent back through `pasted`, addressed to the field that asked.
    property string pasteKey: ""
    property string pasteBuf: ""
    readonly property int pasteMax: 1024
    signal pasted(string key, string text)

    function requestPaste(key) {
        if (pasteKey !== "" || pasteProc.running) return   // one paste at a time
        pasteKey = key
        pasteBuf = ""
        pasteProc.running = true
        pasteKill.restart()
    }
    function finishPaste() {
        const k = pasteKey
        if (k === "") return                              // already delivered
        pasteKey = ""
        pasteKill.stop()
        const text = pasteBuf.slice(0, pasteMax)
        pasteBuf = ""
        if (pasteProc.running) pasteProc.running = false  // stop reading the clipboard
        root.pasted(k, text)
    }
    Timer { id: pasteKill; interval: 2000; onTriggered: root.finishPaste() }
    Process {
        id: pasteProc
        running: false
        command: ["wl-paste", "--no-newline"]
        stdout: SplitParser {
            splitMarker: ""
            onRead: function(data) {
                if (root.pasteBuf.length >= root.pasteMax) return
                root.pasteBuf += data
                if (root.pasteBuf.length >= root.pasteMax) root.finishPaste()
            }
        }
        onExited: root.finishPaste()
    }

    // ---- the window: docked to the bar, or popped out ----------------------------------
    // One UiState feeds whichever surface is showing, so the tab, the search and the
    // history filter survive popping out and docking back.
    property bool popped: false
    // Set only by the header's Pop out / Dock buttons. Until then "Open as" decides
    // how the bar button opens, every time, so a change in settings takes effect at once.
    property bool userPicked: false

    // The bar's own colours. Fall back to the shell palette if the bar does not expose them.
    readonly property color barFg: (root.bar && root.bar.barForeground !== undefined)
        ? root.bar.barForeground : (Color.foreground !== undefined ? Color.foreground : "white")
    readonly property color barBg: (root.bar && root.bar.barBackground !== undefined)
        ? root.bar.barBackground : (Color.background !== undefined ? Color.background : "#121217")

    // The shell theme's accent, tried under a few likely names. Unknown names are
    // skipped, and with none found the window falls back to the bar foreground.
    function themeColor(names) {
        for (const name of names) {
            let raw
            try { raw = Color[name] } catch (e) { raw = undefined }
            if (raw === undefined || raw === null) continue
            try {
                const c = Qt.color(raw)
                if (c && c.valid !== false) return c
            } catch (e2) { }
        }
        return null
    }
    readonly property var shellAccent: themeColor(["accent", "primary", "highlight", "accentColor", "color4", "blue"])

    UiState {
        id: ux
        service: root
        themeAccent: root.shellAccent ? root.shellAccent : "transparent"
        store: settingsStore
        cfg: root.cfg
        opened: root.panelOpened || root.windowShown
        popped: root.popped
        barFg: root.barFg
        barBg: root.barBg
        fontName: root.bar && root.bar.fontFamily ? root.bar.fontFamily : Style.font.family
        onPopOutRequested: root.popOut()
        onDockRequested: root.dock()
        onCloseRequested: root.close()
    }

    readonly property bool panelOpened: panelLoader.item ? panelLoader.item.opened === true : false
    readonly property bool windowShown: windowLoader.item ? windowLoader.item.visible === true : false

    // The shell only knows about the bar-panel state.
    readonly property bool opened: panelOpened
    readonly property bool popoutSwitchClosing: panelLoader.item
        ? panelLoader.item.popoutSwitchClosing === true : false

    // Until the header's buttons are used, "Open as" decides.
    function chooseMode() {
        if (userPicked) return
        const want = cfg.openAs === "window"
        if (want === popped) return
        if (windowShown) hideWindow()
        if (panelOpened) closePanel()
        popped = want
    }

    // The window exists exactly while it is wanted. Showing it again after it was
    // closed (by the header, or by the window manager) always creates a fresh one,
    // so a dead window handle can never leave the bar button doing nothing.
    property bool windowRequested: false
    function showWindow() {
        windowRequested = true
        if (windowLoader.item) windowLoader.item.visible = true
    }
    function hideWindow() { windowRequested = false }

    // The window manager closed the window while we still wanted it: forget it, so
    // the next click on the bar button builds a new one.
    Connections {
        target: windowLoader.item
        ignoreUnknownSignals: true
        function onVisibleChanged() {
            if (windowLoader.item && !windowLoader.item.visible && root.windowRequested)
                root.windowRequested = false
        }
    }

    // If the bar panel cannot be shown (Panel.qml failed to load, or the shell never
    // reported it open), show Omaotp as its own window instead of doing nothing.
    // The reason goes to the shell log (`qs log`).
    property bool wantPanel: false
    function fallbackToWindow(reason) {
        console.warn("omaotp: " + reason + "; opening as a window instead")
        wantPanel = false
        panelCheck.stop()
        popped = true
        showWindow()
    }
    function openPanel() {
        if (panelLoader.status === Loader.Error || !panelLoader.item) {
            fallbackToWindow("Panel.qml is not loaded (status " + panelLoader.status + ")")
            return
        }
        injectPanel()
        wantPanel = true
        panelLoader.item.open()
        panelCheck.restart()
    }
    function closePanel() {
        wantPanel = false
        panelCheck.stop()
        if (panelLoader.item) panelLoader.item.close()
    }
    function open() {
        chooseMode()
        if (popped) showWindow()
        else openPanel()
    }
    function close() {
        closePanel()
        hideWindow()
    }
    function toggle() {
        chooseMode()
        if (popped) {
            if (windowShown) hideWindow()
            else showWindow()
        } else if (panelOpened) {
            closePanel()
        } else if (!(panelLoader.item && panelLoader.item.justClosedByGrab === true)) {
            openPanel()
        }
    }
    function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }
    function popOut() {
        userPicked = true
        popped = true
        closePanel()
        showWindow()
    }
    function dock() {
        userPicked = true
        hideWindow()
        popped = false
        Qt.callLater(root.openPanel)
    }
    onPanelOpenedChanged: if (panelOpened) { wantPanel = false; panelCheck.stop() }
    Timer {
        id: panelCheck
        interval: 600
        repeat: false
        onTriggered: if (root.wantPanel && !root.panelOpened && !root.popped)
            root.fallbackToWindow("the panel did not open")
    }

    // Open on a tab (or keep it open and switch to it).
    function showTab(name) {
        ux.tabName = name
        open()
    }

    function injectPanel() {
        if (!panelLoader.item) return
        panelLoader.item.bar = root.bar
        panelLoader.item.anchorItem = button
        panelLoader.item.hostWidget = root
        panelLoader.item.ui = ux
    }

    onBarChanged: injectPanel()

    Loader {
        id: panelLoader
        active: true
        source: Qt.resolvedUrl("panel/Panel.qml")
        onLoaded: {
            root.injectPanel()
            Qt.callLater(root.injectPanel)
        }
        onStatusChanged: if (status === Loader.Error)
            console.warn("omaotp: Panel.qml failed to load; run `qs log` for the QML error")
    }

    // A real, resizable, movable window. Only exists while popped out.
    Loader {
        id: windowLoader
        active: root.windowRequested
        source: Qt.resolvedUrl("panel/PopoutWindow.qml")
        onLoaded: {
            item.ui = ux
            item.visible = root.windowRequested
        }
        onStatusChanged: if (status === Loader.Error)
            console.warn("omaotp: PopoutWindow.qml failed to load; run `qs log` for the QML error")
    }

    // ---- the bar button --------------------------------------------------------------
    readonly property real iconSize: Style.space(14)
    readonly property real badgeSize: Style.space(18)
    readonly property bool showBadge: stage === "open" && current !== null && cfg.barShows !== "lock"
    readonly property bool showCode: showBadge && cfg.barShows === "code"

    implicitWidth: (showBadge ? badgeSize : iconSize) + (showCode ? codeText.implicitWidth + Style.space(6) : 0) + Style.space(12)
    implicitHeight: Math.max(button.implicitHeight, Style.space(14))

    WidgetButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: " "
        tooltipText: root.stage === "open"
            ? "One-time codes (click to open, right click for settings)"
            : "Vault locked (click to unlock)"
        onPressed: function(buttonCode) {
            if (buttonCode === Qt.RightButton || buttonCode === "right") root.showTab("settings")
            else if (buttonCode === Qt.MiddleButton || buttonCode === "middle") {
                if (root.cfg.middleClick === "lock") root.lock()
                else if (root.cfg.middleClick === "copy" && root.current) root.copyCode(root.current)
            } else {
                if (!root.opened && !root.windowShown) ux.tabName = "accounts"
                root.toggle()
            }
        }
    }

    // locked, or nothing to show: the lock
    Text {
        anchors.centerIn: parent
        visible: !root.showBadge
        text: Model.LOCK_GLYPH
        textFormat: Text.PlainText
        color: root.barFg
        font.family: root.bar && root.bar.fontFamily ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.subtitle
    }

    // open: the first account's icon in its countdown ring, and its code if wanted
    Row {
        anchors.centerIn: parent
        height: root.height
        spacing: Style.space(6)
        visible: root.showBadge

        Item {
            width: root.badgeSize
            height: parent.height
            Canvas {
                id: ring
                anchors.centerIn: parent
                width: root.badgeSize
                height: root.badgeSize
                readonly property real secs: root.remainingFor(root.current)
                readonly property real frac: root.current ? secs / root.current.period : 0
                readonly property color accent: ux.accent
                onFracChanged: requestPaint()
                onAccentChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    const r = width / 2 - 1.5
                    ctx.lineWidth = 2
                    ctx.strokeStyle = Qt.alpha(root.barFg, 0.18)
                    ctx.beginPath()
                    ctx.arc(width / 2, height / 2, r, 0, 2 * Math.PI)
                    ctx.stroke()
                    ctx.strokeStyle = secs <= 5 ? "#f85149" : secs <= 10 ? "#e3b341" : accent
                    ctx.beginPath()
                    ctx.arc(width / 2, height / 2, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * frac)
                    ctx.stroke()
                }
            }
            Text {
                anchors.centerIn: parent
                text: root.current ? (Model.issuerGlyph(root.current.issuer) || Model.KEY_GLYPH) : ""
                textFormat: Text.PlainText
                color: root.barFg
                font.family: root.bar && root.bar.fontFamily ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Math.round(Style.font.subtitle * 0.75)
            }
        }
        Text {
            id: codeText
            visible: root.showCode
            anchors.verticalCenter: parent.verticalCenter
            text: root.current ? Model.formatCode(root.current.code, root.cfg.groupCodes) : ""
            textFormat: Text.PlainText
            color: root.barFg
            font.family: root.bar && root.bar.fontFamily ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.subtitle
            font.letterSpacing: 1
        }
    }
}
