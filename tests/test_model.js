// node tests/test_model.js
// The pure logic (Otp.js, Schema.js, Theme.js), the vault helper (bin/omaotp.py, in a
// throwaway home) and the manifest, without Qt. Needs node, python3 and openssl.
const fs = require("fs"), path = require("path"), os = require("os"), assert = require("assert"), cp = require("child_process");
const root = path.join(__dirname, "..");
const load = (file, names) => new Function(fs.readFileSync(path.join(root, "qml", "js", file), "utf8")
    .replace(/^\.pragma.*$/m, "") + "; return { " + names.join(", ") + " };")();

const M = load("Otp.js", ["ERRORS", "parseEntries", "buildUri", "isOtpUri", "formatCode", "remaining", "minPeriod",
    "errorText", "issuerGlyph", "tileLetter", "parseColorFile", "MIN_PASSWORD"]);
const S = load("Schema.js", ["settingKeys", "defaults", "resolve"]);
const T = load("Theme.js", ["parseBorder"]);

let n = 0;
const t = (name, fn) => { fn(); n++; console.log("  ok   " + name); };

t("what the helper prints is checked before it is shown", () => {
    const ok = M.parseEntries(JSON.stringify({ entries: [
        { id: "0123456789ab", issuer: "X‮", account: "a", code: "123456", period: 30 },
        { id: "bad", code: "123456" }, { id: "0123456789ac", code: "12a456" }, 5] }));
    assert.deepStrictEqual(ok.entries, [{ id: "0123456789ab", issuer: "X", account: "a", code: "123456", period: 30 }]);
    assert.strictEqual(M.parseEntries("not json").error, "bad-response");
    assert.strictEqual(M.parseEntries('{"error":"<b>"}').error, "request-failed");
    assert.strictEqual(M.parseEntries('{"error":"bad-password"}').error, "bad-password");
    assert.strictEqual(M.parseEntries('{"error":"tampered"}').error, "tampered");
    assert.strictEqual(M.errorText("nope"), M.ERRORS["request-failed"]);
});

t("links from the three fields carry only base32 in the secret", () => {
    assert.strictEqual(M.buildUri("GitHub", "me", "abcd efgh"), "otpauth://totp/GitHub:me?secret=ABCDEFGH&issuer=GitHub");
    assert.ok(!M.buildUri("A", "b", "ABC&issuer=Evil").includes("Evil"));
    assert.ok(M.isOtpUri(" otpauth://totp/x?secret=A ") && !M.isOtpUri("https://x"));
});

t("codes, rings and icons", () => {
    assert.strictEqual(M.formatCode("123456"), "123 456");
    assert.strictEqual(M.formatCode("12345678"), "1234 5678");
    assert.strictEqual(M.formatCode("123456", false), "123456");
    assert.strictEqual(M.remaining(30, 31000), 29);
    assert.strictEqual(M.minPeriod([{ period: 60 }, { period: 30 }]), 30);
    assert.ok(M.issuerGlyph("Git Hub") !== "" && M.issuerGlyph("Nowhere") === "");
    assert.strictEqual(M.tileLetter("", "andrei"), "A");
});

t("settings are clamped, and 1.1's colors still apply", () => {
    const c = S.resolve({ autoLockMinutes: 999, colorMode: "neon", clipboardSeconds: "20", hideCodes: "true" }, {});
    assert.deepStrictEqual([c.autoLockMinutes, c.colorMode, c.clipboardSeconds, c.hideCodes], [60, "theme", 20, true]);
    assert.deepStrictEqual(S.resolve({}, {}), S.defaults);
    const old = S.resolve({ colorMode: "mono", customBackground: "#f8f8f2", customAccent: "#58a6ff" }, {});
    assert.deepStrictEqual([old.colorMode, old.customBg, old.accentColor, old.customFg], ["monochrome", "#f8f8f2", "#58a6ff", "#141414"]);
    assert.strictEqual(S.resolve({ customColor: "#bc8cff" }, {}).accentColor, "#bc8cff");
    assert.deepStrictEqual(M.parseColorFile("mono\n"), { mode: "monochrome", hex: "#39d353" });
    assert.deepStrictEqual(M.parseColorFile("#58A6FF"), { mode: "custom", hex: "#58a6ff" });
});

t("the window border is read from the theme's files", () => {
    assert.deepStrictEqual(T.parseBorder('local active_border_color = { colors = { "rgba(1ee9d6ee)", "rgba(fe4fb6ee)" }, angle = 45 }'),
        { colors: ["#1ee9d6", "#fe4fb6"], angle: 45 });
});

t("the vault: private, authenticated, and refusing a wrong password or a changed file", () => {
    const home = fs.mkdtempSync(path.join(os.tmpdir(), "omaotp-"));
    const env = Object.assign({}, process.env, { HOME: home, XDG_DATA_HOME: "" });
    delete env.XDG_DATA_HOME;
    const run = (cmd, input, script) => JSON.parse(cp.execFileSync("python3",
        [script || path.join(root, "bin", "omaotp.py"), cmd], { input, env, encoding: "utf8" }).trim());
    const pw = "correct horse battery\n";
    assert.deepStrictEqual(run("status", ""), { exists: false });
    assert.deepStrictEqual(run("init", pw), { ok: true });
    assert.strictEqual(run("init", pw).error, "exists");
    assert.ok(run("add", pw + "otpauth://totp/GitHub:me?secret=JBSWY3DPEHPK3PXP&issuer=GitHub\n").ok);
    assert.strictEqual(run("add", pw + "otpauth://hotp/x?secret=JBSWY3DPEHPK3PXP\n").error, "bad-uri");
    assert.strictEqual(run("add", pw + "otpauth://totp/x?secret=JBSWY3DPEHPK3PXP&digits=7\n").error, "bad-uri");
    const codes = run("codes", pw);
    assert.strictEqual(codes.entries.length, 1);
    assert.ok(/^\d{6}$/.test(codes.entries[0].code));
    assert.strictEqual(run("codes", "wrong password\n").error, "bad-password");

    const dir = path.join(home, ".local", "share", "omaotp"), vault = path.join(dir, "vault.enc");
    assert.strictEqual(fs.statSync(dir).mode & 0o777, 0o700);
    assert.strictEqual(fs.statSync(vault).mode & 0o777, 0o600);
    assert.ok(fs.readFileSync(vault).subarray(0, 8).equals(Buffer.from("OMAOTP2\n")));
    const blob = fs.readFileSync(vault);
    blob[blob.length - 1] ^= 1;
    fs.writeFileSync(vault, blob);
    assert.strictEqual(run("codes", pw).error, "bad-password", "a changed vault is refused");
    fs.rmSync(home, { recursive: true, force: true });
});

t("a newer vault with its HMAC stripped off is refused, and not rewritten", () => {
    const home = fs.mkdtempSync(path.join(os.tmpdir(), "omaotp-"));
    const env = Object.assign({}, process.env, { HOME: home });
    delete env.XDG_DATA_HOME;
    const run = (cmd, input) => JSON.parse(cp.execFileSync("python3", [path.join(root, "bin", "omaotp.py"), cmd],
        { input, env, encoding: "utf8" }).trim());
    const pw = "correct horse battery\n";
    assert.ok(run("init", pw).ok);
    assert.ok(run("add", pw + "otpauth://totp/GitHub:me?secret=JBSWY3DPEHPK3PXP&issuer=GitHub\n").ok);
    const vault = path.join(home, ".local", "share", "omaotp", "vault.enc");
    // remove the whole wrapper (magic, salt and HMAC): only openssl's own bytes remain
    const stripped = fs.readFileSync(vault).subarray(8 + 16 + 32);
    assert.ok(stripped.subarray(0, 8).equals(Buffer.from("Salted__")));
    fs.writeFileSync(vault, stripped);
    for (const cmd of ["codes", "add", "remove", "reorder"]) {
        const extra = cmd === "add" ? "otpauth://totp/X:y?secret=JBSWY3DPEHPK3PXP\n" : (cmd === "remove" ? "0123456789ab\n" : "\n");
        assert.strictEqual(run(cmd, pw + extra).error, "tampered", cmd);
        assert.ok(fs.readFileSync(vault).equals(stripped), cmd + " left the file as it was");
    }
    assert.strictEqual(run("codes", "wrong password\n").error, "bad-password");
    fs.rmSync(home, { recursive: true, force: true });
});

t("a vault from 1.1 is read and rewritten in the new form", () => {
    const home = fs.mkdtempSync(path.join(os.tmpdir(), "omaotp-"));
    const env = Object.assign({}, process.env, { HOME: home });
    delete env.XDG_DATA_HOME;
    const dir = path.join(home, ".local", "share", "omaotp");
    fs.mkdirSync(dir, { recursive: true, mode: 0o755 });
    const plain = JSON.stringify({ version: 1, entries: [{ id: "0123456789ab", issuer: "X", account: "me",
        secret: "JBSWY3DPEHPK3PXP", digits: 6, period: 30, algorithm: "SHA1" }] });
    // the 1.1 form: openssl's own output, nothing around it
    const r = cp.spawnSync("sh", ["-c", 'exec 3<<EOF\npass word 1\nEOF\nopenssl enc -aes-256-cbc -pbkdf2 -iter 300000 -md sha256 -pass fd:3 -out "$1"', "sh",
        path.join(dir, "vault.enc")], { input: plain });
    assert.strictEqual(r.status, 0, String(r.stderr));
    const out = JSON.parse(cp.execFileSync("python3", [path.join(root, "bin", "omaotp.py"), "codes"],
        { input: "pass word 1\n", env, encoding: "utf8" }));
    assert.strictEqual(out.entries.length, 1);
    assert.ok(fs.readFileSync(path.join(dir, "vault.enc")).subarray(0, 8).equals(Buffer.from("OMAOTP2\n")));
    assert.strictEqual(fs.statSync(dir).mode & 0o777, 0o700);
    fs.rmSync(home, { recursive: true, force: true });
});

t("text is drawn plain, and no native text field reads the clipboard", () => {
    const walk = (d) => fs.readdirSync(d, { withFileTypes: true }).flatMap((e) =>
        e.isDirectory() ? walk(path.join(d, e.name)) : [path.join(d, e.name)]);
    for (const f of walk(path.join(root, "qml")).filter((f) => f.endsWith(".qml"))) {
        const src = fs.readFileSync(f, "utf8");
        assert.ok(!/\b(TextInput|TextField|TextArea|TextEdit)\s*\{/.test(src), f + " creates a native text field");
        assert.ok(!src.includes("import QtQuick.Controls"), f + " imports QtQuick.Controls");
        assert.ok(!/Text\.(RichText|StyledText|AutoText)/.test(src), f + " allows markup");
    }
    // the master password never goes on a command line
    const bar = fs.readFileSync(path.join(root, "qml", "BarWidget.qml"), "utf8");
    assert.ok(!/command\s*=.*password/.test(bar) && !/concat\([^)]*password/.test(bar));
});

t("manifest matches Schema.js", () => {
    const m = JSON.parse(fs.readFileSync(path.join(root, "manifest.json"), "utf8"));
    assert.strictEqual(m.id, "io.github.qempexe.omaotp");
    assert.strictEqual(m.version, "1.2.2");
    assert.ok(fs.readFileSync(path.join(root, "CHANGELOG.md"), "utf8").includes("## [" + m.version + "] - "), "the version has a changelog entry");
    assert.deepStrictEqual(m.barWidget.schema.map((e) => e.key), S.settingKeys);
    assert.deepStrictEqual(m.barWidget.defaults, S.defaults);
    assert.ok(fs.existsSync(path.join(root, m.entryPoints.barWidget)));
});

console.log("\nALL OK (" + n + ")");
