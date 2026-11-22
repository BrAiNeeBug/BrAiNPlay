<div align="center">

# 🎧 BrAiNPlay

### The "Intuitive-Player"

A compact audio & video player for Windows (and Linux via Wine), written in AutoIt, with native MQTT and Home Assistant integration.

![Version](https://img.shields.io/badge/version-V4-blue)
![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux%2FWine-lightgrey)
![Language](https://img.shields.io/badge/language-AutoIt3-orange)
![MQTT](https://img.shields.io/badge/MQTT-3.1.1-purple)
![Home Assistant](https://img.shields.io/badge/Home%20Assistant-discovery-41BDF5)

<img width="480" height="540" alt="BrAiNPlay main window" src="https://github.com/user-attachments/assets/e7997895-fd8d-466a-a666-6f2227229054" />
<img width="720" height="452" alt="BrAiNPlay video and playlist" src="https://github.com/user-attachments/assets/c873075b-d791-4b8a-a416-dc8e689220e6" />

[Forum thread](https://www.autoitscript.com/forum/topic/213899-brainplay-intuitiveplayer/) · [Features](#-features) · [MQTT](#-mqtt--home-assistant) · [Shortcuts](#%EF%B8%8F-keyboard-shortcuts) · [History](#-development-history)

</div>

---

> BrAiNPlay is uploaded to Git for better support. Feedback, ideas and bug reports are welcome!

## ✨ Features

### 🎵 Audio Player

- MP3, WAV and WMA playback
- Play, pause, stop, previous/next and automatic next track
- Waveform and seekable playback timeline
- Volume, stereo balance and mute controls
- Shuffle and loop modes
- Global multimedia keyboard controls
- **MP3 compatibility fixer** for files with unusual tags or junk before the actual MPEG stream, without re-encoding the original file

### 🎬 Video Support *(since V2)*

- Dedicated video window
- Windowed and fullscreen modes
- Video sizing, zoom and monitor selection
- Optional click-to-toggle fullscreen/window mode
- On-screen messages and video controls
- MCI playback with a Windows Media Player fallback when needed
- Audio-track selection through the fallback engine when supported

### 📂 Playlist

- Add files and folders
- Drag and drop files onto the player
- Remove or clear playlist entries
- Load and save M3U/M3U8 playlists
- Optionally restore the last playlist
- Compact playlist show/hide mode

### ⚙️ Options Menu *(since V3)*

Open it by clicking on the app name.

- Enable or disable logging
- Configure global multimedia keyboard controls
- Keep the screen awake during video playback
- Remember the playlist between sessions
- Configure video click behavior
- Enable and configure MQTT
- Set the MQTT base topic and Home Assistant discovery prefix
- Open the log file and configuration folder

Settings are stored in `%APPDATA%\BrAiNPlay`.

---

## 🏠 MQTT & Home Assistant

*New in V3.* BrAiNPlay talks MQTT directly over native TCP (**MQTT 3.1.1, QoS 0**). No additional MQTT library is required.

- Configurable broker host and port
- Optional username and password (DPAPI secured)
- Custom MQTT base topic
- Player state published as JSON
- Remote control of playback, volume, balance and seek
- Shuffle, loop and video control via MQTT
- Automatic reconnection attempts
- Optional Home Assistant MQTT discovery

### Default topics

| Purpose      | Topic                    |
|--------------|--------------------------|
| Commands     | `brainplay/cmd`          |
| State        | `brainplay/state`        |
| Availability | `brainplay/availability` |

The default Home Assistant discovery prefix is `homeassistant`. MQTT and discovery are configured in the Options menu.

### Published state

Track information, playlist position, duration, volume, balance, mute, shuffle, loop and video status.

### Supported commands

| Command                                | Description              |
|----------------------------------------|--------------------------|
| `play` / `pause` / `playpause`         | Playback control         |
| `next` / `prev` / `stop`               | Track navigation / stop  |
| `mute`                                 | Toggle mute              |
| `volume 40`                            | Set volume               |
| `balance -20`                          | Set stereo balance       |
| `seek -10`                             | Seek relative (seconds)  |
| `shuffle on` / `loop off`              | Shuffle and loop modes   |
| `video toggle` / `fullscreen`          | Video control            |

### Home Assistant entities (auto-discovered)

- Currently playing track and playback state
- Volume slider
- Play/Pause, Next, Previous, Stop and Mute buttons
- Shuffle and Loop switches

---

## ⌨️ Keyboard Shortcuts

### Global multimedia keys

Work even while the player is minimized. They can be disabled independently in the Options menu, so other applications can use them instead.

| Key            | Action                                                                      |
|----------------|-----------------------------------------------------------------------------|
| Play/Pause     | Toggle playback                                                             |
| Stop           | Stop playback                                                               |
| Next track     | Short press: next track · Hold: fast-forward in 5-second steps              |
| Previous track | Short press: previous track · Hold: rewind in 5-second steps                |

### In video fullscreen (Windows Media Player mode)

| Key                          | Action                                              |
|------------------------------|-----------------------------------------------------|
| `Space`                      | Play/Pause                                          |
| `←` / `→`                    | Seek backward / forward by 5 seconds                |
| `↑` / `↓`                    | Increase / decrease volume                          |
| `Ctrl` + `↑` / `↓`           | Increase / decrease volume                          |
| `N`                          | Next track                                          |
| `P`                          | Previous track                                      |
| `S`                          | Stop                                                |
| `M`                          | Mute / unmute                                       |
| `F`                          | Toggle video fullscreen                             |
| `W`                          | Toggle window/fullscreen mode where supported       |
| `A`                          | Select audio track where supported                  |
| 😧 Switch video monitor      | If you can't find this key, try `D`                 |
| `Esc`                        | Close the video display                             |

---

## 📜 Development History

| Version | Changes                                                                                                   | Made with  |
|---------|-----------------------------------------------------------------------------------------------------------|------------|
| **V1**  | Initial compact player GUI with playback controls, visualizer, volume, balance and a basic playlist       | Claude     |
| **V2**  | Video support, dedicated video window, fullscreen/window modes and extended video controls                | Claude     |
| **V3**  | Native MQTT integration, Home Assistant discovery and a new Options menu                                  | Claude     |
| **V4**  | Native Linux/Wine compatibility (the design is now a mix of 1984 Windows and 2026 UI style)               | Claude/GPT |

**Last update:** 18.10.2026, 11:50 GMT+1 (Claude) – Fixed player drag

---

<div align="center">

BrAiNPlay is still evolving. Enjoy! 🎧

</div>
