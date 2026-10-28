# Contributing

Omaotp is small: one list of settings, one file of pure logic, one vault helper, and
the QML that shows them. Most changes touch one or two files.

```
qml/BarWidget.qml         the bar button, the vault's state and the helper's job queue,
                          copying, docking and popping out, and what the window asks of it
qml/core/UiState.qml      colors, spacing and the open tab, shared by both windows (`ui.*`)
qml/panel/OtpView.qml     the window: header, tabs, Accounts, Settings, footer
qml/panel/AccountsPage.qml creating and unlocking the vault, the codes, adding an account
qml/panel/SettingRow.qml  one setting, drawn from its Schema.js entry
qml/js/Schema.js          every setting, in the tabs and order the Settings tab shows
qml/js/Otp.js             pure logic: checking what the helper prints, links, icons
bin/omaotp.py             the vault and the codes
```

## A new setting

1. Add it to a group in `qml/js/Schema.js`: a `key` that never changes once released, a
   `kind` (`bool`, `int`, `enum`, `string`, `color` or `palette`), a `label`, a `fallback`
   and a one-sentence `hint`. An `int` takes `min`, `max` and `step`; an `enum` takes
   `options` and `labels`, and `control: "tiles"` to draw it as tiles (add its picture
   to `qml/panel/TileArt.qml`). `section` puts it under a heading, `when` dims it
   unless another setting has one of the given values.
2. Read it as `cfg.<key>` in `qml/BarWidget.qml` or `ui.cfgSafe.<key>` in the window. The
   value is already clean (`Schema.resolve`).
3. Write the manifest again: `node tools/gen-manifest.js`.

## An issuer icon

Add the issuer's name (lower case, letters and digits only) and its Nerd Font code point
to `ISSUER_GLYPHS` in `qml/js/Otp.js`. Check that the code point is in the Nerd Font;
the tests don't.

## Rules

- `qml/js/Otp.js` and `qml/js/Schema.js` stay pure: no Qt, so the tests run in node.
- The master password and the secrets never go on a command line, into a log, or into
  the settings. They go to `bin/omaotp.py` on stdin; it hands the password to `openssl`
  through a pipe.
- The vault is only written by `bin/omaotp.py`, to a new file that is then moved over
  the old one, in a folder that is yours alone. A vault that fails its HMAC is never
  decrypted.
- Anything the helper prints goes through `Otp.parseEntries()` before it is shown.
- Text goes through `controls/Txt.qml`, which is plain text only. A text field is
  `controls/InputBox.qml` (on `PasteInput.qml`), never a `TextInput`, so the clipboard is
  only read on Ctrl+V, capped. Password and secret fields set `masked: true`.
- Locking forgets the password, the codes and everything typed into the window.
- Helper commands are argument arrays. A shell script only gets its values as
  arguments or on stdin, never pasted into the script.
- ES6 JavaScript: `const` and `let`, and arrow functions for callbacks.

## Tests

```bash
node tests/test_model.js
```

They need node, python3 and openssl: the parsing, the links, the settings and their
1.1 names, the border colors, the vault (its folder and file modes, a wrong password, a
changed file, a 1.1 vault brought to the new form), plain text everywhere, and that
`manifest.json` matches `Schema.js`. The vault tests run in a throwaway home folder.

Everyone taking part is expected to follow the [code of conduct](CODE_OF_CONDUCT.md).
