$folder = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $folder) { $folder = (Get-Location).Path }
$scriptPath = Join-Path $folder "Island.ps1"

if (-not (Test-Path $scriptPath)) {
    Write-Host "[ERROR] Cannot find $scriptPath!" -ForegroundColor Red
    return
}

Write-Host "--------------------------------------------------------" -ForegroundColor Cyan
Write-Host " Dynamic Island DevWatch Active" -ForegroundColor Green
Write-Host " Edit and save G:\island\Island.ps1 to see live reloads." -ForegroundColor Cyan
Write-Host " Press CTRL + C in this window to stop watching." -ForegroundColor Gray
Write-Host "--------------------------------------------------------" -ForegroundColor Cyan

# Function to start/restart Island.ps1
function Start-IslandProcess {
    if ($global:islandProc -and -not $global:islandProc.HasExited) {
        Write-Host "[DEVWATCH] Closing previous Island instance..." -ForegroundColor Yellow
        Stop-Process -Id $global:islandProc.Id -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 400
    }
    Write-Host "[DEVWATCH] Launching Island.ps1..." -ForegroundColor Green
    $global:islandProc = Start-Process powershell -ArgumentList "-STA -WindowStyle Normal -ExecutionPolicy Bypass -File ""$scriptPath""" -PassThru
}

# Initial Launch
Start-IslandProcess

# Set up FileSystemWatcher
$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $folder
$watcher.Filter = "Island.ps1"
$watcher.NotifyFilter = [System.IO.NotifyFilters]::LastWrite
$watcher.EnableRaisingEvents = $true

# Register Event Action
$action = {
    Write-Host "[DEVWATCH] Change detected in Island.ps1! Reloading..." -ForegroundColor Yellow
    Start-IslandProcess
}

$subscriber = Register-ObjectEvent -InputObject $watcher -EventName "Changed" -Action $action

# Keep PowerShell session alive to catch file changes
try {
    while ($true) {
        Wait-Event -Timeout 1
    }
} finally {
    Write-Host "`n[DEVWATCH] Shutting down watcher..." -ForegroundColor Red
    Unregister-Event -SubscriptionId $subscriber.Id -ErrorAction SilentlyContinue
    $watcher.Dispose()
    if ($global:islandProc -and -not $global:islandProc.HasExited) {
        Stop-Process -Id $global:islandProc.Id -Force -ErrorAction SilentlyContinue
    }
}