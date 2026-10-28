import QtQuick
import "../js/Schema.js" as Schema

// All of Omaotp's window state, kept in its own item (not in Panel) so none of
// these names can collide with members of the shell's Panel base type.
// Children read it as `ui.*`: theme colors, spacing helpers and the open tab.
Item {
    id: root

    visible: false

    property var service: null
    property var store: null
    property var cfg: null          // resolved settings, from BarWidget.qml
    property bool opened: false

    property bool popped: false     // true while Omaotp lives in its own window

    signal searchCleared()
    signal locked()                 // the vault was locked: forget what was typed
    signal focusSearch()
    signal popOutRequested()
    signal dockRequested()
    signal closeRequested()

    // ---- theme & spacing helpers (used by every child as ui.*) ----------------
    readonly property var cfgSafe: cfg ? cfg : Schema.resolve({}, {})

    // Narrow scalars, so a delegate that only needs one of them doesn't re-evaluate
    // whenever any setting changes.
    readonly property real densityF: cfgSafe.density === "compact" ? 0.85 : (cfgSafe.density === "spacious" ? 1.2 : 1.0)
    readonly property real fontPct: cfgSafe.fontScale
    readonly property real tintPct: cfgSafe.surfaceTint
    readonly property bool frameOn: cfgSafe.frame === true
    readonly property real opacityF: Math.max(0.5, Math.min(1, Number(cfgSafe.opacity) / 100))

    // Colours handed in by BarWidget: the bar's own foreground and background.
    property color barFg: "white"
    property color barBg: "#121217"

    // The theme's own colors and its window border, read by BarWidget.
    readonly property var borderColors: service ? service.borderColors : []
    readonly property real borderAngle: service ? service.borderAngle : 0

    function lumOf(c) { return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b }
    // Black or white, whichever reads better on colour c.
    function contrast(c) {
        return lumOf(c) > 0.5 ? Qt.rgba(0.08, 0.08, 0.08, 1) : Qt.rgba(0.96, 0.96, 0.96, 1)
    }
    function grey(l) { return Qt.rgba(l, l, l, 1) }
    function hexOr(v, fallback) { return Qt.color(Schema.isHex(v) ? v : fallback) }
    // Text has to read against the surface: too close to it, and it turns black or white.
    function readable(c, on) { return Math.abs(lumOf(c) - lumOf(on)) >= 0.35 ? c : contrast(on) }
    // Your own text color, kept as it is when it reads on the surface. When it is too
    // close to the surface, it is made darker (on a light surface) or lighter (on a
    // dark one), keeping its tint, only as much as needed.
    function keepTint(c, on) {
        const need = 0.4
        if (Math.abs(lumOf(c) - lumOf(on)) >= need) return c
        const to = lumOf(on) > 0.5 ? 0 : 1
        for (let t = 0.05; t < 1; t += 0.05) {
            const m = Qt.rgba(c.r + (to - c.r) * t, c.g + (to - c.g) * t, c.b + (to - c.b) * t, 1)
            if (Math.abs(lumOf(m) - lumOf(on)) >= need) return m
        }
        return contrast(on)
    }

    // ---- the color scheme (Settings > Colors) -------------------------------------
    //   theme       the bar's own colors and the theme's accent
    //   borders     the same, with the accent from the window border
    //   custom      your background, text and accent, exactly as picked
    //   monochrome  no hue at all: greys at the bar's brightness
    readonly property string colorModeKey: cfgSafe.colorMode
    readonly property bool mono: colorModeKey === "monochrome"
    readonly property bool custom: colorModeKey === "custom"

    // The opaque base every surface paints. It is the bar's real background, so the
    // bar panel and the pop-out window show the same colour.
    readonly property color barSurface: Qt.rgba(barBg.r, barBg.g, barBg.b, 1)
    readonly property color surface: custom ? hexOr(cfgSafe.customBg, "#141414")
        : (mono ? grey(lumOf(barSurface)) : barSurface)
    readonly property bool lightSurface: lumOf(surface) > 0.5
    readonly property color customFg: hexOr(cfgSafe.customFg, "#e0e0e0")
    readonly property color fg: custom ? keepTint(customFg, surface)
        : (mono ? contrast(surface)
        : (cfgSafe.textColor === "custom" ? keepTint(customFg, surface)
        : (cfgSafe.textColor === "theme" ? barFg : readable(barFg, surface))))
    readonly property real lum: lumOf(fg)
    readonly property bool lightText: lum > 0.5
    // The shell theme's own accent (BarWidget looks it up; transparent when the
    // shell does not expose one). It colors selected tiles, tabs and sliders, so
    // the window matches the rest of the shell.
    property color themeAccent: "transparent"
    readonly property bool hasThemeAccent: themeAccent.a > 0
    readonly property color themeAc: hasThemeAccent ? Qt.rgba(themeAccent.r, themeAccent.g, themeAccent.b, 1) : fg
    readonly property color accent: custom ? hexOr(cfgSafe.accentColor, "#d4a35a")
        : (mono ? fg
        : (colorModeKey === "borders" && borderColors.length > 0 ? Qt.color(borderColors[0]) : themeAc))

    // The window outline: the window border's gradient, one color from it, or the accent.
    readonly property bool frameGradientOn: frameOn && cfgSafe.frameGradient !== false && borderColors.length > 1
    readonly property color frameColor: {
        const n = borderColors.length
        const pick = cfgSafe.frameColor
        if (n === 0 || pick === "accent" || !pick) return accent
        if (pick === "first") return Qt.color(borderColors[0])
        if (pick === "last") return Qt.color(borderColors[n - 1])
        return Qt.color(borderColors[Math.floor((n - 1) / 2)])
    }
    // the window background, as solid as Window opacity says
    readonly property color panelColor: Qt.rgba(surface.r, surface.g, surface.b, opacityF)

    // The colors of a scheme, for its tile in Settings: background, text, accent.
    function schemeColors(name) {
        if (name === "custom")
            return { bg: hexOr(cfgSafe.customBg, "#141414"), fg: customFg, ac: hexOr(cfgSafe.accentColor, "#d4a35a") }
        if (name === "monochrome") {
            const g = grey(lumOf(barSurface))
            return { bg: g, fg: contrast(g), ac: contrast(g) }
        }
        if (name === "borders" && borderColors.length > 0) {
            const n = borderColors.length
            return { bg: barSurface, fg: barFg, ac: Qt.color(borderColors[0]),
                     acs: [Qt.color(borderColors[0]), Qt.color(borderColors[Math.min(n - 1, 1)]), Qt.color(borderColors[Math.min(n - 1, 2)])] }
        }
        return { bg: barSurface, fg: barFg, ac: themeAc }
    }

    readonly property real accLum: 0.299 * accent.r + 0.587 * accent.g + 0.114 * accent.b
    // text on an accent fill: black or white, or in Custom your own text color
    // when it reads on the accent (a dark accent with dark text gets white instead)
    readonly property color accentText: custom ? readable(fg, accent) : contrast(accent)
    // Status colours: the pastels used on dark bars vanish on light ones, so pick
    // darker variants for light surfaces. Monochrome removes hues altogether.
    readonly property color good: mono ? fg
        : (lightSurface ? Qt.rgba(0.14, 0.50, 0.26, 1) : Qt.rgba(0.48, 0.85, 0.56, 1))
    readonly property color warn: mono ? fg
        : (lightSurface ? Qt.rgba(0.62, 0.40, 0.02, 1) : Qt.rgba(0.94, 0.71, 0.30, 1))
    readonly property color bad: mono ? fg
        : (lightSurface ? Qt.rgba(0.74, 0.16, 0.26, 1) : Qt.rgba(0.97, 0.46, 0.56, 1))
    readonly property color warnText: contrast(warn)
    property string fontName: ""
    readonly property string cardStyle: cfgSafe.cardStyle
    readonly property real radius: cfgSafe.cornerRadius
    // Corner radius for a surface, as a multiple of the Roundness setting:
    // 1.5 buttons and chips, 2 account rows, 2.5 cards, 3 the window itself.
    // Roundness 0 stays square; the cap keeps very round settings sensible.
    function r(k) { return Math.min(24, Math.round(radius * k)) }
    readonly property bool animations: true

    function tint(a) { return Qt.rgba(fg.r, fg.g, fg.b, a) }

    // Cards and account rows, by Card style: soft (filled), outline, flat.
    function cardFill(hover) {
        if (cardStyle === "soft") return tint(hover ? 0.10 : 0.06)
        return hover ? tint(0.05) : "transparent"
    }
    readonly property int cardBorder: cardStyle === "outline" ? 1 : 0

    // Label colour for text on an "on" chip or tab filled with colour `c` (the fill is
    // c at 22% over the surface). Works for any accent, light or dark.
    function onFill(c) {
        return Qt.rgba(surface.r * 0.78 + c.r * 0.22, surface.g * 0.78 + c.g * 0.22,
                       surface.b * 0.78 + c.b * 0.22, 1)
    }
    function onText(c) { return custom ? readable(fg, onFill(c)) : contrast(onFill(c)) }
    function accentTint(a) { return Qt.rgba(accent.r, accent.g, accent.b, a) }
    // Type is drawn: 11 titles, 10 body, 8 to 9 hints.
    readonly property real baseScale: 0.82
    function fs(n) { return Math.max(7, Math.round(n * fontPct / 100 * baseScale)) }
    function px(n) {
        return Math.round(n * densityF)
    }
    // ---- what is showing ----------------------------------------------------------
    property string tabName: "accounts"      // accounts | settings
    property string settingsFilter: ""       // the search box while the Settings tab is open
}
