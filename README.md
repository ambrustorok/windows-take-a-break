# Break Reminder for Windows

A lightweight PowerShell script that reminds you to take breaks by flashing a red border on all your screens. No installation, no admin rights required.

## Features

- **Screen flash** - red border flashes on all connected monitors
- **Configurable** - break interval, flash count, border thickness, and color
- **Snooze** - "Remind me in 5 min" / "Remind me in 10 min" options
- **System tray icon** - right-click to stop the reminder
- **No admin required** - runs entirely in user space
- **No dependencies** - just PowerShell and Windows Forms (built into Windows)

## Quick Start

**Option A:** Right-click `break_reminder.ps1` -> **Run with PowerShell**

**Option B:** Double-click `break_reminder_launcher.cmd` (runs hidden in the background)

You will get a break reminder every 45 minutes.

To stop it, click the **^** arrow in the system tray (bottom right), find the info icon, right-click -> **Stop Reminders**.

## Configuration

Edit the top of `break_reminder.ps1`:

```powershell
$breakEveryMinutes  = 45    # How often to remind you to take a break
$flashCount         = 4     # How many times the border flashes
$borderThickness    = 25    # Thickness of the flash border in pixels
$flashColor         = [System.Drawing.Color]::Red  # Flash color
```

## How It Works

- A hidden PowerShell process sleeps for the configured interval
- When the timer fires, a transparent full-screen overlay draws a colored border on every monitor
- The border flashes on/off several times
- A dialog appears with three options:
  - **Break taken** - resets the full timer
  - **Remind in 5 min** - snoozes for 5 minutes
  - **Remind in 10 min** - snoozes for 10 minutes
- The timer does not reset until you acknowledge the break

## Auto-Start on Login

1. Press `Win+R` -> type `shell:startup` -> press Enter
2. The Startup folder opens
3. Right-click inside the folder -> **New** -> **Shortcut**
4. Browse to `break_reminder_launcher.cmd` and select it
5. Name it `Break Reminder` -> Finish

The reminder will now launch automatically every time you log in.

## Files

| File | Purpose |
|---|---|
| `break_reminder.ps1` | Main script |
| `break_reminder_launcher.cmd` | Launcher - runs the script with a hidden window |

## Requirements

- Windows 10 / 11
- PowerShell 5.1+ (pre-installed on Windows)
- No admin rights needed

## License

MIT
