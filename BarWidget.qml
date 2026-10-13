import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Otp.js" as Model

BarWidget {
  id: root
  moduleName: "io.github.qempexe.omaotp"

  property string stage: "checking"
  property var entries: []
  property string password: ""
  property string pendingPassword: ""
  property string errorCode: ""
  property string lastCopied: ""
  property real now: Date.now()
  property int lastWindow: -1

  // ---- Settings -----------------------------------------------------------------
  SettingsStore { id: settingsStore }
  readonly property var cfg: Model.normalizeSettings(settingsStore.values)

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")
  readonly property string omarchyConfig: configHome + "/omarchy"

  readonly property string scriptPath: decodeURIComponent(
    String(Qt.resolvedUrl("bin/omaotp.py")).replace(/^file:\/\//, ""))

  readonly property var current: entries.length > 0 ? entries[0] : null
  readonly property color fg: fgProbe.item ? fgProbe.item.barForeground : "#cccccc"
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property real iconSize: Style.space(14)
  readonly property real badgeSize: Style.space(18)
  readonly property real badgeGap: Style.space(6)

  function remainingFor(e) {
    return e ? Model.remaining(e.period, now) : 0
  }

  property var jobs: []
  property var job: null
  // Bumped by lock(). Jobs remember the epoch they were queued in; results from an
  // older epoch are dropped, so nothing started before a lock can reopen the vault.
  property int epoch: 0

  function enqueue(args, input, tag) {
    var q = jobs.slice()
    q.push({ args: args, input: input, tag: tag, epoch: epoch })
    jobs = q
  }

  function startNextJob() {
    if (helperProc.running || jobs.length === 0) return
    var q = jobs.slice()
    job = q.shift()
    jobs = q
    helperProc.command = ["python3", scriptPath].concat(job.args)
    helperProc.running = true
  }

  function onHelperStarted() {
    if (job && job.input) helperProc.write(job.input)
  }

  function parseError(text) {
    try {
      var o = JSON.parse(text)
      return o && o.error && Model.ERRORS[o.error] ? o.error : "request-failed"
    } catch (e) { return "bad-response" }
  }

  function onHelperOutput(text) {
    var finished = job
    job = null
    var tag = finished ? finished.tag : ""
    // Pre-lock result: ignore it. "status" carries no secrets and only ever yields
    // locked/setup, so it is exempt.
    if (finished && finished.epoch !== epoch && tag !== "status") return
    if (tag === "status") {
      stage = text.indexOf('"exists": true') >= 0 ? "locked" : "setup"
      return
    }
    if (tag === "init") {
      if (text.indexOf('"ok": true') >= 0) unlockWith(pendingPassword)
      else { errorCode = parseError(text); stage = "setup" }
      return
    }
    if (tag === "unlock" || tag === "codes") {
      var res = Model.parseEntries(text)
      if (res.error) {
        if (tag === "unlock") {
          errorCode = res.error
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

  function checkVault() {
    enqueue(["status"], "", "status")
  }

  function createVault(pw) {
    errorCode = ""
    if (pw.length < Model.MIN_PASSWORD) { errorCode = "short"; return }
    pendingPassword = pw
    enqueue(["init"], pw + "\n", "init")
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
    if (password === "") return
    enqueue(["codes"], password + "\n", "codes")
  }

  function addUri(uri) {
    if (password === "") return
    enqueue(["add"], password + "\n" + uri + "\n", "add")
  }

  function removeEntry(id) {
    if (password === "") return
    enqueue(["remove"], password + "\n" + id + "\n", "remove")
  }

  function lock() {
    epoch++
    // Drop queued jobs (they hold the master password in `input`); keep status checks.
    jobs = jobs.filter(function (j) { return j.tag === "status" })
    password = ""
    pendingPassword = ""
    entries = []
    errorCode = ""
    stage = "locked"
    autoLock.stop()
  }

  // The code is written to the helper's stdin, never placed in argv.
  function copyCode(code) {
    pendingCopy = code
    copyProc.running = true
  }

  function moveEntry(id, targetId) {
    if (password === "") return
    var ids = entries.map(function (e) { return e.id })
    var from = ids.indexOf(id), to = ids.indexOf(targetId)
    if (from < 0 || to < 0 || from === to) return
    ids.splice(from, 1)
    ids.splice(to, 0, id)
    var byId = {}
    for (var i = 0; i < entries.length; i++) byId[entries[i].id] = entries[i]
    entries = ids.map(function (k) { return byId[k] })
    enqueue(["reorder"], password + "\n" + ids.join(",") + "\n", "reorder")
  }

  function setValue(key, value) { settingsStore.set(key, value) }
  function resetAll() { settingsStore.reset() }

  // ---- theme -----------------------------------------------------------------
  // The active Omarchy theme: one shell script that
  // dumps colors.toml / alacritty.toml / kitty.conf from the current theme
  // folder (or, if no current folder exists, from every installed theme, so the
  // shell's own bar colour can pick the right one). Re-run on theme.name changes
  // and shortly after (the swap is not atomic), and on a slow poll while the
  // colour mode is "theme".
  property var omarchy: null
  property string omarchyNote: "Looking for your Omarchy theme…"
  property var shellBg: null
  property string lastThemeText: ""
  readonly property var themeScriptArgs: [omarchyConfig + "/current", omarchyConfig]
  readonly property string themeScript: [
    'd="$1"; cfg="$2"; n=""',
    '[ -r "$d/theme.name" ] && n=$(tr -d "\r\n" < "$d/theme.name")',
    '[ -z "$n" ] && n=$(omarchy-theme-current 2>/dev/null)',
    'n=$(printf %s "$n" | tr "A-Z " "a-z-")',
    'echo "@@NAME $n"',
    'found=0',
    'for t in "$d/theme" "$cfg/themes/$n"; do',
    '  [ "$found" = 1 ] && break',
    '  [ -d "$t" ] || continue',
    '  for f in colors.toml alacritty.toml kitty.conf; do',
    '    if [ -r "$t/$f" ]; then echo "@@FILE $f"; cat "$t/$f"; echo; found=1; fi',
    '  done',
    'done',
    'if [ "$found" = 0 ]; then',
    '  for t in "$cfg"/themes/*; do',
    '    [ -d "$t" ] || continue',
    '    for f in colors.toml alacritty.toml kitty.conf; do',
    '      if [ -r "$t/$f" ]; then echo "@@THEME $(basename "$t")"; echo "@@FILE $f"; cat "$t/$f"; echo; break; fi',
    '    done',
    '  done',
    'fi',
    'exit 0'
  ].join("\n")

  function refreshTheme() { if (!themeProc.running) themeProc.running = true }

  function hexOf(c) {
    function h(v) { return ("0" + Math.round(v * 255).toString(16)).slice(-2) }
    return "#" + h(c.r) + h(c.g) + h(c.b)
  }
  onShellBgChanged: if (lastThemeText.indexOf("@@THEME") >= 0) themeRead(lastThemeText)

  function themeRead(text) {
    lastThemeText = String(text || "")
    var t = null
    if (lastThemeText.indexOf("@@THEME") >= 0) {
      var installed = Model.parseOmarchyThemes(lastThemeText)
      var named = /^@@NAME[ \t]*(.*)$/m.exec(lastThemeText)
      var want = named ? Model.themeSlug(named[1]) : ""
      for (var i = 0; i < installed.length && !t; i++)
        if (want && Model.themeSlug(installed[i].name) === want) t = installed[i]
      if (!t && shellBg !== null && shellBg !== undefined) {
        var best = Model.closestTheme(installed, hexOf(shellBg))
        t = best && best.dist < 0.012 ? best.theme : null
      }
    } else {
      t = Model.parseOmarchyTheme(lastThemeText)
    }
    omarchy = t
    omarchyNote = t
      ? "Following “" + (t.name || "your current theme") + "”."
      : "Using the shell's own colours."
  }

  Process {
    id: themeProc
    command: ["sh", "-c", root.themeScript, "sh", root.themeScriptArgs[0], root.themeScriptArgs[1]]
    stdout: StdioCollector { onStreamFinished: root.themeRead(text) }
  }
  FileView {
    id: themeNameFile
    path: root.omarchyConfig + "/current/theme.name"
    watchChanges: true
    onFileChanged: { reload(); root.refreshTheme(); themeSettle.restart() }
  }
  Timer { id: themeSettle; interval: 600; onTriggered: root.refreshTheme() }
  Timer {
    interval: 2000
    repeat: true
    running: root.cfg.colorMode === "theme"
    onTriggered: root.refreshTheme()
  }
  onCfgChanged: if (cfg.colorMode === "theme") refreshTheme()

  // The full palette for the current mode, plus the tinted tile used by the
  // account rows. Theme: Omarchy's palette. Custom: the user's three colours,
  // with readability fixes. Mono: fixed neutral.
  readonly property var colors: Model.resolveColors(cfg, omarchy)
  readonly property color tileColor: Model.shade(colors.accent, 0.35)

  // Older versions kept the colour in ~/.config/omaotp/color and then in a single
  // `customColor` setting. Both are folded into the new three-colour scheme once.
  property string legacyText: ""
  property bool legacyReady: false
  property bool legacyDone: false
  function migrateLegacy() {
    if (legacyDone || !legacyReady || !settingsStore.loaded) return
    legacyDone = true
    var v = settingsStore.values
    var patch = {}
    // Very old: ~/.config/omaotp/color file
    if (legacyText.trim() !== "" && v.colorMode === undefined) {
      var c = Model.parseColorFile(legacyText)
      patch.colorMode = c.mode
      patch.customAccent = c.hex
    }
    // Older: single customColor key -> customAccent
    if (v.customColor !== undefined) {
      if (patch.customAccent === undefined && v.customAccent === undefined)
        patch.customAccent = Model.validColor(v.customColor)
      patch.customColor = null
    }
    if (Object.keys(patch).length > 0) settingsStore.setMany(patch)
  }

  Connections {
    target: settingsStore
    function onLoadedChanged() { root.migrateLegacy() }
  }
  FileView {
    id: legacyColor
    path: root.configHome + "/omaotp/color"
    onLoaded: { root.legacyText = text(); root.legacyReady = true; root.migrateLegacy() }
    onLoadFailed: function (error) { root.legacyText = ""; root.legacyReady = true; root.migrateLegacy() }
  }

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
    panelLoader.item.widget = root
    if (fgProbe.item) fgProbe.item.bar = root.bar
  }

  Process {
    id: helperProc
    stdinEnabled: true
    onStarted: root.onHelperStarted()
    stdout: StdioCollector { onStreamFinished: root.onHelperOutput(text.trim()) }
  }

  property string pendingCopy: ""

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
  Timer {
    interval: 40
    repeat: true
    running: root.jobs.length > 0
    onTriggered: root.startNextJob()
  }

  Timer {
    interval: 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: {
      root.now = Date.now()
      if (root.stage !== "open" || root.password === "") return
      var w = Math.floor(root.now / 1000 / Model.minPeriod(root.entries))
      if (w !== root.lastWindow) {
        root.lastWindow = w
        root.fetchCodes()
      }
    }
  }

  Timer {
    id: autoLock
    interval: root.cfg.autoLockMinutes * 60 * 1000
    running: root.stage === "open" && !root.opened
    onTriggered: root.lock()
  }

  Component.onCompleted: { checkVault(); refreshTheme() }

  implicitWidth: stage === "open" && current !== null
    ? badgeSize + Style.space(12)
    : iconSize + Style.space(12)
  implicitHeight: Math.max(button.implicitHeight, Style.space(14))

  onBarChanged: injectPanel()

  Loader {
    id: fgProbe
    active: true
    source: Qt.resolvedUrl("Foreground.qml")
    visible: false
    onLoaded: root.injectPanel()
  }
  Binding { target: panelLoader.item; property: "probeFg"; value: fgProbe.item ? fgProbe.item.barForeground : undefined; when: !!panelLoader.item && !!fgProbe.item }
  Binding { target: panelLoader.item; property: "probeBg"; value: fgProbe.item ? fgProbe.item.barBackground : undefined; when: !!panelLoader.item && !!fgProbe.item }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: " "
    tooltipText: root.stage === "open" ? "One-time codes (click to open, middle-click to lock)"
      : "Vault locked (click to unlock)"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
      else if (buttonCode === Qt.MiddleButton) root.lock()
    }
  }

  Text {
    anchors.centerIn: parent
    visible: root.stage !== "open"
    text: Model.LOCK_GLYPH
    textFormat: Text.PlainText
    color: root.fg
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.subtitle
  }

  Row {
    id: strip
    anchors.centerIn: parent
    height: root.height
    spacing: root.badgeGap
    visible: root.stage === "open"

    Repeater {
      model: root.stage === "open" && root.current !== null ? [root.current] : []

      Item {
        id: badge
        required property var modelData
        width: root.badgeSize
        height: strip.height

        Canvas {
          id: ring
          anchors.centerIn: parent
          width: root.badgeSize
          height: root.badgeSize
          readonly property real secs: root.remainingFor(badge.modelData)
          readonly property real frac: secs / badge.modelData.period
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
            ctx.strokeStyle = secs <= 5 ? "#f85149" : secs <= 10 ? "#e3b341" : root.colors.accent
            ctx.beginPath()
            ctx.arc(width / 2, height / 2, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * frac)
            ctx.stroke()
          }
        }

        Text {
          anchors.centerIn: parent
          visible: Model.issuerGlyph(badge.modelData.issuer) !== ""
          text: Model.issuerGlyph(badge.modelData.issuer)
          textFormat: Text.PlainText
          color: root.fg
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Math.round(Style.font.subtitle * 0.75)
        }

        Image {
          anchors.centerIn: parent
          visible: Model.issuerGlyph(badge.modelData.issuer) === ""
          source: Qt.resolvedUrl("assets/key.png")
          width: root.badgeSize - Style.space(4)
          height: root.badgeSize - Style.space(4)
          fillMode: Image.PreserveAspectFit
          smooth: false
        }
      }
    }
  }
}
