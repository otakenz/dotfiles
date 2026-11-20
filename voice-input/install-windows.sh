#!/usr/bin/env bash
# Copies voice-input.ahk to %USERPROFILE%\voice-input, adds a Startup-folder
# shortcut and (re)starts it. Needs AutoHotkey v2. Safe to re-run.

set -o errexit
set -o pipefail
set -o nounset

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
win="/mnt/c/Windows/System32"
ps="${win}/WindowsPowerShell/v1.0/powershell.exe"

profile_win="$("${win}/cmd.exe" /c "echo %USERPROFILE%" 2>/dev/null | tr -d '\r')"
profile="$(wslpath "${profile_win}")"

ahk=""
for candidate in \
  "${profile}/AppData/Local/Programs/AutoHotkey/v2/AutoHotkey64.exe" \
  "/mnt/c/Program Files/AutoHotkey/v2/AutoHotkey64.exe"; do
  if [ -f "${candidate}" ]; then
    ahk="${candidate}"
    break
  fi
done
if [ -z "${ahk}" ]; then
  printf "AutoHotkey v2 not found. Install it from https://www.autohotkey.com (v2, current user), then re-run.\n" >&2
  exit 1
fi

dest="${profile}/voice-input"
mkdir -p "${dest}"
cp "${here}/voice-input.ahk" "${dest}/voice-input.ahk"

export AHK_EXE AHK_SCRIPT
AHK_EXE="$(wslpath -w "${ahk}")"
AHK_SCRIPT="$(wslpath -w "${dest}/voice-input.ahk")"
export WSLENV="AHK_EXE:AHK_SCRIPT${WSLENV:+:${WSLENV}}"

# shellcheck disable=SC2016 # PowerShell expands these, not bash
"${ps}" -NoProfile -Command '
  $lnk = Join-Path ([Environment]::GetFolderPath("Startup")) "voice-input.lnk"
  $s = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
  $s.TargetPath = $env:AHK_EXE
  $s.Arguments = "`"$env:AHK_SCRIPT`""
  $s.Save()
  Start-Process -FilePath $env:AHK_EXE -ArgumentList "`"$env:AHK_SCRIPT`""
'

printf "voice-input.ahk installed to %s and started (also starts with Windows).\n" "${profile_win}\\voice-input"
