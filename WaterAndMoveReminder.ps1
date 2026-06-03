# ============================================================
#  💧 Water & Movement Reminder
#  Reminds every 60 minutes, tracks daily water intake
#  Run once — loops all day until you close the terminal
# ============================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ── Daily state ─────────────────────────────────────────────
$script:totalWaterMl  = 0
$script:reminderCount = 0
$script:startTime     = Get-Date

# ── Helper: themed message box with water amount input ───────
function Show-WaterReminder {
    # Build the form
    $form = New-Object System.Windows.Forms.Form
    $form.Text            = "💧 Time to Drink Water!"
    $form.Size            = New-Object System.Drawing.Size(420, 300)
    $form.StartPosition   = "CenterScreen"
    $form.BackColor       = [System.Drawing.Color]::FromArgb(230, 245, 255)
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox     = $false
    $form.MinimizeBox     = $false
    $form.TopMost         = $true

    # Icon emoji label
    $lblIcon = New-Object System.Windows.Forms.Label
    $lblIcon.Text      = "💧"
    $lblIcon.Font      = New-Object System.Drawing.Font("Segoe UI Emoji", 36)
    $lblIcon.Location  = New-Object System.Drawing.Point(170, 15)
    $lblIcon.Size      = New-Object System.Drawing.Size(80, 60)
    $form.Controls.Add($lblIcon)

    # Main message
    $lblMsg = New-Object System.Windows.Forms.Label
    $lblMsg.Text      = "Hey Karthik! Drink some water now. 🥤`r`nHow much did you just drink?"
    $lblMsg.Font      = New-Object System.Drawing.Font("Segoe UI", 11)
    $lblMsg.Location  = New-Object System.Drawing.Point(20, 85)
    $lblMsg.Size      = New-Object System.Drawing.Size(380, 50)
    $lblMsg.TextAlign = "MiddleCenter"
    $form.Controls.Add($lblMsg)

    # Daily total label
    $lblTotal = New-Object System.Windows.Forms.Label
    $lblTotal.Text      = "Total today: $script:totalWaterMl ml"
    $lblTotal.Font      = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Italic)
    $lblTotal.ForeColor = [System.Drawing.Color]::FromArgb(0, 100, 160)
    $lblTotal.Location  = New-Object System.Drawing.Point(20, 135)
    $lblTotal.Size      = New-Object System.Drawing.Size(380, 20)
    $lblTotal.TextAlign = "MiddleCenter"
    $form.Controls.Add($lblTotal)

    # Amount input
    $numAmount = New-Object System.Windows.Forms.NumericUpDown
    $numAmount.Minimum   = 0
    $numAmount.Maximum   = 2000
    $numAmount.Value     = 250
    $numAmount.Increment = 50
    $numAmount.Font      = New-Object System.Drawing.Font("Segoe UI", 12)
    $numAmount.Location  = New-Object System.Drawing.Point(120, 165)
    $numAmount.Size      = New-Object System.Drawing.Size(100, 30)
    $form.Controls.Add($numAmount)

    $lblMl = New-Object System.Windows.Forms.Label
    $lblMl.Text     = "ml"
    $lblMl.Font     = New-Object System.Drawing.Font("Segoe UI", 12)
    $lblMl.Location = New-Object System.Drawing.Point(228, 168)
    $lblMl.Size     = New-Object System.Drawing.Size(40, 26)
    $form.Controls.Add($lblMl)

    # OK button
    $btnOK = New-Object System.Windows.Forms.Button
    $btnOK.Text      = "✅  Done!"
    $btnOK.Font      = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnOK.BackColor = [System.Drawing.Color]::FromArgb(0, 150, 220)
    $btnOK.ForeColor = [System.Drawing.Color]::White
    $btnOK.FlatStyle = "Flat"
    $btnOK.Location  = New-Object System.Drawing.Point(120, 215)
    $btnOK.Size      = New-Object System.Drawing.Size(100, 36)
    $btnOK.Add_Click({ $form.Tag = $numAmount.Value; $form.Close() })
    $form.Controls.Add($btnOK)

    # Skip button
    $btnSkip = New-Object System.Windows.Forms.Button
    $btnSkip.Text      = "Skip"
    $btnSkip.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
    $btnSkip.BackColor = [System.Drawing.Color]::FromArgb(200, 200, 200)
    $btnSkip.FlatStyle = "Flat"
    $btnSkip.Location  = New-Object System.Drawing.Point(235, 215)
    $btnSkip.Size      = New-Object System.Drawing.Size(60, 36)
    $btnSkip.Add_Click({ $form.Tag = 0; $form.Close() })
    $form.Controls.Add($btnSkip)

    $form.AcceptButton = $btnOK
    $form.ShowDialog() | Out-Null

    return [int]$form.Tag
}

# ── Helper: movement reminder ────────────────────────────────
function Show-MoveReminder {
    $form = New-Object System.Windows.Forms.Form
    $form.Text            = "🚶 Time to Move!"
    $form.Size            = New-Object System.Drawing.Size(420, 230)
    $form.StartPosition   = "CenterScreen"
    $form.BackColor       = [System.Drawing.Color]::FromArgb(230, 255, 235)
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox     = $false
    $form.MinimizeBox     = $false
    $form.TopMost         = $true

    $lblIcon = New-Object System.Windows.Forms.Label
    $lblIcon.Text      = "🚶"
    $lblIcon.Font      = New-Object System.Drawing.Font("Segoe UI Emoji", 36)
    $lblIcon.Location  = New-Object System.Drawing.Point(170, 15)
    $lblIcon.Size      = New-Object System.Drawing.Size(80, 60)
    $form.Controls.Add($lblIcon)

    $tips = @(
        "Stand up & stretch for 2 minutes!",
        "Take a short walk around the room!",
        "Do 10 shoulder rolls — each side!",
        "Walk to the window, look outside!",
        "Quick neck stretch — left & right!",
        "Stand, shake it out, reset your posture!"
    )
    $tip = $tips | Get-Random

    $lblMsg = New-Object System.Windows.Forms.Label
    $lblMsg.Text      = "Hey Karthik! Get up & move! 💪`r`n$tip"
    $lblMsg.Font      = New-Object System.Drawing.Font("Segoe UI", 11)
    $lblMsg.Location  = New-Object System.Drawing.Point(20, 85)
    $lblMsg.Size      = New-Object System.Drawing.Size(380, 60)
    $lblMsg.TextAlign = "MiddleCenter"
    $form.Controls.Add($lblMsg)

    $btnOK = New-Object System.Windows.Forms.Button
    $btnOK.Text      = "✅  Done!"
    $btnOK.Font      = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnOK.BackColor = [System.Drawing.Color]::FromArgb(34, 180, 80)
    $btnOK.ForeColor = [System.Drawing.Color]::White
    $btnOK.FlatStyle = "Flat"
    $btnOK.Location  = New-Object System.Drawing.Point(155, 160)
    $btnOK.Size      = New-Object System.Drawing.Size(100, 36)
    $btnOK.Add_Click({ $form.Close() })
    $form.Controls.Add($btnOK)

    $form.AcceptButton = $btnOK
    $form.ShowDialog() | Out-Null
}

# ── Helper: daily summary ─────────────────────────────────────
function Show-Summary {
    $elapsed = [math]::Round(((Get-Date) - $script:startTime).TotalHours, 1)
    $msg = "Great job today, Karthik! 🎉`n`n" +
           "💧 Total water consumed : $script:totalWaterMl ml`n" +
           "⏰ Reminders received   : $script:reminderCount`n" +
           "🕐 Session duration     : $elapsed hours`n`n" +
           "Recommended daily intake: ~2000–2500 ml"

    [System.Windows.Forms.MessageBox]::Show(
        $msg,
        "📊 Daily Summary",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
}

# ── Main loop ────────────────────────────────────────────────
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  💧 Water & Movement Reminder is RUNNING  " -ForegroundColor Cyan
Write-Host "  Reminders every 60 minutes               " -ForegroundColor Cyan
Write-Host "  Press Ctrl+C to stop and see your summary" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

# Alternate: even reminder = water, odd = move
$reminderIndex = 0

try {
    while ($true) {
        Write-Host "`n[$(Get-Date -Format 'hh:mm tt')] Waiting 60 minutes for next reminder..." -ForegroundColor Gray
        Start-Sleep -Seconds 3600

        $script:reminderCount++
        $reminderIndex++

        if ($reminderIndex % 2 -eq 1) {
            # ODD → Water reminder
            Write-Host "[$(Get-Date -Format 'hh:mm tt')] 💧 Showing water reminder..." -ForegroundColor Blue
            $drank = Show-WaterReminder
            $script:totalWaterMl += $drank
            Write-Host "  → Logged: $drank ml | Total today: $script:totalWaterMl ml" -ForegroundColor Cyan
        } else {
            # EVEN → Move reminder
            Write-Host "[$(Get-Date -Format 'hh:mm tt')] 🚶 Showing movement reminder..." -ForegroundColor Green
            Show-MoveReminder
            Write-Host "  → Movement reminder acknowledged." -ForegroundColor Green
        }
    }
}
finally {
    # Always show summary when script ends (Ctrl+C or terminal close)
    Show-Summary
}
