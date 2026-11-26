# Captures one window (not the screen) of a running Windows app to a PNG.
# Restores the window first if it is minimized (minimized windows render nothing).
param(
  [Parameter(Mandatory = $true)][string]$Process,
  [string]$Title = "",
  [Parameter(Mandatory = $true)][string]$Out
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public class CaptureWin {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint f);
  public struct RECT { public int L, T, R, B; }
}
"@
[CaptureWin]::SetProcessDPIAware() | Out-Null

$candidates = @(Get-Process -Name $Process -ErrorAction SilentlyContinue | Where-Object {
    $_.MainWindowHandle -ne 0 -and ($Title -eq "" -or $_.MainWindowTitle -like "*$Title*")
  })
if ($candidates.Count -eq 0) { throw "no window for process '$Process' (title filter '$Title')" }
if ($candidates.Count -gt 1) {
  $candidates | ForEach-Object { "candidate: $($_.MainWindowTitle)" }
  throw "several windows match; pass -Title"
}
$h = $candidates[0].MainWindowHandle
"window: $($candidates[0].MainWindowTitle)"

if ([CaptureWin]::IsIconic($h)) {
  [CaptureWin]::ShowWindow($h, 9) | Out-Null  # SW_RESTORE
  Start-Sleep -Milliseconds 1500
  "restored from minimized"
}
$r = New-Object CaptureWin+RECT
[CaptureWin]::GetWindowRect($h, [ref]$r) | Out-Null
$w = $r.R - $r.L; $ht = $r.B - $r.T
$bmp = New-Object Drawing.Bitmap $w, $ht
$g = [Drawing.Graphics]::FromImage($bmp)
$dc = $g.GetHdc()
$ok = [CaptureWin]::PrintWindow($h, $dc, 2)  # PW_RENDERFULLCONTENT: GPU-drawn apps (Electron, browsers)
$g.ReleaseHdc($dc)
if (-not $ok) { throw "PrintWindow failed" }
$bmp.Save($Out, [Drawing.Imaging.ImageFormat]::Png)
"saved ${w}x${ht} to $Out"
