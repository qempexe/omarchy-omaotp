#!/usr/bin/env python3

import base64
import hashlib
import hmac
import json
import os
import re
import struct
import subprocess
import sys
import time
from urllib.parse import parse_qsl, unquote, urlparse

DATA_DIR = os.path.join(
    os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"), "omaotp")
VAULT = os.path.join(DATA_DIR, "vault.enc")
PBKDF2_ITER = "300000"
ALGOS = {"SHA1": hashlib.sha1, "SHA256": hashlib.sha256, "SHA512": hashlib.sha512}
MAX_ENTRIES = 200
ID_RE = re.compile(r"^[0-9a-f]{12}$")

def out(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()
    sys.exit(0)

def fail(code):
    out({"error": code})

def clean(value, limit):
    return "".join(ch for ch in str(value) if ch.isprintable()).strip()[:limit]

def norm_secret(secret):
    return secret.replace(" ", "").replace("-", "").upper().rstrip("=")

def b32key(secret):
    s = norm_secret(secret)
    if not s:
        raise ValueError("empty secret")
    return base64.b32decode(s + "=" * (-len(s) % 8))

def totp(secret, digits, period, algo, now):
    mac = hmac.new(b32key(secret), struct.pack(">Q", int(now // period)), ALGOS[algo]).digest()
    offset = mac[-1] & 0x0F
    number = (struct.unpack(">I", mac[offset:offset + 4])[0] & 0x7FFFFFFF) % (10 ** digits)
    return str(number).zfill(digits)

def entry_id(issuer, account, secret):
    raw = "%s|%s|%s" % (issuer, account, norm_secret(secret))
    return hashlib.sha256(raw.encode()).hexdigest()[:12]

def parse_uri(uri):
    if not isinstance(uri, str) or len(uri) > 2048:
        fail("bad-uri")
    u = urlparse(uri.strip())
    if u.scheme != "otpauth" or u.netloc != "totp":
        fail("bad-uri")
    q = dict(parse_qsl(u.query))
    label = unquote(u.path.lstrip("/"))
    if ":" in label:
        label_issuer, account = label.split(":", 1)
    else:
        label_issuer, account = "", label
    issuer = clean(q.get("issuer", label_issuer), 64)
    account = clean(account, 128)
    secret = norm_secret(q.get("secret", ""))
    algo = q.get("algorithm", "SHA1").upper()
    try:
        digits = int(q.get("digits", "6"))
        period = int(q.get("period", "30"))
        b32key(secret)
    except (ValueError, TypeError):
        fail("bad-uri")
    if not secret or not account or algo not in ALGOS or digits not in (6, 8) or not (15 <= period <= 120):
        fail("bad-uri")
    return {"id": entry_id(issuer, account, secret), "issuer": issuer, "account": account,
            "secret": secret, "digits": digits, "period": period, "algorithm": algo}

def run_openssl(args, password, data):
    r, w = os.pipe()
    try:
        os.write(w, (password + "\n").encode())
    finally:
        os.close(w)
    try:
        return subprocess.run(
            ["openssl", "enc", "-aes-256-cbc", "-pbkdf2", "-iter", PBKDF2_ITER, "-md", "sha256",
             "-pass", "fd:%d" % r] + args,
            input=data, capture_output=True, pass_fds=(r,))
    except FileNotFoundError:
        fail("no-openssl")
    finally:
        os.close(r)

def load(password):
    if not os.path.exists(VAULT):
        fail("no-vault")
    with open(VAULT, "rb") as f:
        blob = f.read()
    p = run_openssl(["-d"], password, blob)
    if p.returncode != 0:
        fail("bad-password")
    try:
        entries = json.loads(p.stdout.decode())["entries"]
        if not isinstance(entries, list):
            raise ValueError
    except (ValueError, KeyError, UnicodeDecodeError):
        fail("bad-response")
    return entries

def save(password, entries):
    os.makedirs(DATA_DIR, mode=0o700, exist_ok=True)
    plain = json.dumps({"version": 1, "entries": entries}).encode()
    p = run_openssl([], password, plain)
    if p.returncode != 0:
        fail("request-failed")
    tmp = VAULT + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "wb") as f:
        f.write(p.stdout)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, VAULT)

def read_lines(n):
    return [sys.stdin.readline().rstrip("\r\n") for _ in range(n)]

def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""

    if cmd == "status":
        out({"exists": os.path.exists(VAULT)})

    if cmd == "init":
        (pw,) = read_lines(1)
        if not pw:
            fail("bad-password")
        if os.path.exists(VAULT):
            fail("exists")
        save(pw, [])
        out({"ok": True})

    if cmd == "codes":
        (pw,) = read_lines(1)
        if not pw:
            fail("bad-password")
        now = time.time()
        result = []
        for e in load(pw)[:MAX_ENTRIES]:
            try:
                result.append({
                    "id": e["id"],
                    "issuer": clean(e.get("issuer", ""), 64),
                    "account": clean(e.get("account", ""), 128),
                    "code": totp(e["secret"], e["digits"], e["period"], e["algorithm"], now),
                    "period": e["period"],
                })
            except (KeyError, TypeError, ValueError):
                continue  # skip a damaged entry instead of failing the whole list
        out({"entries": result})

    if cmd == "add":
        pw, uri = read_lines(2)
        if not pw:
            fail("bad-password")
        entries = load(pw)
        new = parse_uri(uri)
        if len(entries) >= MAX_ENTRIES:
            fail("too-many")
        if any(e.get("id") == new["id"] for e in entries):
            fail("duplicate")
        entries.append(new)
        save(pw, entries)
        out({"ok": True, "id": new["id"]})

    if cmd == "remove":
        pw, eid = read_lines(2)
        if not pw:
            fail("bad-password")
        if not ID_RE.match(eid):
            fail("not-found")
        entries = load(pw)
        kept = [e for e in entries if e.get("id") != eid]
        if len(kept) == len(entries):
            fail("not-found")
        save(pw, kept)
        out({"ok": True})

    if cmd == "reorder":
        pw, line = read_lines(2)
        if not pw:
            fail("bad-password")
        wanted = [x for x in line.split(",") if ID_RE.match(x)]
        entries = load(pw)
        by_id = {e.get("id"): e for e in entries}
        ordered = [by_id[i] for i in wanted if i in by_id]
        seen = {e.get("id") for e in ordered}
        ordered += [e for e in entries if e.get("id") not in seen]
        save(pw, ordered)
        out({"ok": True})

    fail("unknown-command")

if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception:
        fail("request-failed")
