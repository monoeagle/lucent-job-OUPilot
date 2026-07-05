# run.ps1 — Launcher für OUPilot.
# Startet main.ps1 in Windows PowerShell 5.1 (Desktop, STA) mit -NoProfile.
# WPF benötigt die Desktop-Edition; pwsh (Core) wird hier bewusst nicht genutzt.

param(
    [switch]$Headless
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$main      = Join-Path $scriptDir 'main.ps1'

# Windows PowerShell 5.1 finden (Desktop-Edition für WPF).
$ps51 = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path $ps51)) { $ps51 = 'powershell.exe' }

$argList = @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', $main)
if ($Headless) { $argList += '-Headless' }

& $ps51 @argList
