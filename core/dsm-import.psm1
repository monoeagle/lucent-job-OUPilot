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

Export-ModuleMember -Function Read-OupDsmGroupFile
