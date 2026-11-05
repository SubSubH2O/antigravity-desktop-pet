#!/bin/bash
# set_state.sh: Instantly update pet live state with multi-conversation support
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$DIR/set_state.py" "$@"
