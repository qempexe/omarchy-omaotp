import QtQuick
import QtQuick.Layouts
import "../controls"
import "../js/Otp.js" as Model

// The Accounts tab: creating or unlocking the vault, then the list of codes, with
// search, copying, reordering by dragging, removing, and adding an account.
// What it shows lives in BarWidget.qml (`ui.service`).
Item {
    id: root

    property var ui: null
    readonly property var otp: ui ? ui.service : null
    readonly property var cfg: ui.cfgSafe
    readonly property string stage: otp ? otp.stage : "checking"

    property string query: ""
    property bool adding: false
    property string confirmId: ""
    readonly property var all: otp && stage === "open" ? otp.entries : []
    readonly property var shown: {
        const q = query.toLowerCase()
        return q === "" ? all : all.filter((e) => e.issuer.toLowerCase().includes(q) || e.account.toLowerCase().includes(q))
    }

    // dragging a row by its handle
    property string dragId: ""
    property int dragFrom: -1
    property int dragTarget: -1
    property real dragStartY: 0
    property real dragOffset: 0
    readonly property real rowHeight: ui.px(56)
    readonly property real rowGap: ui.px(6)

    function finishDrag() {
        if (dragId !== "" && dragTarget >= 0 && dragTarget < shown.length && dragTarget !== dragFrom && otp)
            otp.moveEntry(dragId, shown[dragTarget].id)
        dragId = ""
        dragFrom = -1
        dragTarget = -1
        dragOffset = 0
    }

    // Everything typed here is forgotten when the vault locks or the window closes.
    function clearAll() {
        passBox.clear(); againBox.clear()
        clearAdd()
        adding = false
        confirmId = ""
        query = ""; searchBox.clear()
        dragId = ""
    }
    function clearAdd() { uriBox.clear(); issuerBox.clear(); accountBox.clear(); secretBox.clear() }
    Connections {
        target: root.ui
        function onLocked() { root.clearAll() }
        function onOpenedChanged() { if (!root.ui.opened) root.clearAll() }
    }

    function submitAuth() {
        if (!otp) return
        if (stage === "setup") {
            if (otp.createVault(passBox.text, againBox.text)) { passBox.clear(); againBox.clear() }
        } else if (stage === "locked") {
            otp.unlock(passBox.text)
            passBox.clear()
        }
    }
    function submitAdd() {
        if (!otp) return
        const uri = uriBox.text.trim()
        if (Model.isOtpUri(uri)) otp.addUri(uri)
        else if (secretBox.text !== "" && accountBox.text.trim() !== "")
            otp.addUri(Model.buildUri(issuerBox.text.trim(), accountBox.text.trim(), secretBox.text))
        else return
        clearAdd()
        adding = false
    }
    onStageChanged: if ((stage === "setup" || stage === "locked") && visible) Qt.callLater(() => passBox.focusField())

    // ---- creating or unlocking the vault ----------------------------------------------
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        visible: root.stage !== "open"
        implicitHeight: authCol.implicitHeight + ui.px(28)
        height: implicitHeight
        radius: ui.r(2.5)
        color: ui.cardFill(false)
        border.width: ui.cardBorder
        border.color: ui.tint(0.12)

        ColumnLayout {
            id: authCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: ui.px(14)
            spacing: ui.px(10)

            Txt {
                ui: root.ui
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                font.pixelSize: ui.fs(12)
                font.weight: Font.DemiBold
                text: root.stage === "setup" ? "Create your vault"
                    : root.stage === "locked" ? "Unlock your vault" : "Checking the vault…"
            }
            Txt {
                ui: root.ui
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                opacity: 0.65
                visible: root.stage !== "checking"
                text: root.stage === "setup"
                    ? "Your codes are kept encrypted on this computer, behind a master password of at least 8 characters. Without it the vault can't be opened, so keep it safe."
                    : "Enter your master password to show your codes."
            }
            InputBox {
                id: passBox
                ui: root.ui
                Layout.fillWidth: true
                visible: root.stage === "setup" || root.stage === "locked"
                key: "password"
                masked: true
                maximumLength: 256
                placeholder: root.stage === "setup" ? "Master password" : "Master password"
                onAccepted: root.stage === "setup" ? againBox.focusField() : root.submitAuth()
            }
            InputBox {
                id: againBox
                ui: root.ui
                Layout.fillWidth: true
                visible: root.stage === "setup"
                key: "password-again"
                masked: true
                maximumLength: 256
                placeholder: "The same password again"
                onAccepted: root.submitAuth()
            }
            Txt {
                ui: root.ui
                Layout.fillWidth: true
                visible: !!root.otp && root.otp.errorCode !== ""
                wrapMode: Text.Wrap
                color: ui.bad
                text: root.otp ? Model.errorText(root.otp.errorCode) : ""
            }
            Btn {
                ui: root.ui
                Layout.fillWidth: true
                implicitHeight: ui.px(34)
                kind: "primary"
                visible: root.stage === "setup" || root.stage === "locked"
                text: root.stage === "setup" ? "Create vault" : "Unlock"
                onClicked: root.submitAuth()
            }
        }
    }

    // ---- the open vault -----------------------------------------------------------------
    ColumnLayout {
        anchors.fill: parent
        visible: root.stage === "open"
        spacing: ui.px(8)

        InputBox {
            id: searchBox
            ui: root.ui
            Layout.fillWidth: true
            key: "search"
            maximumLength: 64
            placeholder: "Search accounts"
            onEdited: root.query = text
        }

        Flickable {
            id: listFlick
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: listCol.implicitHeight
            interactive: root.dragId === ""
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: listCol
                width: listFlick.width
                spacing: root.rowGap

                Txt {
                    ui: root.ui
                    visible: root.shown.length === 0
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    topPadding: ui.px(16)
                    bottomPadding: ui.px(16)
                    opacity: 0.55
                    text: root.all.length === 0 ? "No accounts yet. Add one below." : "No accounts match."
                }

                Repeater {
                    model: root.shown
                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property bool dragging: root.dragId !== "" && root.dragId === modelData.id
                        readonly property bool confirming: root.confirmId === modelData.id
                        readonly property bool hovered: rowArea.containsMouse || handleArea.containsMouse || removeArea.containsMouse
                        width: listCol.width
                        height: root.rowHeight
                        radius: ui.r(2)
                        z: dragging ? 2 : 0
                        transform: Translate { y: row.dragging ? root.dragOffset : 0 }
                        color: row.dragging ? ui.tint(0.14) : ui.cardFill(row.hovered)
                        border.width: root.dragId !== "" && root.dragTarget === row.index && root.dragFrom !== row.index ? 1 : ui.cardBorder
                        border.color: root.dragId !== "" && root.dragTarget === row.index ? ui.accent : ui.tint(0.12)

                        // the handle: drag to reorder; the top account is the one on the bar
                        Txt {
                            ui: root.ui
                            anchors.left: parent.left
                            anchors.leftMargin: ui.px(8)
                            anchors.verticalCenter: parent.verticalCenter
                            text: "≡"
                            opacity: 0.5
                            font.pixelSize: ui.fs(13)
                        }
                        MouseArea {
                            id: handleArea
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: ui.px(24)
                            hoverEnabled: true
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
                                const y = mapToItem(listCol, mouse.x, mouse.y).y
                                root.dragOffset = y - root.dragStartY
                                const t = Math.floor(y / (root.rowHeight + root.rowGap))
                                root.dragTarget = Math.max(0, Math.min(root.shown.length - 1, t))
                            }
                            onReleased: root.finishDrag()
                            onCanceled: root.finishDrag()
                        }

                        Rectangle {
                            id: tile
                            anchors.left: parent.left
                            anchors.leftMargin: ui.px(28)
                            anchors.verticalCenter: parent.verticalCenter
                            width: ui.px(34)
                            height: width
                            radius: ui.r(1.5)
                            color: ui.accentTint(0.22)
                            Txt {
                                ui: root.ui
                                anchors.centerIn: parent
                                readonly property string glyph: root.cfg.showIcons ? Model.issuerGlyph(row.modelData.issuer) : ""
                                text: glyph || Model.tileLetter(row.modelData.issuer, row.modelData.account)
                                font.pixelSize: ui.fs(15)
                                font.weight: glyph ? Font.Normal : Font.DemiBold
                            }
                        }

                        Column {
                            anchors.left: tile.right
                            anchors.leftMargin: ui.px(10)
                            anchors.right: codeArea.left
                            anchors.rightMargin: ui.px(8)
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: ui.px(2)
                            Txt {
                                ui: root.ui
                                width: parent.width
                                text: row.modelData.issuer || "Account"
                                elide: Text.ElideRight
                                font.pixelSize: ui.fs(12)
                                font.weight: Font.DemiBold
                            }
                            Txt {
                                ui: root.ui
                                width: parent.width
                                text: row.modelData.account
                                elide: Text.ElideRight
                                opacity: 0.6
                            }
                        }

                        Row {
                            id: codeArea
                            anchors.right: parent.right
                            anchors.rightMargin: ui.px(10)
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: ui.px(10)

                            Txt {
                                ui: root.ui
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !row.confirming
                                readonly property bool hidden: root.cfg.hideCodes && !row.hovered
                                text: hidden ? "••• •••" : Model.formatCode(row.modelData.code, root.cfg.groupCodes)
                                color: root.otp && root.otp.lastCopied === row.modelData.id ? ui.accent : ui.fg
                                font.pixelSize: ui.fs(17)
                                font.weight: Font.DemiBold
                                font.letterSpacing: 1
                            }
                            Canvas {
                                id: rowRing
                                anchors.verticalCenter: parent.verticalCenter
                                width: ui.px(16)
                                height: width
                                visible: !row.confirming
                                readonly property real secs: root.otp ? root.otp.remainingFor(row.modelData) : 0
                                readonly property real frac: secs / row.modelData.period
                                readonly property color ink: ui.fg
                                readonly property color accent: ui.accent
                                onFracChanged: requestPaint()
                                onInkChanged: requestPaint()
                                onAccentChanged: requestPaint()
                                onPaint: {
                                    const ctx = getContext("2d")
                                    ctx.reset()
                                    const r = width / 2 - 1.5
                                    ctx.lineWidth = 2
                                    ctx.strokeStyle = Qt.alpha(ink, 0.18)
                                    ctx.beginPath()
                                    ctx.arc(width / 2, height / 2, r, 0, 2 * Math.PI)
                                    ctx.stroke()
                                    ctx.strokeStyle = secs <= 5 ? ui.bad : secs <= 10 ? ui.warn : accent
                                    ctx.beginPath()
                                    ctx.arc(width / 2, height / 2, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * frac)
                                    ctx.stroke()
                                }
                            }
                            Txt {
                                ui: root.ui
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.confirming ? "Remove?" : "×"
                                color: row.confirming ? ui.bad : ui.fg
                                opacity: row.confirming || removeArea.containsMouse ? 1 : 0.45
                                font.pixelSize: ui.fs(13)
                                MouseArea {
                                    id: removeArea
                                    anchors.fill: parent
                                    anchors.margins: -ui.px(6)
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (row.confirming) {
                                            root.confirmId = ""
                                            if (root.otp) root.otp.removeEntry(row.modelData.id)
                                        } else root.confirmId = row.modelData.id
                                    }
                                }
                            }
                        }

                        // the row itself: click to copy its code
                        MouseArea {
                            id: rowArea
                            anchors.left: tile.left
                            anchors.right: codeArea.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.otp) root.otp.copyCode(row.modelData)
                                root.confirmId = ""
                            }
                        }
                    }
                }
            }
        }

        Txt {
            ui: root.ui
            Layout.fillWidth: true
            visible: !!root.otp && root.otp.errorCode !== ""
            wrapMode: Text.Wrap
            color: ui.bad
            text: root.otp ? Model.errorText(root.otp.errorCode) : ""
        }

        // adding an account: a link, or the three fields
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.adding
            spacing: ui.px(8)

            Txt {
                ui: root.ui
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                opacity: 0.65
                text: "Paste an otpauth:// link, or fill in the issuer, the account and the secret."
            }
            InputBox {
                id: uriBox
                ui: root.ui
                Layout.fillWidth: true
                key: "uri"
                maximumLength: 2048
                placeholder: "otpauth://totp/…"
                onAccepted: root.submitAdd()
            }
            RowLayout {
                Layout.fillWidth: true
                visible: uriBox.text === ""
                spacing: ui.px(8)
                InputBox { id: issuerBox; ui: root.ui; Layout.fillWidth: true; Layout.preferredWidth: 1; key: "issuer"; maximumLength: 64; placeholder: "Issuer" }
                InputBox { id: accountBox; ui: root.ui; Layout.fillWidth: true; Layout.preferredWidth: 1; key: "account"; maximumLength: 128; placeholder: "Account" }
            }
            InputBox {
                id: secretBox
                ui: root.ui
                Layout.fillWidth: true
                visible: uriBox.text === ""
                key: "secret"
                masked: true
                maximumLength: 128
                placeholder: "Secret (hidden)"
                onAccepted: root.submitAdd()
            }
            Btn {
                ui: root.ui
                Layout.fillWidth: true
                implicitHeight: ui.px(32)
                kind: "primary"
                text: "Add"
                onClicked: root.submitAdd()
            }
        }

        Btn {
            ui: root.ui
            Layout.fillWidth: true
            implicitHeight: ui.px(32)
            text: root.adding ? "Cancel" : "+ Add account"
            onClicked: { root.adding = !root.adding; if (!root.adding) root.clearAdd(); else Qt.callLater(() => uriBox.focusField()) }
        }
    }
}
