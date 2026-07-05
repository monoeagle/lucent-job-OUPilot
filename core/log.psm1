# core/log.psm1 — Zentrales Logging für OUPilot
# Schreibt zeilenweise nach Logs/oupilot.log (UTF-8, append-only).
# Konvention wie CodeSigningCommander: niemals werfen, immer sanft degradieren.

$script:OupLogPath = $null

function Initialize-OupLog {
    <#
        .SYNOPSIS  Legt den Logordner an und merkt sich den Pfad.
        .PARAMETER AppRoot  Wurzelverzeichnis der App (wo main.ps1 liegt).
    #>
    param([Parameter(Mandatory)][string]$AppRoot)

    $logDir = Join-Path $AppRoot 'Logs'
    if (-not (Test-Path $logDir)) {
        [void](New-Item -ItemType Directory -Path $logDir -Force)
    }
    $script:OupLogPath = Join-Path $logDir 'oupilot.log'
}

function Write-OupLog {
    <#
        .SYNOPSIS  Schreibt eine Logzeile mit Zeitstempel und Level.
        .PARAMETER Message  Klartext.
        .PARAMETER Level    INFO | WARN | ERROR | DEBUG.
    #>
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')][string]$Level = 'INFO'
    )

    $ts   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "$ts  [$Level]  $Message"

    # Konsole (sichtbar beim Start aus run.ps1)
    switch ($Level) {
        'ERROR' { Write-Host $line -ForegroundColor Red }
        'WARN'  { Write-Host $line -ForegroundColor Yellow }
        'DEBUG' { Write-Host $line -ForegroundColor DarkGray }
        default { Write-Host $line -ForegroundColor Gray }
    }

    if ($script:OupLogPath) {
        try { Add-Content -Path $script:OupLogPath -Value $line -Encoding UTF8 } catch { }
    }
}

Export-ModuleMember -Function Initialize-OupLog, Write-OupLog
