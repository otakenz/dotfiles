Set-PSReadLineOption -MaximumHistoryCount 50000
Set-PSReadLineOption -HistorySaveStyle SaveIncrementally
Set-PSReadLineOption -HistoryNoDuplicates: $true

Set-PSReadLineKeyHandler -Key "Ctrl+r" -ScriptBlock {
    $historyFile = "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt"

    # Reverse the content, then remove duplicates (latest occurrences kept)
    $lines = Get-Content $historyFile
    $reversed = [System.Collections.Generic.List[string]]::new()

    $lines | ForEach-Object { $reversed.Insert(0, $_) }
    $unique = $reversed | Select-Object -Unique

    # Reverse back to the original order
    $final = [System.Collections.Generic.List[string]]::new()
    $unique | ForEach-Object { $final.Insert(0, $_) }

    # Write the cleaned history back to the file
    $final | Set-Content $historyFile

    if (Test-Path $historyFile) {
        $lines = Get-Content $historyFile
        $selected = $lines | fzf --tac
        if ($selected) {
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($selected)
        }
    }
}

# Insert selected file(s) at the cursor using Ctrl+T
Set-PSReadLineKeyHandler -Key "Ctrl+t" -ScriptBlock {
    $files = fzf --multi
    if ($files) {
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert($files -join ' ')
    }
}

# Change directory using Alt+C
Set-PSReadLineKeyHandler -Key "Alt+c" -ScriptBlock {
    $dir = Get-ChildItem -Directory -Recurse -ErrorAction SilentlyContinue |
           ForEach-Object { $_.FullName } | fzf --height 40%
    if ($dir) {
        Set-Location $dir
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert("cd `"$dir`"")
    }
}

