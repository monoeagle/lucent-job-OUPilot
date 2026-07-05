# core/import-engine.psm1 — Liest die JSON-Exporte des Admins ein und
# normalisiert sie zu Importeinträgen.
#
# Die Exporte sind heterogen (mal Einzelrechner, mal Gruppen, mal Listen).
# Der Parser ist daher tolerant und über eine Feld-Map konfigurierbar:
#   - Top-Level-Array  von Strings           -> jeder String ist ein Identifier
#   - Top-Level-Array  von Objekten          -> Felder gemäß Map auslesen
#   - Objekt mit Listen-Property (items/...)  -> diese Liste verwenden
#
# Eigene Feldnamen für exotische Exporte kommen aus einer optionalen fieldmap.json
# (App-Root, Pfad via Settings-Key FieldMapPath überschreibbar). Sie ERWEITERT die
# eingebauten Kandidaten (custom zuerst -> gewinnt), dedupliziert case-insensitiv;
# angewendet beim Start via Set-OupFieldMap. Siehe samples\fieldmap.example.json.
#
# Normalisierter Eintrag:
#   { importedAt; sourceFile; type; identifier; raw }
#     type        'computer' | 'group' | 'user' | 'unknown'
#     identifier  stabiler Bezeichner (SID > GUID > sAMAccountName > Name)

# Feldnamen, in denen wir Werte suchen (erste Treffer gewinnt, case-insensitiv).
$script:OupFieldMap = @{
    Name       = @('name', 'cn', 'displayName', 'computerName', 'hostname', 'sAMAccountName')
    Sid        = @('sid', 'objectSid', 'SID')
    Guid       = @('guid', 'objectGUID', 'GUID')
    Dn         = @('distinguishedName', 'dn', 'DistinguishedName')
    Sam        = @('sAMAccountName', 'samAccountName', 'sam')
    ObjectType = @('objectClass', 'type', 'category', 'objectType')
}

function _Oup-FirstField {
    param($Obj, [string[]]$Candidates)
    foreach ($c in $Candidates) {
        $prop = $Obj.PSObject.Properties | Where-Object { $_.Name -ieq $c } | Select-Object -First 1
        if ($prop -and $null -ne $prop.Value -and "$($prop.Value)" -ne '') { return "$($prop.Value)" }
    }
    return $null
}

function _Oup-InferType {
    param([string]$ObjectType, [string]$Name, $Raw)
    if ($ObjectType) {
        $t = $ObjectType.ToLower()
        if ($t -match 'group')    { return 'group' }
        if ($t -match 'computer') { return 'computer' }
        if ($t -match 'user|person') { return 'user' }
    }
    if ($Name -and $Name.EndsWith('$')) { return 'computer' }
    if ($Raw -and (_Oup-FirstField $Raw @('dNSHostName', 'operatingSystem'))) { return 'computer' }
    return 'unknown'
}

function _Oup-NormalizeRecord {
    param($Obj, [string]$SourceFile)

    # String-Eintrag (reine Namensliste).
    if ($Obj -is [string]) {
        return [ordered]@{
            importedAt = (Get-Date -Format 'o'); sourceFile = $SourceFile
            type = 'computer'; identifier = $Obj; raw = $Obj
        }
    }

    $name = _Oup-FirstField $Obj $script:OupFieldMap.Name
    $sid  = _Oup-FirstField $Obj $script:OupFieldMap.Sid
    $guid = _Oup-FirstField $Obj $script:OupFieldMap.Guid
    $sam  = _Oup-FirstField $Obj $script:OupFieldMap.Sam
    $otype= _Oup-FirstField $Obj $script:OupFieldMap.ObjectType

    # Stabiler Identifier: SID > GUID > sAMAccountName > Name.
    $identifier = @($sid, $guid, $sam, $name | Where-Object { $_ }) | Select-Object -First 1

    return [ordered]@{
        importedAt = (Get-Date -Format 'o')
        sourceFile = $SourceFile
        type       = (_Oup-InferType -ObjectType $otype -Name $name -Raw $Obj)
        identifier = $identifier
        raw        = $Obj
    }
}

function Read-OupExportFile {
    <#
        .SYNOPSIS  Liest eine JSON-Exportdatei und liefert normalisierte Einträge.
        .OUTPUTS   PSCustomObject: @{ Entries; SourceFile; Error }
    #>
    param([Parameter(Mandatory)][string]$Path)

    $entries = New-Object System.Collections.Generic.List[object]
    try {
        $data = Get-Content $Path -Raw | ConvertFrom-Json
    } catch {
        return [PSCustomObject]@{ Entries = @(); SourceFile = $Path; Error = "Ungültiges JSON: $($_.Exception.Message)" }
    }

    $fileName = Split-Path -Leaf $Path

    # Wenn Top-Level kein Array ist, nach erster Array-Property suchen.
    $items = $null
    if ($data -is [System.Array]) {
        $items = $data
    } else {
        foreach ($p in $data.PSObject.Properties) {
            if ($p.Value -is [System.Array]) { $items = $p.Value; break }
        }
        # Einzelobjekt ohne Array -> als ein Eintrag behandeln.
        if ($null -eq $items) { $items = @($data) }
    }

    foreach ($it in $items) {
        $rec = _Oup-NormalizeRecord -Obj $it -SourceFile $fileName
        if ($rec.identifier) { $entries.Add([PSCustomObject]$rec) }
    }

    return [PSCustomObject]@{ Entries = $entries.ToArray(); SourceFile = $Path; Error = $null }
}

# ─────────────────────────────────────────────────────────────────────────────
# Sammelliste (Form B): pro Rechner stehen seine Zielgruppen im JSON. Das Tool
# verteilt jeden Rechner dann auf alle genannten Gruppen ("Einsortierung").
#
#   [ { "computer": "PC-0001$", "groups": ["StandortA-Office", "StandortA-7Zip"] },
#     { "computer": "PC-0002$", "groups": ["StandortA-Office"] } ]
#
# Erkannt wird die Form an einem Listen-Feld groups/gruppen/apps je Eintrag.
# ─────────────────────────────────────────────────────────────────────────────
$script:OupAssignGroupFields = @('groups', 'gruppen', 'apps', 'applications', 'memberOf')
$script:OupAssignCompFields  = @('computer', 'rechner', 'client', 'name', 'hostname', 'computerName', 'sAMAccountName')

function Read-OupAssignmentFile {
    <#
        .SYNOPSIS  Liest eine Rechner→Gruppen-Sammelliste.
        .OUTPUTS   PSCustomObject: @{ IsAssignment; Assignments; SourceFile; Error }
                   Assignment = @{ entry (normalisiert); groups (string[]) }.
                   IsAssignment=$false, wenn die Datei keine Zuordnung enthält.
    #>
    param([Parameter(Mandatory)][string]$Path)

    try {
        $data = Get-Content $Path -Raw | ConvertFrom-Json
    } catch {
        return [PSCustomObject]@{ IsAssignment = $false; Assignments = @(); SourceFile = $Path; Error = "Ungültiges JSON: $($_.Exception.Message)" }
    }

    $fileName = Split-Path -Leaf $Path
    $items = $null
    if ($data -is [System.Array]) { $items = $data }
    else {
        foreach ($p in $data.PSObject.Properties) { if ($p.Value -is [System.Array]) { $items = $p.Value; break } }
        if ($null -eq $items) { $items = @($data) }
    }

    $assignments     = New-Object System.Collections.Generic.List[object]
    $looksAssignment = $false

    foreach ($it in $items) {
        if ($it -is [string]) { continue }   # reine Namensliste -> keine Zuordnung

        # Gruppen-Feld (Array) suchen: groups/gruppen/apps/...
        $groupsProp = $it.PSObject.Properties | Where-Object { $_.Name -in $script:OupAssignGroupFields } | Select-Object -First 1
        if (-not $groupsProp -or -not $groupsProp.Value) { continue }

        $looksAssignment = $true
        $groups = @(@($groupsProp.Value) | ForEach-Object { "$_" } | Where-Object { $_ })

        # Rechner-Identifier bestimmen.
        $compProp = $it.PSObject.Properties | Where-Object { $_.Name -in $script:OupAssignCompFields } | Select-Object -First 1
        $src = if ($compProp -and ($compProp.Value -is [string])) { $compProp.Value } else { $it }
        $rec = _Oup-NormalizeRecord -Obj $src -SourceFile $fileName
        if (-not $rec.identifier) { continue }

        $assignments.Add([PSCustomObject]@{ entry = [PSCustomObject]$rec; groups = $groups })
    }

    return [PSCustomObject]@{
        IsAssignment = $looksAssignment
        Assignments  = $assignments.ToArray()
        SourceFile   = $Path
        Error        = $null
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Geräte-Zuweisungen (SubOU-Workflow): je Rechner Standort + Zuweisungen, jede
# Zuweisung hat Software + Typ (Job|Policy). Der Admin wählt im Baum die SubOU;
# Ziel ist <SubOU>-<Software>-<Typ> innerhalb DIESER SubOU.
#
#   [ { "computer":"PC-1001$", "standort":"Berlin-Nord",
#       "assignments":[ {"software":"Office","type":"Policy"},
#                       {"software":"PDFCreator","type":"Job"} ] } ]
# ─────────────────────────────────────────────────────────────────────────────
$script:OupDevStandortFields = @('standort', 'site', 'location', 'ou', 'subou', 'unterstandort')
$script:OupDevAssignFields   = @('assignments', 'zuweisungen', 'apps', 'software', 'applications', 'packages')
$script:OupSoftwareFields    = @('software', 'app', 'application', 'name', 'paket', 'package')
$script:OupTypeFields        = @('type', 'typ', 'kind', 'art')

function _Oup-NormType {
    <#  .SYNOPSIS  Normalisiert einen Zuweisungstyp auf 'Policy' | 'Job'.  #>
    param([string]$T)
    if (-not $T) { return $null }
    switch -regex ($T.ToLower()) {
        'pol|richtlin'     { return 'Policy' }
        'job|auftrag|task' { return 'Job' }
        default            { return $T }   # unbekannt -> roh (führt zu 'Gruppe fehlt')
    }
}

function Read-OupDeviceAssignmentFile {
    <#
        .SYNOPSIS  Liest eine Geräte-Zuweisungsdatei (Rechner + Standort + Zuweisungen).
        .OUTPUTS   PSCustomObject @{ IsDeviceAssignment; Devices; SourceFile; Error }
                   Device = @{ entry(normalisiert); standort; assignments[ @{software;type} ] }
    #>
    param([Parameter(Mandatory)][string]$Path)

    try {
        $data = Get-Content $Path -Raw | ConvertFrom-Json
    } catch {
        return [PSCustomObject]@{ IsDeviceAssignment = $false; Devices = @(); SourceFile = $Path; Error = "Ungültiges JSON: $($_.Exception.Message)" }
    }

    $fileName = Split-Path -Leaf $Path
    $items = $null
    if ($data -is [System.Array]) { $items = $data }
    else {
        foreach ($p in $data.PSObject.Properties) { if ($p.Value -is [System.Array]) { $items = $p.Value; break } }
        if ($null -eq $items) { $items = @($data) }
    }

    $devices = New-Object System.Collections.Generic.List[object]
    $looks   = $false

    foreach ($it in $items) {
        if ($it -is [string]) { continue }

        $assignProp = $it.PSObject.Properties | Where-Object { $_.Name -in $script:OupDevAssignFields } | Select-Object -First 1
        if (-not $assignProp -or -not $assignProp.Value) { continue }
        $looks = $true

        $compProp = $it.PSObject.Properties | Where-Object { $_.Name -in $script:OupAssignCompFields } | Select-Object -First 1
        $src = if ($compProp -and ($compProp.Value -is [string])) { $compProp.Value } else { $it }
        $rec = _Oup-NormalizeRecord -Obj $src -SourceFile $fileName
        if (-not $rec.identifier) { continue }

        $stProp   = $it.PSObject.Properties | Where-Object { $_.Name -in $script:OupDevStandortFields } | Select-Object -First 1
        $standort = if ($stProp) { "$($stProp.Value)" } else { $null }

        $assigns = New-Object System.Collections.Generic.List[object]
        foreach ($av in @($assignProp.Value)) {
            if ($av -is [string]) {
                $assigns.Add([PSCustomObject]@{ software = $av; type = $null })
            } else {
                $swP = $av.PSObject.Properties | Where-Object { $_.Name -in $script:OupSoftwareFields } | Select-Object -First 1
                $tyP = $av.PSObject.Properties | Where-Object { $_.Name -in $script:OupTypeFields } | Select-Object -First 1
                $sw  = if ($swP) { "$($swP.Value)" } else { $null }
                $ty  = if ($tyP) { _Oup-NormType "$($tyP.Value)" } else { $null }
                if ($sw) { $assigns.Add([PSCustomObject]@{ software = $sw; type = $ty }) }
            }
        }

        $devices.Add([PSCustomObject]@{ entry = [PSCustomObject]$rec; standort = $standort; assignments = $assigns.ToArray() })
    }

    return [PSCustomObject]@{ IsDeviceAssignment = $looks; Devices = $devices.ToArray(); SourceFile = $Path; Error = $null }
}

# ─────────────────────────────────────────────────────────────────────────────
# Konfigurierbare Feld-Map: eigene Feldnamen aus fieldmap.json ergänzen.
# ─────────────────────────────────────────────────────────────────────────────
function Get-OupFieldMapPath {
    <#  .SYNOPSIS  Effektiver Pfad zur Feld-Map (Default: <AppRoot>\fieldmap.json).  #>
    param([string]$ConfiguredPath, [Parameter(Mandatory)][string]$AppRoot)
    if ($ConfiguredPath) { return $ConfiguredPath }
    return Join-Path $AppRoot 'fieldmap.json'
}

function Import-OupFieldMap {
    <#  .SYNOPSIS  Lädt fieldmap.json (oder $null, wenn nicht vorhanden/ungültig).  #>
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    try {
        return (Get-Content $Path -Raw | ConvertFrom-Json)
    } catch {
        if (Get-Command Write-OupLog -ErrorAction SilentlyContinue) {
            Write-OupLog "fieldmap.json unlesbar, ignoriere: $($_.Exception.Message)" 'WARN'
        }
        return $null
    }
}

function _Oup-CfgList {
    <#  .SYNOPSIS  Liest eine Feldnamen-Liste case-insensitiv aus dem Config-Objekt
                   (PSCustomObject aus JSON oder Hashtable). Fehlt der Key -> @().  #>
    param($Config, [string]$Key)
    $val = $null
    if ($Config -is [System.Collections.IDictionary]) {
        foreach ($k in @($Config.Keys)) { if ("$k" -ieq $Key) { $val = $Config[$k]; break } }
    } elseif ($Config) {
        $p = $Config.PSObject.Properties | Where-Object { $_.Name -ieq $Key } | Select-Object -First 1
        if ($p) { $val = $p.Value }
    }
    if ($null -eq $val) { return @() }
    return @(@($val) | ForEach-Object { "$_" } | Where-Object { $_ })
}

function _Oup-MergeFieldList {
    <#  .SYNOPSIS  Custom-Namen vor die Basis stellen, case-insensitiv dedupen
                   (erste Nennung gewinnt -> idempotent bei erneutem Anwenden).  #>
    param([string[]]$Custom, [string[]]$Base)
    $seen = @{}
    $out  = New-Object System.Collections.Generic.List[string]
    foreach ($n in (@($Custom) + @($Base))) {
        if (-not $n) { continue }
        $k = $n.ToLowerInvariant()
        if ($seen.ContainsKey($k)) { continue }
        $seen[$k] = $true
        $out.Add($n)
    }
    return $out.ToArray()
}

function Set-OupFieldMap {
    <#
        .SYNOPSIS  Wendet eine Feld-Map-Konfiguration auf die Parser an: eigene
                   Feldnamen werden den eingebauten Kandidaten vorangestellt.
        .DESCRIPTION  Bekannte Schlüssel: Name, Sid, Guid, Dn, Sam, ObjectType
                      (Identifier-Map) sowie AssignGroupFields, AssignCompFields,
                      DevStandortFields, DevAssignFields, SoftwareFields, TypeFields.
                      Idempotent (case-insensitive Dedupe).
        .OUTPUTS   PSCustomObject @{ CustomCount; Keys } — Summe eigener Namen und
                   die Config-Schlüssel, die etwas beigesteuert haben.
    #>
    param($Config)

    $touched = New-Object System.Collections.Generic.List[string]
    $total   = 0
    $m       = $script:OupFieldMap

    # Identifier-Map (Sub-Arrays).
    foreach ($key in @('Name', 'Sid', 'Guid', 'Dn', 'Sam', 'ObjectType')) {
        $custom = _Oup-CfgList $Config $key
        if ($custom.Count -gt 0) { $touched.Add($key); $total += $custom.Count }
        $m[$key] = _Oup-MergeFieldList $custom $m[$key]
    }

    # Listen-Variablen (Sammelliste / Geräte-Zuweisung).
    $listVars = @{
        AssignGroupFields = 'OupAssignGroupFields'
        AssignCompFields  = 'OupAssignCompFields'
        DevStandortFields = 'OupDevStandortFields'
        DevAssignFields   = 'OupDevAssignFields'
        SoftwareFields    = 'OupSoftwareFields'
        TypeFields        = 'OupTypeFields'
    }
    foreach ($key in $listVars.Keys) {
        $custom = _Oup-CfgList $Config $key
        if ($custom.Count -gt 0) { $touched.Add($key); $total += $custom.Count }
        $varName = $listVars[$key]
        $merged  = _Oup-MergeFieldList $custom (Get-Variable -Name $varName -Scope Script -ValueOnly)
        Set-Variable -Name $varName -Scope Script -Value $merged
    }

    return [PSCustomObject]@{ CustomCount = $total; Keys = $touched.ToArray() }
}

Export-ModuleMember -Function Read-OupExportFile, Read-OupAssignmentFile, Read-OupDeviceAssignmentFile, `
    Get-OupFieldMapPath, Import-OupFieldMap, Set-OupFieldMap
