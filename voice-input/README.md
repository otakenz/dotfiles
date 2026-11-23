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

WSL2 with an NVIDIA GPU only; macOS and native Linux are not supported.

1. Windows **Settings → Privacy & security → Microphone**: turn on
   "Let desktop apps access your microphone" (WSL counts as a desktop app).
   If it was off, run `wsl --shutdown` afterwards.
2. Optional, for noise: NVIDIA Broadcast, Microphone tab, Noise Removal +
   Room Echo Removal; set Windows default input to
   "Microphone (NVIDIA Broadcast)" and Broadcast's source to the headset.
3. Install AutoHotkey v2 in Windows: `winget install AutoHotkey.AutoHotkey`
   (or autohotkey.com, current user).
4. In WSL:

   ```sh
   ~/dotfiles/install --only voice-input
   ```

   Installs `parecord`, the Python environment and the model (about 3 GB
   with the CUDA libraries), links the config and starts the service, then
   runs `install-windows.sh`. Safe to re-run: finished steps are skipped.
   A normal `./install` never does this. Run a normal `./install` first: the
   piece needs `uv` from it.

   If AutoHotkey is missing, the WSL service is still installed but Ctrl+Q
   does nothing yet; the piece prints the `winget` command. Install
   AutoHotkey, then re-run `./install --only voice-input`.

### Manual setup (the same steps by hand)

```sh
sudo apt-get install -y pulseaudio-utils     # Arch: sudo pacman -S libpulse
d=~/.local/share/voice-input
uv venv --python 3.12 "$d/.venv"
uv pip install --python "$d/.venv" faster-whisper==1.2.1 nvidia-cublas-cu12 \
  "nvidia-cudnn-cu12==9.*" "av<16"
"$d/.venv/bin/python" -c 'import sys; from faster_whisper.utils import download_model; \
  download_model("large-v3-turbo", cache_dir=sys.argv[1])' "$d/models"

ln -fs ~/dotfiles/.local/bin/voice-input ~/.local/bin/voice-input
# Skip this link if ~/.config/voice-input is your own folder (the installer keeps it)
[ -d ~/.config/voice-input ] && [ ! -L ~/.config/voice-input ] ||
  ln -sfn ~/dotfiles/.config/voice-input ~/.config/voice-input
mkdir -p ~/.config/systemd/user
ln -fs ~/dotfiles/voice-input/voice-input.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now voice-input

~/dotfiles/voice-input/install-windows.sh
```

`install-windows.sh` copies the script to `%USERPROFILE%\voice-input`, adds
it to the Startup folder and starts it. Re-run it after changing
`voice-input.ahk`. For development, add pytest:
`uv pip install --python ~/.local/share/voice-input/.venv pytest`.

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
| `🎙 off` | service stopped answering after it had answered in this session |
| (nothing) | service has not answered yet in this session (also on machines without voice input) |

It polls `GET /status` every 0.2 s while recording, every 2 s otherwise.
Tests: `cd ~/dotfiles/.config/opencode/tui-plugins/voice-input && bun test`
