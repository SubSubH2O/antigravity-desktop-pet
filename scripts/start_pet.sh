#!/bin/bash
# start_pet.sh: Auto-compile and ensure DesktopPetCat daemon is running
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$PLUGIN_DIR/bin/DesktopPetCat"
SRC="$PLUGIN_DIR/main.swift"

mkdir -p "$HOME/.desktop-pet" "$PLUGIN_DIR/bin"

# 1. Auto-compile on first launch or if main.swift was modified
if [ ! -x "$BIN" ] || [ "$SRC" -nt "$BIN" ]; then
    swiftc "$SRC" -o "$BIN" 2>&1
fi

# 2. Check if process is already running; start if not
if ! pgrep -fl DesktopPetCat >/dev/null 2>&1; then
    nohup "$BIN" >/dev/null 2>&1 &
fi

# Output required JSON to stdout for Antigravity hook system
echo '{}'
