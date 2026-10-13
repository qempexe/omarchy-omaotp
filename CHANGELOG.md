## 1.1.0

- Panel rebuilt with a header card with lock and close, Accounts and Settings tabs, footer with status
- New Settings tab: accent colour (Theme, Custom, Mono, with swatches and a hex field), lock timeout and clipboard timeout
- Settings are saved to `~/.config/omaotp/settings.json` through a shared store that watches the file, so hand edits apply live
- A password field now shows bullets, and passwords and secrets are cleared when the panel closes
- The old `~/.config/omaotp/color` file is migrated once, then left in place
- Lock and clipboard timers follow the chosen settings
- Theme mode takes the whole Omarchy theme (background, text and accent) and updates when you switch themes

## 1.0.1

- Earlier release

## 1.0.0

- First release