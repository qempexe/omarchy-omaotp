.pragma library

var ERRORS = {
  "no-vault": "No vault yet. Create one with a master password.",
  "exists": "A vault already exists.",
  "bad-password": "Wrong master password.",
  "bad-uri": "That is not a valid otpauth:// TOTP link.",
  "duplicate": "That account is already in the vault.",
  "not-found": "That entry no longer exists.",
  "too-many": "The vault is full.",
  "no-openssl": "openssl is not installed.",
  "bad-response": "The helper returned something unexpected.",
  "request-failed": "Something went wrong. Try again.",
  "short": "Use at least 8 characters."
}

var ISSUER_GLYPHS = {
  github: "\uf09b", gitlab: "\uf296", google: "\uf1a0", microsoft: "\uf3ca",
  apple: "\uf179", discord: "\uf392", reddit: "\uf281", dropbox: "\uf16b",
  amazon: "\uf270", twitter: "\uf099", facebook: "\uf09a", linkedin: "\uf0e1",
  slack: "\uf198", steam: "\uf1b6", twitch: "\uf1e8", youtube: "\uf167", paypal: "\uf1ed"
}
var LOCK_GLYPH = "\uf023"

var DEFAULT_COLOR = "#39d353"
var HEX_COLOR = /^#[0-9a-fA-F]{6}$/
var ID_RE = /^[0-9a-f]{12}$/
var CODE_RE = /^\d{6,8}$/
var MAX_ENTRIES = 200
var MIN_PASSWORD = 8

var PRESET_COLORS = [
  { name: "Green", hex: "#39d353" },
  { name: "Blue", hex: "#58a6ff" },
  { name: "Purple", hex: "#bc8cff" },
  { name: "Orange", hex: "#ff6b2c" },
  { name: "Red", hex: "#f85149" },
  { name: "Yellow", hex: "#e3b341" }
]

// Settings (saved by SettingsStore.qml to ~/.config/omaotp/settings.json)
var MODES = ["theme", "custom", "mono"]

// Monochrome palette (fixed neutral).
var MONO = { background: "#141414", text: "#e0e0e0", accent: "#aaaaaa" }

var DEFAULTS = {
  colorMode: "theme",
  customBackground: MONO.background,
  customText: MONO.text,
  customAccent: DEFAULT_COLOR,
  autoLockMinutes: 5,
  clipboardSeconds: 30
}
var OPTIONS = {
  autoLockMinutes: [1, 2, 5, 10, 15, 30],
  clipboardSeconds: [10, 20, 30, 60, 120]
}

function inList(list, v, d) {
  return typeof v === "number" && list.indexOf(v) >= 0 ? v : d
}

function normalizeSettings(raw) {
  var r = raw && typeof raw === "object" ? raw : {}
  return {
    colorMode: MODES.indexOf(r.colorMode) >= 0 ? r.colorMode : DEFAULTS.colorMode,
    customBackground: isHex(r.customBackground) ? r.customBackground.toLowerCase() : DEFAULTS.customBackground,
    customText: isHex(r.customText) ? r.customText.toLowerCase() : DEFAULTS.customText,
    customAccent: isHex(r.customAccent) ? r.customAccent.toLowerCase() : DEFAULTS.customAccent,
    autoLockMinutes: inList(OPTIONS.autoLockMinutes, r.autoLockMinutes, DEFAULTS.autoLockMinutes),
    clipboardSeconds: inList(OPTIONS.clipboardSeconds, r.clipboardSeconds, DEFAULTS.clipboardSeconds)
  }
}

// The next (dir = 1) or previous (dir = -1) value in a list, staying at the ends.
function stepOption(list, value, dir) {
  var i = list.indexOf(value)
  if (i < 0) i = 0
  return list[Math.max(0, Math.min(list.length - 1, i + dir))]
}

function formatSetting(fmt, v) {
  if (fmt === "mins") return v + (v === 1 ? " minute" : " minutes")
  if (fmt === "secs") return v + " s"
  return String(v)
}

// ---------------------------------------------------------------------------
// Colours. Theme reads the whole Omarchy palette (background, text, accent);
// Custom takes the user's own three colours (with readability fixes);
// Mono is a fixed neutral palette.
// ---------------------------------------------------------------------------

function isHex(s) { return /^#[0-9a-fA-F]{6}$/.test(String(s || "")) }

function _lum(hex) {
  var n = parseInt(String(hex).slice(1), 16), out = 0, w = [0.2126, 0.7152, 0.0722]
  for (var i = 0; i < 3; i++) {
    var c = ((n >> (16 - 8 * i)) & 255) / 255
    out += w[i] * (c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4))
  }
  return out
}
function contrast(a, b) {
  var x = _lum(a), y = _lum(b), hi = Math.max(x, y), lo = Math.min(x, y)
  return (hi + 0.05) / (lo + 0.05)
}
function readableOn(fg, bg, minRatio) {
  if (contrast(fg, bg) >= minRatio) return fg
  return contrast("#141414", bg) >= contrast("#f5f5f5", bg) ? "#141414" : "#f5f5f5"
}

// resolveColors(cfg, omarchy) -> { background, text, accent } (all "#rrggbb")
function resolveColors(cfg, omarchy) {
  if (cfg && cfg.colorMode === "custom") {
    var bg = isHex(cfg.customBackground) ? cfg.customBackground : MONO.background
    var tx = isHex(cfg.customText) ? cfg.customText : MONO.text
    var ac = isHex(cfg.customAccent) ? cfg.customAccent : MONO.accent
    return { background: bg, text: readableOn(tx, bg, 4.5), accent: readableOn(ac, bg, 3) }
  }
  if (cfg && cfg.colorMode === "theme" && omarchy
      && isHex(omarchy.background) && isHex(omarchy.text))
    return {
      background: omarchy.background,
      text: omarchy.text,
      accent: isHex(omarchy.accent) ? omarchy.accent : omarchy.text
    }
  return { background: MONO.background, text: MONO.text, accent: MONO.accent }
}

// ---------------------------------------------------------------------------
// Omarchy theme reader
// Reads the @@NAME / @@FILE / @@THEME text dumped by BarWidget.qml's script.
// colors.toml, alacritty.toml and kitty.conf are understood.
// ---------------------------------------------------------------------------

function str(v, max) {
  var s = String(v === undefined || v === null ? "" : v).replace(/\s+/g, " ").trim()
  return s.length > (max || 200) ? s.slice(0, (max || 200) - 1) + "…" : s
}

function _hex(v) {
  var m = /^(?:#|0x)?([0-9a-fA-F]{6})(?:[0-9a-fA-F]{2})?$/.exec(String(v).trim())
  return m ? "#" + m[1].toLowerCase() : ""
}

function parseOmarchyTheme(text) {
  var files = {}, cur = null, curName = "", sec = "", name = ""
  var lines = String(text === undefined || text === null ? "" : text).split(/\r?\n/)
  for (var i = 0; i < lines.length; i++) {
    var ln = lines[i], m
    if ((m = /^@@NAME\s*(.*)$/.exec(ln))) { name = m[1].trim(); continue }
    if ((m = /^@@FILE\s+(\S+)\s*$/.exec(ln))) { curName = m[1]; cur = files[curName] = {}; sec = ""; continue }
    if (!cur) continue
    var h
    if (curName === "colors.toml") {
      m = /^\s*([A-Za-z0-9_]+)\s*=\s*["']?((?:#|0x)?[0-9a-fA-F]{6})["']?/.exec(ln)
      if (m && !(m[1] in cur)) cur[m[1]] = _hex(m[2])
    } else if (curName === "alacritty.toml") {
      if ((m = /^\s*\[([^\]]+)\]/.exec(ln))) { sec = m[1].trim(); continue }
      m = /^\s*([A-Za-z0-9_]+)\s*=\s*["']([^"']+)["']/.exec(ln)
      if (m && (h = _hex(m[2])) && !((sec + "." + m[1]) in cur)) cur[sec + "." + m[1]] = h
    } else if (curName === "kitty.conf") {
      m = /^\s*(foreground|background|cursor|color4)\s+((?:#|0x)?[0-9a-fA-F]{6})\s*$/.exec(ln)
      if (m && !(m[1] in cur)) cur[m[1]] = _hex(m[2])
    }
  }
  var c = files["colors.toml"] || {},
      a = files["alacritty.toml"] || {},
      k = files["kitty.conf"] || {}
  var bg = c.background || a["colors.primary.background"] || k.background || ""
  var fg = c.foreground || a["colors.primary.foreground"] || k.foreground || ""
  if (!bg || !fg) return null
  var accent = c.accent || c.primary || c.color4 || c.color5 || c.color2
             || a["colors.normal.blue"] || a["colors.cursor.cursor"]
             || k.color4 || k.cursor || fg
  var src = ""
  var order = ["colors.toml", "alacritty.toml", "kitty.conf"]
  for (var j = 0; j < order.length && !src; j++)
    if (files[order[j]] && Object.keys(files[order[j]]).length) src = order[j]
  return { text: fg, background: bg, accent: accent, name: name, source: src }
}

function parseOmarchyThemes(text) {
  var out = [], chunks = String(text === undefined || text === null ? "" : text).split(/^@@THEME\s+/m)
  for (var i = 1; i < chunks.length; i++) {
    var nl = chunks[i].indexOf("\n")
    var nm = (nl < 0 ? chunks[i] : chunks[i].slice(0, nl)).trim()
    var t = parseOmarchyTheme("@@NAME " + nm + "\n" + (nl < 0 ? "" : chunks[i].slice(nl + 1)))
    if (t) out.push(t)
  }
  return out
}

function _dist(a, b) {
  var x = parseInt(a.slice(1), 16), y = parseInt(b.slice(1), 16), s = 0
  for (var sh = 0; sh < 24; sh += 8) { var d = ((x >> sh) & 255) - ((y >> sh) & 255); s += d * d }
  return Math.sqrt(s) / 441.67
}

function closestTheme(list, bgHex) {
  var best = null
  for (var i = 0; i < list.length; i++) {
    var d = _dist(list[i].background, bgHex)
    if (!best || d < best.dist) best = { theme: list[i], dist: d }
  }
  return best
}

function themeSlug(s) {
  return String(s === undefined || s === null ? "" : s).trim().toLowerCase().replace(/[\s_]+/g, "-")
}

// ---------------------------------------------------------------------------
// Misc helpers
// ---------------------------------------------------------------------------

function clean(value, max) {
  var s = String(value === undefined || value === null ? "" : value)
  s = s.replace(/[\u0000-\u001f\u007f-\u009f\u200e\u200f\u202a-\u202e\u2066-\u2069]/g, "")
  return s.length > max ? s.slice(0, max) : s
}

function validColor(value) {
  return typeof value === "string" && HEX_COLOR.test(value) ? value.toLowerCase() : DEFAULT_COLOR
}

function shade(hex, t) {
  var n = parseInt(hex.slice(1), 16)
  var r = Math.round(((n >> 16) & 255) * (1 - t))
  var g = Math.round(((n >> 8) & 255) * (1 - t))
  var b = Math.round((n & 255) * (1 - t))
  return "#" + ((1 << 24) | (r << 16) | (g << 8) | b).toString(16).slice(1)
}

function iconKey(issuer) {
  return clean(issuer, 64).toLowerCase().replace(/[^a-z0-9]/g, "")
}

function issuerGlyph(issuer) {
  return ISSUER_GLYPHS[iconKey(issuer)] || ""
}

function tileLetter(issuer, account) {
  var s = clean(issuer, 64) || clean(account, 128) || "?"
  return s.charAt(0).toUpperCase()
}

function errorText(code) {
  return ERRORS[code] || ERRORS["request-failed"]
}

function formatCode(code) {
  var h = code.length / 2
  return code.slice(0, h) + " " + code.slice(h)
}

function remaining(period, nowMs) {
  var p = period > 0 ? period : 30
  return p - (Math.floor(nowMs / 1000) % p)
}

function parseEntries(text) {
  var raw
  try { raw = JSON.parse(text) } catch (e) { return { error: "bad-response" } }
  if (!raw || typeof raw !== "object") return { error: "bad-response" }
  if (raw.error !== undefined) return { error: ERRORS[raw.error] ? raw.error : "request-failed" }
  if (!Array.isArray(raw.entries)) return { error: "bad-response" }
  var out = []
  for (var i = 0; i < raw.entries.length && out.length < MAX_ENTRIES; i++) {
    var e = raw.entries[i]
    if (!e || typeof e !== "object") continue
    if (typeof e.id !== "string" || !ID_RE.test(e.id)) continue
    if (typeof e.code !== "string" || !CODE_RE.test(e.code)) continue
    var period = typeof e.period === "number" && e.period >= 15 && e.period <= 120 ? Math.floor(e.period) : 30
    out.push({
      id: e.id,
      issuer: clean(e.issuer, 64),
      account: clean(e.account, 128),
      code: e.code,
      period: period
    })
  }
  return { entries: out }
}

function minPeriod(entries) {
  var p = 30
  for (var i = 0; i < entries.length; i++)
    if (entries[i].period < p) p = entries[i].period
  return p
}

function buildUri(issuer, account, secret) {
  var label = issuer ? encodeURIComponent(issuer) + ":" + encodeURIComponent(account) : encodeURIComponent(account)
  var s = String(secret).replace(/[\s-]/g, "").toUpperCase()
  var uri = "otpauth://totp/" + label + "?secret=" + s
  if (issuer) uri += "&issuer=" + encodeURIComponent(issuer)
  return uri
}

function parseColorFile(text) {
  var t = String(text || "").trim()
  if (t === "mono") return { mode: "mono", hex: DEFAULT_COLOR }
  if (HEX_COLOR.test(t)) return { mode: "custom", hex: t.toLowerCase() }
  return { mode: "theme", hex: DEFAULT_COLOR }
}

function isOtpUri(text) {
  return typeof text === "string" && /^otpauth:\/\/totp\//i.test(text.trim())
}
