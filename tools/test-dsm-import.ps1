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

# ── Mapping-Loader ──────────────────────────────────────────────────────────
$map = Import-OupDsmMapping -Path (Join-Path $samples 'dsm-mapping.example.json')
Assert ($null -ne $map) 'Mapping: Beispieldatei geladen'
Assert ($map.Count -eq 5) 'Mapping: 5 Eintraege'
Assert ($map['7-zip 24.09 x64'] -eq '7Zip') 'Mapping: Schluessel lowercase (case-insensitiv)'
Assert ($null -eq (Import-OupDsmMapping -Path (Join-Path $samples 'gibt-es-nicht.json'))) 'Mapping: fehlende Datei -> $null'
Assert ((Get-OupDsmMappingPath -ConfiguredPath '' -AppRoot 'C:\App') -eq 'C:\App\dsm-mapping.json') 'Mapping: Default-Pfad'
Assert ((Get-OupDsmMappingPath -ConfiguredPath 'D:\x.json' -AppRoot 'C:\App') -eq 'D:\x.json') 'Mapping: konfigurierter Pfad gewinnt'

# ── Resolve-OupDsmAssignments ───────────────────────────────────────────────
$now = [DateTimeOffset]::Parse('2026-07-06T12:00:00+02:00', [System.Globalization.CultureInfo]::InvariantCulture)

$r   = Read-OupDsmGroupFile -Path (Join-Path $samples 'RBSSt01_Clients_Basis.txt')
$res = Resolve-OupDsmAssignments -FileResult $r -Mapping $map -Now $now
$names = @($res.Targets | ForEach-Object { $_.TargetName })
Assert (@($res.Targets).Count -eq 3) 'Basis: 3 Ziele (7-Zip-Doppelzuweisung dedupliziert)'
Assert ($names -contains 'RBSSt01-ClientBasis-Policy') 'Basis: SwSet -> RBSSt01-ClientBasis-Policy'
Assert ($names -contains 'RBSSt01-7Zip-Policy') 'Basis: SwPolicy+Required -> RBSSt01-7Zip-Policy'
Assert ($names -contains 'RBSSt01-Firefox-Job') 'Basis: JobPolicy+Required -> RBSSt01-Firefox-Job'
Assert (@($res.ReportRows).Count -eq 0) 'Basis: keine Filter-Zeilen'

$r   = Read-OupDsmGroupFile -Path (Join-Path $samples 'RBSSt01_Clients_Fach_X.txt')
$res = Resolve-OupDsmAssignments -FileResult $r -Mapping $map -Now $now
Assert (@($res.Targets).Count -eq 1) 'FachX: 1 Ziel'
Assert ($res.Targets[0].TargetName -eq 'RBSSt01-Office-Policy-Available') 'FachX: SwPolicy+Available -> -Policy-Available'

$r   = Read-OupDsmGroupFile -Path (Join-Path $samples 'RBSSt01_Clients_Alt.txt')
$res = Resolve-OupDsmAssignments -FileResult $r -Mapping $map -Now $now
Assert (@($res.Targets).Count -eq 1) 'Alt: nur VLC bleibt uebrig'
Assert ($res.Targets[0].TargetName -eq 'RBSSt01-VLC-Policy') 'Alt: VLC -> RBSSt01-VLC-Policy'
$g = @($res.ReportRows | ForEach-Object { $_.Grund })
Assert ($g -contains 'Deny-Policy (nicht automatisiert)') 'Alt: Deny im Report'
Assert ($g -contains 'Policy deaktiviert') 'Alt: deaktiviert im Report'
Assert ($g -contains 'Keine Instanz-Erzeugung') 'Alt: NoDeployment im Report'
Assert ($g -contains 'Policy abgelaufen') 'Alt: abgelaufen im Report'
Assert ($g -contains 'Policy noch nicht aktiv') 'Alt: Zukunfts-Start im Report'
Assert ($g -contains 'Kein Mapping fuer DSM-Software') 'Alt: fehlendes Mapping im Report'
Assert (@($res.ReportRows).Count -eq 6) 'Alt: genau 6 Filter-Zeilen'

# ── Mock: DSM-Standort RBSSt01 ──────────────────────────────────────────────
Import-Module (Join-Path $root 'core/ad-reader.psm1') -Force -DisableNameChecking
$tree    = Get-OupAdTree -Mode Mock
$rbsst01 = @($tree.Roots[0].Children | Where-Object { $_.Name -eq 'RBSSt01' }) | Select-Object -First 1
Assert ($null -ne $rbsst01) 'Mock: Standort RBSSt01 vorhanden'
Assert (@($rbsst01.Children | Where-Object { $_.NodeType -eq 'Group' }).Count -eq 0) 'Mock: RBSSt01 ohne direkte Gruppen (Standort-Modus)'
$index = Get-OupGroupIndex -Roots @($rbsst01)
Assert ($index.ByName.Count -eq 7) 'Mock: 7 Gruppen unter RBSSt01'
Assert ($index.ByName.ContainsKey('rbsst01-office-policy-available')) 'Mock: Available-Gruppe vorhanden'
Assert ($index.ByName.ContainsKey('rbsst01-clientbasis-policy')) 'Mock: ClientBasis-Gruppe vorhanden'
Assert (-not $index.ByName.ContainsKey('rbsst01-vlc-policy')) 'Mock: VLC-Gruppe fehlt absichtlich'

# ── Ergebnis ────────────────────────────────────────────────────────────────
Write-Host ''
if ($script:fails -gt 0) { Write-Host "$script:fails Assertion(s) fehlgeschlagen." -ForegroundColor Red; exit 1 }
Write-Host 'Alle Tests gruen.' -ForegroundColor Green
