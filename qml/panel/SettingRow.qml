import QtQuick
import QtQuick.Layouts
import "../controls"

// One setting: label + plain-language hint on the left, current value and a
// reset arrow on the right, and a purpose-built control underneath.
//   kind  enum    drawn by `control`:
//                   tiles  big tiles with a little picture (few, visual choices)
//                   seg    one segmented bar (short choices)
//                   chips  wrapping chips (long lists)
//                 `control` comes from js/Schema.js; left empty it is seg for up
//                 to 5 options and chips for more.
//         int     slider with - / + buttons
//         bool    switch
//                   scheme a tile per color scheme, with a tiny window in its colors
//         string  text field (+ optional preset chips)
//         color   swatches + hex field
//         palette a few colors edited together: pick one, then a swatch or a hex
Item {
    id: root

    property var ui: null
    property string settingKey: ""
    property string label: ""
    property string hint: ""
    property string kind: "string"
    property string control: ""
    property var options: []
    property var labels: ({})
    property var presets: []
    property var value: null
    property var targets: []          // palette: [{ key, label }]
    property int target: 0            // palette: the color being edited
    readonly property string targetKey: targets.length > 0 ? targets[Math.min(target, targets.length - 1)].key : ""
    function colorOf(key) {
        const v = value && typeof value === "object" ? value[key] : undefined
        return validHex(String(v)) ? String(v) : "#000000"
    }

    // What the control shows. A choice is shown the moment it is made, so the control
    // never waits for the settings round trip; it follows the real value again as soon
    // as the parent hands it back.
    property var optimistic: undefined
    readonly property var current: optimistic !== undefined ? optimistic : value
    onValueChanged: optimistic = undefined
    function commit(v) { optimistic = v; edited(v) }
    property var defaultValue: null
    property real min: 0
    property real max: 100
    property real step: 1
    property real divisor: 1
    property int decimals: 0
    property bool dimmed: false
    property int maxLength: 2048       // longest text this row accepts
    property bool locked: false        // shown, but has no effect right now and ignores input

    signal edited(var v)

    function str(v) { return (v === null || v === undefined) ? "" : String(v) }
    function same(a, b) { return str(a) === str(b) }
    function labelFor(opt) { return labels[opt] !== undefined ? labels[opt] : String(opt) }
    function show(v) {
        const n = Number(v) / divisor
        return isFinite(n) ? String(parseFloat(n.toFixed(decimals))) : "?"
    }
    function nudge(dir) {
        const cur = Number(current)
        const v = Math.max(min, Math.min(max, cur + dir * step))
        if (v !== cur) commit(v)
    }
    function validHex(s) { return /^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/.test(s) }
    function rad(k) { return ui.r(k) }

    readonly property string mode: kind !== "enum" ? ""
        : (control !== "" ? control : (options.length <= 5 ? "seg" : "chips"))
    readonly property bool boolValue: current === true || current === "true"
    // palette rows hold { key: color }: equal when every color is
    function sameColors(a, b) {
        if (!a || !b) return false
        for (const k in b) if (str(a[k]).toLowerCase() !== str(b[k]).toLowerCase()) return false
        return true
    }
    readonly property bool atDefault: kind === "palette" ? sameColors(value, defaultValue) : same(current, defaultValue)
    readonly property real span: Math.max(1e-9, max - min)
    readonly property real frac: Math.max(0, Math.min(1, (Number(current) - min) / span))
    readonly property real defFrac: Math.max(0, Math.min(1, (Number(defaultValue) - min) / span))

    implicitWidth: 400
    implicitHeight: col.implicitHeight
    opacity: (dimmed || locked) ? 0.4 : 1.0
    enabled: !locked
    Behavior on opacity { enabled: ui.animations; NumberAnimation { duration: 140 } }

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: ui.px(10)

        RowLayout {
            Layout.fillWidth: true
            spacing: ui.px(10)

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                Txt {
                    ui: root.ui
                    Layout.fillWidth: true
                    text: root.label
                    font.pixelSize: ui.fs(13)
                    font.weight: Font.DemiBold
                }
                Txt {
                    ui: root.ui
                    Layout.fillWidth: true
                    visible: root.hint !== ""
                    text: root.hint
                    font.pixelSize: ui.fs(10)
                    opacity: 0.55
                    wrapMode: Text.Wrap
                }
            }

            // - value +  (sliders)
            RowLayout {
                visible: root.kind === "int"
                spacing: ui.px(6)
                Btn { ui: root.ui; text: "\u2212"; implicitWidth: ui.px(28); implicitHeight: ui.px(28); onClicked: root.nudge(-1) }
                Txt {
                    ui: root.ui
                    Layout.minimumWidth: ui.px(38)
                    horizontalAlignment: Text.AlignHCenter
                    text: root.show(root.current)
                    font.pixelSize: ui.fs(12)
                    font.weight: Font.DemiBold
                }
                Btn { ui: root.ui; text: "+"; implicitWidth: ui.px(28); implicitHeight: ui.px(28); onClicked: root.nudge(1) }
            }

            // reset arrow, only once it differs from the default
            Rectangle {
                visible: !root.atDefault
                implicitWidth: ui.px(24); implicitHeight: ui.px(24)
                radius: root.rad(0.5)
                color: ui.tint(resetArea.containsMouse ? 0.18 : 0.08)
                Txt { ui: root.ui; anchors.centerIn: parent; text: "\u21BA"; font.pixelSize: ui.fs(12) }
                MouseArea {
                    id: resetArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.kind === "palette" ? root.edited({ reset: true }) : root.commit(root.defaultValue)
                }
            }

            // switch
            Sw {
                Layout.alignment: Qt.AlignVCenter
                visible: root.kind === "bool"
                k: ui.densityF
                animate: ui.animations
                ink: ui.fg; accent: ui.accent; knob: ui.accentText
                on: root.boolValue
                onFlipped: root.commit(!root.boolValue)
            }
        }

        // ---- enum: tiles ------------------------------------------------------------
        GridLayout {
            Layout.fillWidth: true
            visible: root.mode === "tiles"
            columns: Math.max(1, Math.min(4, root.options.length))
            columnSpacing: ui.px(10)
            rowSpacing: ui.px(10)

            Repeater {
                model: root.mode === "tiles" ? root.options : []
                delegate: Rectangle {
                    id: tile
                    readonly property bool on: root.same(root.current, modelData)
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: ui.px(84)
                    radius: root.rad(1.4)
                    color: on ? ui.accentTint(0.16) : ui.tint(tArea.containsMouse ? 0.09 : 0.04)
                    border.width: on ? 1.5 : 1
                    border.color: on ? ui.accent : ui.tint(0.08)
                    Behavior on color { enabled: ui.animations; ColorAnimation { duration: 100 } }

                    TileArt {
                        ui: root.ui
                        key: root.settingKey
                        opt: String(modelData)
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: ui.px(12)
                    }
                    Txt {
                        ui: root.ui
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: ui.px(9)
                        width: parent.width - ui.px(12)
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: root.labelFor(modelData)
                        font.pixelSize: ui.fs(10)
                        font.weight: tile.on ? Font.DemiBold : Font.Normal
                        opacity: tile.on ? 1.0 : 0.75
                    }
                    MouseArea {
                        id: tArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.commit(modelData)
                    }
                }
            }
        }

        // ---- enum: color schemes, each a tiny window in its colors --------------------
        GridLayout {
            Layout.fillWidth: true
            visible: root.mode === "scheme"
            columns: Math.max(1, Math.min(5, root.options.length))
            columnSpacing: ui.px(8)
            rowSpacing: ui.px(8)

            Repeater {
                model: root.mode === "scheme" ? root.options : []
                delegate: Rectangle {
                    id: stile
                    readonly property bool on: root.same(root.current, modelData)
                    readonly property var sc: root.ui.schemeColors(String(modelData))
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: ui.px(84)
                    radius: root.rad(1.4)
                    color: on ? ui.accentTint(0.16) : ui.tint(scArea.containsMouse ? 0.09 : 0.04)
                    border.width: on ? 1.5 : 1
                    border.color: on ? ui.accent : ui.tint(0.08)
                    Behavior on color { enabled: ui.animations; ColorAnimation { duration: 100 } }

                    Rectangle {   // the window: a header line and three rows
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: ui.px(9)
                        width: parent.width - ui.px(18)
                        height: ui.px(42)
                        radius: 4
                        color: stile.sc.bg
                        border.width: 1
                        border.color: Qt.rgba(stile.sc.fg.r, stile.sc.fg.g, stile.sc.fg.b, 0.18)
                        Rectangle {
                            x: 5; y: 5
                            width: parent.width * 0.4; height: 3; radius: 1.5
                            color: Qt.rgba(stile.sc.fg.r, stile.sc.fg.g, stile.sc.fg.b, 0.75)
                        }
                        Repeater {
                            model: 3
                            delegate: Item {
                                x: 5
                                y: 12 + index * 9
                                width: parent.width - 10
                                height: 6
                                Rectangle {
                                    width: 6; height: 6; radius: 1.5
                                    color: stile.sc.acs ? stile.sc.acs[index] : stile.sc.ac
                                }
                                Rectangle {
                                    x: 10; anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width * (0.62 - index * 0.12); height: 2; radius: 1
                                    color: Qt.rgba(stile.sc.fg.r, stile.sc.fg.g, stile.sc.fg.b, 0.45)
                                }
                                Rectangle {
                                    visible: index === 0
                                    anchors.right: parent.right
                                    width: 10; height: 5; radius: 2
                                    color: stile.sc.ac
                                }
                            }
                        }
                    }
                    Txt {
                        ui: root.ui
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: ui.px(8)
                        width: parent.width - ui.px(8)
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: root.labelFor(modelData)
                        font.pixelSize: ui.fs(10)
                        font.weight: stile.on ? Font.DemiBold : Font.Normal
                        opacity: stile.on ? 1.0 : 0.75
                    }
                    MouseArea {
                        id: scArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.commit(modelData)
                    }
                }
            }
        }

        // ---- palette: pick a color, then a swatch or a hex ----------------------------
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.kind === "palette"
            spacing: ui.px(10)

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: ui.px(34)
                radius: root.rad(1.4)
                color: ui.tint(0.05)
                border.width: 1
                border.color: ui.tint(0.08)
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 3
                    spacing: 2
                    Repeater {
                        model: root.kind === "palette" ? root.targets : []
                        delegate: Rectangle {
                            id: tg
                            readonly property bool on: index === root.target
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.fillHeight: true
                            radius: root.rad(1.1)
                            color: on ? ui.accent : (tgArea.containsMouse ? ui.tint(0.08) : "transparent")
                            Row {
                                anchors.centerIn: parent
                                spacing: ui.px(6)
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: ui.px(11); height: width; radius: width / 2
                                    color: root.colorOf(modelData.key)
                                    border.width: 1
                                    border.color: tg.on ? ui.accentText : ui.tint(0.35)
                                }
                                Txt {
                                    ui: root.ui
                                    text: modelData.label
                                    color: tg.on ? ui.accentText : ui.fg
                                    font.pixelSize: ui.fs(11)
                                    font.weight: tg.on ? Font.DemiBold : Font.Normal
                                }
                            }
                            MouseArea {
                                id: tgArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.target = index
                            }
                        }
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 8
                columnSpacing: ui.px(8)
                rowSpacing: ui.px(8)
                Repeater {
                    model: root.kind === "palette" ? root.presets : []
                    delegate: Rectangle {
                        readonly property bool on: root.colorOf(root.targetKey).toLowerCase() === String(modelData).toLowerCase()
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: ui.px(24); implicitHeight: implicitWidth
                        radius: width / 2
                        color: modelData
                        border.width: on ? 2 : 1
                        border.color: on ? ui.accent : ui.tint(0.25)
                        scale: swArea.containsMouse ? 1.12 : 1.0
                        Behavior on scale { enabled: ui.animations; NumberAnimation { duration: 90 } }
                        MouseArea {
                            id: swArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.edited({ key: root.targetKey, value: String(modelData).toLowerCase() })
                        }
                    }
                }
            }

            RowLayout {
                spacing: ui.px(8)
                Rectangle {
                    implicitWidth: ui.px(28); implicitHeight: implicitWidth
                    radius: root.rad(1)
                    color: root.colorOf(root.targetKey)
                    border.width: 1
                    border.color: ui.tint(0.25)
                }
                Rectangle {
                    implicitWidth: ui.px(120)
                    implicitHeight: ui.px(28)
                    radius: root.rad(1)
                    color: ui.tint(0.05)
                    border.width: 1
                    border.color: hexBox.activeFocus ? ui.tint(0.28) : ui.tint(0.08)
                    clip: true
                    PasteInput {
                        id: hexBox
                        key: "palette:" + root.settingKey
                        service: root.ui ? root.ui.service : null
                        anchors.fill: parent
                        anchors.leftMargin: ui.px(9)
                        anchors.rightMargin: ui.px(9)
                        color: ui.fg
                        font.family: ui.fontName
                        font.pixelSize: ui.fs(11)
                        maximumLength: 7
                        text: root.kind === "palette" ? root.colorOf(root.targetKey) : ""
                        onEditingFinished: {
                            if (!root.validHex(text)) { text = root.colorOf(root.targetKey); return }
                            if (text.toLowerCase() !== root.colorOf(root.targetKey).toLowerCase())
                                root.edited({ key: root.targetKey, value: text.toLowerCase() })
                        }
                        Keys.onEscapePressed: { text = root.colorOf(root.targetKey); focus = false }
                        Connections {
                            target: root
                            function onTargetKeyChanged() { hexBox.text = root.colorOf(root.targetKey) }
                            function onValueChanged() { hexBox.text = root.colorOf(root.targetKey) }
                        }
                    }
                }
                Txt {
                    ui: root.ui
                    text: "Pick a swatch, or type a hex like #c8925a"
                    font.pixelSize: ui.fs(9)
                    opacity: 0.5
                }
            }
        }

        // ---- enum: segmented bar ----------------------------------------------------
        Rectangle {
            Layout.fillWidth: true
            visible: root.mode === "seg"
            implicitHeight: ui.px(38)
            radius: root.rad(1.4)
            color: ui.tint(0.05)
            border.width: 1
            border.color: ui.tint(0.08)

            RowLayout {
                anchors.fill: parent
                anchors.margins: 3
                spacing: 2

                Repeater {
                    model: root.mode === "seg" ? root.options : []
                    delegate: Rectangle {
                        readonly property bool on: root.same(root.current, modelData)
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.fillHeight: true
                        radius: root.rad(1.1)
                        color: on ? ui.accent : (sArea.containsMouse ? ui.tint(0.08) : "transparent")
                        Behavior on color { enabled: ui.animations; ColorAnimation { duration: 90 } }
                        Txt {
                            ui: root.ui
                            anchors.centerIn: parent
                            width: parent.width - ui.px(8)
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: root.labelFor(modelData)
                            color: parent.on ? ui.accentText : ui.fg
                            font.pixelSize: ui.fs(11)
                            font.weight: parent.on ? Font.DemiBold : Font.Normal
                        }
                        MouseArea {
                            id: sArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.commit(modelData)
                        }
                    }
                }
            }
        }

        // ---- enum: chips ------------------------------------------------------------
        Flow {
            Layout.fillWidth: true
            visible: root.mode === "chips"
            spacing: ui.px(6)
            Repeater {
                model: root.mode === "chips" ? root.options : []
                delegate: Chip {
                    ui: root.ui
                    label: root.labelFor(modelData)
                    on: root.same(root.current, modelData)
                    onClicked: root.commit(modelData)
                }
            }
        }

        // ---- slider: full-width track with the range under its ends -------------------
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.kind === "int"
            spacing: ui.px(2)

            Item {
                id: track
                Layout.fillWidth: true
                implicitHeight: ui.px(24)

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width; height: 6; radius: 3
                    color: ui.tint(0.12)
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width * root.frac; height: 6; radius: 3
                    color: ui.accent
                }
                Rectangle {   // notch at the default
                    anchors.verticalCenter: parent.verticalCenter
                    x: parent.width * root.defFrac - 1
                    width: 2; height: 12
                    color: ui.tint(0.45)
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    x: Math.max(0, Math.min(parent.width - width, parent.width * root.frac - width / 2))
                    width: ui.px(16); height: width; radius: width / 2
                    color: ui.accent
                    border.width: 2
                    border.color: ui.surface
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    function apply(mx) {
                        const f = Math.max(0, Math.min(1, mx / width))
                        const raw = root.min + f * root.span
                        let snapped = root.min + Math.round((raw - root.min) / root.step) * root.step
                        snapped = Math.max(root.min, Math.min(root.max, snapped))
                        if (snapped !== Number(root.current)) root.commit(snapped)
                    }
                    onPressed: function(m) { apply(m.x) }
                    onPositionChanged: function(m) { if (pressed) apply(m.x) }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Txt { ui: root.ui; text: root.show(root.min); font.pixelSize: ui.fs(9); opacity: 0.5 }
                Item { Layout.fillWidth: true }
                Txt { ui: root.ui; text: root.show(root.max); font.pixelSize: ui.fs(9); opacity: 0.5 }
            }
        }

        // ---- text field -------------------------------------------------------------
        Rectangle {
            Layout.fillWidth: true
            visible: root.kind === "string" || root.kind === "color"
            implicitHeight: ui.px(34)
            radius: root.rad(1.4)
            color: ui.tint(0.05)
            border.width: 1
            border.color: field.activeFocus ? ui.tint(0.28) : ui.tint(0.08)
            clip: true

            PasteInput {
                id: field
                key: "setting:" + root.label
                service: root.ui ? root.ui.service : null
                anchors.fill: parent
                anchors.leftMargin: ui.px(12)
                anchors.rightMargin: ui.px(12)
                color: ui.fg
                font.family: ui.fontName
                font.pixelSize: ui.fs(12)
                text: root.str(root.current)
                maximumLength: root.maxLength
                onEditingFinished: {
                    if (root.kind === "color" && !root.validHex(text)) { text = root.str(root.current); return }
                    if (text !== root.str(root.current)) root.commit(text)
                }
                Keys.onEscapePressed: { text = root.str(root.current); focus = false }
                Connections {
                    target: root
                    function onCurrentChanged() { field.text = root.str(root.current) }
                }
            }
        }

        // string presets
        Flow {
            Layout.fillWidth: true
            visible: root.kind === "string" && root.presets.length > 0
            spacing: ui.px(6)
            Repeater {
                model: root.kind === "string" ? root.presets : []
                delegate: Chip {
                    ui: root.ui
                    label: String(modelData).trim() === "" ? "(none)" : String(modelData)
                    on: root.same(root.current, modelData)
                    onClicked: root.commit(modelData)
                }
            }
        }

        // color swatches
        Flow {
            Layout.fillWidth: true
            visible: root.kind === "color"
            spacing: ui.px(10)
            Repeater {
                model: root.kind === "color" ? root.presets : []
                delegate: Rectangle {
                    readonly property bool on: root.same(root.current, modelData)
                    width: ui.px(28); height: width; radius: width / 2
                    color: modelData
                    border.width: on ? 2 : 1
                    border.color: on ? ui.fg : ui.tint(0.25)
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.commit(modelData)
                    }
                }
            }
        }
    }
}
