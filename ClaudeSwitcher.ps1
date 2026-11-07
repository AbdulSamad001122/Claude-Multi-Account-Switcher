<#
  Claude Account Switcher
  -----------------------
  Lets the Claude desktop app (Windows, Microsoft Store version) keep one
  profile per account, e.g. "Work" and "Personal". Each profile keeps its own
  sign-in, settings, chats and Claude Code sessions.

  How it works: the app keeps everything in ONE folder:
      %LOCALAPPDATA%\Claude-Data\claude_pzs8sxrjxfjjc
  When you switch, this script (with Claude fully closed) renames that folder
  to  claude_pzs8sxrjxfjjc~Work  and renames  claude_pzs8sxrjxfjjc~Personal
  back to the real name, then reopens Claude. Folders are only RENAMED in
  place - nothing is copied, moved elsewhere, or deleted.

  Usage (normally via "Claude Account Switcher.cmd"):
      ClaudeSwitcher.ps1                  interactive menu
      ClaudeSwitcher.ps1 -SwitchTo Work   switch straight to an account
      ClaudeSwitcher.ps1 -Status          show active and saved accounts

  IMPORTANT: keep this script OUTSIDE the Claude-Data folder.
#>
[CmdletBinding()]
param(
    [string]$SwitchTo,
    [switch]$Status,
    [switch]$DryRun,
    [switch]$Yes,                 # answer Yes to confirmations (testing)
    [string]$DataRoot = (Join-Path $env:LOCALAPPDATA 'Claude-Data'),
    [string]$FolderName = 'claude_pzs8sxrjxfjjc',
    [switch]$NoLaunch,            # testing: do not start Claude
    [switch]$SkipProcessCheck,    # testing: do not look for running Claude
    [string]$Delete               # remove a saved (not active) account from this PC
)

$ErrorActionPreference = 'Stop'
$AppId       = 'Claude_pzs8sxrjxfjjc!Claude'
$Active      = Join-Path $DataRoot $FolderName
$Sep         = '~'
$MarkerName  = '.switcher-profile-name'
$PendingFile = Join-Path $DataRoot '.switcher-pending-new'

function Say([string]$msg, [string]$color = 'Gray') { Write-Host $msg -ForegroundColor $color }

function Confirm([string]$question) {
    if ($Yes) { Say "$question (Y/N): Y"; return $true }
    return ((Read-Host "$question (Y/N)") -match '^\s*[Yy]')
}

function Test-Name([string]$n) { return ($n -match '^[A-Za-z0-9][A-Za-z0-9 _-]{0,39}$') }

function Get-ProfileFolder([string]$name) { Join-Path $DataRoot ($FolderName + $Sep + $name) }

function Get-SavedProfiles {
    if (-not (Test-Path -LiteralPath $DataRoot)) { return @() }
    @(Get-ChildItem -LiteralPath $DataRoot -Directory |
        Where-Object { $_.Name.StartsWith($FolderName + $Sep) } |
        ForEach-Object { $_.Name.Substring($FolderName.Length + $Sep.Length) } |
        Sort-Object)
}

function Set-Marker([string]$name) {
    if ($DryRun) { Say "[dry run] would label the active profile '$name'"; return }
    Set-Content -LiteralPath (Join-Path $Active $MarkerName) -Value $name -NoNewline
}

# Returns: $null = no active folder, '' = active but unlabeled, else the name.
function Get-ActiveName {
    if (-not (Test-Path -LiteralPath $Active)) { return $null }
    $m = Join-Path $Active $MarkerName
    if (Test-Path -LiteralPath $m) { return (Get-Content -LiteralPath $m -Raw).Trim() }
    if (Test-Path -LiteralPath $PendingFile) {
        # Claude created a fresh folder for a new account since the last switch.
        $n = (Get-Content -LiteralPath $PendingFile -Raw).Trim()
        if (-not $DryRun) {
            Set-Marker $n
            Remove-Item -LiteralPath $PendingFile
        }
        return $n
    }
    return ''
}

function Read-Label([string]$prompt) {
    while ($true) {
        $n = (Read-Host $prompt).Trim()
        if (-not (Test-Name $n)) { Say "Use 1-40 letters, numbers, spaces, - or _." Yellow; continue }
        if (Test-Path -LiteralPath (Get-ProfileFolder $n)) { Say "An account called '$n' is already saved. Pick another name." Yellow; continue }
        return $n
    }
}

function Get-ClaudeProcesses {
    $activeFull = [IO.Path]::GetFullPath($Active)
    @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $p = $null
        try { $p = $_.Path } catch { }
        $p -and (($p -like '*\WindowsApps\Claude_*') -or
                 $p.StartsWith($activeFull, [StringComparison]::OrdinalIgnoreCase))
    })
}

function Close-Claude {
    if ($SkipProcessCheck) { return $true }
    $procs = Get-ClaudeProcesses
    if ($procs.Count -eq 0) { return $true }
    Say ""
    Say "Claude is running. It must be fully closed before switching." Yellow
    Say "Anything still running in Claude (chats, Claude Code tasks) will stop." Yellow
    if (-not (Confirm "Close Claude now?")) { Say "Nothing was changed." ; return $false }
    if ($DryRun) { Say "[dry run] would close $($procs.Count) Claude processes"; return $true }

    # Ask nicely first (lets Claude save its window state), but only briefly:
    # Claude normally hides in the system tray instead of exiting.
    foreach ($p in $procs) { try { if ($p.MainWindowHandle -ne 0) { [void]$p.CloseMainWindow() } } catch { } }
    for ($i = 0; $i -lt 10; $i++) {
        Start-Sleep -Milliseconds 200
        if ((Get-ClaudeProcesses).Count -eq 0) { return $true }
    }
    Get-ClaudeProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
    for ($i = 0; $i -lt 50; $i++) {
        Start-Sleep -Milliseconds 200
        if ((Get-ClaudeProcesses).Count -eq 0) { return $true }
    }
    Say "Could not close Claude. Quit it from the system tray (right-click the icon > Quit) and try again." Red
    return $false
}

function Rename-Safe([string]$from, [string]$to) {
    if ($DryRun) { Say "[dry run] rename '$from' -> '$to'"; return }
    for ($i = 1; $i -le 20; $i++) {
        try { [IO.Directory]::Move($from, $to); return }
        catch {
            if ($i -eq 20) { throw }
            Start-Sleep -Milliseconds 500   # files can stay locked a moment after Claude exits
        }
    }
}

function Start-Claude {
    if ($NoLaunch -or $DryRun) { Say "(not starting Claude)"; return }
    Start-Process explorer.exe "shell:AppsFolder\$AppId"
}

function Show-Status {
    $cur = Get-ActiveName
    Say ""
    if ($null -eq $cur)   { Say "Active account : (none yet - Claude will create a fresh profile)" Cyan }
    elseif ($cur -eq '')  { Say "Active account : (not named yet)" Cyan }
    else                  { Say "Active account : $cur" Green }
    $saved = Get-SavedProfiles
    if ($saved.Count -gt 0) { Say ("Saved accounts : " + ($saved -join ', ')) }
    else                    { Say "Saved accounts : (none)" }
}

function Switch-Profile([string]$target) {
    $target = $target.Trim()
    if (-not (Test-Name $target)) { Say "Invalid name '$target'. Use letters, numbers, spaces, - or _." Red; return $false }

    $current = Get-ActiveName
    if ($current -and ($current -ieq $target)) {
        Say "'$current' is already the active account. Opening Claude." Green
        Start-Claude; return $true
    }

    $match = Get-SavedProfiles | Where-Object { $_ -ieq $target } | Select-Object -First 1
    if ($match) { $target = $match }   # use the saved spelling, e.g. work -> Work
    $targetFolder = Get-ProfileFolder $target
    $isNew = -not (Test-Path -LiteralPath $targetFolder)
    if ($isNew) {
        if (-not (Confirm "No saved account called '$target'. Create it as a new, signed-out profile?")) { return $false }
    }

    # Name the current profile BEFORE closing anything.
    if ($current -eq '') {
        if ($Yes) { Say "The active account has no name yet. Name it first." Red; return $false }
        $current = Read-Label "Name the account that is signed in right now (e.g. Work)"
        Set-Marker $current
    }
    $park = $null
    if ($current) {
        $park = Get-ProfileFolder $current
        if (Test-Path -LiteralPath $park) {
            Say "A saved folder for '$current' already exists ($park). Nothing was changed." Red
            return $false
        }
    }

    if (-not (Close-Claude)) { return $false }

    # 1) Put the current profile aside.
    if ($current) {
        try { Rename-Safe $Active $park }
        catch {
            Say "Could not put '$current' aside: $($_.Exception.Message)" Red
            Say "Some file is still in use. Nothing was changed. Restart Windows if this keeps happening." Red
            return $false
        }
    } elseif (Test-Path -LiteralPath $PendingFile) {
        if (-not $DryRun) { Remove-Item -LiteralPath $PendingFile }
    }

    # 2) Bring the target profile in (or leave the slot empty for a new one).
    if (-not $isNew) {
        try { Rename-Safe $targetFolder $Active }
        catch {
            Say "Could not activate '$target': $($_.Exception.Message)" Red
            if ($park) { Rename-Safe $park $Active; Say "'$current' was put back. Nothing was changed." Yellow }
            return $false
        }
        if (-not $DryRun -and -not (Test-Path -LiteralPath (Join-Path $Active $MarkerName))) { Set-Marker $target }
    } elseif (-not $DryRun) {
        Set-Content -LiteralPath $PendingFile -Value $target -NoNewline
    }

    Say ""
    Say "Switched to '$target'." Green
    if ($isNew) { Say "Claude will open signed out. Sign in with the $target account." Cyan }
    Start-Claude

    return $true
}

function Remove-SavedProfile([string]$name) {
    $match = @(Get-SavedProfiles) | Where-Object { $_ -ieq $name.Trim() } | Select-Object -First 1
    if (-not $match) { Say "There is no saved account called '$name'." Red; return $false }
    if (-not (Confirm "Delete the saved account '$match' from this PC? (It goes to the Recycle Bin.)")) { return $false }
    $folder = Get-ProfileFolder $match
    if ($DryRun) { Say "[dry run] would move '$folder' to the Recycle Bin"; return $true }
    try {
        Add-Type -AssemblyName Microsoft.VisualBasic
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($folder, 'OnlyErrorDialogs', 'SendToRecycleBin')
    } catch {
        Say "Could not delete '$match': $($_.Exception.Message)" Red; return $false
    }
    if (Test-Path -LiteralPath $folder) { Say "'$match' was not deleted." Red; return $false }
    $lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) "Claude - $match.lnk"
    if (Test-Path -LiteralPath $lnk) { Remove-Item -LiteralPath $lnk -ErrorAction SilentlyContinue }
    Say "Deleted '$match' (moved to the Recycle Bin)." Green
    return $true
}

function New-Shortcut([string]$name, [string]$script = $PSCommandPath, [switch]$Hidden) {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $lnkPath = Join-Path $desktop "Claude - $name.lnk"
    $ws = New-Object -ComObject WScript.Shell
    $lnk = $ws.CreateShortcut($lnkPath)
    $lnk.TargetPath = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $extra = ''
    if ($Hidden) { $extra = '-WindowStyle Hidden -STA '; $lnk.WindowStyle = 7 }
    $lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass $extra-File `"$script`" -SwitchTo `"$name`""
    $lnk.WorkingDirectory = Split-Path $script
    $claudeExe = Get-ChildItem 'C:\Program Files\WindowsApps' -Filter 'Claude_*_x64__pzs8sxrjxfjjc' -Directory -ErrorAction SilentlyContinue |
                 Sort-Object Name -Descending | Select-Object -First 1
    if ($claudeExe) { $lnk.IconLocation = (Join-Path $claudeExe.FullName 'app\Claude.exe') + ',0' }
    $lnk.Save()
    Say "Created desktop shortcut: Claude - $name" Green
}

# ---------------- main ----------------
if ($MyInvocation.InvocationName -eq '.') { return }   # loaded by the UI: functions only

if (-not (Test-Path -LiteralPath $DataRoot)) {
    Say "Claude data folder not found: $DataRoot" Red
    Say "Is the Microsoft Store version of Claude installed and opened at least once?" Red
    exit 1
}
if ($PSCommandPath -and $PSCommandPath.StartsWith([IO.Path]::GetFullPath($DataRoot), [StringComparison]::OrdinalIgnoreCase)) {
    Say "This script is inside the Claude-Data folder, so it would move with a profile." Red
    Say "Copy the switcher to another folder (e.g. Documents) and run it from there." Red
    exit 1
}

if ($Status)   { Show-Status; exit 0 }
if ($Delete) {
    $r = @(Remove-SavedProfile $Delete)
    if ($r.Count -gt 0 -and $r[-1] -eq $true) { exit 0 } else { exit 1 }
}
if ($SwitchTo) {
    $r = @(Switch-Profile $SwitchTo)
    if ($r.Count -gt 0 -and $r[-1] -eq $true) { exit 0 } else { exit 1 }
}

while ($true) {
    Clear-Host
    Say "=== Claude Account Switcher ===" Cyan
    Show-Status
    $saved = Get-SavedProfiles
    Say ""
    for ($i = 0; $i -lt $saved.Count; $i++) { Say ("  {0}) Switch to {1}" -f ($i + 1), $saved[$i]) }
    Say "  N) Add a new account"
    Say "  L) Name / rename the active account"
    Say "  S) Make a desktop shortcut for an account"
    Say "  Q) Quit"
    $c = (Read-Host "`nChoose").Trim()

    if ($c -match '^\d+$' -and [int]$c -ge 1 -and [int]$c -le $saved.Count) {
        [void](Switch-Profile $saved[[int]$c - 1]); Read-Host "`nPress Enter to close"; break
    }
    switch -Regex ($c) {
        '^[Nn]$' {
            $n = Read-Label "Name for the new account (e.g. Client A)"
            [void](Switch-Profile $n); Read-Host "`nPress Enter to close"; return
        }
        '^[Ll]$' {
            if ($null -eq (Get-ActiveName)) { Say "No active profile yet - open Claude first." Yellow; Start-Sleep 2; break }
            Set-Marker (Read-Label "Name for the active account")
        }
        '^[Ss]$' {
            $all = @(Get-SavedProfiles) + @(Get-ActiveName) | Where-Object { $_ } | Sort-Object -Unique
            if ($all.Count -eq 0) { Say "Name the active account first (L)." Yellow; Start-Sleep 2; break }
            Say ("Accounts: " + ($all -join ', '))
            $n = (Read-Host "Shortcut for which account").Trim()
            if ($all -contains $n) { New-Shortcut $n } else { Say "Unknown account '$n'." Yellow }
            Start-Sleep 2
        }
        '^[Qq]$' { return }
    }
}
