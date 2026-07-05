# main.ps1 — Bootstrap für OUPilot (WPF auf PowerShell 5.1).
# Lädt Core-/UI-Module und öffnet das Hauptfenster. PS 5.1 Desktop läuft
# automatisch STA, daher ist WPF direkt nutzbar.

param(
    [switch]$Headless   # reserviert für späteren CLI-Modus
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "OUPilot · PowerShell $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))" -ForegroundColor DarkCyan

# ── Module laden (Reihenfolge: Log -> Settings/Store/AD/Import -> UI) ─────────
$modules = @(
    'core/log.psm1',
    'core/settings.psm1',
    'core/ad-reader.psm1',
    'core/ad-writer.psm1',
    'core/mapping-store.psm1',
    'core/import-engine.psm1',
    'ui/about-dialog.psm1',
    'ui/main-window.psm1'
)
foreach ($m in $modules) {
    Import-Module (Join-Path $scriptDir $m) -Force -DisableNameChecking
}

Initialize-OupLog -AppRoot $scriptDir
Write-OupLog "OUPilot gestartet (PS $($PSVersionTable.PSVersion))."

$configPath = Join-Path $scriptDir 'settings.json'

if ($Headless) {
    Write-OupLog "Headless-Modus ist noch nicht implementiert." 'WARN'
    exit 0
}

try {
    Show-OupMainWindow -AppRoot $scriptDir -ConfigPath $configPath
} catch {
    Write-OupLog "Fataler Fehler: $($_.Exception.Message) @ $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)" 'ERROR'
    throw
}

Write-OupLog "OUPilot beendet."
