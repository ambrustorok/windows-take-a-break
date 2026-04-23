# Load assemblies FIRST
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ===================== CONFIGURATION =====================
$breakEveryMinutes  = 45    # How often to remind you to take a break
$flashCount         = 4     # How many times the border flashes
$borderThickness    = 25    # Thickness of the flash border in pixels
$flashColor         = [System.Drawing.Color]::Red  # Flash color
# =========================================================

# System tray icon to allow stopping the script
$trayIcon = New-Object System.Windows.Forms.NotifyIcon
$trayIcon.Icon    = [System.Drawing.SystemIcons]::Information
$trayIcon.Text    = "Break Reminder"
$trayIcon.Visible = $true

$contextMenu = New-Object System.Windows.Forms.ContextMenuStrip
$stopItem = $contextMenu.Items.Add("Stop Reminders")
$stopItem.Add_Click({
    $trayIcon.Visible = $false
    $trayIcon.Dispose()
    [System.Environment]::Exit(0)
})
$trayIcon.ContextMenuStrip = $contextMenu

function Flash-Screen {
    $forms = @()

    foreach ($screen in [System.Windows.Forms.Screen]::AllScreens) {
        $form = New-Object System.Windows.Forms.Form
        $form.FormBorderStyle = 'None'
        $form.TopMost         = $true
        $form.BackColor       = [System.Drawing.Color]::Lime
        $form.TransparencyKey = [System.Drawing.Color]::Lime
        $form.ShowInTaskbar   = $false
        $form.Bounds          = $screen.Bounds

        $screenBounds = $screen.Bounds
        $form.Add_Paint({
            param($s, $e)
            $g   = $e.Graphics
            $pen = New-Object System.Drawing.Pen($flashColor, $borderThickness)
            $rect = [System.Drawing.Rectangle]::new(
                [int]($borderThickness / 2),
                [int]($borderThickness / 2),
                $screenBounds.Width  - $borderThickness,
                $screenBounds.Height - $borderThickness
            )
            $g.DrawRectangle($pen, $rect)
            $pen.Dispose()
        })

        $form.Show()
        $forms += $form
    }

    for ($i = 0; $i -lt $flashCount; $i++) {
        foreach ($f in $forms) { $f.Opacity = 1.0; $f.Refresh() }
        Start-Sleep -Milliseconds 300
        foreach ($f in $forms) { $f.Opacity = 0.0; $f.Refresh() }
        Start-Sleep -Milliseconds 200
    }

    foreach ($f in $forms) { $f.Close(); $f.Dispose() }
}

function Show-BreakDialog {
    param([int]$minutesUntilNext)

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text            = "Break Reminder"
    $dialog.Size            = New-Object System.Drawing.Size(360, 160)
    $dialog.StartPosition   = 'CenterScreen'
    $dialog.TopMost         = $true
    $dialog.FormBorderStyle = 'FixedDialog'
    $dialog.MaximizeBox     = $false
    $dialog.MinimizeBox     = $false

    $label = New-Object System.Windows.Forms.Label
    $label.Text      = "Time for a break!`nYou've been working for $minutesUntilNext minutes."
    $label.Location  = New-Object System.Drawing.Point(20, 15)
    $label.Size      = New-Object System.Drawing.Size(320, 40)
    $label.Font      = New-Object System.Drawing.Font("Segoe UI", 10)

    $btnBreak = New-Object System.Windows.Forms.Button
    $btnBreak.Text     = "Break taken"
    $btnBreak.Location = New-Object System.Drawing.Point(20, 70)
    $btnBreak.Size     = New-Object System.Drawing.Size(90, 35)
    $btnBreak.Font     = New-Object System.Drawing.Font("Segoe UI", 9)

    $btn5 = New-Object System.Windows.Forms.Button
    $btn5.Text     = "Remind in 5 min"
    $btn5.Location = New-Object System.Drawing.Point(125, 70)
    $btn5.Size     = New-Object System.Drawing.Size(95, 35)
    $btn5.Font     = New-Object System.Drawing.Font("Segoe UI", 9)

    $btn10 = New-Object System.Windows.Forms.Button
    $btn10.Text     = "Remind in 10 min"
    $btn10.Location = New-Object System.Drawing.Point(230, 70)
    $btn10.Size     = New-Object System.Drawing.Size(105, 35)
    $btn10.Font     = New-Object System.Drawing.Font("Segoe UI", 9)

    $result = "break"
    $btnBreak.Add_Click({ $script:result = "break";    $dialog.Close() })
    $btn5.Add_Click({     $script:result = "snooze5";  $dialog.Close() })
    $btn10.Add_Click({    $script:result = "snooze10"; $dialog.Close() })

    $dialog.Controls.AddRange(@($label, $btnBreak, $btn5, $btn10))
    $dialog.ShowDialog() | Out-Null

    return $script:result
}

# ===================== MAIN LOOP =====================
$nextReminderMinutes = $breakEveryMinutes
$script:shouldStop = $false

while (-not $script:shouldStop) {
    # Sleep in small chunks so we can respond to the stop flag quickly
    $totalSeconds = $nextReminderMinutes * 60
    $elapsed = 0
    while ($elapsed -lt $totalSeconds -and -not $script:shouldStop) {
        Start-Sleep -Seconds 1
        $elapsed++
        [System.Windows.Forms.Application]::DoEvents()  # keeps tray icon responsive
    }

    if ($script:shouldStop) { break }

    Flash-Screen

    $response = Show-BreakDialog -minutesUntilNext $breakEveryMinutes

    switch ($response) {
        "break"    { $nextReminderMinutes = $breakEveryMinutes }
        "snooze5"  { $nextReminderMinutes = 5  }
        "snooze10" { $nextReminderMinutes = 10 }
    }
}

# Clean exit
$trayIcon.Visible = $false
$trayIcon.Dispose()
exit