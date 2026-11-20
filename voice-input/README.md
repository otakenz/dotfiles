# Voice input

Hold **Ctrl+Q** in WezTerm, talk, release: the text is typed into WezTerm
(OpenCode, tmux, shell). Whisper (large-v3-turbo) runs locally on the GPU;
no audio leaves the machine.

| Key (WezTerm only) | Action |
|---|---|
| hold Ctrl+Q | record while held; text typed ~1 s after release |
| Ctrl+Shift+Q | toggle "type only" (default) / "send right away" (adds Enter) |

Tooltips near the mouse show "🎙 listening", "… transcribing" and warnings.
Outside WezTerm, Ctrl+Q keeps its normal meaning.

```
Windows                                   WSL
voice-input.ahk (AutoHotkey v2)           voice-input.service (systemd --user)
  Ctrl+Q down  -- POST /start -->           parecord RDPSource (Windows default mic)
  Ctrl+Q up    -- POST /stop  -->           level check, Whisper, replacements
  types text  <--  JSON text  ---
                  127.0.0.1:47821
```

## One-time setup

1. Windows **Settings → Privacy & security → Microphone**: turn on
   "Let desktop apps access your microphone" (WSL counts as a desktop app).
   If it was off, run `wsl --shutdown` afterwards.
2. Optional, for noise: NVIDIA Broadcast, Microphone tab, Noise Removal +
   Room Echo Removal; set Windows default input to
   "Microphone (NVIDIA Broadcast)" and Broadcast's source to the headset.
3. Python environment and model (about 3 GB with the CUDA libraries):

   ```sh
   d=~/.local/share/voice-input
   uv venv --python 3.12 "$d/.venv"
   uv pip install --python "$d/.venv" faster-whisper nvidia-cublas-cu12 \
     "nvidia-cudnn-cu12==9.*" "av<16" pytest
   "$d/.venv/bin/python" -c "from faster_whisper.utils import download_model; \
     download_model('large-v3-turbo', cache_dir='$d/models')"
   ```

4. Links and service:

   ```sh
   ln -fs ~/dotfiles/.local/bin/voice-input ~/.local/bin/voice-input
   ln -sfn ~/dotfiles/.config/voice-input ~/.config/voice-input
   mkdir -p ~/.config/systemd/user
   ln -fs ~/dotfiles/voice-input/voice-input.service ~/.config/systemd/user/
   systemctl --user daemon-reload
   systemctl --user enable --now voice-input
   ```

5. Install AutoHotkey v2 (autohotkey.com, current user), then:

   ```sh
   ~/dotfiles/voice-input/install-windows.sh
   ```

   Copies the script to `%USERPROFILE%\voice-input`, adds it to the Startup
   folder and starts it. Re-run after changing `voice-input.ahk`.

## New mic or new place (e.g. office headset)

- Pick the mic in Broadcast's source (or as Windows default input without
  Broadcast). WSL always records the Windows default input.
- Run `voice-input check` twice, quiet and with background noise, saying a
  typical prompt. Check the text, `seconds` (about 1), and `clipped: 0`.
  If `clipped` is above 0, lower the mic level in Windows sound settings.
- Bluetooth headsets (AirPods) switch to call mode when the mic is on;
  accuracy drops a lot. Prefer a wired or USB headset.

## Word list and fix-ups

`~/.config/voice-input/` (in the dotfiles), re-read on every use:

- `vocab.txt`: terms Whisper should recognise, one per line.
- `replacements.txt`: `regex => replacement` per line, applied in order,
  e.g. `\bSOME[\s,-]+IP\b => SOME/IP`.

## Troubleshooting

| Tooltip / symptom | Fix |
|---|---|
| "no audio – check mic" | Broadcast not running or its source is a disconnected mic; Windows mic permission off (then `wsl --shutdown`) |
| "voice service not running" | `systemctl --user status voice-input`, `journalctl --user -u voice-input` |
| "no speech" | Mic picks up only noise; speak closer or check the input device |
| Nothing happens on Ctrl+Q | AutoHotkey not running: re-run `install-windows.sh` |

Tests: `cd ~/dotfiles/voice-input && ~/.local/share/voice-input/.venv/bin/python -m pytest tests`

## Indicator in OpenCode

The TUI plugin `.config/opencode/tui-plugins/voice-input` (registered in
`cli.json`) shows the state under the prompt:

| Footer | Meaning |
|---|---|
| `🎙 ready` | service up, idle |
| `🔴 ▁▃▆█▆▃▁ 4.2s` | recording; the bar follows your voice, flat means not heard |
| `⏹ recording stopped – release Ctrl+Q` | 120 s limit reached or recording failed; release to transcribe what was caught |
| `… transcribing` | text comes next |
| `⚠ no audio – check mic` | last clip's warning, for 10 s |
| `🎙 off` | service not running |

It polls `GET /status` every 0.2 s while recording, every 2 s otherwise.
Tests: `cd ~/dotfiles/.config/opencode/tui-plugins/voice-input && bun test`
