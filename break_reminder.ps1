# Load assemblies FIRST
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
# ===================== CONFIGURATION =====================
$breakEveryMinutes  = 45
$flashCount         = 4
$borderThickness    = 25
$flashColor         = [System.Drawing.Color]::Red
$logFilePath        = Join-Path $env:USERPROFILE "break_reminder_log.csv"
# =========================================================
# Initialise log file with header if it doesn't exist
if (-not (Test-Path $logFilePath)) {
    "Timestamp,Event,Detail" | Out-File -FilePath $logFilePath -Encoding UTF8
}
function Write-BreakLog {
    param([string]$Event, [string]$Detail = "")
    $line = "{0},{1},{2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Event, $Detail
    $line | Out-File -FilePath $logFilePath -Append -Encoding UTF8
}
# Track state
$script:nextBreakTime    = (Get-Date).AddMinutes($breakEveryMinutes)
$script:snoozeStreak     = 0
$script:shouldStop       = $false
# -- System tray icon --
$trayIcon = New-Object System.Windows.Forms.NotifyIcon
$trayIcon.Icon    = [System.Drawing.SystemIcons]::Information
$trayIcon.Visible = $true
$contextMenu = New-Object System.Windows.Forms.ContextMenuStrip
# --- Status line (disabled, just for display) ---
$statusItem = $contextMenu.Items.Add("...")
$statusItem.Enabled = $false
$statusItem.Font = New-Object System.Drawing.Font("Consolas", 9)
$contextMenu.Items.Add("-")
# --- Start break now ---
$startBreakItem = $contextMenu.Items.Add("Start break now")
$startBreakItem.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$startBreakItem.Add_Click({
    Start-Break -Source "tray menu"
})
# --- I just took a break ---
$breakTakenItem = $contextMenu.Items.Add("I just took a break")
$breakTakenItem.Add_Click({
    $script:nextBreakTime = (Get-Date).AddMinutes($breakEveryMinutes)
    $script:snoozeStreak  = 0
    Write-BreakLog "break_manual" "Reset via tray menu"
    $trayIcon.ShowBalloonTip(2000, "Break Reminder", "Timer reset. Next break in $breakEveryMinutes min.", [System.Windows.Forms.ToolTipIcon]::Info)
})
# --- Today's summary ---
$summaryItem = $contextMenu.Items.Add("Today's summary")
$summaryItem.Add_Click({
    Show-DailySummary
})
$contextMenu.Items.Add("-")
# --- Stop ---
$stopItem = $contextMenu.Items.Add("Stop Reminders")
$stopItem.Add_Click({
    $trayIcon.Visible = $false
    $trayIcon.Dispose()
    [System.Environment]::Exit(0)
})
$trayIcon.ContextMenuStrip = $contextMenu
# Update the status line every time the menu opens
$contextMenu.Add_Opening({
    $remaining = $script:nextBreakTime - (Get-Date)
    if ($remaining.TotalSeconds -lt 0) { $remaining = [TimeSpan]::Zero }
    $minLeft = [math]::Floor($remaining.TotalMinutes)
    $secLeft = $remaining.Seconds
    $timeStr = $script:nextBreakTime.ToString("HH:mm")
    $statusItem.Text = "Next break: $timeStr  ($minLeft min $secLeft sec)"
})
# -- Helper functions --
function Update-TrayTooltip {
    $remaining = $script:nextBreakTime - (Get-Date)
    if ($remaining.TotalSeconds -lt 0) { $remaining = [TimeSpan]::Zero }
    $minLeft  = [math]::Floor($remaining.TotalMinutes)
    $secLeft  = $remaining.Seconds
    $timeStr  = $script:nextBreakTime.ToString("HH:mm")
    $trayIcon.Text = "Break at $timeStr ($minLeft min $secLeft sec left)"
}
function Get-FlashParams {
    switch ($script:snoozeStreak) {
        0 { return @{ Count = $flashCount; Thickness = $borderThickness;    Color = [System.Drawing.Color]::Red;       Beep = $false } }
        1 { return @{ Count = 6;           Thickness = $borderThickness+10; Color = [System.Drawing.Color]::OrangeRed; Beep = $false } }
        2 { return @{ Count = 8;           Thickness = $borderThickness+20; Color = [System.Drawing.Color]::DarkRed;   Beep = $true  } }
        default {
              return @{ Count = 10;        Thickness = $borderThickness+30; Color = [System.Drawing.Color]::DarkRed;   Beep = $true  }
        }
    }
}
function Flash-Screen {
    $params = Get-FlashParams
    $fCount     = $params.Count
    $fThickness = $params.Thickness
    $fColor     = $params.Color
    $fBeep      = $params.Beep
    $forms = @()
    foreach ($screen in [System.Windows.Forms.Screen]::AllScreens) {
        $form = New-Object System.Windows.Forms.Form
        $form.FormBorderStyle = 'None'
        $form.TopMost         = $true
        $form.BackColor       = [System.Drawing.Color]::Lime
        $form.TransparencyKey = [System.Drawing.Color]::Lime
        $form.ShowInTaskbar   = $false
        $form.Bounds          = $screen.Bounds
        $form.Tag = @{
            ScreenBounds = $screen.Bounds
            Color        = $fColor
            Thickness    = $fThickness
        }
        $form.Add_Paint({
            param($s, $e)
            $tag  = $s.Tag
            $g    = $e.Graphics
            $t    = $tag.Thickness
            $pen  = New-Object System.Drawing.Pen($tag.Color, $t)
            $rect = [System.Drawing.Rectangle]::new(
                [int]($t / 2),
                [int]($t / 2),
                $tag.ScreenBounds.Width  - $t,
                $tag.ScreenBounds.Height - $t
            )
            $g.DrawRectangle($pen, $rect)
            $pen.Dispose()
        })
        $form.Show()
        $forms += $form
    }
    for ($i = 0; $i -lt $fCount; $i++) {
        if ($fBeep) { [Console]::Beep(1000, 100) }
        foreach ($f in $forms) { $f.Opacity = 1.0; $f.Refresh() }
        Start-Sleep -Milliseconds 300
        foreach ($f in $forms) { $f.Opacity = 0.0; $f.Refresh() }
        Start-Sleep -Milliseconds 200
    }
    foreach ($f in $forms) { $f.Close(); $f.Dispose() }
}
function Start-Break {
    param([string]$Source = "unknown")

    $breakStart = Get-Date
    Write-BreakLog "break_started" "Via $Source"

    $breakDialog = New-Object System.Windows.Forms.Form
    $breakDialog.Text            = "On Break"
    $breakDialog.Size            = New-Object System.Drawing.Size(320, 170)
    $breakDialog.StartPosition   = 'CenterScreen'
    $breakDialog.TopMost         = $true
    $breakDialog.FormBorderStyle = 'FixedDialog'
    $breakDialog.MaximizeBox     = $false
    $breakDialog.MinimizeBox     = $false

    $timerLabel = New-Object System.Windows.Forms.Label
    $timerLabel.Text     = "Break in progress...  0:00"
    $timerLabel.Location = New-Object System.Drawing.Point(20, 20)
    $timerLabel.Size     = New-Object System.Drawing.Size(270, 30)
    $timerLabel.Font     = New-Object System.Drawing.Font("Segoe UI", 11)

    $btnEnd = New-Object System.Windows.Forms.Button
    $btnEnd.Text     = "Break ended"
    $btnEnd.Location = New-Object System.Drawing.Point(90, 70)
    $btnEnd.Size     = New-Object System.Drawing.Size(130, 40)
    $btnEnd.Font     = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)

    $ticker = New-Object System.Windows.Forms.Timer
    $ticker.Interval = 1000
    $ticker.Tag      = $breakStart
    $ticker.Add_Tick({
        $elapsed = (Get-Date) - $ticker.Tag
        $mins = [math]::Floor($elapsed.TotalMinutes)
        $secs = $elapsed.Seconds.ToString("00")
        $timerLabel.Text = "Break in progress...  ${mins}:${secs}"
    })
    $ticker.Start()

    $btnEnd.Add_Click({
        $ticker.Stop()
        $ticker.Dispose()
        $breakDialog.Close()
    })

    $breakDialog.Add_FormClosing({
        $ticker.Stop()
        $ticker.Dispose()
    })

    $breakDialog.Controls.AddRange(@($timerLabel, $btnEnd))
    $breakDialog.ShowDialog() | Out-Null

    $breakEnd  = Get-Date
    $duration  = $breakEnd - $breakStart
    $durMins   = [math]::Round($duration.TotalMinutes, 1)

    Write-BreakLog "break_ended" "Duration: $durMins min (via $Source)"

    $script:nextBreakTime = (Get-Date).AddMinutes($breakEveryMinutes)
    $script:snoozeStreak  = 0

    $trayIcon.ShowBalloonTip(
        2000,
        "Break Reminder",
        "Break lasted $durMins min. Next break in $breakEveryMinutes min.",
        [System.Windows.Forms.ToolTipIcon]::Info
    )
}
function Show-BreakDialog {
    param([int]$minutesWorked)
    $streakNote = ""
    if ($script:snoozeStreak -ge 2) {
        $streakNote = "`nYou've snoozed $($script:snoozeStreak) times in a row - take a break!"
    }
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text            = "Break Reminder"
    $dialog.Size            = New-Object System.Drawing.Size(470, 180)
    $dialog.StartPosition   = 'CenterScreen'
    $dialog.TopMost         = $true
    $dialog.FormBorderStyle = 'FixedDialog'
    $dialog.MaximizeBox     = $false
    $dialog.MinimizeBox     = $false
    $label = New-Object System.Windows.Forms.Label
    $label.Text      = "Time for a break!`nYou've been working for $minutesWorked minutes.$streakNote"
    $label.Location  = New-Object System.Drawing.Point(20, 15)
    $label.Size      = New-Object System.Drawing.Size(430, 55)
    $label.Font      = New-Object System.Drawing.Font("Segoe UI", 10)

    $btnStartBreak = New-Object System.Windows.Forms.Button
    $btnStartBreak.Text     = "Start break now"
    $btnStartBreak.Location = New-Object System.Drawing.Point(20, 80)
    $btnStartBreak.Size     = New-Object System.Drawing.Size(110, 35)
    $btnStartBreak.Font     = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)

    $btnBreak = New-Object System.Windows.Forms.Button
    $btnBreak.Text     = "Break taken"
    $btnBreak.Location = New-Object System.Drawing.Point(140, 80)
    $btnBreak.Size     = New-Object System.Drawing.Size(90, 35)
    $btnBreak.Font     = New-Object System.Drawing.Font("Segoe UI", 9)

    $btn5 = New-Object System.Windows.Forms.Button
    $btn5.Text     = "Remind in 5 min"
    $btn5.Location = New-Object System.Drawing.Point(240, 80)
    $btn5.Size     = New-Object System.Drawing.Size(95, 35)
    $btn5.Font     = New-Object System.Drawing.Font("Segoe UI", 9)

    $btn10 = New-Object System.Windows.Forms.Button
    $btn10.Text     = "Remind in 10 min"
    $btn10.Location = New-Object System.Drawing.Point(345, 80)
    $btn10.Size     = New-Object System.Drawing.Size(105, 35)
    $btn10.Font     = New-Object System.Drawing.Font("Segoe UI", 9)

    $script:dialogResult = "break"
    $btnStartBreak.Add_Click({ $script:dialogResult = "startbreak"; $dialog.Close() })
    $btnBreak.Add_Click({      $script:dialogResult = "break";      $dialog.Close() })
    $btn5.Add_Click({          $script:dialogResult = "snooze5";    $dialog.Close() })
    $btn10.Add_Click({         $script:dialogResult = "snooze10";   $dialog.Close() })

    $dialog.Controls.AddRange(@($label, $btnStartBreak, $btnBreak, $btn5, $btn10))
    $dialog.ShowDialog() | Out-Null
    return $script:dialogResult
}
function Show-DailySummary {
    $today = (Get-Date).ToString("yyyy-MM-dd")
    $breaks      = 0
    $snoozes     = 0
    $manuals     = 0
    $timedBreaks = 0
    $durations   = @()

    if (Test-Path $logFilePath) {
        $lines = Get-Content $logFilePath | Select-Object -Skip 1
        foreach ($line in $lines) {
            if ($line -match "^$today") {
                if ($line -match ",break_taken,")  { $breaks++  }
                if ($line -match ",break_manual,") { $manuals++ }
                if ($line -match ",snooze,")       { $snoozes++ }
                if ($line -match ",break_ended,.*Duration:\s*([\d.]+)\s*min") {
                    $timedBreaks++
                    $durations += [double]$Matches[1]
                }
            }
        }
    }

    $totalBreaks   = $breaks + $manuals + $timedBreaks
    $expectedSlots = [math]::Floor(((Get-Date) - (Get-Date).Date).TotalMinutes / $breakEveryMinutes)
    if ($expectedSlots -lt 1) { $expectedSlots = 1 }

    $sep = "------------------------------"
    $msg  = "Today's Break Summary`n"
    $msg += "$sep`n"
    $msg += "Breaks taken:        $totalBreaks / $expectedSlots expected`n"
    $msg += "  via dialog:        $breaks`n"
    $msg += "  via tray menu:     $manuals`n"
    $msg += "  timed breaks:      $timedBreaks`n"
    $msg += "Snoozes:             $snoozes`n"

    if ($timedBreaks -gt 0) {
        $totalMin   = [math]::Round(($durations | Measure-Object -Sum).Sum, 1)
        $avgMin     = [math]::Round($totalMin / $timedBreaks, 1)
        $minMin     = [math]::Round(($durations | Measure-Object -Minimum).Minimum, 1)
        $maxMin     = [math]::Round(($durations | Measure-Object -Maximum).Maximum, 1)
        $msg += "$sep`n"
        $msg += "Total break time:    $totalMin min`n"
        $msg += "Average break:       $avgMin min`n"
        $msg += "Shortest break:      $minMin min`n"
        $msg += "Longest break:       $maxMin min`n"
    }

    $msg += "$sep`n"
    if ($snoozes -eq 0 -and $totalBreaks -ge $expectedSlots) {
        $msg += "Perfect day so far!"
    } elseif ($snoozes -gt $totalBreaks) {
        $msg += "You're snoozing a lot - try to take real breaks."
    } else {
        $msg += "Keep it up!"
    }

    $summaryDialog = New-Object System.Windows.Forms.Form
    $summaryDialog.Text            = "Break Reminder - Daily Summary"
    $summaryDialog.Size            = New-Object System.Drawing.Size(360, 310)
    $summaryDialog.StartPosition   = 'CenterScreen'
    $summaryDialog.TopMost         = $true
    $summaryDialog.FormBorderStyle = 'FixedDialog'
    $summaryDialog.MaximizeBox     = $false
    $summaryDialog.MinimizeBox     = $false

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text     = $msg
    $lbl.Location = New-Object System.Drawing.Point(20, 15)
    $lbl.Size     = New-Object System.Drawing.Size(320, 210)
    $lbl.Font     = New-Object System.Drawing.Font("Consolas", 9.5)

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text     = "OK"
    $btnOk.Location = New-Object System.Drawing.Point(140, 230)
    $btnOk.Size     = New-Object System.Drawing.Size(70, 30)
    $btnOk.Add_Click({ $summaryDialog.Close() })

    $summaryDialog.Controls.AddRange(@($lbl, $btnOk))
    $summaryDialog.ShowDialog() | Out-Null
}
# ===================== MAIN LOOP =====================
Write-BreakLog "session_start" "Break every $breakEveryMinutes min"
while (-not $script:shouldStop) {
    while ((Get-Date) -lt $script:nextBreakTime -and -not $script:shouldStop) {
        Start-Sleep -Seconds 1
        Update-TrayTooltip
        [System.Windows.Forms.Application]::DoEvents()
    }
    if ($script:shouldStop) { break }
    Flash-Screen
    $response = Show-BreakDialog -minutesWorked $breakEveryMinutes
    switch ($response) {
        "startbreak" {
            Start-Break -Source "dialog"
        }
        "break" {
            $script:nextBreakTime = (Get-Date).AddMinutes($breakEveryMinutes)
            $script:snoozeStreak  = 0
            Write-BreakLog "break_taken" "Via dialog"
        }
        "snooze5" {
            $script:nextBreakTime = (Get-Date).AddMinutes(5)
            $script:snoozeStreak++
            Write-BreakLog "snooze" "5 min (streak: $($script:snoozeStreak))"
        }
        "snooze10" {
            $script:nextBreakTime = (Get-Date).AddMinutes(10)
            $script:snoozeStreak++
            Write-BreakLog "snooze" "10 min (streak: $($script:snoozeStreak))"
        }
    }
}
# Clean exit
$trayIcon.Visible = $false
$trayIcon.Dispose()
exit
