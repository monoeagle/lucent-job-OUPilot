# run-docs.ps1 — OUPilot-Doku-Site (zensical). Windows-Wrapper fuer dieselbe
# Pipeline wie OUPilot-docs\run_OUPilot_docs.sh: bootstrappt ein eigenes
# .venv-docs, installiert zensical und baut/serviert die Site.
#
#   .\run-docs.ps1            baut die Site und oeffnet sie im Browser
#   .\run-docs.ps1 -Serve     lokaler Server auf http://127.0.0.1:8047
#   .\run-docs.ps1 -Serve -Port 9000
#   .\run-docs.ps1 -NoOpen    nur bauen (kein Browser)
param(
    [switch]$Serve,
    [int]$Port = 8047,
    [switch]$NoOpen
)
$ErrorActionPreference = 'Stop'
$here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$docs    = Join-Path $here 'OUPilot-docs'
$venv    = Join-Path $docs '.venv-docs'
$venvPy  = Join-Path $venv 'Scripts\python.exe'

# Python finden (py-Launcher bevorzugt).
function Get-Python {
    foreach ($c in @('py -3.14', 'py -3', 'python')) {
        $exe, $arg = $c.Split(' ', 2)
        if (Get-Command $exe -ErrorAction SilentlyContinue) { return @($exe, $arg) }
    }
    throw 'Kein Python gefunden (py/python). Bitte Python 3 installieren.'
}

# .venv-docs anlegen.
if (-not (Test-Path $venvPy)) {
    Write-Host '  > Erstelle .venv-docs ...' -ForegroundColor Cyan
    $py = Get-Python
    if ($py[1]) { & $py[0] $py[1] -m venv $venv } else { & $py[0] -m venv $venv }
}

# Zensical sicherstellen.
& $venvPy -m pip show zensical *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host '  > Installiere Zensical ...' -ForegroundColor Cyan
    & $venvPy -m pip install --quiet --upgrade pip
    & $venvPy -m pip install --quiet zensical
}
$zv = (& $venvPy -m zensical --version 2>$null | Select-Object -First 1)
Write-Host "  Zensical: $zv" -ForegroundColor Green

$build = Join-Path $docs 'build_docs.py'
if ($Serve) {
    Write-Host "  Live-Server auf http://127.0.0.1:$Port  (Strg+C zum Beenden)" -ForegroundColor Cyan
    if (-not $NoOpen) { Start-Process "http://127.0.0.1:$Port" }
    & $venvPy $build --serve --port $Port
} else {
    & $venvPy $build
    $index = Join-Path $docs 'site\index.html'
    if (Test-Path $index) {
        Write-Host "  Fertig: $index"
        if (-not $NoOpen) { Start-Process $index }
    }
}
