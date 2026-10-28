import QtQuick
import QtQuick.Layouts
import "../controls"

// The whole Omaotp window, drawn: one rounded panel, a header card, underlined
// tabs, one content card, and the Esc footer. It lives either in the docked popup
// (Panel.qml) or in a floating window (PopoutWindow.qml); both feed it the same
// UiState (`ui`).
Item {
    id: view

    property var ui: null
    readonly property var otp: ui ? ui.service : null        // BarWidget: the vault, the codes, the actions
    clip: true

    // Esc steps back out of a search first. True when it did something.
    function stepBack() {
        if (ui.tabName === "settings" && ui.settingsFilter !== "") {
            ui.settingsFilter = ""
            ui.searchCleared()
            return true
        }
        return false
    }

    // In a window nothing else listens for Esc; the docked popup has its own shortcut.
    Keys.onEscapePressed: function(e) {
        if (ui.popped) {
            if (!view.stepBack()) ui.closeRequested()
            e.accepted = true
        } else e.accepted = false
    }

    Connections {
        target: view.ui
        ignoreUnknownSignals: true
        function onSearchCleared() { searchField.text = "" }
        function onTabNameChanged() { searchField.text = view.ui.settingsFilter }
    }

    // ---- chrome: the same panel in the dock and in the pop-out window ------------
    Rectangle {
        anchors.fill: parent
        radius: ui.r(3)
        color: ui.panelColor
    }
    Rectangle {   // optional accent wash (Window tint, 0 by default)
        anchors.fill: parent
        radius: ui.r(3)
        visible: ui.tintPct > 0
        color: ui.accentTint(ui.tintPct / 100)
    }
    Rectangle {   // edge: a plain neutral line, or one color if "Window outline" is on
        anchors.fill: parent
        radius: ui.r(3)
        color: "transparent"
        visible: !ui.frameGradientOn
        border.width: 1
        border.color: ui.frameOn ? ui.frameColor : ui.tint(0.14)
        opacity: ui.frameOn ? 0.8 : 1
    }
    Canvas {      // edge in the theme's window border gradient, at its angle
        anchors.fill: parent
        visible: ui.frameGradientOn
        opacity: 0.85
        readonly property var stops: ui.borderColors
        readonly property real angle: ui.borderAngle
        readonly property real rad: ui.r(3)
        onStopsChanged: requestPaint()
        onAngleChanged: requestPaint()
        onRadChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onVisibleChanged: if (visible) requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const n = stops.length
            if (!visible || n < 2 || width < 4 || height < 4) return
            const a = angle * Math.PI / 180, dx = Math.cos(a), dy = Math.sin(a)
            const half = (Math.abs(dx) * width + Math.abs(dy) * height) / 2
            const g = ctx.createLinearGradient(width / 2 - dx * half, height / 2 - dy * half,
                                               width / 2 + dx * half, height / 2 + dy * half)
            for (let i = 0; i < n; i++) g.addColorStop(i / (n - 1), stops[i])
            const r = Math.max(0, Math.min(rad, width / 2, height / 2)), x = 0.5, y = 0.5, w = width - 1, h = height - 1
            ctx.strokeStyle = g
            ctx.lineWidth = 1
            ctx.beginPath()
            ctx.moveTo(x + r, y)
            ctx.arcTo(x + w, y, x + w, y + h, r)
            ctx.arcTo(x + w, y + h, x, y + h, r)
            ctx.arcTo(x, y + h, x, y, r)
            ctx.arcTo(x, y, x + w, y, r)
            ctx.closePath()
            ctx.stroke()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: ui.px(14)
        spacing: ui.px(12)

        // ---- header card: the logo, name and status, locking, actions ---------------
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: headerRow.implicitHeight + ui.px(24)
            radius: ui.r(2.5)
            color: ui.tint(0.05)
            border.width: 1
            border.color: ui.tint(0.08)

            RowLayout {
                id: headerRow
                anchors.fill: parent
                anchors.margins: ui.px(12)
                spacing: ui.px(12)

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: ui.px(30); implicitHeight: ui.px(30)
                    radius: ui.r(1.5)
                    color: ui.accentTint(0.18)
                    border.width: 1
                    border.color: ui.tint(0.08)
                    Image {   // the logo, light or dark to suit the window
                        anchors.centerIn: parent
                        width: ui.px(24); height: width
                        source: Qt.resolvedUrl(ui.lightSurface ? "../../assets/logo-dark.png" : "../../assets/logo.png")
                        sourceSize.width: 96
                        sourceSize.height: 96
                        smooth: true
                        mipmap: true
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2
                    Txt {
                        ui: view.ui
                        Layout.fillWidth: true
                        text: "Omaotp"
                        font.pixelSize: ui.fs(13)
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Txt {
                        ui: view.ui
                        Layout.fillWidth: true
                        font.pixelSize: ui.fs(11)
                        opacity: 0.6
                        elide: Text.ElideRight
                        text: !view.otp ? "Starting…" : view.otp.statusLine
                    }
                }

                Btn {
                    ui: view.ui
                    Layout.alignment: Qt.AlignVCenter
                    visible: ui.tabName === "settings"
                    kind: settingsView.confirmReset ? "primary" : "normal"
                    text: settingsView.confirmReset ? "Really reset?" : "Reset all"
                    onClicked: settingsView.resetAll()
                }
                Btn {
                    ui: view.ui
                    Layout.alignment: Qt.AlignVCenter
                    visible: ui.tabName !== "settings" && !!view.otp && view.otp.stage === "open"
                    text: "Lock"
                    onClicked: view.otp.lock()
                }
                Btn {
                    ui: view.ui
                    Layout.alignment: Qt.AlignVCenter
                    text: ui.popped ? "Dock" : "Pop out"
                    onClicked: ui.popped ? ui.dockRequested() : ui.popOutRequested()
                }
                Btn { ui: view.ui; Layout.alignment: Qt.AlignVCenter; text: "×"; implicitWidth: ui.px(24); onClicked: ui.closeRequested() }
            }
        }

        // ---- tabs ------------------------------------------------------------------
        Item {
            Layout.fillWidth: true
            implicitHeight: ui.px(32)

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: ui.tint(0.10)
            }

            RowLayout {
                anchors.fill: parent
                spacing: 0

                Repeater {
                    model: [
                        { key: "accounts", label: "Accounts", n: view.otp && view.otp.stage === "open" ? view.otp.entries.length : 0 },
                        { key: "settings", label: "Settings", n: -1 }
                    ]
                    delegate: Item {
                        readonly property bool on: ui.tabName === modelData.key
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.fillHeight: true

                        Row {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: -1
                            spacing: ui.px(6)
                            Txt {
                                ui: view.ui
                                text: modelData.label
                                font.pixelSize: ui.fs(12)
                                font.weight: parent.parent.on ? Font.DemiBold : Font.Normal
                                opacity: parent.parent.on ? 1 : (tabArea.containsMouse ? 0.8 : 0.5)
                            }
                            Rectangle {
                                visible: modelData.n > 0
                                width: cnt.implicitWidth + ui.px(10); height: ui.px(15); radius: height / 2
                                color: ui.tint(0.16)
                                anchors.verticalCenter: parent.verticalCenter
                                Txt {
                                    id: cnt
                                    ui: view.ui
                                    anchors.centerIn: parent
                                    text: modelData.n
                                    font.pixelSize: ui.fs(9)
                                }
                            }
                        }
                        Rectangle {
                            visible: parent.on
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 2
                            radius: 1
                            color: ui.accent
                        }
                        MouseArea {
                            id: tabArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ui.tabName = modelData.key
                        }
                    }
                }
            }
        }

        // ---- content card -------------------------------------------------------------
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 0
            radius: ui.r(2.5)
            color: ui.tint(0.035)
            border.width: 1
            border.color: ui.tint(0.07)
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: ui.px(10)
                spacing: ui.px(8)

                // the search box, on the Settings tab
                Rectangle {
                    visible: ui.tabName === "settings"
                    Layout.fillWidth: true
                    Layout.maximumWidth: ui.px(420)
                    implicitHeight: ui.px(28)
                    radius: ui.r(1.5)
                    color: ui.tint(0.05)
                    border.width: 1
                    border.color: searchField.activeFocus ? ui.tint(0.28) : ui.tint(0.08)
                    clip: true

                    Txt { ui: view.ui; anchors.left: parent.left; anchors.leftMargin: ui.px(10); anchors.verticalCenter: parent.verticalCenter; text: "⌕"; opacity: 0.5; font.pixelSize: ui.fs(14) }
                    PasteInput {
                        id: searchField
                        key: "search"
                        service: view.otp
                        anchors.fill: parent
                        anchors.leftMargin: ui.px(30)
                        anchors.rightMargin: ui.px(30)
                        color: ui.fg
                        font.family: ui.fontName
                        font.pixelSize: ui.fs(12)
                        maximumLength: 50
                        text: ui.settingsFilter
                        onTextEdited: ui.settingsFilter = text
                        Keys.onEscapePressed: function(e) {
                            if (text !== "") { text = ""; ui.settingsFilter = ""; e.accepted = true }
                            else e.accepted = false
                        }
                        Txt {
                            ui: view.ui
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            elide: Text.ElideRight
                            visible: searchField.text === "" && !searchField.activeFocus
                            text: "Search settings…"
                            opacity: 0.4
                        }
                    }
                    Txt {
                        ui: view.ui
                        anchors.right: parent.right
                        anchors.rightMargin: ui.px(10)
                        anchors.verticalCenter: parent.verticalCenter
                        visible: searchField.text !== ""
                        text: "✕"
                        opacity: 0.6
                        MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: { searchField.text = ""; ui.settingsFilter = "" } }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    AccountsPage {
                        ui: view.ui
                        anchors.fill: parent
                        visible: ui.tabName === "accounts"
                    }
                    SettingsView {
                        id: settingsView
                        ui: view.ui
                        anchors.fill: parent
                        visible: ui.tabName === "settings"
                    }
                }
            }
        }

        // ---- footer: Esc hint and a line about what's showing ----------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: ui.px(8)

            Rectangle {
                implicitWidth: escLabel.implicitWidth + ui.px(12)
                implicitHeight: ui.px(18)
                radius: ui.r(1)
                color: ui.tint(0.08)
                Txt { id: escLabel; ui: view.ui; anchors.centerIn: parent; text: "Esc"; font.pixelSize: ui.fs(10); opacity: 0.75 }
            }
            Txt { ui: view.ui; text: "close"; font.pixelSize: ui.fs(10); opacity: 0.45 }

            Txt {
                ui: view.ui
                Layout.fillWidth: true
                elide: Text.ElideRight
                font.pixelSize: ui.fs(10)
                opacity: 0.45
                text: ui.tabName === "settings"
                    ? (settingsView.changed === 0 ? "All settings are at their defaults"
                       : settingsView.changed + (settingsView.changed === 1 ? " setting differs" : " settings differ") + " from the defaults")
                    : (view.otp && view.otp.stage === "open" ? "Click a row to copy its code" : "Encrypted on this computer")
            }
            Txt { ui: view.ui; visible: ui.tabName === "settings"; text: "Changes apply instantly"; font.pixelSize: ui.fs(10); opacity: 0.45 }
        }
    }
}
