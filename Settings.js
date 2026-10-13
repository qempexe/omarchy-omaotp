.pragma library

// The one list of settings. tools/gen-manifest.js writes manifest.json from it, and the
// panel's Settings tab is built from it, grouped in the order below.
//   type "palette" is a UI-only row (the custom colour picker); it is not saved.
//   ui "hidden" rows are saved but have no row of their own.
var GROUPS = ["Color", "Security", "Reset"];

// Swatches offered by the custom colour picker (dark backgrounds, light text, a few accents).
var PALETTE = [
    "#141414", "#1d1510", "#1a1b26", "#282a36", "#2e3440", "#2d353b", "#1f1f28", "#3b2a1f",
    "#e0e0e0", "#eadbc8", "#ffffff", "#c0caf5", "#d8dee9", "#dcd7ba", "#f8f8f2", "#e0def4",
    "#39d353", "#7aa2f7", "#bc8cff", "#ff6b2c", "#f85149", "#e3b341", "#58a6ff", "#a7c080"
];

var SCHEMA = [
    { group: "Color", key: "colorMode", type: "enum", label: "Theme",
      options: ["theme", "custom", "mono"], labels: ["Theme", "Custom", "Mono"],
      defaultValue: "theme",
      description: "Theme follows the Omarchy theme's background, text and accent colors. Custom lets you choose every color. Mono is a plain neutral palette." },
    { group: "Color", key: "customPalette", type: "palette", showWhen: "custom",
      label: "Custom colors",
      description: "Choose which color to change, then pick a swatch or type your own hex code." },
    { group: "Color", key: "customBackground", type: "string", ui: "hidden",
      label: "Custom background", defaultValue: "#141414",
      description: "Background color used with the Custom theme." },
    { group: "Color", key: "customText", type: "string", ui: "hidden",
      label: "Custom text", defaultValue: "#e0e0e0",
      description: "Text color used with the Custom theme." },
    { group: "Color", key: "customAccent", type: "string", ui: "hidden",
      label: "Custom accent", defaultValue: "#39d353",
      description: "Accent color used with the Custom theme." },

    { group: "Security", key: "autoLockMinutes", type: "stepper", fmt: "mins",
      label: "Lock after", description: "The vault locks this long after the panel closes.",
      defaultValue: 5 },
    { group: "Security", key: "clipboardSeconds", type: "stepper", fmt: "secs",
      label: "Clear clipboard after",
      description: "A copied code is removed from the clipboard after this long, if it is still there.",
      defaultValue: 30 },

    { group: "Reset", key: "actions", type: "actions", virtual: true,
      label: "Housekeeping", description: "Reset puts every setting back to its default. Your accounts are not touched." }
];

// Saved settings only (the picker row is not a setting).
function realSettings() {
    return SCHEMA.filter(function(d) { return d.type !== "palette" })
}

function defaults() {
    var out = {}, s = realSettings()
    for (var i = 0; i < s.length; i++) out[s[i].key] = s[i].defaultValue
    return out
}
