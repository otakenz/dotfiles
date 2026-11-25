# Backing up a WSL distro

All commands in Windows PowerShell, with WSL shut down (`wsl --shutdown`):
export stops the distro, and a running one can change files mid-copy.

## 1. Measure first

| What | Command | Means |
|---|---|---|
| Data in the distro | WSL: `df -h /` (Used) | size of a `tar` export |
| Disk file on C: | Explorer → `ext4.vhdx` → Properties → **Size on disk** | size of a `vhd` export; "Size" is the logical maximum, ignore it |
| Free on C: | `Get-PSDrive C` | must exceed the export |
| Disk file path | `(Get-ChildItem HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss \| Get-ItemProperty \| ? DistributionName -eq Ubuntu).BasePath` | |

If "Size on disk" is far above `df` Used, shrink first: in WSL
`sudo fstrim -av` (with sparse VHDX, see SKILL.md "Removing"), then check
again. Clean caches before a backup: the export copies them too.

## 2. Pick a format

| Format | Command | Size | Speed | Restore |
|---|---|---|---|---|
| tar.gz | `wsl --export Ubuntu <file>.tar.gz --format tar.gz` | below Used; models, git packs and archives barely compress | slow (single-thread gzip, hours for 250 GB) | `wsl --import`, default user must be reset |
| tar | `wsl --export Ubuntu <file>.tar` | = Used | fast | same |
| vhd | `wsl --export Ubuntu <file>.vhdx --format vhd` (older WSL: `--vhd`) | = allocated disk (trim first) | fastest | `wsl --import-in-place`, keeps the user |

`wsl --help` shows which flags the installed WSL accepts.

## 3. Where to write it

- **External or second drive**: best; nothing on C:.
- **OneDrive folder** (`$env:OneDriveCommercial` for the work account):
  the file lands on C: first, then uploads. Needs free C: space for the
  whole file until the upload finishes; afterwards right-click → "Free up
  space" turns it into a cloud-only placeholder. Large uploads take hours;
  keep the PC awake.
- **Temp on C:, then move**: same C: need as writing into OneDrive
  directly, plus a copy step, so write into the OneDrive folder directly.

Rule: free C: space must exceed the export size plus ~20 GB margin.

## 4. Verify

- The command printed "The operation completed successfully."
- tar.gz: `tar -tzf <file> > /dev/null` from WSL (reads the whole file).
- vhd: `wsl --import-in-place UbuntuTest <copy>.vhdx`, `wsl -d UbuntuTest`,
  look around, `wsl --unregister UbuntuTest` (deletes only the test copy).
- Keep the previous backup until the new one is verified and uploaded.

## 5. Restore

```powershell
wsl --import Ubuntu C:\WSL\Ubuntu <file>.tar.gz          # tar / tar.gz
wsl -d Ubuntu -u root -- sh -c 'printf "[user]\ndefault=<name>\n" >> /etc/wsl.conf'
wsl --terminate Ubuntu
# or, for a vhd export (keeps the user):
wsl --import-in-place Ubuntu <file>.vhdx
```

An existing distro with the same name must be unregistered first
(`wsl --unregister Ubuntu` deletes it for good: only after the backup is
verified).

Sources: https://learn.microsoft.com/windows/wsl/basic-commands,
https://learn.microsoft.com/windows/wsl/faq
