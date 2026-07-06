# core/dsm-import.psm1 — Verarbeitet DSM-Export-Dateien (eine JSON-Datei je
# DSM-Gruppe nach int_jsonStructure.md, SchemaVersion 1.0) zu einem Import-Plan:
# jedes Gruppenmitglied wird für jede relevante Policy-Zuweisung der AD-Gruppe
# <RBSSt>-<App>-<Endung> zugeordnet (Endungen: Policy, Job, Policy-Available,
# Job-Available). Deny-/deaktivierte/abgelaufene Policies, fehlende Mappings
# und fehlende Zielgruppen werden NICHT einsortiert, sondern als Report-Zeilen
# geliefert. UI-frei; Spec: docs/superpowers/specs/2026-07-06-dsm-export-import-design.md
#
# Pipeline:  Read-OupDsmGroupFile -> Resolve-OupDsmAssignments -> New-OupDsmImportPlan
# Report-Zeile: @{ Datei; Ebene (Datei|Mitglied|Policy|Gruppe); Betroffen; Grund; Detail }

$script:OupDsmSchemaVersion = '1.0'

function _Oup-DsmRow {
    param([string]$Datei, [string]$Ebene, [string]$Betroffen, [string]$Grund, [string]$Detail = '')
    return [PSCustomObject]@{ Datei = $Datei; Ebene = $Ebene; Betroffen = $Betroffen; Grund = $Grund; Detail = $Detail }
}

function _Oup-DsmRejected {
    <#  .SYNOPSIS  Einheitliches Ergebnisobjekt für abgelehnte Dateien.  #>
    param([string]$File, [object[]]$Rows)
    return [PSCustomObject]@{
        File = $File; Rejected = $true
        Rbsst = $null; GroupName = $null; MembershipType = $null
        Members = @(); Assignments = @(); ReportRows = @($Rows)
    }
}

function Read-OupDsmGroupFile {
    <#
        .SYNOPSIS  Liest eine DSM-Exportdatei: JSON, SchemaVersion, Validation-Gate,
                   Computer-Mitglieder (Nicht-Computer -> Report-Zeile).
        .OUTPUTS   PSCustomObject @{ File; Rejected; Rbsst; GroupName; MembershipType;
                   Members; Assignments; ReportRows }
    #>
    param([Parameter(Mandatory)][string]$Path)

    $file = Split-Path -Leaf $Path
    $rows = New-Object System.Collections.Generic.List[object]

    try {
        $data = Get-Content $Path -Raw | ConvertFrom-Json
    } catch {
        $rows.Add((_Oup-DsmRow $file 'Datei' $file 'Ungueltiges JSON' $_.Exception.Message))
        return (_Oup-DsmRejected -File $file -Rows $rows.ToArray())
    }

    # Gate: SchemaVersion, Validation, Pflichtfelder — erster Treffer lehnt ab.
    $reject = $null
    if ("$($data.SchemaVersion)" -ne $script:OupDsmSchemaVersion) {
        $reject = "SchemaVersion '$($data.SchemaVersion)' wird nicht unterstuetzt (erwartet $($script:OupDsmSchemaVersion))"
    } elseif (-not $data.Validation) {
        $reject = 'Validation-Block fehlt'
    } elseif (-not $data.Validation.IsValidForMigration) {
        $reject = 'IsValidForMigration = false'
    } elseif (@($data.Validation.Errors | Where-Object { $_ }).Count -gt 0) {
        $reject = 'Validation-Errors: ' + (@($data.Validation.Errors) -join ' | ')
    } elseif (-not $data.DSMGroup -or -not $data.DSMGroup.RBSSt) {
        $reject = 'DSMGroup.RBSSt fehlt'
    } elseif (-not $data.Membership) {
        $reject = 'Membership-Block fehlt'
    }
    if ($reject) {
        $rows.Add((_Oup-DsmRow $file 'Datei' "$($data.DSMGroup.Name)" 'Datei abgelehnt' $reject))
        return (_Oup-DsmRejected -File $file -Rows $rows.ToArray())
    }

    # Export-Warnungen informativ übernehmen; verarbeitet wird trotzdem.
    foreach ($w in @($data.Validation.Warnings | Where-Object { $_ })) {
        $rows.Add((_Oup-DsmRow $file 'Datei' "$($data.DSMGroup.Name)" 'Export-Warnung' "$w"))
    }
    if ("$($data.Membership.MembershipType)" -ieq 'Dynamic') {
        $rows.Add((_Oup-DsmRow $file 'Datei' "$($data.DSMGroup.Name)" 'Dynamische Gruppe' 'Mitglieder = aufgeloester Snapshot zum Exportzeitpunkt'))
    }

    # Mitglieder: nur Computer werden einsortiert (Eintragsform wie import-engine).
    $members = New-Object System.Collections.Generic.List[object]
    foreach ($m in @($data.Membership.Members)) {
        if (-not $m) { continue }
        if ("$($m.SchemaTag)" -ine 'Computer') {
            $rows.Add((_Oup-DsmRow $file 'Mitglied' "$($m.Name)" 'Kein Computer-Objekt' "SchemaTag=$($m.SchemaTag)"))
            continue
        }
        if (-not $m.Name) { continue }
        $members.Add([PSCustomObject]@{
            importedAt = (Get-Date -Format 'o'); sourceFile = $file
            type = 'computer'; identifier = "$($m.Name)"; raw = $m
        })
    }

    return [PSCustomObject]@{
        File = $file; Rejected = $false
        Rbsst = "$($data.DSMGroup.RBSSt)"; GroupName = "$($data.DSMGroup.Name)"
        MembershipType = "$($data.Membership.MembershipType)"
        Members = $members.ToArray()
        Assignments = @($data.PolicyAssignments | Where-Object { $_ })
        ReportRows = $rows.ToArray()
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Namensbrücke: dsm-mapping.json (App-Root) — DSM-Paketname -> AD-App-Name.
# Ohne Eintrag wird eine Software NICHT einsortiert (Report), kein Fuzzy-Match.
# ─────────────────────────────────────────────────────────────────────────────
function Get-OupDsmMappingPath {
    <#  .SYNOPSIS  Effektiver Pfad zur DSM-Mapping-Datei (Default: <AppRoot>\dsm-mapping.json).  #>
    param([string]$ConfiguredPath, [Parameter(Mandatory)][string]$AppRoot)
    if ($ConfiguredPath) { return $ConfiguredPath }
    return "$AppRoot\dsm-mapping.json"
}

function Import-OupDsmMapping {
    <#  .SYNOPSIS  Lädt dsm-mapping.json als Hashtable (Key lowercase) — $null, wenn fehlt/unlesbar.  #>
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    try {
        $cfg = Get-Content $Path -Raw | ConvertFrom-Json
    } catch {
        if (Get-Command Write-OupLog -ErrorAction SilentlyContinue) {
            Write-OupLog "dsm-mapping.json unlesbar: $($_.Exception.Message)" 'WARN'
        }
        return $null
    }
    $map = @{}
    if ($cfg.Software) {
        foreach ($p in $cfg.Software.PSObject.Properties) {
            if ($p.Name -and $p.Value) { $map[$p.Name.ToLowerInvariant()] = "$($p.Value)" }
        }
    }
    return $map
}

function _Oup-DsmDate {
    <#  .SYNOPSIS  Parst einen Export-Zeitstempel (mit Offset/Z) — $null bei leer/unlesbar.  #>
    param($Value)
    if ($null -eq $Value -or "$Value" -eq '') { return $null }
    try { return [DateTimeOffset]::Parse("$Value", [System.Globalization.CultureInfo]::InvariantCulture) }
    catch { return $null }
}

function Resolve-OupDsmAssignments {
    <#
        .SYNOPSIS  Filtert die Policy-Zuweisungen einer Datei und bildet die
                   Zielgruppen-Namen <RBSSt>-<App>-<Endung>.
        .DESCRIPTION  Filterreihenfolge (Spec, erster Treffer -> Report-Zeile):
                      Deny -> deaktiviert -> NoDeployment -> abgelaufen ->
                      noch nicht aktiv -> unbekannter Modus -> unbekannter
                      Policy-Typ -> fehlendes Mapping. Danach Dedupe je Zielname.
        .OUTPUTS   PSCustomObject @{ Targets; ReportRows }
    #>
    param(
        [Parameter(Mandatory)]$FileResult,
        [Parameter(Mandatory)][hashtable]$Mapping,
        [Nullable[DateTimeOffset]]$Now
    )
    if ($null -eq $Now) { $Now = [DateTimeOffset]::Now }

    $file    = $FileResult.File
    $rows    = New-Object System.Collections.Generic.List[object]
    $targets = [ordered]@{}    # Zielname lowercase -> Target (Dedupe NACH Filterung)

    foreach ($pa in @($FileResult.Assignments)) {
        if (-not $pa -or -not $pa.Policy) { continue }
        $p    = $pa.Policy
        $sw   = $pa.Software
        $pn   = "$($p.PolicyName)"
        $swn  = "$($sw.Name)"
        $tag  = "$($p.PolicySchemaTag)"
        $mode = "$($pa.Assignment.AssignmentMode)"

        # 1) Deny wird bewusst nicht automatisiert (keine Deny-Gruppen im AD).
        if ($tag -ieq 'DenyPolicy') {
            $rows.Add((_Oup-DsmRow $file 'Policy' $pn 'Deny-Policy (nicht automatisiert)' "Software=$swn"))
            continue
        }
        # 2) deaktiviert
        if ((-not $p.IsActive) -or ($mode -ieq 'Disabled')) {
            $rows.Add((_Oup-DsmRow $file 'Policy' $pn 'Policy deaktiviert' "Software=$swn"))
            continue
        }
        # 3) keine Instanz-Erzeugung
        if ($mode -ieq 'NoDeployment') {
            $rows.Add((_Oup-DsmRow $file 'Policy' $pn 'Keine Instanz-Erzeugung' "Software=$swn"))
            continue
        }
        # 4/5) Aktivierungsfenster (steckt NICHT im AssignmentMode -> selbst prüfen).
        $end   = _Oup-DsmDate $p.ActivationEndDate
        $start = _Oup-DsmDate $p.ActivationStartDate
        if ($end -and $end -lt $Now) {
            $rows.Add((_Oup-DsmRow $file 'Policy' $pn 'Policy abgelaufen' "Ende=$($p.ActivationEndDate), Software=$swn"))
            continue
        }
        if ($start -and $start -gt $Now) {
            $rows.Add((_Oup-DsmRow $file 'Policy' $pn 'Policy noch nicht aktiv' "Start=$($p.ActivationStartDate), Software=$swn"))
            continue
        }
        # 6) Modus muss Required oder Available sein.
        if (@('Required', 'Available') -notcontains $mode) {
            $rows.Add((_Oup-DsmRow $file 'Policy' $pn "Unbekannter Zuweisungsmodus '$mode'" "Software=$swn"))
            continue
        }
        # Endung aus PolicySchemaTag x AssignmentMode (Spec-Namensschema).
        $suffix = $null
        if     ($tag -ieq 'SwPolicy'  -and $mode -ieq 'Required')  { $suffix = 'Policy' }
        elseif ($tag -ieq 'JobPolicy' -and $mode -ieq 'Required')  { $suffix = 'Job' }
        elseif ($tag -ieq 'SwPolicy'  -and $mode -ieq 'Available') { $suffix = 'Policy-Available' }
        elseif ($tag -ieq 'JobPolicy' -and $mode -ieq 'Available') { $suffix = 'Job-Available' }
        if (-not $suffix) {
            $rows.Add((_Oup-DsmRow $file 'Policy' $pn "Unbekannter Policy-Typ '$tag'" "Software=$swn"))
            continue
        }
        # 7) Namensbrücke: DSM-Paketname -> AD-App-Name.
        $app = $null
        if ($swn) { $app = $Mapping[$swn.ToLowerInvariant()] }
        if (-not $app) {
            $rows.Add((_Oup-DsmRow $file 'Policy' $pn 'Kein Mapping fuer DSM-Software' "Software=$swn"))
            continue
        }

        $name = "$($FileResult.Rbsst)-$app-$suffix"
        $key  = $name.ToLowerInvariant()
        if (-not $targets.Contains($key)) {
            $targets[$key] = [PSCustomObject]@{
                TargetName = $name; App = $app; Software = $swn
                Mode = $mode; PolicySchemaTag = $tag
            }
        }
    }

    return [PSCustomObject]@{ Targets = @($targets.Values); ReportRows = $rows.ToArray() }
}

Export-ModuleMember -Function Read-OupDsmGroupFile, Get-OupDsmMappingPath, Import-OupDsmMapping, `
    Resolve-OupDsmAssignments
