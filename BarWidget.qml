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

  property string colorMode: "theme"
  property string customHex: Model.DEFAULT_COLOR
  property string themeHex: Model.DEFAULT_COLOR

  readonly property string scriptPath: decodeURIComponent(
    String(Qt.resolvedUrl("bin/omaotp.py")).replace(/^file:\/\//, ""))
  readonly property string themeScriptPath: decodeURIComponent(
    String(Qt.resolvedUrl("bin/theme-accent.sh")).replace(/^file:\/\//, ""))

  readonly property var current: entries.length > 0 ? entries[0] : null
  readonly property color fg: panelLoader.item ? panelLoader.item.barForeground : "#cccccc"
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property real iconSize: Style.space(14)
  readonly property real badgeSize: Style.space(18)
  readonly property real badgeGap: Style.space(6)

  readonly property string accentHex: colorMode === "custom" ? customHex : themeHex
  readonly property color accentColor: colorMode === "mono" ? fg : accentHex
  readonly property color tileColor: colorMode === "mono" ? Qt.alpha(fg, 0.2) : Model.shade(accentHex, 0.35)

  function remainingFor(e) {
    return e ? Model.remaining(e.period, now) : 0
  }

  property var jobs: []
  property var job: null

  function enqueue(args, input, tag) {
    var q = jobs.slice()
    q.push({ args: args, input: input, tag: tag })
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
    var tag = job ? job.tag : ""
    job = null
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

  function setColorMode(mode) {
    if (mode !== "theme" && mode !== "custom" && mode !== "mono") return
    colorMode = mode
    saveColor()
  }

  function setCustomHex(value) {
    customHex = Model.validColor(value)
    colorMode = "custom"
    saveColor()
  }

  function saveColor() {
    var value = colorMode === "custom" ? customHex : colorMode
    saveColorProc.command = ["bash", "-c",
      'd="${XDG_CONFIG_HOME:-$HOME/.config}/omaotp"; mkdir -p "$d" && printf "%s\\n" "$1" > "$d/color"',
      "_", value]
    saveColorProc.running = true
  }

  function applyColorFile(text) {
    var c = Model.parseColorFile(text)
    colorMode = c.mode
    customHex = c.hex
  }

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
    panelLoader.item.store = root
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
    // Reads the code from stdin, copies it, drops it from the shell's variables,
    // and clears the clipboard after 30 s only if it still holds the same value.
    // The clear step compares SHA-256 hashes, so no code is kept in argv or in the
    // background shell.
    command: ["sh", "-c",
      'IFS= read -r c || exit 1; ' +
      'h=$(printf %s "$c" | sha256sum); printf %s "$c" | wl-copy -n; unset c; ' +
      '( sleep 30; [ "$(wl-paste -n 2>/dev/null | sha256sum)" = "$h" ] && wl-copy --clear ) >/dev/null 2>&1 &']
    onStarted: {
      copyProc.write(root.pendingCopy + "\n")
      root.pendingCopy = ""
    }
  }
  Process { id: saveColorProc }

  Process {
    id: loadColorProc
    command: ["bash", "-c", 'cat "${XDG_CONFIG_HOME:-$HOME/.config}/omaotp/color" 2>/dev/null || true']
    stdout: StdioCollector { onStreamFinished: root.applyColorFile(text) }
  }

  Process {
    id: themeProc
    command: ["bash", root.themeScriptPath]
    stdout: StdioCollector { onStreamFinished: root.themeHex = Model.validColor(text.trim()) }
  }

  Timer {
    interval: 60 * 1000
    repeat: true
    running: root.colorMode === "theme"
    triggeredOnStart: true
    onTriggered: if (!themeProc.running) themeProc.running = true
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
    interval: 5 * 60 * 1000
    running: root.stage === "open" && !root.opened
    onTriggered: root.lock()
  }

  Component.onCompleted: {
    loadColorProc.running = true
    checkVault()
  }

  implicitWidth: stage === "open" && current !== null
    ? badgeSize + Style.space(12)
    : iconSize + Style.space(12)
  implicitHeight: Math.max(button.implicitHeight, Style.space(14))

  onBarChanged: injectPanel()

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
    tooltipText: "One-time codes (click to open, middle-click to lock)"
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
            ctx.strokeStyle = secs <= 5 ? "#f85149" : secs <= 10 ? "#e3b341" : root.accentColor
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
