Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ===== CONFIGURATION =====
$LogicMonitorURL = ""
$IntervalSeconds = 10   # 1 hour
$LogFile = ""

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
