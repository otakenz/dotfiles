---
name: voice-input
description: Use when working on or troubleshooting the local voice input (hold Ctrl+Q in WezTerm to dictate, Whisper on the GPU in WSL): the voice-input service, its /status API, the AutoHotkey script, the OpenCode footer indicator, vocab/replacement files, a new or silent microphone, or poor transcription accuracy.
---

# Voice input

User docs and setup: `voice-input/README.md`. This skill is the map for
changing or debugging it.

## Parts

| Part | Where | Runs |
|---|---|---|
| Service (Python) | `voice-input/voice_input/`: `service.py` (logic, lock), `recorder.py` (parecord), `transcriber.py` (faster-whisper), `audio.py` (levels), `config.py`, `server.py` (HTTP) | systemd user unit `voice-input.service` → `.local/bin/voice-input serve` |
| Venv + model | `~/.local/share/voice-input/{.venv,models}` (not in git; faster-whisper 1.2.1, `av<16`, pip CUDA libs; large-v3-turbo) | wrapper sets `LD_LIBRARY_PATH` and `PYTHONPATH` |
| Word list, fix-ups | `.config/voice-input/{vocab.txt,replacements.txt}` → `~/.config/voice-input` | re-read on every `/stop` |
| Hotkey (Windows) | `voice-input/voice-input.ahk`, installed by `voice-input/install-windows.sh` to `%USERPROFILE%\voice-input` + Startup shortcut | AutoHotkey v2, only while `wezterm-gui.exe` is active |
| Footer indicator | `.config/opencode/tui-plugins/voice-input/` (TUI-only, in `cli.json` `plugins`; not under `plugins/`, which loads server plugins) | polls `/status` 0.2 s busy, 2 s idle |

## API (127.0.0.1:47821)

Every request needs header `X-Voice-Input: 1` and Host `127.0.0.1` or
`localhost`, else 403 (blocks browser pages and DNS rebinding).

`POST /start`, `POST /stop` (→ `text`, `warning`, levels, `seconds`),
`POST /cancel`, `GET /health`, `GET /status` (→ `state`
idle/recording/stopped/transcribing, `level_dbfs`, `elapsed_s`, `warning`,
`warning_age_s`; lock-free so it answers during transcription).

Rules: clips < 0.3 s dropped; auto-stop at 120 s; peak < -45 dBFS →
"no audio – check mic"; empty text → "no speech".

## Change and test

```bash
cd voice-input && ~/.local/share/voice-input/.venv/bin/python -m pytest tests -q
cd .config/opencode/tui-plugins/voice-input && bun test
systemctl --user restart voice-input          # after Python changes
voice-input/install-windows.sh                # after .ahk changes
```

AutoHotkey has no tests: check syntax with
`AutoHotkey64.exe /ErrorStdOut /validate <script>` (copy it to a Windows
path first), then test by hand. `SendMode` is a built-in name; do not use
it as a variable.

## Debug

| Symptom | Look at |
|---|---|
| "no audio" / flat bar | Windows default input (should be the NVIDIA Broadcast mic), Broadcast running and its source set; `pactl list short sources` shows `RDPSource` |
| `parecord` makes 44-byte files, `pactl` hangs | Windows "Let desktop apps access your microphone" off → turn on, then `wsl --shutdown` |
| "voice service not running" / footer `🎙 off` | `systemctl --user status voice-input`, `journalctl --user -u voice-input` |
| Wrong words | add terms to `vocab.txt`, spelling fixes to `replacements.txt`; check the mic: `voice-input check` (peak, clipping, timing) |
| Poor accuracy overall | Bluetooth headsets (AirPods) switch to call mode: use wired/USB. large-v3 was tested: not better, twice as slow. ffmpeg denoise before Whisper made it worse |
| Ctrl+Q does nothing | AutoHotkey not running → re-run `install-windows.sh` |
