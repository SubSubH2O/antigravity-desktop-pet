#!/bin/bash
# start_pet.sh: Ensure DesktopPetCat daemon is running
mkdir -p "$HOME/.desktop-pet"

# Check if process is already running
if ! pgrep -fl DesktopPetCat >/dev/null 2>&1; then
    nohup "$HOME/.gemini/config/plugins/desktop-pet/bin/DesktopPetCat" >/dev/null 2>&1 &
fi

# Output required JSON to stdout
echo '{}'
