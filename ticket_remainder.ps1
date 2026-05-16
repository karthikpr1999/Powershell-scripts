param(
    [int]$IntervalMinutes = 1,
    [string]$Title = "Ticket Reminder",
    [string]$Message = "Check the ticket queue now."
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Icon = [System.Drawing.SystemIcons]::Information
$notify.Visible = $true

Write-Host "Ticket reminder started. Notifying every $IntervalMinutes minute(s). Press Ctrl+C to stop."

try {
    while ($true) {
        $notify.ShowBalloonTip(10000, $Title, $Message, [System.Windows.Forms.ToolTipIcon]::Info)
        [System.Media.SystemSounds]::Exclamation.Play()
        Start-Sleep -Seconds ($IntervalMinutes * 60)
    }
}
finally {
    $notify.Visible = $false
    $notify.Dispose()
    Write-Host "Ticket reminder stopped."
}
