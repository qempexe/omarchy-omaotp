// Run with: node tests/otp.test.js
const fs = require("fs"), path = require("path"), assert = require("assert")
function load(name, exports) {
  const src = fs.readFileSync(path.join(__dirname, "..", name), "utf8").replace(/^\.pragma library.*$/m, "")
  return new Function(src + "\nreturn {" + exports + "}")()
}
const M = load("Otp.js", "DEFAULTS, OPTIONS, MODES, normalizeSettings, stepOption, formatSetting, parseAccent, parseTheme, validColor, parseEntries, buildUri, parseColorFile, formatCode, remaining, errorText, isOtpUri, minPeriod, shade, MIN_PASSWORD")
const { SCHEMA, SWATCHES } = load("Settings.js", "SCHEMA, SWATCHES")

// schema and model agree
const keys = new Set()
for (const d of SCHEMA) {
  if (d.virtual) continue
  keys.add(d.key)
  assert.deepStrictEqual(d.defaultValue, M.DEFAULTS[d.key], "default drift: " + d.key)
}
for (const k in M.DEFAULTS) assert.ok(keys.has(k), "no row for " + k)
for (const d of SCHEMA.filter(d => d.type === "stepper")) {
  assert.ok(M.OPTIONS[d.key].includes(M.DEFAULTS[d.key])); assert.ok(M.formatSetting(d.fmt, M.DEFAULTS[d.key]))
}
const en = SCHEMA.find(d => d.type === "enum"); assert.strictEqual(en.options.length, en.labels.length)
assert.ok(SWATCHES.every(h => M.validColor(h) === h))

// normalisation rejects junk and keeps good values
assert.deepStrictEqual(M.normalizeSettings({}), M.DEFAULTS)
assert.deepStrictEqual(M.normalizeSettings(null), M.DEFAULTS)
const n = M.normalizeSettings({ colorMode: "neon", customColor: "red", autoLockMinutes: 7, clipboardSeconds: "30" })
assert.deepStrictEqual(n, M.DEFAULTS)
const g = M.normalizeSettings({ colorMode: "custom", customColor: "#ABCDEF", autoLockMinutes: 15, clipboardSeconds: 60 })
assert.deepStrictEqual(g, { colorMode: "custom", customColor: "#abcdef", autoLockMinutes: 15, clipboardSeconds: 60 })

// stepping stays inside the list
const L = M.OPTIONS.autoLockMinutes
assert.strictEqual(M.stepOption(L, 1, -1), 1); assert.strictEqual(M.stepOption(L, 30, 1), 30)
assert.strictEqual(M.stepOption(L, 5, 1), 10); assert.strictEqual(M.stepOption(L, 99, 1), 2)
assert.strictEqual(M.formatSetting("mins", 1), "1 minute"); assert.strictEqual(M.formatSetting("secs", 30), "30 s")

// theme accent and the old colour file
assert.strictEqual(M.parseAccent('accent = "#7AA2F7"\n'), "#7aa2f7"); assert.strictEqual(M.parseAccent("x"), "")
assert.deepStrictEqual(M.parseColorFile("mono\n"), { mode: "mono", hex: "#39d353" })
assert.deepStrictEqual(M.parseColorFile("#58A6FF\n"), { mode: "custom", hex: "#58a6ff" })
assert.deepStrictEqual(M.parseColorFile(""), { mode: "theme", hex: "#39d353" })

// unchanged behaviour still works
assert.strictEqual(M.formatCode("123456"), "123 456"); assert.strictEqual(M.remaining(30, 31000), 29)
assert.ok(M.errorText("short").length > 0 && M.errorText("nope") === M.errorText("request-failed"))
assert.strictEqual(M.buildUri("GitHub", "me", "abcd efgh"), "otpauth://totp/GitHub:me?secret=ABCDEFGH&issuer=GitHub")
const ok = M.parseEntries(JSON.stringify({ entries: [{ id: "0123456789ab", issuer: "X", account: "a", code: "123456", period: 30 }, { id: "bad", code: "1" }] }))
assert.strictEqual(ok.entries.length, 1)
const th = M.parseTheme('accent = "#7AA2F7"\nforeground = "#c0caf5"\nbackground = "#1a1b26"\nselection_background = "#333"\n')
assert.deepStrictEqual(th, { accent: "#7aa2f7", background: "#1a1b26", foreground: "#c0caf5" })
assert.deepStrictEqual(M.parseTheme("accent = \"#112233\""), { accent: "#112233", background: "", foreground: "" })
console.log("otp tests passed")
