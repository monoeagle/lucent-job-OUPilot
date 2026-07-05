# core/ad-writer.psm1 — Schreibt Mitglieder in AD-Gruppen.
#
# Zwei Pfade mit Fallback (wie ad-reader):
#   1. ActiveDirectory-Modul: Add-ADGroupMember
#   2. ADSI / System.DirectoryServices: member-Attribut + CommitChanges
#   (3. Mock: simuliert nur, kein echter Schreibvorgang)
#
# Ablauf je Aufruf:
#   - Gruppe wird über ihre objectGUID (Modul) bzw. ihren aktuellen DN (ADSI)
#     gebunden.
#   - Bestehende Mitglieder werden vorab gelesen -> Doppeladd wird als
#     'AlreadyMember' gemeldet (locale-unabhängig, ohne Fehlertext-Parsing).
#   - Jeder Eintrag wird über seinen Identifier (SID/GUID/sAMAccountName/Name)
#     im AD aufgelöst; nicht auffindbare -> 'NotFound'.
#   - WhatIf: nichts wird geschrieben, Ergebnis 'Would'.
#
# Ergebnis je Eintrag: PSCustomObject @{ identifier; type; status; message }
#   status: Added | AlreadyMember | NotFound | Would | Simuliert | Error

function _Oup-WriteResult {
    param($Entry, [string]$Status, [string]$Message = '')
    [PSCustomObject]@{
        identifier = $Entry.identifier
        type       = $Entry.type
        status     = $Status
        message    = $Message
    }
}

function _Oup-ClassifyIdentifier {
    <#  .SYNOPSIS  Erkennt die Art eines Identifiers für die AD-Auflösung.  #>
    param([string]$Id)
    if ($Id -match '^S-1-\d') { return 'Sid' }
    if ($Id -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') { return 'Guid' }
    return 'Name'   # sAMAccountName oder name/cn
}

# ─────────────────────────────────────────────────────────────────────────────
# Pfad 1: ActiveDirectory-Modul
# ─────────────────────────────────────────────────────────────────────────────
function _Oup-ResolveViaModule {
    param([string]$Id, [string]$Kind, [hashtable]$Common)
    switch ($Kind) {
        'Sid'  { return Get-ADObject -Filter "objectSID -eq '$Id'" @Common -ErrorAction SilentlyContinue }
        'Guid' { return Get-ADObject -Identity $Id                 @Common -ErrorAction SilentlyContinue }
        default {
            # Zielobjekte sind Rechner (Software-Gruppen für MECM). Name kommt mal
            # als 'PC-0001', mal als 'PC-0001$' (sAMAccountName) -> beides treffen.
            $bare = $Id.TrimEnd('$')
            $o = Get-ADObject -LDAPFilter "(&(objectClass=computer)(|(name=$bare)(sAMAccountName=$bare`$)))" @Common -ErrorAction SilentlyContinue
            if (-not $o) { $o = Get-ADObject -Filter "sAMAccountName -eq '$Id'" @Common -ErrorAction SilentlyContinue }
            if (-not $o) { $o = Get-ADObject -Filter "name -eq '$Id'"           @Common -ErrorAction SilentlyContinue }
            return $o
        }
    }
}

function _Oup-AddMembersViaModule {
    param($GroupNode, [object[]]$Entries, [string]$Server, [switch]$WhatIf)

    Import-Module ActiveDirectory -ErrorAction Stop

    $common = @{}
    if ($Server) { $common['Server'] = $Server }

    # Gruppe über stabile GUID binden, bestehende Mitglieder vorab lesen.
    $grp = Get-ADGroup -Identity $GroupNode.Guid -Properties member @common -ErrorAction Stop
    $existing = @{}
    foreach ($m in @($grp.member)) { $existing[([string]$m).ToLowerInvariant()] = $true }

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($e in $Entries) {
        $kind = _Oup-ClassifyIdentifier $e.identifier
        $obj  = _Oup-ResolveViaModule -Id $e.identifier -Kind $kind -Common $common
        if (-not $obj) { $results.Add((_Oup-WriteResult $e 'NotFound' 'Objekt im AD nicht gefunden')); continue }

        $dn = [string]$obj.DistinguishedName
        if ($existing.ContainsKey($dn.ToLowerInvariant())) { $results.Add((_Oup-WriteResult $e 'AlreadyMember' $dn)); continue }
        if ($WhatIf) { $results.Add((_Oup-WriteResult $e 'Would' $dn)); continue }

        try {
            Add-ADGroupMember -Identity $GroupNode.Guid -Members $obj @common -Confirm:$false -ErrorAction Stop
            $existing[$dn.ToLowerInvariant()] = $true
            $results.Add((_Oup-WriteResult $e 'Added' $dn))
        } catch {
            $results.Add((_Oup-WriteResult $e 'Error' $_.Exception.Message))
        }
    }
    return $results.ToArray()
}

# ─────────────────────────────────────────────────────────────────────────────
# Pfad 2: ADSI / System.DirectoryServices
# ─────────────────────────────────────────────────────────────────────────────
function _Oup-ResolveDnViaAdsi {
    param([string]$Id, [string]$Kind, [string]$RootPrefix, [string]$BaseDn)
    try {
        switch ($Kind) {
            'Sid' {
                # Direktes Binden per SID-ADsPath ist locale-/escape-frei.
                $de = New-Object System.DirectoryServices.DirectoryEntry("$RootPrefix<SID=$Id>")
                return [string]$de.Properties['distinguishedName'].Value
            }
            'Guid' {
                # objectGUID als escapte Bytefolge suchen (zuverlässiger als GUID-Bind).
                $bytes   = ([Guid]$Id).ToByteArray()
                $escaped = ($bytes | ForEach-Object { '\{0:x2}' -f $_ }) -join ''
                $root = New-Object System.DirectoryServices.DirectoryEntry("$RootPrefix$BaseDn")
                $s = New-Object System.DirectoryServices.DirectorySearcher($root)
                $s.Filter = "(objectGUID=$escaped)"
                $r = $s.FindOne()
                if ($r) { return [string]$r.Properties['distinguishedname'][0] }
                return $null
            }
            default {
                # Rechner bevorzugt (MECM-Software-Gruppen); 'PC-0001' und
                # 'PC-0001$' auf denselben Computer auflösen.
                $bare = $Id.TrimEnd('$')
                $root = New-Object System.DirectoryServices.DirectoryEntry("$RootPrefix$BaseDn")
                $s = New-Object System.DirectoryServices.DirectorySearcher($root)
                $s.Filter = "(&(objectClass=computer)(|(name=$bare)(sAMAccountName=$bare`$)))"
                $r = $s.FindOne()
                if (-not $r) {
                    $s.Filter = "(|(sAMAccountName=$Id)(name=$Id)(cn=$Id))"
                    $r = $s.FindOne()
                }
                if ($r) { return [string]$r.Properties['distinguishedname'][0] }
                return $null
            }
        }
    } catch {
        return $null   # Bind/Suche fehlgeschlagen -> als NotFound behandeln
    }
}

function _Oup-AddMembersViaAdsi {
    param($GroupNode, [object[]]$Entries, [string]$Server, [switch]$WhatIf)

    $rootPrefix = if ($Server) { "LDAP://$Server/" } else { 'LDAP://' }

    $rootDse = New-Object System.DirectoryServices.DirectoryEntry("${rootPrefix}RootDSE")
    $baseDn  = [string]$rootDse.Properties['defaultNamingContext'][0]

    $group = New-Object System.DirectoryServices.DirectoryEntry("$rootPrefix$($GroupNode.DistinguishedName)")
    $existing = @{}
    foreach ($m in @($group.Properties['member'])) { $existing[([string]$m).ToLowerInvariant()] = $true }

    $results = New-Object System.Collections.Generic.List[object]
    $toAdd   = New-Object System.Collections.Generic.List[string]

    foreach ($e in $Entries) {
        $kind = _Oup-ClassifyIdentifier $e.identifier
        $dn   = _Oup-ResolveDnViaAdsi -Id $e.identifier -Kind $kind -RootPrefix $rootPrefix -BaseDn $baseDn
        if (-not $dn) { $results.Add((_Oup-WriteResult $e 'NotFound' 'Objekt im AD nicht gefunden')); continue }
        if ($existing.ContainsKey($dn.ToLowerInvariant())) { $results.Add((_Oup-WriteResult $e 'AlreadyMember' $dn)); continue }
        if ($WhatIf) { $results.Add((_Oup-WriteResult $e 'Would' $dn)); continue }

        $toAdd.Add($dn)
        $existing[$dn.ToLowerInvariant()] = $true
        $results.Add((_Oup-WriteResult $e 'Added' $dn))   # optimistisch; bei Commit-Fehler korrigiert
    }

    if (-not $WhatIf -and $toAdd.Count -gt 0) {
        try {
            foreach ($dn in $toAdd) { [void]$group.Properties['member'].Add($dn) }
            $group.CommitChanges()
        } catch {
            $msg = $_.Exception.Message
            foreach ($r in $results) {
                if ($r.status -eq 'Added') { $r.status = 'Error'; $r.message = $msg }
            }
        }
    }
    return $results.ToArray()
}

# ─────────────────────────────────────────────────────────────────────────────
# Öffentlicher Einstieg
# ─────────────────────────────────────────────────────────────────────────────
function Add-OupGroupMembers {
    <#
        .SYNOPSIS  Fügt Einträge als Mitglieder einer AD-Gruppe hinzu (mit Fallback).
        .PARAMETER GroupNode  AD-Gruppenknoten (Guid, DistinguishedName).
        .PARAMETER Entries    Normalisierte Importeinträge (.identifier, .type).
        .PARAMETER Mode       Auto | Module | Adsi | Mock.
        .PARAMETER WhatIf     Testlauf ohne Schreibvorgang.
        .OUTPUTS   Ergebnisobjekte je Eintrag (identifier, type, status, message).
    #>
    param(
        [Parameter(Mandatory)]$GroupNode,
        [Parameter(Mandatory)][object[]]$Entries,
        [ValidateSet('Auto', 'Module', 'Adsi', 'Mock')][string]$Mode = 'Auto',
        [string]$Server = '',
        [switch]$WhatIf
    )

    if (-not $Entries -or $Entries.Count -eq 0) { return @() }

    if ($Mode -eq 'Mock') {
        return @($Entries | ForEach-Object { _Oup-WriteResult $_ 'Simuliert' 'Mock-Modus: kein echter AD-Schreibvorgang' })
    }

    $attempts = switch ($Mode) {
        'Module' { @('Module') }
        'Adsi'   { @('Adsi') }
        default  { @('Module', 'Adsi') }
    }

    $lastError = $null
    foreach ($a in $attempts) {
        try {
            switch ($a) {
                'Module' { return _Oup-AddMembersViaModule -GroupNode $GroupNode -Entries $Entries -Server $Server -WhatIf:$WhatIf }
                'Adsi'   { return _Oup-AddMembersViaAdsi   -GroupNode $GroupNode -Entries $Entries -Server $Server -WhatIf:$WhatIf }
            }
        } catch {
            $lastError = $_.Exception.Message
            if (Get-Command Write-OupLog -ErrorAction SilentlyContinue) {
                Write-OupLog "AD-Schreibpfad '$a' nicht verfügbar: $lastError" 'WARN'
            }
        }
    }

    # Beide Pfade nicht verfügbar -> alle als Fehler melden.
    return @($Entries | ForEach-Object { _Oup-WriteResult $_ 'Error' $lastError })
}

Export-ModuleMember -Function Add-OupGroupMembers
