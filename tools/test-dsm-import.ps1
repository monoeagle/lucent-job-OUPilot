# tools/test-dsm-import.ps1 — Prüft das DSM-Import-Modul (core\dsm-import.psm1)
# gegen die Beispieldateien unter samples\. Läuft unter Windows PowerShell 5.1
# und pwsh 7:   pwsh -NoProfile -File tools/test-dsm-import.ps1
# Exit-Code 0 = alle Assertions grün.

$ErrorActionPreference = 'Stop'
$root    = Split-Path -Parent $PSScriptRoot
$samples = Join-Path $root 'samples'
Import-Module (Join-Path $root 'core/dsm-import.psm1') -Force -DisableNameChecking

$script:fails = 0
function Assert {
    param([bool]$Cond, [string]$Msg)
    if ($Cond) { Write-Host "OK   $Msg" -ForegroundColor Green }
    else       { $script:fails++; Write-Host "FAIL $Msg" -ForegroundColor Red }
}

# ── Read-OupDsmGroupFile ────────────────────────────────────────────────────
$r = Read-OupDsmGroupFile -Path (Join-Path $samples 'RBSSt01_Clients_Basis.txt')
Assert (-not $r.Rejected) 'Basis: nicht abgelehnt'
Assert ($r.Rbsst -eq 'RBSSt01') 'Basis: RBSSt erkannt'
Assert ($r.GroupName -eq 'Clients_Basis') 'Basis: Gruppenname erkannt'
Assert (@($r.Members).Count -eq 3) 'Basis: 3 Computer-Mitglieder'
Assert ($r.Members[0].identifier -eq 'PC-010001') 'Basis: identifier = DSM-Name'
Assert ($r.Members[0].type -eq 'computer') 'Basis: type = computer'
Assert (@($r.Assignments).Count -eq 4) 'Basis: 4 Policy-Zuweisungen durchgereicht'
Assert (@($r.ReportRows).Count -eq 0) 'Basis: keine Report-Zeilen'

$r = Read-OupDsmGroupFile -Path (Join-Path $samples 'RBSSt01_Clients_Fach_X.txt')
Assert (-not $r.Rejected) 'FachX: nicht abgelehnt'
Assert ($r.MembershipType -eq 'Dynamic') 'FachX: MembershipType Dynamic'
Assert (@($r.Members).Count -eq 2) 'FachX: 2 Snapshot-Mitglieder'
Assert (@($r.ReportRows | Where-Object { $_.Grund -eq 'Dynamische Gruppe' }).Count -eq 1) 'FachX: Dynamik-Hinweis'
Assert (@($r.ReportRows | Where-Object { $_.Grund -eq 'Export-Warnung' }).Count -eq 2) 'FachX: 2 Export-Warnungen uebernommen'

$r = Read-OupDsmGroupFile -Path (Join-Path $samples 'RBSSt01_Clients_Inventar.txt')
Assert (-not $r.Rejected) 'Inventar: nicht abgelehnt'
Assert (@($r.Members).Count -eq 2) 'Inventar: Nicht-Computer-Mitglied uebersprungen'
Assert (@($r.ReportRows | Where-Object { $_.Ebene -eq 'Mitglied' -and $_.Betroffen -eq 'Untergruppe_Inventar' }).Count -eq 1) 'Inventar: Mitglied-Report-Zeile'
Assert (@($r.Assignments).Count -eq 0) 'Inventar: keine Zuweisungen'

$r = Read-OupDsmGroupFile -Path (Join-Path $samples 'RBSSt01_Clients_Defekt.txt')
Assert ($r.Rejected) 'Defekt: abgelehnt (IsValidForMigration=false / Errors)'
Assert (@($r.ReportRows | Where-Object { $_.Ebene -eq 'Datei' -and $_.Grund -eq 'Datei abgelehnt' }).Count -eq 1) 'Defekt: Ablehnungszeile'

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) 'oup-dsm-kaputt.txt'
Set-Content -Path $tmp -Value '{ kein json' -Encoding UTF8
$r = Read-OupDsmGroupFile -Path $tmp
Assert ($r.Rejected) 'Kaputtes JSON: abgelehnt'
Assert (@($r.ReportRows | Where-Object { $_.Grund -eq 'Ungueltiges JSON' }).Count -eq 1) 'Kaputtes JSON: Report-Zeile'
Remove-Item $tmp -Force

# ── Ergebnis ────────────────────────────────────────────────────────────────
Write-Host ''
if ($script:fails -gt 0) { Write-Host "$script:fails Assertion(s) fehlgeschlagen." -ForegroundColor Red; exit 1 }
Write-Host 'Alle Tests gruen.' -ForegroundColor Green
