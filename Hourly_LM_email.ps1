Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ===== CONFIGURATION =====
# Set LM_URL env var to your LogicMonitor dashboard URL before running, or edit config below
$LogicMonitorURL = if ($env:LM_URL) { $env:LM_URL } else {
    # Fallback: read from a local config file that is NOT committed to version control
    $configPath = Join-Path $PSScriptRoot "Hourly_LM_email.config.json"
    if (Test-Path $configPath) {
        (Get-Content $configPath | ConvertFrom-Json).LogicMonitorURL
    } else {
        Write-Error "LogicMonitor URL not set. Set the LM_URL environment variable or create Hourly_LM_email.config.json."
        exit 1
    }
}
$IntervalSeconds = 10   # 1 hour
$LogFile = Join-Path $PSScriptRoot "logic_monitor_logs\HourLogicMonitor.log"

# ===== SYSTEM TRAY ICON =====
$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Icon = [System.Drawing.SystemIcons]::Information
$notify.Visible = $true

while ($true) {

    # Open LogicMonitor in default browser
    Start-Process $LogicMonitorURL

    # Open Outlook if not already running
    if (-not (Get-Process -Name OUTLOOK -ErrorAction SilentlyContinue)) {
        Start-Process "outlook.exe"
    }

    # Show Notification
    $notify.ShowBalloonTip(
        5000,
        "Hourly Monitoring Check",
        "Review LogicMonitor alerts and Outlook emails.",
        [System.Windows.Forms.ToolTipIcon]::Info
    )

    # Play sound
    [System.Media.SystemSounds]::Exclamation.Play()

    # Log activity
    Add-Content -Path $LogFile -Value "$(Get-Date) - Hourly check triggered"

    # Wait 1 hour
    Start-Sleep -Seconds $IntervalSeconds
}