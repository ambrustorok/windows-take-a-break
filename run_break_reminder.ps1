$logFile = Join-Path $env:USERPROFILE "break_reminder_debug.log"

# Redirect ALL output (stdout, stderr, verbose, etc.) to the log file
Start-Transcript -Path $logFile -Force

try {
    Write-Host "Script starting at $(Get-Date)"
    
    # Dot-source or paste your full script path here:
    & "$env:USERPROFILE\break_reminder.ps1"
}
catch {
    Write-Host "CAUGHT ERROR: $_"
    Write-Host $_.ScriptStackTrace
}
finally {
    Write-Host "Script ended at $(Get-Date)"
    Stop-Transcript
}