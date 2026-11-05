---
name: desktop-pet
description: Control and manage the Desktop Pet Cat companion. Use to launch the pet, toggle its appearance, reset its screen position, or open the custom sprites folder. Triggered by /pet or asking about the pet.
---

# Desktop Pet Cat Skill

This skill manages the Desktop Pet Cat companion plugin for Antigravity.

## Usage & Commands

- **Launch / Start**: Starts the floating pixel pet companion if not currently active.
  ```bash
  ~/.gemini/config/plugins/desktop-pet/scripts/start_pet.sh
  ```
- **Reset Position**: Moves the cat back to the bottom-right corner of the primary screen.
  ```bash
  rm -f ~/.desktop-pet/position.json
  ```
- **Stop / Quit**: Quits the floating pet companion.
  ```bash
  killall DesktopPetCat
  ```
- **Custom Sprites**: The user can place custom 24x24 or 32x32 pixel sprites into `~/.desktop-pet/sprites/`.
