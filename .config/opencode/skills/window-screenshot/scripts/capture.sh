#!/usr/bin/env bash
# From WSL: capture one Windows app window to a PNG in WSL.
# Usage: bash capture.sh <process name, e.g. Code> <out.png> [window title part]
set -euo pipefail

process="${1:?process name, e.g. Code, msedge, Teams}"
out="${2:?output .png path}"
title="${3:-}"

ps=/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
win_temp="$(/mnt/c/Windows/System32/cmd.exe /c 'echo %TEMP%' 2>/dev/null | tr -d '\r')"
tmp_name="window-screenshot-$$.png"

# Run the script from Windows TEMP: PowerShell may refuse scripts on \\wsl.localhost paths.
cp "${here}/capture-window.ps1" "$(wslpath "${win_temp}")/capture-window-$$.ps1"
trap 'rm -f "$(wslpath "${win_temp}")/capture-window-$$.ps1" "$(wslpath "${win_temp}")/${tmp_name}"' EXIT

timeout 60 "${ps}" -NoProfile -ExecutionPolicy Bypass -File "${win_temp}\\capture-window-$$.ps1" \
  -Process "${process}" -Title "${title}" -Out "${win_temp}\\${tmp_name}" | tr -d '\r'

mkdir -p "$(dirname "${out}")"
mv "$(wslpath "${win_temp}")/${tmp_name}" "${out}"
echo "wrote ${out}"
