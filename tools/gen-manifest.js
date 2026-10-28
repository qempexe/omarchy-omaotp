#!/usr/bin/env node
// Regenerates manifest.json from Schema.js:  node tools/gen-manifest.js
const fs = require("fs"), path = require("path");
const root = path.join(__dirname, "..");
const src = fs.readFileSync(path.join(root, "qml", "js", "Schema.js"), "utf8").replace(".pragma library", "");
const { groups } = new Function(src + ";return { groups }")();

// One manifest entry per saved key: a palette row (several colors edited together)
// becomes one "#rrggbb" string entry per color.
const TYPES = { enum: "enum", int: "integer", bool: "boolean", string: "string", color: "string" };
const settings = [];
for (const g of groups) {
  for (const it of g.items) {
    if (it.kind === "palette") {
      for (const t of it.targets)
        settings.push({ key: t.key, type: "string", label: "Custom " + t.label.toLowerCase(), defaultValue: it.fallback[t.key],
          description: it.hint + " A #rrggbb color, used when Colors is Custom." });
      continue;
    }
    const d = { key: it.key, type: TYPES[it.kind], label: it.label, defaultValue: it.fallback, description: it.hint };
    if (it.options) d.options = it.options.slice();
    if (it.kind === "int") { d.min = it.min; d.max = it.max; d.step = it.step || 1; }
    settings.push(d);
  }
}

const manifest = {
  schemaVersion: 1,
  id: "io.github.qempexe.omaotp",
  name: "Omaotp",
  version: "1.2.0",
  author: "qempexe",
  license: "MIT",
  description: "One-time codes (TOTP) in the Omarchy bar, from an encrypted vault on your computer: countdown rings, one-click copy that clears itself, and a window docked to the bar or popped out.",
  kinds: ["bar-widget"],
  entryPoints: { barWidget: "qml/BarWidget.qml" },
  barWidget: {
    displayName: "Omaotp",
    description: "TOTP authenticator with an encrypted local vault",
    category: "Security",
    aliases: ["otp", "totp", "2fa", "authenticator", "codes", "mfa"],
    allowMultiple: false,
    defaultSection: "right",
    defaults: {},
    schema: []
  }
};

for (const d of settings) {
  manifest.barWidget.defaults[d.key] = d.defaultValue;
  const entry = { key: d.key, type: d.type, label: d.label, defaultValue: d.defaultValue, description: d.description };
  if (d.options) entry.options = d.options;
  if (d.min !== undefined) entry.min = d.min;
  if (d.max !== undefined) entry.max = d.max;
  if (d.step !== undefined) entry.step = d.step;
  manifest.barWidget.schema.push(entry);
}

fs.writeFileSync(path.join(root, "manifest.json"), JSON.stringify(manifest, null, 2) + "\n");
console.log("manifest.json written with", settings.length, "settings");
