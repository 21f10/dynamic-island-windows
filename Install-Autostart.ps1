<#
.SYNOPSIS
    Installs (or uninstalls) a Windows Startup shortcut for Dynamic Island.

.DESCRIPTION
    Creates a .lnk shortcut in the current user's shell:startup folder that
    points to LaunchIsland.vbs via wscript.exe, ensuring Dynamic Island starts
    silently on every logon.

    Use the -Uninstall switch to remove the shortcut.

.PARAMETER Uninstall
    If specified, removes the Dynamic Island shortcut from the Startup folder
    instead of creating it.

.EXAMPLE
    # Install autostart
    .\Install-Autostart.ps1

.EXAMPLE
    # Remove autostart
    .\Install-Autostart.ps1 -Uninstall

.NOTES
    Place this script in the same folder as Island.ps1 and LaunchIsland.vbs.
#>

[CmdletBinding()]
param(
    [switch]$Uninstall
)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
$ShortcutName    = "DynamicIsland.lnk"
$Description     = "Dynamic Island for Windows"

# ---------------------------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------------------------

# The folder where this script (and Island.ps1 / LaunchIsland.vbs) lives
$IslandFolder    = $PSScriptRoot

# Full path to the VBScript silent launcher
$LaunchVbs       = Join-Path -Path $IslandFolder -ChildPath "LaunchIsland.vbs"

# The user's Startup folder (shell:startup)
$StartupFolder   = [System.Environment]::GetFolderPath('Startup')
$ShortcutPath    = Join-Path -Path $StartupFolder -ChildPath $ShortcutName

# ---------------------------------------------------------------------------
# Uninstall mode -- remove the shortcut and exit
# ---------------------------------------------------------------------------
if ($Uninstall) {
    if (Test-Path -LiteralPath $ShortcutPath) {
        Remove-Item -LiteralPath $ShortcutPath -Force
        Write-Host "[OK] Startup shortcut removed: $ShortcutPath" -ForegroundColor Green
    }
    else {
        Write-Host "[INFO] No startup shortcut found at: $ShortcutPath" -ForegroundColor Yellow
    }
    return
}

# ---------------------------------------------------------------------------
# Install mode -- create the shortcut
# ---------------------------------------------------------------------------

# Validate that LaunchIsland.vbs exists before creating a shortcut to it
if (-not (Test-Path -LiteralPath $LaunchVbs)) {
    Write-Error "Cannot find LaunchIsland.vbs in: $IslandFolder"
    Write-Error "Make sure LaunchIsland.vbs is in the same folder as this script."
    return
}

# Use the WScript.Shell COM object to create a proper .lnk shortcut
$WshShell = New-Object -ComObject WScript.Shell

try {
    $Shortcut                  = $WshShell.CreateShortcut($ShortcutPath)
    $Shortcut.TargetPath       = "wscript.exe"                  # Host for the VBS
    $Shortcut.Arguments        = "`"$LaunchVbs`""               # Path to the VBS launcher
    $Shortcut.WorkingDirectory = $IslandFolder                   # CWD = island folder
    $Shortcut.Description      = $Description                   # Tooltip text
    $Shortcut.WindowStyle      = 7                               # 7 = Minimized (wscript itself)
    $Shortcut.Save()

    Write-Host ""
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host " Dynamic Island - Autostart Installed" -ForegroundColor Cyan
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Shortcut : $ShortcutPath" -ForegroundColor White
    Write-Host "  Target   : wscript.exe" -ForegroundColor White
    Write-Host "  Arguments: `"$LaunchVbs`"" -ForegroundColor White
    Write-Host "  Folder   : $IslandFolder" -ForegroundColor White
    Write-Host ""
    Write-Host "  Dynamic Island will now start automatically on logon." -ForegroundColor Green
    Write-Host "  To remove, run:  .\Install-Autostart.ps1 -Uninstall" -ForegroundColor DarkGray
    Write-Host ""
}
catch {
    Write-Error "Failed to create startup shortcut: $_"
}
finally {
    # Release the COM object
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($WshShell) | Out-Null
}
