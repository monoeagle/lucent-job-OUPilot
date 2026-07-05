# core/ad-reader.psm1 — Liest die OU-Struktur und AD-Gruppen ein.
#
# Drei Pfade mit Fallback (Einstellung AdMode = Auto):
#   1. ActiveDirectory-Modul (RSAT)         -> Get-OupAdTree (Mode 'Module')
#   2. ADSI / System.DirectoryServices       -> (Mode 'Adsi')   ohne RSAT
#   3. Mock-Daten                            -> (Mode 'Mock')   ohne Domäne, zum Testen
#
# Jeder Knoten ist ein PSCustomObject. Stabiler Schlüssel ist IMMER Guid
# (objectGUID) — überlebt Umbenennen und OU-Verschieben. Der Name ist reine
# Anzeige und wird bei jedem Einlesen frisch geholt.
#
#   Knotenfelder:
#     NodeType          'OU' | 'Group'
#     Name              Anzeigename (cn / ou)
#     Guid              objectGUID als kanonischer String  <-- Primärschlüssel
#     Sid               objectSID als String (nur Gruppen; sonst '')
#     DistinguishedName aktueller DN (nur Anzeige/Sortierung)
#     ParentDn          DN des Elternobjekts (zum Baumaufbau)
#     MemberCount       Anzahl Mitglieder (nur Gruppen; -1 = unbekannt)
#     Children          ObservableCollection[object] (Sub-OUs + Gruppen)

function New-OupTreeNode {
    param(
        [string]$NodeType, [string]$Name, [string]$Guid, [string]$Sid,
        [string]$DistinguishedName, [string]$ParentDn, [int]$MemberCount = -1
    )
    $node = [PSCustomObject]@{
        NodeType          = $NodeType
        Name              = $Name
        Guid              = $Guid
        Sid               = $Sid
        DistinguishedName = $DistinguishedName
        ParentDn          = $ParentDn
        MemberCount       = $MemberCount
        Children          = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
    }
    # Anzeigetext für die TreeView (Name + ggf. Mitgliederzahl).
    $display = if ($NodeType -eq 'Group' -and $MemberCount -ge 0) { "$Name  ($MemberCount)" } else { $Name }
    $node | Add-Member -NotePropertyName 'Display' -NotePropertyValue $display
    return $node
}

function _Oup-ParentDn {
    # Entfernt die erste RDN aus einem DN -> Eltern-DN.
    param([string]$Dn)
    $idx = $Dn.IndexOf(',')
    if ($idx -lt 0) { return '' }
    return $Dn.Substring($idx + 1)
}

function _Oup-BuildHierarchy {
    <#
        .SYNOPSIS  Baut aus einer flachen Knotenliste den Baum (per ParentDn).
        .OUTPUTS   ObservableCollection der Wurzelknoten.
    #>
    param([object[]]$Flat)

    $byDn = @{}
    foreach ($n in $Flat) { $byDn[$n.DistinguishedName] = $n }

    $roots = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'

    # OUs zuerst einhängen, dann Gruppen — so liegen Gruppen unter ihren OUs.
    foreach ($n in ($Flat | Sort-Object @{e={$_.NodeType}}, DistinguishedName)) {
        $parent = $null
        if ($n.ParentDn -and $byDn.ContainsKey($n.ParentDn)) { $parent = $byDn[$n.ParentDn] }
        if ($parent) { [void]$parent.Children.Add($n) }
        else         { [void]$roots.Add($n) }
    }
    return $roots
}

# ─────────────────────────────────────────────────────────────────────────────
# Pfad 1: ActiveDirectory-Modul (RSAT)
# ─────────────────────────────────────────────────────────────────────────────
function _Oup-ReadViaModule {
    param([string]$SearchBase, [string]$Server)

    Import-Module ActiveDirectory -ErrorAction Stop

    $common = @{ Filter = '*' }
    if ($SearchBase) { $common['SearchBase'] = $SearchBase }
    if ($Server)     { $common['Server']     = $Server }

    $flat = New-Object System.Collections.Generic.List[object]

    # OUs
    Get-ADOrganizationalUnit @common -Properties objectGUID, distinguishedName |
        ForEach-Object {
            $flat.Add( (New-OupTreeNode -NodeType 'OU' -Name $_.Name `
                -Guid $_.ObjectGUID.Guid -Sid '' `
                -DistinguishedName $_.DistinguishedName `
                -ParentDn (_Oup-ParentDn $_.DistinguishedName)) )
        }

    # Gruppen
    Get-ADGroup @common -Properties objectGUID, objectSID, distinguishedName, member |
        ForEach-Object {
            $mc = if ($_.member) { @($_.member).Count } else { 0 }
            $sid = if ($_.objectSID) { $_.objectSID.Value } else { '' }
            $flat.Add( (New-OupTreeNode -NodeType 'Group' -Name $_.Name `
                -Guid $_.ObjectGUID.Guid -Sid $sid `
                -DistinguishedName $_.DistinguishedName `
                -ParentDn (_Oup-ParentDn $_.DistinguishedName) -MemberCount $mc) )
        }

    return ,(_Oup-BuildHierarchy -Flat $flat.ToArray())
}

# ─────────────────────────────────────────────────────────────────────────────
# Pfad 2: ADSI / System.DirectoryServices (kein RSAT nötig)
# ─────────────────────────────────────────────────────────────────────────────
function _Oup-ReadViaAdsi {
    param([string]$SearchBase, [string]$Server)

    $prefix = if ($Server) { "LDAP://$Server" } else { 'LDAP://' }

    # SearchBase bestimmen (Default: defaultNamingContext aus RootDSE).
    $base = $SearchBase
    if (-not $base) {
        $rootDse = New-Object System.DirectoryServices.DirectoryEntry("$prefix/RootDSE")
        $base    = [string]$rootDse.Properties['defaultNamingContext'][0]
    }

    $entry    = New-Object System.DirectoryServices.DirectoryEntry("$prefix/$base")
    $searcher = New-Object System.DirectoryServices.DirectorySearcher($entry)
    $searcher.Filter      = '(|(objectCategory=organizationalUnit)(objectCategory=group))'
    $searcher.PageSize    = 1000
    $searcher.SearchScope = 'Subtree'
    [void]$searcher.PropertiesToLoad.AddRange(@('name', 'distinguishedName', 'objectGUID', 'objectSid', 'objectClass', 'member'))

    $flat = New-Object System.Collections.Generic.List[object]
    foreach ($r in $searcher.FindAll()) {
        $p       = $r.Properties
        $dn      = [string]$p['distinguishedname'][0]
        $name    = [string]$p['name'][0]
        $guid    = (New-Object Guid (,[byte[]]$p['objectguid'][0])).ToString()
        $classes = @($p['objectclass'])
        $isGroup = $classes -contains 'group'

        if ($isGroup) {
            $sid = ''
            if ($p['objectsid'].Count -gt 0) {
                $sid = (New-Object System.Security.Principal.SecurityIdentifier([byte[]]$p['objectsid'][0], 0)).Value
            }
            $mc = if ($p['member']) { $p['member'].Count } else { 0 }
            $flat.Add( (New-OupTreeNode -NodeType 'Group' -Name $name -Guid $guid -Sid $sid `
                -DistinguishedName $dn -ParentDn (_Oup-ParentDn $dn) -MemberCount $mc) )
        } else {
            $flat.Add( (New-OupTreeNode -NodeType 'OU' -Name $name -Guid $guid -Sid '' `
                -DistinguishedName $dn -ParentDn (_Oup-ParentDn $dn)) )
        }
    }
    return ,(_Oup-BuildHierarchy -Flat $flat.ToArray())
}

# ─────────────────────────────────────────────────────────────────────────────
# Pfad 3: Mock (keine Domäne) — fester GUID-Satz, damit Mapping testbar bleibt.
# ─────────────────────────────────────────────────────────────────────────────
function _Oup-DnGuid {
    <#  .SYNOPSIS  Deterministische GUID aus einem DN (stabil über Programmläufe,
                   damit der Mapping-Store die Mock-Gruppen wiederfindet).  #>
    param([string]$Dn)
    $md5 = [System.Security.Cryptography.MD5]::Create()
    try {
        $bytes = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Dn.ToLowerInvariant()))
        return (New-Object Guid (,$bytes)).ToString()
    } finally { $md5.Dispose() }
}

function _Oup-ReadMock {
    <#
        .SYNOPSIS  Erzeugt einen realistischen Test-Baum ohne Domäne:
                   Standorte -> Unterstandorte -> je 20-30 Anwendungs-Gruppen.
    #>
    $domain = 'DC=contoso,DC=local'
    $rootDn = "OU=Standorte,$domain"

    # Standort -> Unterstandorte
    $sites = [ordered]@{
        'Berlin'   = @('Berlin-Nord', 'Berlin-Sued', 'Berlin-Mitte')
        'Hamburg'  = @('Hamburg-HafenCity', 'Hamburg-Altona')
        'Muenchen' = @('Muenchen-Zentrum', 'Muenchen-Ost', 'Muenchen-West')
    }

    # Anwendungen — je Software gibt es pro Unterstandort ZWEI Gruppen:
    # <SubOU>-<Software>-Policy und <SubOU>-<Software>-Job (eigene Gruppen je Typ).
    $apps = @(
        'Office', 'PDFCreator', '7Zip', 'GoogleChrome', 'Firefox', 'AdobeReader',
        'MSTeams', 'Zoom', 'VLC', 'Notepad', 'VSCode', 'Git', 'KeePass',
        'LibreOffice', 'PuTTY'
    )
    $types = @('Policy', 'Job')

    $flat = New-Object System.Collections.Generic.List[object]
    $flat.Add( (New-OupTreeNode 'OU' 'Standorte' (_Oup-DnGuid $rootDn) '' $rootDn (_Oup-ParentDn $rootDn)) )

    $siteIdx = 0
    foreach ($site in $sites.Keys) {
        $siteDn = "OU=$site,$rootDn"
        $flat.Add( (New-OupTreeNode 'OU' $site (_Oup-DnGuid $siteDn) '' $siteDn (_Oup-ParentDn $siteDn)) )

        $subIdx = 0
        foreach ($sub in $sites[$site]) {
            $subDn = "OU=$sub,$siteDn"
            $flat.Add( (New-OupTreeNode 'OU' $sub (_Oup-DnGuid $subDn) '' $subDn (_Oup-ParentDn $subDn)) )

            # 10-15 Anwendungen x 2 Typen = 20-30 Gruppen je Unterstandort.
            $swCount = 10 + (((($siteIdx * 3) + $subIdx) * 5) % 6)
            $rid = 1000 + ($siteIdx * 1000) + ($subIdx * 100)
            for ($i = 0; $i -lt $swCount; $i++) {
                $app = $apps[$i % $apps.Count]
                foreach ($t in $types) {
                    $gName = "$sub-$app-$t"           # z. B. Berlin-Nord-Office-Policy
                    $gDn   = "CN=$gName,$subDn"
                    $sid   = "S-1-5-21-1234567890-1234567890-1234567890-$rid"
                    $flat.Add( (New-OupTreeNode 'Group' $gName (_Oup-DnGuid $gDn) $sid $gDn (_Oup-ParentDn $gDn) 0) )
                    $rid++
                }
            }
            $subIdx++
        }
        $siteIdx++
    }

    return ,(_Oup-BuildHierarchy -Flat $flat.ToArray())
}

# ─────────────────────────────────────────────────────────────────────────────
# Öffentlicher Einstieg
# ─────────────────────────────────────────────────────────────────────────────
function Get-OupAdTree {
    <#
        .SYNOPSIS  Liest die OU-/Gruppen-Struktur gemäß Modus mit Fallback.
        .OUTPUTS   PSCustomObject: @{ Roots; ModeUsed; Error }
                   Roots = ObservableCollection der Wurzelknoten.
    #>
    param(
        [ValidateSet('Auto', 'Module', 'Adsi', 'Mock')][string]$Mode = 'Auto',
        [string]$SearchBase = '',
        [string]$Server = ''
    )

    $attempts = switch ($Mode) {
        'Module' { @('Module') }
        'Adsi'   { @('Adsi') }
        'Mock'   { @('Mock') }
        default  { @('Module', 'Adsi', 'Mock') }   # Auto: voller Fallback
    }

    $lastError = $null
    foreach ($a in $attempts) {
        try {
            $roots = switch ($a) {
                'Module' { _Oup-ReadViaModule -SearchBase $SearchBase -Server $Server }
                'Adsi'   { _Oup-ReadViaAdsi   -SearchBase $SearchBase -Server $Server }
                'Mock'   { _Oup-ReadMock }
            }
            # PowerShell entrollt Collections über Funktionsgrenzen hinweg. Damit
            # TreeView.ItemsSource zuverlässig eine Collection erhält, hier neu fassen.
            $coll = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
            foreach ($r in @($roots)) { [void]$coll.Add($r) }
            return [PSCustomObject]@{ Roots = $coll; ModeUsed = $a; Error = $null }
        } catch {
            $lastError = $_.Exception.Message
            if (Get-Command Write-OupLog -ErrorAction SilentlyContinue) {
                Write-OupLog "AD-Lesepfad '$a' fehlgeschlagen: $lastError" 'WARN'
            }
        }
    }

    # Sollte nur eintreten, wenn ein einzelner Modus erzwungen wurde und scheitert.
    return [PSCustomObject]@{
        Roots    = (New-Object 'System.Collections.ObjectModel.ObservableCollection[object]')
        ModeUsed = 'None'
        Error    = $lastError
    }
}

function Get-OupGroupIndex {
    <#
        .SYNOPSIS  Flacht den Baum zu einem Namens-Index aller Gruppen ab.
        .DESCRIPTION  Für den Sammelimport: Gruppenname (aus der JSON-Zuordnung)
                      -> AD-Gruppenknoten. Schlüssel ist der kleingeschriebene Name.
        .OUTPUTS   PSCustomObject @{ ByName (hashtable); Duplicates (string[]) }
    #>
    param([Parameter(Mandatory)]$Roots)

    $byName = @{}
    $dups   = New-Object System.Collections.Generic.List[string]
    $stack  = New-Object System.Collections.Stack
    foreach ($r in @($Roots)) { $stack.Push($r) }

    while ($stack.Count -gt 0) {
        $n = $stack.Pop()
        if ($n.NodeType -eq 'Group') {
            $key = $n.Name.ToLowerInvariant()
            if ($byName.ContainsKey($key)) {
                if (-not $dups.Contains($n.Name)) { $dups.Add($n.Name) }
            } else {
                $byName[$key] = $n
            }
        }
        foreach ($c in @($n.Children)) { $stack.Push($c) }
    }
    return [PSCustomObject]@{ ByName = $byName; Duplicates = $dups.ToArray() }
}

function Get-OupGroupLocations {
    <#
        .SYNOPSIS  Bestimmt zu jeder Gruppe ihren Standort/Unterstandort aus der
                   Baumhierarchie (robuster als DN-Parsing).
        .DESCRIPTION  Ebenen: Wurzel(0)=Container, (1)=Standort, (2)=Unterstandort,
                      darunter Gruppen. Gruppen erben Standort/Unterstandort ihrer
                      Vorfahren.
        .OUTPUTS   PSCustomObject @{ ByGuid = @{ guid -> @{ Standort; Unterstandort } } }
    #>
    param([Parameter(Mandatory)]$Roots)

    $byGuid = @{}
    $stack  = New-Object System.Collections.Stack
    foreach ($r in @($Roots)) {
        $stack.Push([PSCustomObject]@{ Node = $r; Depth = 0; Standort = $null; Unter = $null })
    }
    while ($stack.Count -gt 0) {
        $cur = $stack.Pop()
        $n   = $cur.Node
        $std = $cur.Standort
        $unt = $cur.Unter

        if ($n.NodeType -eq 'OU') {
            if     ($cur.Depth -eq 1) { $std = $n.Name }
            elseif ($cur.Depth -ge 2) { $unt = $n.Name }   # tiefste OU = Unterstandort
        } elseif ($n.NodeType -eq 'Group') {
            $byGuid[$n.Guid] = [PSCustomObject]@{ Standort = $std; Unterstandort = $unt }
        }
        foreach ($c in @($n.Children)) {
            $stack.Push([PSCustomObject]@{ Node = $c; Depth = ($cur.Depth + 1); Standort = $std; Unter = $unt })
        }
    }
    return [PSCustomObject]@{ ByGuid = $byGuid }
}

Export-ModuleMember -Function Get-OupAdTree, New-OupTreeNode, Get-OupGroupIndex, Get-OupGroupLocations
