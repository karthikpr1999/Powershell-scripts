Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ===== CONFIGURATION =====
$LogicMonitorURL = "https://sap.logicmonitor.com/santaba/uiv4/resources/treeNodes?resourcePath=resourceGroups-1%2A%2CresourceGroups-17%2CresourceGroups-25"
$IntervalSeconds = 10   # 1 hour
$LogFile = "C:\Users\C5340448\OneDrive - SAP SE\Powershell_scripts\logic_monitor_logs\HourLogicMonitor.log"

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