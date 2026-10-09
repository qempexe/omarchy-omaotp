#!/usr/bin/env bash
f="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/current/theme/colors.toml"
[ -r "$f" ] || exit 0
grep -m1 -E '^[[:space:]]*accent[[:space:]]*=' "$f" | grep -oE '#[0-9a-fA-F]{6}' | head -n1
