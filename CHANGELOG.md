# Changelog

All notable changes to Omaotp. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [1.2.0] - 2026-10-28

### Added

- **Pop out**: Omaotp can leave the bar and become a window you can move, resize and
  tile, and **Dock** puts it back. **Open as** picks which one the bar button opens.
- Many new settings, in tabs with a search box: color schemes (Follow theme, Window
  borders, Custom, Monochrome) and the text color; card style, spacing, roundness and
  text size; issuer icons and split codes; window size, outline, tint and opacity;
  locking when the window closes, and hiding codes until hovered; what the bar button
  shows (the ring, the ring and the code, or only the lock) and what a middle click
  does. Each has its own reset, and **Reset all** puts everything back.
- Creating a vault asks for the master password twice.
- More issuer icons: Gitea, Codeberg, Instagram, Mastodon, npm, Docker, Atlassian, Trello,
  Figma, Spotify, Firefox, Stripe, Patreon, PlayStation, Xbox, Nintendo and itch.io.
- A logo, and an **About** tab with the version and a link to more plugins.
- Tests for the parsing, the settings, the border colors, the vault helper and the
  manifest: `node tests/test_model.js`.
- A contributing guide and a code of conduct.

### Changed

- A new window: header card, underlined Accounts and Settings tabs, one content card,
  and a footer with the shortcuts. **Alt+←/→** switches tabs.
- The colors follow the bar and the theme straight from the shell, instead of reading
  Omarchy's theme files with a script. The logo turns dark on a light window.
- The files live in `qml/` folders: `core/`, `panel/`, `controls/` and `js/`.
- The JavaScript is written in ES6: `const` and `let`, and arrow functions.
- The README follows a new layout, with screenshots and a new preview.
- Settings saved by 1.1 keep working under their new names.

### Fixed

- The Discord and Microsoft icons were missing from the Nerd Font; the right ones are used.
- An account with no known icon showed a broken picture on the bar; it shows a key.

### Security

- The vault is now authenticated: an HMAC-SHA256 of the encrypted bytes, with its own
  key from the master password, is checked before anything is decrypted, so a changed
  or swapped vault is refused. A 1.1 vault is read as it is and rewritten in the new
  form the first time it is opened.
- The vault's folder is made private (0700) on every save, and Omaotp refuses to use
  it, or the vault, through a link.
- A secret typed in the Secret field keeps only base32 letters, so it can't add fields
  of its own to the link it is saved from.
- The job queue forgets the master password as soon as it has been handed to the helper.

## [1.1.0] - 2026-10-13

### Added

- A Settings tab: accent color (Theme, Custom, Mono, with swatches and a hex field),
  lock timeout and clipboard timeout.
- A header card with lock and close, Accounts and Settings tabs, and a footer with the
  status.

### Changed

- Settings are saved to `~/.config/omaotp/settings.json`, and hand edits apply live.
  The old `~/.config/omaotp/color` file is moved over once.
- Theme mode takes the whole Omarchy theme (background, text and accent) and follows it
  when you switch themes.

### Fixed

- The password field shows dots, and passwords and secrets are cleared when the panel
  closes.

## [1.0.1] - 2026-10-09

### Security

- Copied codes are no longer passed as process arguments.

## [1.0.0] - 2026-10-09

### Added

- First release: a TOTP authenticator for the Omarchy bar, with an encrypted vault
  behind a master password, countdown rings, drag to reorder, and theme, custom and
  mono colors.

[1.2.0]: https://github.com/qempexe/omarchy-omaotp/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/qempexe/omarchy-omaotp/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/qempexe/omarchy-omaotp/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/qempexe/omarchy-omaotp/releases/tag/v1.0.0
