---
name: window-screenshot
description: Use when a screenshot of a Windows app (VS Code, Edge, Teams, a terminal) is needed from WSL, for docs, Confluence or checking what the user sees.
---

# Window screenshot (Windows, from WSL)

Capture **one app window**, never the whole screen. Full-screen captures pick
up whatever else is open: chats, mail, pinned passwords. A full-screen grab to
"find" an app once exposed a password in a Teams chat.

## Steps

1. Find the process name (only processes with a window):
   ```bash
   /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoProfile -Command \
     'Get-Process | ? MainWindowHandle -ne 0 | select ProcessName, MainWindowTitle | ft -Auto | Out-String -Width 200'
   ```
   VS Code is `Code`, Edge `msedge`, Teams `ms-teams`, WezTerm `wezterm-gui`.
   Not listed: the app is closed; ask the user to open it.
2. Capture that window:
   ```bash
   bash ~/.config/opencode/skills/window-screenshot/scripts/capture.sh Code /tmp/opencode/shot/raw.png [title part]
   ```
   It restores a minimized window first (that changes the user's screen; say
   so), and stops when several windows match: pass a title part then.
3. Look at a thumbnail before anything else. If the window shows secrets
   (keys, passwords, tokens, personal chats), delete the file and tell the
   user; do not crop around it and keep going.
4. Crop to the part that matters and mark it; then delete the raw capture:
   ```python
   from PIL import Image, ImageDraw
   im = Image.open("/tmp/opencode/shot/raw.png").convert("RGB")
   W, H = im.size
   c = im.crop((W - 900, H - 130, W, H)).resize((1800, 260), Image.LANCZOS)  # region, 2x for readability
   ImageDraw.Draw(c).rounded_rectangle((1460, 192, 1702, 242), radius=6, outline=(230, 40, 40), width=4)
   c.save("/tmp/opencode/result.png")
   ```
   Find the coordinates from a 2x crop first, then draw the box.
5. Uploads (Confluence, Jira) go from `/tmp/opencode`; give the user a copy in
   `C:\Users\<user>\Downloads` if they want to see it.

## When the whole screen seems necessary

Ask the user first and say why. Their own Snipping Tool (`Win+Shift+S`) is
better: they choose what is visible.

## Common mistakes

| Mistake | Instead |
|---|---|
| `CopyFromScreen` over all monitors to locate an app | Step 1: list windows by process |
| Black or empty image | The window was minimized or GPU-drawn; the script restores it and uses `PW_RENDERFULLCONTENT` |
| Wrong size on scaled displays | The script is DPI aware; do not drop `SetProcessDPIAware` |
| Raw captures left in `Downloads` or `/tmp/opencode` | Delete them after cropping |
