#!/bin/bash
# set_state.sh: Instantly update pet live state with multi-conversation support
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$DIR/../bin/DesktopPetCat"

# 1. Ensure DesktopPetCat is compiled and running
if ! pgrep -fl DesktopPetCat >/dev/null 2>&1; then
    if [ ! -x "$BIN" ]; then
        SRC="$DIR/../main.swift"
        swiftc -O -o "$BIN" "$SRC" 2>&1
    fi
    if [ -x "$BIN" ]; then
        nohup "$BIN" >/dev/null 2>&1 &
    fi
fi

# 2. Update state JSON
exec python3 "$DIR/set_state.py" "$@"
