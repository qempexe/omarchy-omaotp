.pragma library

// Pure logic for Omaotp: the error messages, issuer icons, and checking what the
// helper prints before it reaches the window. No Qt here, so it can be tested with node.

const ERRORS = {
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
  "short": "Use at least 8 characters.",
  "mismatch": "The two passwords are not the same.",
  "tampered": "The vault file was changed outside Omaotp, so it is not opened. Restore it from a backup."
}

// Nerd Font icons of well-known services, by issuer name (letters and digits only)
const ISSUER_GLYPHS = {
  github: "\uf09b", gitlab: "\uf296", gitea: "\uf339", codeberg: "\uf330", google: "\uf1a0",
  microsoft: "\ued04", apple: "\uf179", discord: "\uf1ff", reddit: "\uf281", dropbox: "\uf16b",
  amazon: "\uf270", twitter: "\uf099", facebook: "\uf09a", instagram: "\uf16d", linkedin: "\uf0e1",
  slack: "\uf198", steam: "\uf1b6", twitch: "\uf1e8", youtube: "\uf16a", paypal: "\uf1ed",
  mastodon: "\uedc0", npm: "\ued0e", docker: "\uf21f", atlassian: "\uef32", trello: "\uf181",
  figma: "\uef47", spotify: "\uf1bc", firefox: "\uf269", mozilla: "\uf269", stripe: "\ued53",
  patreon: "\ued13", playstation: "\ued18", xbox: "\ued3e", nintendo: "\ue22a", itchio: "\uef99"
}
const LOCK_GLYPH = "\uf023"

const DEFAULT_COLOR = "#39d353"
const HEX_COLOR = /^#[0-9a-fA-F]{6}$/
const ID_RE = /^[0-9a-f]{12}$/
const CODE_RE = /^\d{6,8}$/
const MAX_ENTRIES = 200
const MIN_PASSWORD = 8
const KEY_GLYPH = "\uf084"

function clean(value, max) {
  let s = String(value === undefined || value === null ? "" : value)
  s = s.replace(/[\u0000-\u001f\u007f-\u009f\u200e\u200f\u202a-\u202e\u2066-\u2069]/g, "")
  return s.length > max ? s.slice(0, max) : s
}

function iconKey(issuer) {
  return clean(issuer, 64).toLowerCase().replace(/[^a-z0-9]/g, "")
}

function issuerGlyph(issuer) {
  return ISSUER_GLYPHS[iconKey(issuer)] || ""
}

function tileLetter(issuer, account) {
  const s = clean(issuer, 64) || clean(account, 128) || "?"
  return s.charAt(0).toUpperCase()
}

function errorText(code) {
  return ERRORS[code] || ERRORS["request-failed"]
}

// "123 456" (or "1234 5678"), or the code as it is when `group` is false
function formatCode(code, group) {
  if (group === false) return code
  const h = code.length / 2
  return code.slice(0, h) + " " + code.slice(h)
}

function remaining(period, nowMs) {
  const p = period > 0 ? period : 30
  return p - (Math.floor(nowMs / 1000) % p)
}

function parseEntries(text) {
  let raw
  try { raw = JSON.parse(text) } catch (e) { return { error: "bad-response" } }
  if (!raw || typeof raw !== "object") return { error: "bad-response" }
  if (raw.error !== undefined) return { error: ERRORS[raw.error] ? raw.error : "request-failed" }
  if (!Array.isArray(raw.entries)) return { error: "bad-response" }
  const out = []
  for (let i = 0; i < raw.entries.length && out.length < MAX_ENTRIES; i++) {
    const e = raw.entries[i]
    if (!e || typeof e !== "object") continue
    if (typeof e.id !== "string" || !ID_RE.test(e.id)) continue
    if (typeof e.code !== "string" || !CODE_RE.test(e.code)) continue
    const period = typeof e.period === "number" && e.period >= 15 && e.period <= 120 ? Math.floor(e.period) : 30
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
  let p = 30
  for (let i = 0; i < entries.length; i++)
    if (entries[i].period < p) p = entries[i].period
  return p
}

// A link from the three fields. The secret keeps only base32 letters, so nothing
// typed there can add fields of its own to the link.
function buildUri(issuer, account, secret) {
  const label = issuer ? encodeURIComponent(issuer) + ":" + encodeURIComponent(account) : encodeURIComponent(account)
  const s = String(secret).toUpperCase().replace(/[^A-Z2-7]/g, "")
  let uri = "otpauth://totp/" + label + "?secret=" + s
  if (issuer) uri += "&issuer=" + encodeURIComponent(issuer)
  return uri
}

// The color file of 1.0 (~/.config/omaotp/color): "mono", a hex, or anything else
function parseColorFile(text) {
  const t = String(text || "").trim()
  if (t === "mono") return { mode: "monochrome", hex: DEFAULT_COLOR }
  if (HEX_COLOR.test(t)) return { mode: "custom", hex: t.toLowerCase() }
  return { mode: "theme", hex: DEFAULT_COLOR }
}

function isOtpUri(text) {
  return typeof text === "string" && /^otpauth:\/\/totp\//i.test(text.trim())
}
