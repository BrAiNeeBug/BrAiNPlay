BrAiNPlay "Intuitive-Player" uploaded to Git for better support...

<img width="480" height="540" alt="image" src="https://github.com/user-attachments/assets/e7997895-fd8d-466a-a666-6f2227229054" />
<img width="720" height="452" alt="image" src="https://github.com/user-attachments/assets/c873075b-d791-4b8a-a416-dc8e689220e6" />

source: https://www.autoitscript.com/forum/topic/213899-brainplay-intuitiveplayer/


Features
🎵 Audio Player
MP3, WAV and WMA playback

Play, pause, stop, previous/next and automatic next track

Waveform and seekable playback timeline

Volume, stereo balance and mute controls

Shuffle and loop modes

Global multimedia keyboard controls

MP3 compatibility fixer for files with unusual tags or junk before the actual MPEG stream, without re-encoding the original file

🎬 Video Support (introduced in V2)
Dedicated video window

Windowed and fullscreen modes

Video sizing, zoom and monitor selection

Optional click-to-toggle fullscreen/window mode

On-screen messages and video controls

MCI playback with a Windows Media Player fallback when needed

Audio-track selection through the fallback engine when supported

🏠 NEW in V3: Native MQTT Integration
BrAiNPlay now supports MQTT directly through native TCP communication using MQTT 3.1.1 and QoS 0. No additional MQTT library is required.

Features include:

Configurable broker host and port

Optional username and password (dpapi secured)

Custom MQTT base topic

Player-state publishing as JSON

Remote playback, volume, balance and seek control

Shuffle, loop and video control via MQTT

Automatic reconnection attempts

Optional Home Assistant MQTT discovery

Home Assistant can automatically discover entities for:

Currently playing track and playback state

Volume slider

Play/Pause, Next, Previous, Stop and Mute buttons

Shuffle and Loop switches

The published player state includes track information, playlist position, duration, volume, balance, mute, shuffle, loop and video status.

Default MQTT topics:

Commands: brainplay/cmd

State: brainplay/state

Availability: brainplay/availability

Examples of supported commands include play, pause, playpause, next, prev, stop, mute, volume 40, balance -20, seek -10, shuffle on, loop off, video toggle and fullscreen.

The default Home Assistant discovery prefix is homeassistant. MQTT and discovery can be configured in the Options menu.

⚙️ NEW in V3: Options Menu
Options Menu can be open by clicking on the AppName.

Enable or disable logging

Configure global multimedia keyboard controls

Keep the screen awake during video playback

Remember the playlist between sessions

Configure video click behavior

Enable and configure MQTT

Set the MQTT base topic and Home Assistant discovery prefix

Open the log file and configuration folder

Settings are stored in %APPDATA%\BrAiNPlay.

📂 Playlist
Add files and folders

Drag and drop files onto the player

Remove or clear playlist entries

Load and save M3U/M3U8 playlists

Optionally restore the last playlist

Compact playlist show/hide mode

⌨️ Keyboard Shortcuts & Multimedia Keys
BrAiNPlay supports global hardware multimedia keys, even while the player is minimized. These can be enabled or disabled in the Options menu.

Global multimedia keys

Play/Pause: Toggle playback

Stop: Stop playback

Next track: Short press skips to the next track; hold the key to fast-forward in 5-second steps

Previous track: Short press skips to the previous track; hold the key to rewind in 5-second steps

Keyboard shortcuts while a video is in Windows Media Player fullscreen mode

Space: Play/Pause

Left / Right: Seek backward / forward by 5 seconds

Up / Down: Increase / decrease volume

Ctrl + Up / Ctrl + Down: Increase / decrease volume

N: Next track

P: Previous track

S: Stop

M: Mute / unmute

F: Toggle video fullscreen

W: Toggle window/fullscreen mode where supported

A: Select audio track where supported

😧 Switch video monitor (if you cant find this key try "D" )

Esc: Close the video display

The global multimedia keys can be disabled independently, so other applications can use them instead.

Development History
V1: Initial compact player GUI with playback controls, visualizer, volume, balance and a basic playlist. (CLAUDE)

V2: Video support, dedicated video window, fullscreen/window modes and extended video controls. (CLAUDE)

V3: Native MQTT integration, Home Assistant discovery and a new Options menu. (CLAUDE)

V4: Native Linux/Wine compatibility (so the Design is now a mix of 1984 Windows and 2026 UI-Style) (CLAUDE/GPT)

Last Update: 18.10.2026 / 11:50GMT+1 (Claude), Fixed Player Drag

BrAiNPlay is still evolving, and feedback, ideas and bug reports are welcome!

Enjoy! 🎧
