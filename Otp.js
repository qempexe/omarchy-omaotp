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
  "request-failed": "Something went wrong. Try again."
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
