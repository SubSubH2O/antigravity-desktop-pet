# Desktop Pet Cat for Google Antigravity

A native macOS ambient desktop companion that lives on your screen and reacts to Google Antigravity in real-time.

![Desktop Pet Cat](assets/logo.png)

---

## Features

- **Real-Time Antigravity States**:
  - **Working**: Types energetically on a laptop while Antigravity is generating code or running tools. Stays typing until all parallel sessions finish.
  - **Question**: Tilts its head with a gleaming question mark and plays a chime whenever Antigravity is waiting for human input (`ask_question`).
  - **Idle & Roaming**: Chunky 4-legged standing idle with calm breathing and gentle tail flick. Takes autonomous 2D strolls (smoothly gliding across both X and Y axes via native macOS WindowServer hardware composition) every 35–60 seconds, explores new spots across your screen, settles down, and saves its new location. On-demand stroll via right-click **Take a Stroll** (`s`).
  - **Sleeping**: Curls up with floating cyan z's after 10 continuous minutes of inactivity.
- **Smart 1-Click Jump**:
  - Clicking the cat brings the Antigravity window to the front.
  - If a session is waiting for your input, clicking the cat automatically jumps directly to that specific conversation!
- **Multi-Monitor Support**:
  - Drag the cat freely across all connected displays without hitting an invisible border.
  - Right-click the cat to open the context menu and use **Move to Screen** to teleport it between monitors with 1 click.
- **Audio Feedback & Mute Controls**:
  - Right-click the cat and open the **Sounds** submenu to customize audio feedback.
  - Independent toggles for **Sound Effects** (working typing chimes and task completion) and **Question Chime** (alert ping when human input is requested).
  - Quick **Mute All** / **Unmute All** option. Settings are automatically saved to `~/.desktop-pet/settings.json`.
- **Ultra-Lightweight & Battery-Friendly**:
  - Native Swift + AppKit implementation.
  - Steady-state CPU usage < 0.7%, 0 disk I/O when idle.
  - Automatically pauses animations when screens sleep to preserve MacBook battery.

---

## Installation

Clone this repository into your Antigravity plugins directory:

```bash
mkdir -p ~/.gemini/config/plugins
git clone https://github.com/SubSubH2O/antigravity-desktop-pet.git ~/.gemini/config/plugins/desktop-pet
```

That is it. The next time Antigravity opens (or you start a session), the cat will automatically compile and launch itself behind the scenes. Zero manual build commands required.

---

## Project Structure

```
desktop-pet/
├── main.swift                 # Native AppKit macOS app source
├── plugin.json                # Antigravity plugin manifest
├── hooks.json                 # Antigravity lifecycle hooks
├── assets/                    # Logo and UI assets
├── skills/                    # Skill definition (/pet)
├── scripts/
│   ├── start_pet.sh          # Daemon launcher & compiler
│   ├── set_state.sh          # Hook handler entry point
│   ├── set_state.py          # Multi-conversation priority engine
│   └── switch_conversation.py # Active conversation switcher
└── sprites/                   # Pixel art animation frames
    ├── idle_1..8.png
    ├── working_1..12.png
    ├── question_1..8.png
    ├── walking_1..8.png
    └── sleeping_1..12.png
```
