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
$script:sessionStart        = Get-Date
$script:totalBreakSeconds   = 0
$script:totalMeetingSeconds = 0
$script:nextBreakTime       = (Get-Date).AddMinutes($breakEveryMinutes)
$script:snoozeStreak        = 0
$script:shouldStop          = $false
$script:lockTime            = $null

# -- Helper: format a TimeSpan as "Xh Ym" --
function Format-Duration {
    param([TimeSpan]$ts)
    $h = [math]::Floor($ts.TotalHours)
    $m = $ts.Minutes
    if ($h -gt 0) { return "{0}h {1}m" -f $h, $m }
    return "{0}m" -f $m
}

# ===================== SESSION LOCK/UNLOCK HOOK =====================
$sessionSwitchHandler = [Microsoft.Win32.SessionSwitchEventHandler]{
    param($sender, $e)
    switch ($e.Reason) {
        'SessionLock' {
            $script:lockTime = Get-Date
            Write-BreakLog "screen_locked" ""
        }
        'SessionUnlock' {
            if ($script:lockTime) {
                $unlockTime  = Get-Date
                $awaySeconds = ($unlockTime - $script:lockTime).TotalSeconds
                $awayMins    = [math]::Round($awaySeconds / 60, 1)
                $lockTimeStr = $script:lockTime.ToString("HH:mm")
                Write-BreakLog "screen_unlocked" "Away $awayMins min (locked at $lockTimeStr)"

                # Only ask if away for more than 1 minute
                if ($awaySeconds -ge 60) {
                    $result = Show-AwayDialog -LockTime $script:lockTime -UnlockTime $unlockTime
                    switch ($result.Choice) {
                        "break" {
                            $script:totalBreakSeconds += $awaySeconds
                            $script:nextBreakTime = (Get-Date).AddMinutes($breakEveryMinutes)
                            $script:snoozeStreak  = 0
                            Write-BreakLog "away_break" "Full away time counted as break: $awayMins min"
                            $trayIcon.ShowBalloonTip(2000, "Break Reminder",
                                "Welcome back! $awayMins min counted as break. Next break in $breakEveryMinutes min.",
                                [System.Windows.Forms.ToolTipIcon]::Info)
                        }
                        "meeting" {
                            $script:totalMeetingSeconds += $awaySeconds
                            # Don't reset break timer — they still need a break
                            Write-BreakLog "away_meeting" "Away time counted as meeting: $awayMins min"
                            $trayIcon.ShowBalloonTip(2000, "Break Reminder",
                                "Welcome back! $awayMins min counted as meeting.",
                                [System.Windows.Forms.ToolTipIcon]::Info)
                        }
                        "both" {
                            $breakSec   = $result.BreakMinutes * 60
                            $meetingSec = $awaySeconds - $breakSec
                            if ($meetingSec -lt 0) { $meetingSec = 0 }
                            $script:totalBreakSeconds   += $breakSec
                            $script:totalMeetingSeconds += $meetingSec
                            $script:nextBreakTime = (Get-Date).AddMinutes($breakEveryMinutes)
                            $script:snoozeStreak  = 0
                            Write-BreakLog "away_both" ("Break: {0} min, Meeting: {1} min" -f
                                [math]::Round($breakSec/60,1), [math]::Round($meetingSec/60,1))
                            $trayIcon.ShowBalloonTip(2000, "Break Reminder",
                                "Welcome back! Split recorded. Next break in $breakEveryMinutes min.",
                                [System.Windows.Forms.ToolTipIcon]::Info)
                        }
                        "ignore" {
                            Write-BreakLog "away_ignored" "Away $awayMins min - user chose to ignore"
                        }
                    }
                }
                $script:lockTime = $null
            }
        }
    }
}

[Microsoft.Win32.SystemEvents]::add_SessionSwitch($sessionSwitchHandler)

# ===================== AWAY DIALOG =====================
function Show-AwayDialog {
    param(
        [DateTime]$LockTime,
        [DateTime]$UnlockTime
    )

    $awaySpan  = $UnlockTime - $LockTime
    $awayMins  = [math]::Round($awaySpan.TotalMinutes, 1)
    $awaySecs  = [math]::Round($awaySpan.TotalSeconds)
    $lockStr   = $LockTime.ToString("HH:mm")
    $unlockStr = $UnlockTime.ToString("HH:mm")

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text            = "Welcome Back"
    $dialog.Size            = New-Object System.Drawing.Size(430, 280)
    $dialog.StartPosition   = 'CenterScreen'
    $dialog.TopMost         = $true
    $dialog.FormBorderStyle = 'FixedDialog'
    $dialog.MaximizeBox     = $false
    $dialog.MinimizeBox     = $false

    $label = New-Object System.Windows.Forms.Label
    $label.Text     = "You were away for $awayMins minutes ($lockStr - $unlockStr).`nWhat were you doing?"
    $label.Location = New-Object System.Drawing.Point(20, 15)
    $label.Size     = New-Object System.Drawing.Size(390, 40)
    $label.Font     = New-Object System.Drawing.Font("Segoe UI", 10)

    $btnBreak = New-Object System.Windows.Forms.Button
    $btnBreak.Text     = "Break"
    $btnBreak.Location = New-Object System.Drawing.Point(20, 65)
    $btnBreak.Size     = New-Object System.Drawing.Size(120, 40)
    $btnBreak.Font     = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)

    $btnMeeting = New-Object System.Windows.Forms.Button
    $btnMeeting.Text     = "Meeting"
    $btnMeeting.Location = New-Object System.Drawing.Point(150, 65)
    $btnMeeting.Size     = New-Object System.Drawing.Size(120, 40)
    $btnMeeting.Font     = New-Object System.Drawing.Font("Segoe UI", 9)

    $btnIgnore = New-Object System.Windows.Forms.Button
    $btnIgnore.Text     = "Ignore"
    $btnIgnore.Location = New-Object System.Drawing.Point(280, 65)
    $btnIgnore.Size     = New-Object System.Drawing.Size(120, 40)
    $btnIgnore.Font     = New-Object System.Drawing.Font("Segoe UI", 9)

    # --- "Both" panel with slider ---
    $btnBoth = New-Object System.Windows.Forms.Button
    $btnBoth.Text     = "Both (split it)"
    $btnBoth.Location = New-Object System.Drawing.Point(20, 115)
    $btnBoth.Size     = New-Object System.Drawing.Size(120, 35)
    $btnBoth.Font     = New-Object System.Drawing.Font("Segoe UI", 9)

    # --- 50/50 button ---
    $btnFiftyFifty = New-Object System.Windows.Forms.Button
    $btnFiftyFifty.Text     = "50 / 50"
    $btnFiftyFifty.Location = New-Object System.Drawing.Point(150, 115)
    $btnFiftyFifty.Size     = New-Object System.Drawing.Size(80, 35)
    $btnFiftyFifty.Font     = New-Object System.Drawing.Font("Segoe UI", 9)
    $btnFiftyFifty.Visible  = $false

    $splitPanel = New-Object System.Windows.Forms.Panel
    $splitPanel.Location = New-Object System.Drawing.Point(20, 155)
    $splitPanel.Size     = New-Object System.Drawing.Size(380, 75)
    $splitPanel.Visible  = $false

    $splitLabel = New-Object System.Windows.Forms.Label
    $splitLabel.Location = New-Object System.Drawing.Point(0, 0)
    $splitLabel.Size     = New-Object System.Drawing.Size(380, 20)
    $splitLabel.Font     = New-Object System.Drawing.Font("Segoe UI", 9)

    # Slider works in seconds for precision
    $slider = New-Object System.Windows.Forms.TrackBar
    $slider.Location = New-Object System.Drawing.Point(0, 22)
    $slider.Size     = New-Object System.Drawing.Size(290, 30)
    $slider.Minimum  = 0
    $slider.Maximum  = $awaySecs
    $slider.Value    = [math]::Floor($awaySecs / 2)
    $slider.TickFrequency = [math]::Max(1, [math]::Floor($awaySecs / 20))

    $btnConfirmSplit = New-Object System.Windows.Forms.Button
    $btnConfirmSplit.Text     = "OK"
    $btnConfirmSplit.Location = New-Object System.Drawing.Point(300, 22)
    $btnConfirmSplit.Size     = New-Object System.Drawing.Size(70, 30)
    $btnConfirmSplit.Font     = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)

    $updateSplitLabel = {
        $brkMin = [math]::Round($slider.Value / 60, 1)
        $mtgMin = [math]::Round(($awaySecs - $slider.Value) / 60, 1)
        $splitLabel.Text = "Break: $brkMin min  |  Meeting: $mtgMin min"
    }
    & $updateSplitLabel

    $slider.Add_ValueChanged({ & $updateSplitLabel })

    $splitPanel.Controls.AddRange(@($splitLabel, $slider, $btnConfirmSplit))

    # Result tracking
    $script:awayResult = @{ Choice = "ignore"; BreakMinutes = 0 }

    $btnBreak.Add_Click({
        $script:awayResult = @{ Choice = "break"; BreakMinutes = 0 }
        $dialog.Close()
    })
    $btnMeeting.Add_Click({
        $script:awayResult = @{ Choice = "meeting"; BreakMinutes = 0 }
        $dialog.Close()
    })
    $btnIgnore.Add_Click({
        $script:awayResult = @{ Choice = "ignore"; BreakMinutes = 0 }
        $dialog.Close()
    })

    $btnBoth.Add_Click({
        $splitPanel.Visible    = $true
        $btnFiftyFifty.Visible = $true
        $dialog.Size = New-Object System.Drawing.Size(430, 310)
    })

    $btnFiftyFifty.Add_Click({
        $half = [math]::Round($awaySecs / 60 / 2, 1)
        $script:awayResult = @{ Choice = "both"; BreakMinutes = $half }
        $dialog.Close()
    })

    $btnConfirmSplit.Add_Click({
        $script:awayResult = @{ Choice = "both"; BreakMinutes = [math]::Round($slider.Value / 60, 1) }
        $dialog.Close()
    })

    $dialog.Controls.AddRange(@($label, $btnBreak, $btnMeeting, $btnIgnore, $btnBoth, $btnFiftyFifty, $splitPanel))
    $dialog.ShowDialog() | Out-Null

    return $script:awayResult
}

# -- System tray icon --
$trayIcon = New-Object System.Windows.Forms.NotifyIcon
$trayIcon.Icon    = [System.Drawing.SystemIcons]::Information
$trayIcon.Visible = $true

$contextMenu = New-Object System.Windows.Forms.ContextMenuStrip

# --- Status lines (disabled, just for display) ---
$statusItem = $contextMenu.Items.Add("...")
$statusItem.Enabled = $false
$statusItem.Font = New-Object System.Drawing.Font("Consolas", 9)

$timesItem = $contextMenu.Items.Add("...")
$timesItem.Enabled = $false
$timesItem.Font = New-Object System.Drawing.Font("Consolas", 9)

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
    [Microsoft.Win32.SystemEvents]::remove_SessionSwitch($sessionSwitchHandler)
    $trayIcon.Visible = $false
    $trayIcon.Dispose()
    [System.Environment]::Exit(0)
})

$trayIcon.ContextMenuStrip = $contextMenu

# Update the status lines every time the menu opens
$contextMenu.Add_Opening({
    # Line 1: next break countdown
    $remaining = $script:nextBreakTime - (Get-Date)
    if ($remaining.TotalSeconds -lt 0) { $remaining = [TimeSpan]::Zero }
    $minLeft = [math]::Floor($remaining.TotalMinutes)
    $secLeft = $remaining.Seconds
    $timeStr = $script:nextBreakTime.ToString("HH:mm")
    $statusItem.Text = "Next break: $timeStr  ($minLeft min $secLeft sec)"

    # Line 2: total / working / break
    $totalElapsed  = (Get-Date) - $script:sessionStart
    $breakSpan     = [TimeSpan]::FromSeconds($script:totalBreakSeconds)
    $meetingSpan   = [TimeSpan]::FromSeconds($script:totalMeetingSeconds)
    $workSpan      = $totalElapsed - $breakSpan - $meetingSpan
    if ($workSpan.TotalSeconds -lt 0) { $workSpan = [TimeSpan]::Zero }
    $timesItem.Text = "W:$(Format-Duration $workSpan) B:$(Format-Duration $breakSpan) M:$(Format-Duration $meetingSpan) T:$(Format-Duration $totalElapsed)"
})

# -- Helper functions --
function Update-TrayTooltip {
    $remaining = $script:nextBreakTime - (Get-Date)
    if ($remaining.TotalSeconds -lt 0) { $remaining = [TimeSpan]::Zero }
    $minLeft  = [math]::Floor($remaining.TotalMinutes)
    $secLeft  = $remaining.Seconds
    $timeStr  = $script:nextBreakTime.ToString("HH:mm")

    $totalElapsed = (Get-Date) - $script:sessionStart
    $breakSpan    = [TimeSpan]::FromSeconds($script:totalBreakSeconds)
    $workSpan     = $totalElapsed - $breakSpan - [TimeSpan]::FromSeconds($script:totalMeetingSeconds)
    if ($workSpan.TotalSeconds -lt 0) { $workSpan = [TimeSpan]::Zero }

    $tip = "Break at $timeStr (${minLeft}m ${secLeft}s)`nW:$(Format-Duration $workSpan) B:$(Format-Duration $breakSpan) T:$(Format-Duration $totalElapsed)"
    if ($tip.Length -gt 63) { $tip = $tip.Substring(0, 63) }
    $trayIcon.Text = $tip
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

    # Accumulate break time
    $script:totalBreakSeconds += $duration.TotalSeconds

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
    $awayBreaks  = 0
    $awayMeetings = 0
    $awayBoth    = 0
    $durations   = @()

    if (Test-Path $logFilePath) {
        $lines = Get-Content $logFilePath | Select-Object -Skip 1
        foreach ($line in $lines) {
            if ($line -match "^$today") {
                if ($line -match ",break_taken,")   { $breaks++   }
                if ($line -match ",break_manual,")  { $manuals++  }
                if ($line -match ",snooze,")        { $snoozes++  }
                if ($line -match ",away_break,")    { $awayBreaks++ }
                if ($line -match ",away_meeting,")  { $awayMeetings++ }
                if ($line -match ",away_both,")     { $awayBoth++ }
                if ($line -match ",break_ended,.*Duration:\s*([\d.]+)\s*min") {
                    $timedBreaks++
                    $durations += [double]$Matches[1]
                }
            }
        }
    }

    $totalBreaks   = $breaks + $manuals + $timedBreaks + $awayBreaks + $awayBoth
    $expectedSlots = [math]::Floor(((Get-Date) - (Get-Date).Date).TotalMinutes / $breakEveryMinutes)
    if ($expectedSlots -lt 1) { $expectedSlots = 1 }

    # Session time stats
    $totalElapsed  = (Get-Date) - $script:sessionStart
    $breakSpan     = [TimeSpan]::FromSeconds($script:totalBreakSeconds)
    $meetingSpan   = [TimeSpan]::FromSeconds($script:totalMeetingSeconds)
    $workSpan      = $totalElapsed - $breakSpan - $meetingSpan
    if ($workSpan.TotalSeconds -lt 0) { $workSpan = [TimeSpan]::Zero }

    $sep = "--------------------------------------"

    $msg  = "Today's Break Summary`n"
    $msg += "$sep`n"
    $msg += "Total time:          $(Format-Duration $totalElapsed)`n"
    $msg += "Working time:        $(Format-Duration $workSpan)`n"
    $msg += "Break time:          $(Format-Duration $breakSpan)`n"
    $msg += "Meeting time:        $(Format-Duration $meetingSpan)`n"
    $msg += "$sep`n"
    $msg += "Breaks taken:        $totalBreaks / $expectedSlots expected`n"
    $msg += "  via dialog:        $breaks`n"
    $msg += "  via tray menu:     $manuals`n"
    $msg += "  timed breaks:      $timedBreaks`n"
    $msg += "  away (lock):       $awayBreaks  (+$awayBoth split)`n"
    $msg += "Meetings (lock):     $awayMeetings  (+$awayBoth split)`n"
    $msg += "Snoozes:             $snoozes`n"

    if ($timedBreaks -gt 0) {
        $totalMin   = [math]::Round(($durations | Measure-Object -Sum).Sum, 1)
        $avgMin     = [math]::Round($totalMin / $timedBreaks, 1)
        $minMin     = [math]::Round(($durations | Measure-Object -Minimum).Minimum, 1)
        $maxMin     = [math]::Round(($durations | Measure-Object -Maximum).Maximum, 1)
        $msg += "$sep`n"
        $msg += "Total timed breaks:  $totalMin min`n"
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
    $summaryDialog.Size            = New-Object System.Drawing.Size(400, 400)
    $summaryDialog.StartPosition   = 'CenterScreen'
    $summaryDialog.TopMost         = $true
    $summaryDialog.FormBorderStyle = 'FixedDialog'
    $summaryDialog.MaximizeBox     = $false
    $summaryDialog.MinimizeBox     = $false

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text     = $msg
    $lbl.Location = New-Object System.Drawing.Point(20, 15)
    $lbl.Size     = New-Object System.Drawing.Size(360, 300)
    $lbl.Font     = New-Object System.Drawing.Font("Consolas", 9.5)

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text     = "OK"
    $btnOk.Location = New-Object System.Drawing.Point(160, 320)
    $btnOk.Size     = New-Object System.Drawing.Size(70, 30)
    $btnOk.Add_Click({ $summaryDialog.Close() })

    $summaryDialog.Controls.AddRange(@($lbl, $btnOk))
    $summaryDialog.ShowDialog() | Out-Null
}

# ===================== MAIN LOOP =====================
Write-BreakLog "session_start" "Break every $breakEveryMinutes min"

while (-not $script:shouldStop) {
    # Wait until next break time
    while ((Get-Date) -lt $script:nextBreakTime -and -not $script:shouldStop) {
        Start-Sleep -Seconds 1
        Update-TrayTooltip
        [System.Windows.Forms.Application]::DoEvents()
    }
    if ($script:shouldStop) { break }

    # -- Escalating flash loop --
    # Flash once, show dialog. If they snooze or ignore the dialog (close it),
    # wait reflashIntervalSec, then flash twice, show dialog again, etc.
    $flashRound = 1

    :reminderLoop while ($true) {
        Flash-Screen -FlashCount $flashRound

        $response = Show-BreakDialog -minutesWorked $breakEveryMinutes

        switch ($response) {
            "startbreak" {
                Start-Break -Source "dialog"
                break reminderLoop
            }
            "break" {
                $script:nextBreakTime = (Get-Date).AddMinutes($breakEveryMinutes)
                $script:snoozeStreak  = 0
                Write-BreakLog "break_taken" "Via dialog"
                break reminderLoop
            }
            "snooze5" {
                $script:nextBreakTime = (Get-Date).AddMinutes(5)
                $script:snoozeStreak++
                Write-BreakLog "snooze" "5 min (streak: $($script:snoozeStreak))"
                break reminderLoop
            }
            "snooze10" {
                $script:nextBreakTime = (Get-Date).AddMinutes(10)
                $script:snoozeStreak++
                Write-BreakLog "snooze" "10 min (streak: $($script:snoozeStreak))"
                break reminderLoop
            }
        }

        # If we get here, user closed the dialog without picking an option (X button)
        # Wait, then escalate
        Write-BreakLog "reminder_dismissed" "Round $flashRound - dialog closed without action"
        $flashRound++

        $waitEnd = (Get-Date).AddSeconds($reflashIntervalSec)
        while ((Get-Date) -lt $waitEnd -and -not $script:shouldStop) {
            Start-Sleep -Seconds 1
            Update-TrayTooltip
            [System.Windows.Forms.Application]::DoEvents()
        }
        if ($script:shouldStop) { break reminderLoop }
    }
}

# Clean exit
[Microsoft.Win32.SystemEvents]::remove_SessionSwitch($sessionSwitchHandler)
$trayIcon.Visible = $false
$trayIcon.Dispose()
exit
