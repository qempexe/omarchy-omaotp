import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Otp.js" as Model

Panel {
  id: root
  moduleName: "io.github.qempexe.omaotp"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var store: null

  readonly property string stage: store ? store.stage : "checking"
  readonly property var all: store ? store.entries : []
  readonly property real cell: Style.space(28)
  readonly property real rowHeight: Style.space(44)
  readonly property real smallFont: Math.round(Style.font.subtitle * 0.8)
  readonly property color dim: Qt.alpha(root.barForeground, 0.65)
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family

  property string query: ""
  property bool adding: false
  property string confirmId: ""
  property string dragId: ""
  property int dragFrom: -1
  property int dragTarget: -1
  property real dragStartY: 0
  property real dragOffset: 0

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

  function finishDrag() {
    if (dragId !== "" && dragTarget >= 0 && dragTarget < shown.length
        && dragTarget !== dragFrom && store) {
      store.moveEntry(dragId, shown[dragTarget].id)
    }
    dragId = ""
    dragFrom = -1
    dragTarget = -1
    dragOffset = 0
  }

  function statusText() {
    if (!store) return ""
    if (store.errorCode !== "" && stage !== "open") return Model.errorText(store.errorCode)
    if (stage === "checking") return "Checking vault\u2026"
    if (stage === "setup") return "Create a vault"
    if (stage === "locked") return "Vault locked"
    return "Vault unlocked \u00b7 " + all.length + (all.length === 1 ? " account" : " accounts")
  }

  function open() { root.controller.show() }
  function close() { root.controller.hide() }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      Column {
        id: content
        width: parent.width
        spacing: Style.space(10)

        Text {
          width: parent.width
          text: "omaotp"
          textFormat: Text.PlainText
          color: root.barForeground
          font.family: root.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
          font.letterSpacing: 2
        }

        Text {
          width: parent.width
          text: root.statusText()
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          color: root.barForeground
          font.family: root.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
        }

        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.stage === "setup"

          Text {
            width: parent.width
            text: "Choose a master password. It encrypts your secrets. There is no way to recover it, so keep it safe."
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: root.smallFont
          }

          Rectangle {
            width: parent.width
            height: setupPw.implicitHeight + Style.space(10)
            radius: Style.space(4)
            color: Qt.alpha(root.barForeground, 0.06)
            border.width: 1
            border.color: Qt.alpha(root.barForeground, 0.25)

            TextInput {
              id: setupPw
              anchors.fill: parent
              anchors.margins: Style.space(5)
              echoMode: TextInput.Password
              color: root.barForeground
              font.family: root.fontFamily
              font.pixelSize: root.smallFont
              verticalAlignment: TextInput.AlignVCenter
              onAccepted: if (root.store) root.store.createVault(text)
            }
          }

          Text {
            text: "Create vault"
            textFormat: Text.PlainText
            color: root.barForeground
            font.family: root.fontFamily
            font.pixelSize: root.smallFont
            font.underline: true
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: if (root.store) root.store.createVault(setupPw.text)
            }
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.stage === "locked"

          Rectangle {
            width: parent.width
            height: unlockPw.implicitHeight + Style.space(10)
            radius: Style.space(4)
            color: Qt.alpha(root.barForeground, 0.06)
            border.width: 1
            border.color: Qt.alpha(root.barForeground, 0.25)

            TextInput {
              id: unlockPw
              anchors.fill: parent
              anchors.margins: Style.space(5)
              echoMode: TextInput.Password
              color: root.barForeground
              font.family: root.fontFamily
              font.pixelSize: root.smallFont
              verticalAlignment: TextInput.AlignVCenter
              onAccepted: if (root.store) { root.store.unlock(text); text = "" }
            }
          }

          Text {
            text: "Unlock"
            textFormat: Text.PlainText
            color: root.barForeground
            font.family: root.fontFamily
            font.pixelSize: root.smallFont
            font.underline: true
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: if (root.store) { root.store.unlock(unlockPw.text); unlockPw.text = "" }
            }
          }
        }

        Rectangle {
          width: parent.width
          height: searchField.implicitHeight + Style.space(10)
          visible: root.stage === "open"
          radius: Style.space(4)
          color: Qt.alpha(root.barForeground, 0.06)
          border.width: 1
          border.color: Qt.alpha(root.barForeground, 0.25)

          TextInput {
            id: searchField
            anchors.fill: parent
            anchors.margins: Style.space(5)
            color: root.barForeground
            font.family: root.fontFamily
            font.pixelSize: root.smallFont
            verticalAlignment: TextInput.AlignVCenter
            onTextChanged: root.query = text
          }
          Text {
            visible: searchField.text === ""
            anchors.left: parent.left
            anchors.leftMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            text: "Search accounts"
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: root.smallFont
          }
        }

        Column {
          id: listCol
          width: parent.width
          visible: root.stage === "open"

          Text {
            visible: root.shown.length === 0
            width: parent.width
            text: root.all.length === 0 ? "No accounts yet. Use Add below." : "No accounts match."
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: root.smallFont
            horizontalAlignment: Text.AlignHCenter
            topPadding: Style.space(8)
            bottomPadding: Style.space(8)
          }

          Repeater {
            model: root.shown

            Rectangle {
              id: row
              required property var modelData
              required property int index
              readonly property bool dragging: root.dragId !== "" && root.dragId === row.modelData.id
              width: content.width
              height: root.rowHeight
              radius: Style.space(6)
              z: dragging ? 2 : 0
              transform: Translate { y: row.dragging ? root.dragOffset : 0 }
              color: row.dragging ? Qt.alpha(root.barForeground, 0.12)
                : rowArea.containsMouse ? Qt.alpha(root.barForeground, 0.08) : "transparent"

              Rectangle {
                anchors.fill: parent
                radius: Style.space(6)
                color: "transparent"
                border.width: 1
                border.color: root.store ? root.store.accentColor : root.barForeground
                visible: root.dragId !== "" && root.dragTarget === row.index && root.dragFrom !== row.index
              }

              Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(3)
                anchors.verticalCenter: parent.verticalCenter
                text: "\u2261"
                textFormat: Text.PlainText
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: root.smallFont
              }
              MouseArea {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Style.space(16)
                cursorShape: Qt.SizeVerCursor
                onPressed: function(mouse) {
                  root.dragId = row.modelData.id
                  root.dragFrom = row.index
                  root.dragTarget = row.index
                  root.dragStartY = mapToItem(listCol, mouse.x, mouse.y).y
                  root.dragOffset = 0
                  root.confirmId = ""
                }
                onPositionChanged: function(mouse) {
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
                anchors.leftMargin: Style.space(20)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(30)
                height: Style.space(30)
                radius: Style.space(6)
                color: store ? store.tileColor : Qt.alpha(root.barForeground, 0.18)

                Text {
                  anchors.centerIn: parent
                  text: Model.issuerGlyph(row.modelData.issuer)
                    || Model.tileLetter(row.modelData.issuer, row.modelData.account)
                  textFormat: Text.PlainText
                  color: root.barForeground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.subtitle
                  font.bold: !Model.issuerGlyph(row.modelData.issuer)
                }
              }

              Column {
                anchors.left: tile.right
                anchors.leftMargin: Style.space(8)
                anchors.right: codeArea.left
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  width: parent.width
                  text: row.modelData.issuer || "Account"
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  color: root.barForeground
                  font.family: root.fontFamily
                  font.pixelSize: root.smallFont
                  font.bold: true
                }
                Text {
                  width: parent.width
                  text: row.modelData.account
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Math.round(root.smallFont * 0.9)
                }
              }

              Row {
                id: codeArea
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(6)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  visible: root.confirmId !== row.modelData.id
                  text: Model.formatCode(row.modelData.code)
                  textFormat: Text.PlainText
                  color: root.store && root.store.lastCopied === row.modelData.id
                    ? root.store.accentColor
                    : root.barForeground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.subtitle
                  font.bold: true
                  font.letterSpacing: 1
                }

                Canvas {
                  id: rowRing
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(14)
                  height: Style.space(14)
                  visible: root.confirmId !== row.modelData.id
                  readonly property real secs: root.store ? root.store.remainingFor(row.modelData) : 0
                  readonly property real frac: secs / row.modelData.period
                  onFracChanged: requestPaint()
                  onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    var r = width / 2 - 1.5
                    ctx.lineWidth = 2
                    ctx.strokeStyle = Qt.alpha(root.barForeground, 0.18)
                    ctx.beginPath()
                    ctx.arc(width / 2, height / 2, r, 0, 2 * Math.PI)
                    ctx.stroke()
                    ctx.strokeStyle = secs <= 5 ? "#f85149" : secs <= 10 ? "#e3b341" : (root.store ? root.store.accentColor : root.barForeground)
                    ctx.beginPath()
                    ctx.arc(width / 2, height / 2, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * frac)
                    ctx.stroke()
                  }
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.confirmId === row.modelData.id ? "Remove?" : "\u00d7"
                  textFormat: Text.PlainText
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: root.smallFont
                  MouseArea {
                    anchors.fill: parent
                    anchors.margins: -Style.space(4)
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      if (root.confirmId === row.modelData.id) {
                        root.confirmId = ""
                        if (root.store) root.store.removeEntry(row.modelData.id)
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
                  if (root.store) root.store.copyCode(row.modelData.code)
                  if (root.store) root.store.lastCopied = row.modelData.id
                  root.confirmId = ""
                }
              }
            }
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(6)
          visible: root.stage === "open"

          Text {
            text: root.adding ? "Cancel" : "Add account"
            textFormat: Text.PlainText
            color: root.barForeground
            font.family: root.fontFamily
            font.pixelSize: root.smallFont
            font.underline: true
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.adding = !root.adding
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: root.adding

            Text {
              width: parent.width
              text: "Paste an otpauth:// link, or fill in issuer, account and secret."
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Math.round(root.smallFont * 0.9)
            }

            Rectangle {
              width: parent.width
              height: uriField.implicitHeight + Style.space(10)
              radius: Style.space(4)
              color: Qt.alpha(root.barForeground, 0.06)
              border.width: 1
              border.color: Qt.alpha(root.barForeground, 0.25)
              TextInput {
                id: uriField
                anchors.fill: parent
                anchors.margins: Style.space(5)
                color: root.barForeground
                font.family: root.fontFamily
                font.pixelSize: root.smallFont
                verticalAlignment: TextInput.AlignVCenter
                onAccepted: addBtn.submit()
              }
              Text {
                visible: uriField.text === ""
                anchors.left: parent.left
                anchors.leftMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                text: "otpauth://totp/... (or leave empty and fill below)"
                textFormat: Text.PlainText
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Math.round(root.smallFont * 0.9)
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(6)
              visible: uriField.text === ""

              Row {
                width: parent.width
                spacing: Style.space(6)

                Rectangle {
                  width: (parent.width - Style.space(6)) / 2
                  height: issuerField.implicitHeight + Style.space(10)
                  clip: true
                  radius: Style.space(4)
                  color: Qt.alpha(root.barForeground, 0.06)
                  border.width: 1
                  border.color: Qt.alpha(root.barForeground, 0.25)

                  TextInput {
                    id: issuerField
                    anchors.fill: parent
                    anchors.margins: Style.space(5)
                    clip: true
                    color: root.barForeground
                    font.family: root.fontFamily
                    font.pixelSize: root.smallFont
                    verticalAlignment: TextInput.AlignVCenter
                  }
                  Text {
                    visible: issuerField.text === ""
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(6)
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Issuer"
                    textFormat: Text.PlainText
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: root.smallFont
                  }
                }

                Rectangle {
                  width: (parent.width - Style.space(6)) / 2
                  height: accountField.implicitHeight + Style.space(10)
                  clip: true
                  radius: Style.space(4)
                  color: Qt.alpha(root.barForeground, 0.06)
                  border.width: 1
                  border.color: Qt.alpha(root.barForeground, 0.25)

                  TextInput {
                    id: accountField
                    anchors.fill: parent
                    anchors.margins: Style.space(5)
                    clip: true
                    color: root.barForeground
                    font.family: root.fontFamily
                    font.pixelSize: root.smallFont
                    verticalAlignment: TextInput.AlignVCenter
                  }
                  Text {
                    visible: accountField.text === ""
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(6)
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Account"
                    textFormat: Text.PlainText
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: root.smallFont
                  }
                }
              }

                Rectangle {
                  width: parent.width
                  height: secretField.implicitHeight + Style.space(10)
                  clip: true
                  radius: Style.space(4)
                  color: Qt.alpha(root.barForeground, 0.06)
                  border.width: 1
                  border.color: Qt.alpha(root.barForeground, 0.25)

                  TextInput {
                    id: secretField
                    anchors.fill: parent
                    anchors.margins: Style.space(5)
                    clip: true
                    color: root.barForeground
                    font.family: root.fontFamily
                    font.pixelSize: root.smallFont
                    verticalAlignment: TextInput.AlignVCenter
                  echoMode: TextInput.Password
                  onAccepted: addBtn.submit()
                  }
                  Text {
                    visible: secretField.text === ""
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(6)
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Secret (hidden)"
                    textFormat: Text.PlainText
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: root.smallFont
                  }
                }
            }

            Text {
              id: addBtn
              function submit() {
                if (!root.store) return
                var uri = uriField.text.trim()
                if (Model.isOtpUri(uri)) root.store.addUri(uri)
                else root.store.addUri(Model.buildUri(issuerField.text.trim(), accountField.text.trim(), secretField.text))
                uriField.text = ""; issuerField.text = ""; accountField.text = ""; secretField.text = ""
                root.adding = false
              }
              text: "Add"
              textFormat: Text.PlainText
              color: root.barForeground
              font.family: root.fontFamily
              font.pixelSize: root.smallFont
              font.underline: true
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: addBtn.submit()
              }
            }
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(6)
          visible: root.stage === "open"

          Row {
            width: parent.width
            spacing: Style.space(6)

            Text {
              text: "Color"
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: root.smallFont
            }

            Repeater {
              model: [{ id: "theme", label: "Theme" }, { id: "custom", label: "Custom" }, { id: "mono", label: "Mono" }]

              Rectangle {
                id: modeChip
                required property var modelData
                width: modeLabel.implicitWidth + Style.space(12)
                height: modeLabel.implicitHeight + Style.space(6)
                radius: Style.space(6)
                color: root.store && root.store.colorMode === modeChip.modelData.id
                  ? Qt.alpha(root.barForeground, 0.18)
                  : Qt.alpha(root.barForeground, 0.06)

                Text {
                  id: modeLabel
                  anchors.centerIn: parent
                  text: modeChip.modelData.label
                  textFormat: Text.PlainText
                  color: root.barForeground
                  font.family: root.fontFamily
                  font.pixelSize: root.smallFont
                  font.bold: root.store && root.store.colorMode === modeChip.modelData.id
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: if (root.store) root.store.setColorMode(modeChip.modelData.id)
                }
              }
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(6)
            visible: root.store && root.store.colorMode === "custom"

            Repeater {
              model: Model.PRESET_COLORS

              Rectangle {
                id: swatch
                required property var modelData
                width: Style.space(16)
                height: Style.space(16)
                radius: Style.space(3)
                color: swatch.modelData.hex
                border.width: root.store && root.store.customHex === swatch.modelData.hex ? 2 : 0
                border.color: root.barForeground

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: if (root.store) root.store.setCustomHex(swatch.modelData.hex)
                }
              }
            }

            Rectangle {
              id: hexBox
              width: Style.space(64)
              height: hexField.implicitHeight + Style.space(4)
              radius: Style.space(4)
              color: Qt.alpha(root.barForeground, 0.06)
              border.width: 1
              border.color: Qt.alpha(root.barForeground, 0.25)

              TextInput {
                id: hexField
                anchors.fill: parent
                anchors.leftMargin: Style.space(5)
                anchors.rightMargin: Style.space(5)
                verticalAlignment: TextInput.AlignVCenter
                text: root.store ? root.store.customHex : ""
                maximumLength: 7
                selectByMouse: true
                color: root.barForeground
                font.family: root.fontFamily
                font.pixelSize: root.smallFont
                onAccepted: if (root.store) root.store.setCustomHex(text)
              }
            }

            Text {
              text: "Reset"
              textFormat: Text.PlainText
              color: root.barForeground
              font.family: root.fontFamily
              font.pixelSize: root.smallFont
              font.underline: true

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.store) root.store.setCustomHex(Model.DEFAULT_COLOR)
              }
            }

            Connections {
              target: root.store
              function onCustomHexChanged() { hexField.text = root.store.customHex }
            }
          }

          Text {
            visible: root.store && root.store.colorMode === "theme"
            width: parent.width
            text: "Follows the accent color of your Omarchy theme."
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: root.smallFont
          }

          Text {
            visible: root.store && root.store.colorMode === "mono"
            width: parent.width
            text: "Shades of your bar text color."
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: root.smallFont
          }
        }

        Item {
          width: parent.width
          height: footerLabel.implicitHeight
          visible: root.stage === "open"

          Text {
            id: footerLabel
            anchors.left: parent.left
            anchors.right: lockBtn.left
            anchors.rightMargin: Style.space(8)
            text: root.store && root.store.errorCode !== "" ? Model.errorText(root.store.errorCode) : "Codes refresh every 30 s"
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: root.smallFont
          }

          Text {
            id: lockBtn
            anchors.right: parent.right
            text: "Lock"
            textFormat: Text.PlainText
            color: root.barForeground
            font.family: root.fontFamily
            font.pixelSize: root.smallFont
            font.underline: true
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: if (root.store) root.store.lock()
            }
          }
        }
      }
    }
  }
}
