# core/mapping-store.psm1 — Lokaler Zustands-Store (JSON), Schlüssel = objectGUID.
#
# Hier liegt das, was die App über AD hinaus merken muss: welche Exporte in
# welche Gruppe importiert wurden. Da der Schlüssel die objectGUID ist, findet
# die App die Gruppe nach Umbenennen/Verschieben zuverlässig wieder.
#
#   Struktur:
#   {
#     "version": 1,
#     "groups": {
#       "<guid>": {
#         "guid", "lastKnownName", "lastKnownDn", "sid",
#         "imports": [ { "importedAt","sourceFile","type","identifier","raw" } ]
#       }
#     }
#   }

function Get-OupMappingPath {
    <#  .SYNOPSIS  Effektiver Pfad zum Store (Default: <AppRoot>\data\mapping.json).  #>
    param([string]$ConfiguredPath, [Parameter(Mandatory)][string]$AppRoot)
    if ($ConfiguredPath) { return $ConfiguredPath }
    return Join-Path (Join-Path $AppRoot 'data') 'mapping.json'
}

function Import-OupMapping {
    <#  .SYNOPSIS  Lädt den Store (oder leeres Gerüst, wenn die Datei fehlt).  #>
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path $Path)) {
        return [ordered]@{ version = 1; groups = [ordered]@{} }
    }
    try {
        $raw = Get-Content $Path -Raw | ConvertFrom-Json
    } catch {
        if (Get-Command Write-OupLog -ErrorAction SilentlyContinue) {
            Write-OupLog "Mapping-Store unlesbar, starte leer: $($_.Exception.Message)" 'WARN'
        }
        return [ordered]@{ version = 1; groups = [ordered]@{} }
    }

    # ConvertFrom-Json liefert PSCustomObject -> in geordnete Hashtables wandeln,
    # damit wir bequem schreiben können.
    $groups = [ordered]@{}
    if ($raw.groups) {
        foreach ($p in $raw.groups.PSObject.Properties) {
            $g = $p.Value
            $imports = @()
            if ($g.imports) { $imports = @($g.imports) }
            $groups[$p.Name] = [ordered]@{
                guid          = $g.guid
                lastKnownName = $g.lastKnownName
                lastKnownDn   = $g.lastKnownDn
                sid           = $g.sid
                imports       = $imports
            }
        }
    }
    return [ordered]@{ version = 1; groups = $groups }
}

function Save-OupMapping {
    <#  .SYNOPSIS  Schreibt den Store atomisch (temp -> move) nach JSON.  #>
    param([Parameter(Mandatory)]$Store, [Parameter(Mandatory)][string]$Path)

    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }

    $tmp = "$Path.tmp"
    $Store | ConvertTo-Json -Depth 8 | Out-File $tmp -Encoding UTF8 -Force
    Move-Item -Path $tmp -Destination $Path -Force
}

function Get-OupGroupRecord {
    <#
        .SYNOPSIS  Liefert (und legt bei Bedarf an) den Datensatz einer Gruppe.
        .DESCRIPTION  Aktualisiert immer lastKnownName/Dn/Sid aus dem AD-Knoten,
                      damit der Store den aktuellen Anzeigenamen widerspiegelt.
    #>
    param([Parameter(Mandatory)]$Store, [Parameter(Mandatory)]$GroupNode)

    $guid = $GroupNode.Guid
    if (-not $Store.groups.Contains($guid)) {
        $Store.groups[$guid] = [ordered]@{
            guid = $guid; lastKnownName = $null; lastKnownDn = $null; sid = $null; imports = @()
        }
    }
    $rec = $Store.groups[$guid]
    $rec.lastKnownName = $GroupNode.Name
    $rec.lastKnownDn   = $GroupNode.DistinguishedName
    $rec.sid           = $GroupNode.Sid
    return $rec
}

function Add-OupImportEntries {
    <#
        .SYNOPSIS  Hängt Importeinträge an den Gruppendatensatz an (dedupliziert
                   nach 'identifier').
        .OUTPUTS   Anzahl tatsächlich neu hinzugefügter Einträge.
    #>
    param(
        [Parameter(Mandatory)]$Store,
        [Parameter(Mandatory)]$GroupNode,
        [Parameter(Mandatory)][object[]]$Entries
    )

    $rec      = Get-OupGroupRecord -Store $Store -GroupNode $GroupNode
    $existing = @{}
    foreach ($e in @($rec.imports)) { if ($e.identifier) { $existing[$e.identifier] = $true } }

    $added = New-Object System.Collections.Generic.List[object]
    foreach ($e in $Entries) {
        if ($e.identifier -and $existing.ContainsKey($e.identifier)) { continue }
        $added.Add($e)
        if ($e.identifier) { $existing[$e.identifier] = $true }
    }

    $rec.imports = @($rec.imports) + $added.ToArray()
    return $added.Count
}

function Get-OupClientMemberships {
    <#
        .SYNOPSIS  Liefert alle Gruppen, in denen ein Rechner laut Store steckt.
        .DESCRIPTION  Grundlage für die Rechner-Übersicht und die Standort-
                      Konfliktprüfung. Matcht den Identifier case-insensitiv und
                      tolerant gegenüber dem Computer-Suffix '$' (PC-1 == PC-1$).
                      SID-/Namens-Formen sind verschiedene Strings — wird ein
                      Rechner mal per SID, mal per Name importiert, bitte nach
                      beidem suchen.
        .OUTPUTS   Array @{ guid; name; dn; identifier; adStatus; sourceFile; importedAt }
    #>
    param(
        [Parameter(Mandatory)]$Store,
        [Parameter(Mandatory)][string]$Identifier
    )

    $id      = $Identifier.Trim()
    $bare    = $id.TrimEnd('$')
    $needles = @{}
    foreach ($n in @($id, $bare, ($bare + '$'))) { $needles[$n.ToLowerInvariant()] = $true }

    $result = New-Object System.Collections.Generic.List[object]
    foreach ($guid in @($Store.groups.Keys)) {
        $rec = $Store.groups[$guid]
        foreach ($e in @($rec.imports)) {
            if ($needles.ContainsKey("$($e.identifier)".ToLowerInvariant())) {
                $result.Add([PSCustomObject]@{
                    guid       = $guid
                    name       = $rec.lastKnownName
                    dn         = $rec.lastKnownDn
                    identifier = $e.identifier
                    adStatus   = $e.adStatus
                    sourceFile = $e.sourceFile
                    importedAt = $e.importedAt
                })
                break   # eine Mitgliedschaft je Gruppe genügt
            }
        }
    }
    return $result.ToArray()
}

Export-ModuleMember -Function Get-OupMappingPath, Import-OupMapping, Save-OupMapping, `
    Get-OupGroupRecord, Add-OupImportEntries, Get-OupClientMemberships
