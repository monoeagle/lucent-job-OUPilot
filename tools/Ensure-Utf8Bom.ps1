# tools/Ensure-Utf8Bom.ps1 — Stellt sicher, dass alle PowerShell-Quelldateien
# als UTF-8 MIT BOM gespeichert sind (Pflicht für Windows PowerShell 5.1) und
# prüft sie anschließend mit dem Parser.
#
# Hintergrund: Ohne BOM liest PS 5.1 die Datei als ANSI (Windows-1252), wodurch
# Multi-Byte-UTF-8-Zeichen (z. B. „—") zu Anführungszeichen zerfallen und der
# Parser scheitert. Nach jedem Editieren ausführen:  .\tools\Ensure-Utf8Bom.ps1

$root  = Split-Path -Parent $PSScriptRoot
$files = Get-ChildItem -Path $root -Recurse -Include *.ps1, *.psm1 -File |
    Where-Object { $_.FullName -notmatch '\\samples\\' }

$utf8bom = New-Object System.Text.UTF8Encoding($true)
$bad     = 0

foreach ($f in $files) {
    $text = [System.IO.File]::ReadAllText($f.FullName)   # vorhandenes UTF-8 wird korrekt dekodiert
    [System.IO.File]::WriteAllText($f.FullName, $text, $utf8bom)

    $t = $null; $e = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$t, [ref]$e)
    if ($e -and $e.Count) {
        $bad++
        Write-Host ("FAIL {0}: {1} @L{2}" -f $f.Name, $e[0].Message, $e[0].Extent.StartLineNumber) -ForegroundColor Red
    } else {
        Write-Host ("OK   {0}" -f $f.Name) -ForegroundColor Green
    }
}

Write-Host ("`n{0} Datei(en) geprüft, {1} mit Parserfehlern." -f $files.Count, $bad)
if ($bad -gt 0) { exit 1 }
