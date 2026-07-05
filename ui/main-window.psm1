# ui/main-window.psm1 — Hauptfenster: OU-/Gruppen-TreeView + Import-Panel.
#
# Muster wie CodeSigningCommander: XAML als Here-String, geladen via XamlReader,
# Controls über FindName, UI-State in $script:-Variablen, Events in _-Helfern.
# Neu ggü. CSC: TreeView, manuell aus TreeViewItem-Objekten befüllt (siehe
# _Oup-AddTreeNodes) — robuster als HierarchicalDataTemplate-Binding gegen
# PSCustomObject in PS 5.1.

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml

# ── UI-State ────────────────────────────────────────────────────────────────
$script:oupAppRoot      = $null
$script:oupConfigPath   = $null
$script:oupSettings     = $null
$script:oupStore        = $null
$script:oupMappingPath  = $null
$script:oupWindow       = $null
$script:oupTree         = $null
$script:oupSelectedNode = $null
$script:oupImportItems  = $null   # ObservableCollection der Importeinträge (rechts)
$script:oupAdModeUsed   = $null   # zuletzt genutzter AD-Lesemodus (für Schreibmodus)
$script:oupRoots        = $null   # geladene Wurzelknoten (für Sammelimport-Index)
$script:oupNodeToItem   = $null   # Gruppen-GUID -> TreeViewItem (Header-Updates)
$script:oupLookupWin    = $null   # Rechner-Übersicht: Fenster
$script:oupLookupItems  = $null   # Rechner-Übersicht: Grid-Items
$script:oupLookupLocs   = $null   # Rechner-Übersicht: Standort-Map
$script:oupImportMode   = 'Group' # 'Group' (Gruppe gewählt) | 'SubOU' (Unterstandort)
$script:oupPaletteItems = $null   # Ansicht-Menü: Palette-Name -> MenuItem (Häkchen)
$script:oupStyleItems   = $null   # Ansicht-Menü: Stil-Name    -> MenuItem (Häkchen)
$script:oupFilter       = ''      # aktiver Baum-Filter (Teiltext, case-insensitiv)
$script:oupFilterHits   = 0       # Anzahl namentlicher Treffer beim letzten Render
$script:oupFieldMapNote = $null   # Startup-Hinweis, wenn eine Feld-Map aktiv ist

$script:OupMainXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="OUPilot" Height="720" Width="1180"
        WindowStartupLocation="CenterScreen" FontFamily="Segoe UI" FontSize="13"
        Background="{DynamicResource Theme.Background}"
        TextElement.Foreground="{DynamicResource Theme.TextPrimary}">
  <DockPanel>
    <!-- Menüleiste -->
    <Menu DockPanel.Dock="Top">
      <MenuItem Header="_Datei">
        <MenuItem x:Name="MenuReload" Header="AD neu einlesen"/>
        <Separator/>
        <MenuItem x:Name="MenuExit" Header="Beenden"/>
      </MenuItem>
      <MenuItem x:Name="MenuClientLookup" Header="_Rechner suchen..."/>
      <MenuItem x:Name="MenuView" Header="_Ansicht"/>
      <MenuItem x:Name="MenuInfo" Header="_Info"/>
    </Menu>

    <!-- Toolbar -->
    <Border DockPanel.Dock="Top" Background="{DynamicResource Theme.SoftBg}" Padding="8,6" BorderBrush="{DynamicResource Theme.Border}" BorderThickness="0,0,0,1">
      <StackPanel Orientation="Horizontal">
        <Button x:Name="BtnReload" Content="AD neu einlesen" Padding="10,4" Margin="0,0,8,0"/>
        <TextBlock x:Name="TxtMode" VerticalAlignment="Center" Foreground="{DynamicResource Theme.TextSecondary}"/>
      </StackPanel>
    </Border>

    <!-- Statusleiste -->
    <Border DockPanel.Dock="Bottom" Background="{DynamicResource Theme.SoftBg}" Padding="8,4" BorderBrush="{DynamicResource Theme.Border}" BorderThickness="0,1,0,0">
      <TextBlock x:Name="TxtStatus" Foreground="{DynamicResource Theme.TextSecondary}" Text="Bereit."/>
    </Border>

    <Grid>
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="360" MinWidth="260"/>
        <ColumnDefinition Width="5"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>

      <!-- Links: OU-/Gruppen-Baum -->
      <DockPanel Grid.Column="0">
        <TextBlock DockPanel.Dock="Top" Text="OU-Struktur &amp; AD-Gruppen" FontWeight="SemiBold" Margin="8,8,8,4"/>
        <Grid DockPanel.Dock="Top" Margin="8,0,8,6">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <TextBox x:Name="TxtFilter" Grid.Column="0" VerticalContentAlignment="Center"
                   ToolTip="Nach OU- oder Gruppennamen filtern (Teiltext)"/>
          <Button x:Name="BtnFilterClear" Grid.Column="1" Content="&#x2715;" Width="26" Margin="4,0,0,0"
                  ToolTip="Filter löschen"/>
        </Grid>
        <TreeView x:Name="TreeAd" Margin="8,0,8,8" Background="{DynamicResource Theme.Background}" BorderBrush="{DynamicResource Theme.Border}"/>
      </DockPanel>

      <GridSplitter Grid.Column="1" Width="5" HorizontalAlignment="Stretch" Background="{DynamicResource Theme.SoftBg}"/>

      <!-- Rechts: ausgewählte Gruppe + Importe -->
      <DockPanel Grid.Column="2" Margin="8">
        <Border DockPanel.Dock="Top" BorderBrush="{DynamicResource Theme.Border}" BorderThickness="1" Padding="10" Margin="0,0,0,8" CornerRadius="3">
          <StackPanel>
            <TextBlock x:Name="TxtGroupName" Text="Keine Gruppe gewählt" FontWeight="SemiBold" FontSize="15"/>
            <TextBlock x:Name="TxtGroupGuid" Foreground="{DynamicResource Theme.TextSecondary}" Margin="0,2,0,0"/>
            <TextBlock x:Name="TxtGroupDn"   Foreground="{DynamicResource Theme.TextSecondary}" TextWrapping="Wrap"/>
          </StackPanel>
        </Border>

        <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="0,0,0,4">
          <Button x:Name="BtnImportAssign" Content="Sammelliste importieren (Rechner→Gruppen)..." Padding="10,5"/>
        </StackPanel>
        <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="0,0,0,8">
          <Button x:Name="BtnImport" Content="In gewählte Gruppe importieren..." Padding="10,5" IsEnabled="False"/>
          <Button x:Name="BtnRemove" Content="Ausgewählte entfernen..." Padding="10,5" IsEnabled="False"
                  ToolTip="Markierte Zeilen aus der gewählten Gruppe entfernen (AD + Store)"/>
          <CheckBox x:Name="ChkWhatIf" Content="Nur Testlauf (WhatIf)" VerticalAlignment="Center" Margin="12,0,0,0"/>
        </StackPanel>

        <TextBlock DockPanel.Dock="Top" Text="Importierte Einträge" FontWeight="SemiBold" Margin="0,0,0,4"/>
        <DataGrid x:Name="GridImports" AutoGenerateColumns="False" IsReadOnly="True"
                  CanUserAddRows="False" HeadersVisibility="Column" GridLinesVisibility="Horizontal">
          <DataGrid.Columns>
            <DataGridTextColumn Header="Typ"        Binding="{Binding type}"        Width="75"/>
            <DataGridTextColumn Header="Identifier" Binding="{Binding identifier}"  Width="1.6*"/>
            <DataGridTextColumn Header="Gruppe"     Binding="{Binding targetGroup}" Width="1.6*"/>
            <DataGridTextColumn Header="AD-Status"  Binding="{Binding adStatus}"    Width="100"/>
            <DataGridTextColumn Header="Quelle"     Binding="{Binding sourceFile}"  Width="1.3*"/>
            <DataGridTextColumn Header="Importiert" Binding="{Binding importedAt}"  Width="150"/>
          </DataGrid.Columns>
        </DataGrid>
      </DockPanel>
    </Grid>
  </DockPanel>
</Window>
'@

function _Oup-SetStatus {
    param([string]$Text, [string]$Level = 'INFO')
    if ($script:oupWindow) {
        $b = $script:oupWindow.FindName('TxtStatus')
        if ($b) { $b.Text = $Text }
    }
    if (Get-Command Write-OupLog -ErrorAction SilentlyContinue) { Write-OupLog $Text $Level }
}

function _Oup-NodeHeader {
    <#
        .SYNOPSIS  Header-Text eines Knotens inkl. Mitgliederzahl bei Gruppen.
        .DESCRIPTION  Die angezeigte Zahl ist das Maximum aus realer AD-
                      Mitgliederzahl und der im Store protokollierten Importe —
                      so springt der Zähler nach einem Import sichtbar hoch
                      (auch im Mock, wo das AD keine echte Zahl liefert).
    #>
    param($Node)

    $glyph = if ($Node.NodeType -eq 'Group') { [char]0xD83D, [char]0xDC65 -join '' } `
             else                            { [char]0xD83D, [char]0xDCC1 -join '' }
    if ($Node.NodeType -ne 'Group') { return "$glyph  $($Node.Name)" }

    $storeCount = 0
    if ($script:oupStore -and $script:oupStore.groups.Contains($Node.Guid)) {
        $storeCount = @($script:oupStore.groups[$Node.Guid].imports).Count
    }
    $base  = if ($Node.MemberCount -ge 0) { $Node.MemberCount } else { 0 }
    $shown = [Math]::Max($base, $storeCount)
    return "$glyph  $($Node.Name)  ($shown)"
}

function _Oup-UpdateGroupHeader {
    <#  .SYNOPSIS  Aktualisiert den Header einer Gruppe (nach Import).  #>
    param($Node)
    if ($script:oupNodeToItem -and $script:oupNodeToItem.ContainsKey($Node.Guid)) {
        $script:oupNodeToItem[$Node.Guid].Header = (_Oup-NodeHeader $Node)
    }
}

function _Oup-NodeNameHit {
    <#  .SYNOPSIS  $true, wenn der Knotenname den Filter als Teiltext (case-
                   insensitiv) enthält. Leerer Filter zählt nicht als Treffer.  #>
    param($Node, [string]$Filter)
    if (-not $Filter) { return $false }
    return ($Node.Name.IndexOf($Filter, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
}

function _Oup-BuildFilteredItem {
    <#
        .SYNOPSIS  Baut rekursiv ein TreeViewItem für einen AD-Knoten unter
                   Beachtung des Filters. Gibt $null zurück, wenn der Knoten samt
                   Teilbaum herausgefiltert wird.
        .DESCRIPTION  Bewusst manuell statt HierarchicalDataTemplate: WPF bindet
                      ObservableCollection-Properties auf PSCustomObject in PS 5.1
                      nicht zuverlässig. Der AD-Knoten hängt als .Tag am Item.
                      Sichtbarkeitsregel bei aktivem Filter: ein Knoten erscheint,
                      wenn (a) ein Vorfahre matchte, (b) sein eigener Name matcht,
                      oder (c) ein Nachfahre matcht. Matcht der Name selbst (oder
                      ein Vorfahre), wird der komplette Teilbaum ungefiltert
                      gezeigt. OU-Knoten werden bei aktivem Filter aufgeklappt,
                      damit Treffer sofort sichtbar sind; ohne Filter nur die
                      oberen zwei Ebenen (Standorte/Unterstandorte).
        .PARAMETER AncestorMatched  Ein Vorfahre hat bereits gematcht -> Teilbaum
                                    ungefiltert übernehmen.
        .PARAMETER Depth  Tiefe (0 = Wurzel).
    #>
    param($Node, [string]$Filter, [bool]$AncestorMatched, [int]$Depth)

    $nameHit   = _Oup-NodeNameHit -Node $Node -Filter $Filter
    $selfShown = (-not $Filter) -or $AncestorMatched -or $nameHit
    if ($nameHit) { $script:oupFilterHits++ }

    # Kinder rekursiv (Reihenfolge wie bisher: erst nach NodeType, dann Name).
    $childItems = New-Object System.Collections.Generic.List[object]
    if ($Node.Children -and $Node.Children.Count -gt 0) {
        foreach ($c in (@($Node.Children) | Sort-Object @{e={$_.NodeType}}, Name)) {
            $ci = _Oup-BuildFilteredItem -Node $c -Filter $Filter `
                    -AncestorMatched ($AncestorMatched -or $nameHit) -Depth ($Depth + 1)
            if ($ci) { [void]$childItems.Add($ci) }
        }
    }

    # Herausfiltern, wenn weder selbst sichtbar noch ein sichtbares Kind.
    if (-not ($selfShown -or $childItems.Count -gt 0)) { return $null }

    $tvi = New-Object System.Windows.Controls.TreeViewItem
    $tvi.Header = (_Oup-NodeHeader $Node)
    $tvi.Tag    = $Node
    if ($Node.NodeType -eq 'Group' -and $script:oupNodeToItem) { $script:oupNodeToItem[$Node.Guid] = $tvi }
    foreach ($ci in $childItems) { [void]$tvi.Items.Add($ci) }
    $tvi.IsExpanded = if ($Filter) { ($Node.NodeType -eq 'OU') } else { ($Node.NodeType -eq 'OU' -and $Depth -le 1) }
    return $tvi
}

function _Oup-RenderTree {
    <#  .SYNOPSIS  Zeichnet die TreeView aus $script:oupRoots unter dem aktuellen
                   Filter neu und baut die Gruppen-GUID->Item-Map neu auf.  #>
    if (-not $script:oupTree) { return }
    $script:oupTree.Items.Clear()
    $script:oupNodeToItem = @{}
    $script:oupFilterHits = 0
    foreach ($n in (@($script:oupRoots) | Sort-Object @{e={$_.NodeType}}, Name)) {
        $tvi = _Oup-BuildFilteredItem -Node $n -Filter $script:oupFilter -AncestorMatched $false -Depth 0
        if ($tvi) { [void]$script:oupTree.Items.Add($tvi) }
    }
}

function _Oup-OnFilterChanged {
    <#  .SYNOPSIS  Reagiert auf Änderungen im Filter-Textfeld: Baum neu zeichnen
                   und Treffer in der Statuszeile melden (ohne Log-Spam).  #>
    param([string]$Text)
    $script:oupFilter = ([string]$Text).Trim()
    _Oup-RenderTree
    $status = if ($script:oupWindow) { $script:oupWindow.FindName('TxtStatus') } else { $null }
    if ($status) {
        if ($script:oupFilter) {
            $status.Text = if ($script:oupFilterHits -gt 0) {
                "Filter '$($script:oupFilter)': $($script:oupFilterHits) Treffer."
            } else {
                "Filter '$($script:oupFilter)': keine Treffer."
            }
        } else {
            $status.Text = 'Bereit.'
        }
    }
}

function _Oup-LoadTree {
    <#  Liest das AD (gem. Einstellungen) und füllt die TreeView.  #>
    $mode   = $script:oupSettings.AdMode
    $base   = $script:oupSettings.AdSearchBase
    $server = $script:oupSettings.AdServer

    _Oup-SetStatus "Lese AD ein (Modus: $mode)..."
    $result = Get-OupAdTree -Mode $mode -SearchBase $base -Server $server

    $script:oupRoots      = $result.Roots      # für Sammelimport-Gruppenindex
    _Oup-RenderTree                             # zeichnet Baum (unter aktuellem Filter), baut GUID->Item-Map neu
    $script:oupAdModeUsed = $result.ModeUsed   # bestimmt den Schreibmodus beim Import
    $modeText = if ($result.ModeUsed -eq 'Mock') { "Mock-Daten (keine Domäne)" } else { $result.ModeUsed }
    $script:oupWindow.FindName('TxtMode').Text = "Quelle: $modeText"

    if ($result.Error -and $result.ModeUsed -eq 'None') {
        _Oup-SetStatus "AD-Einlesen fehlgeschlagen: $($result.Error)" 'ERROR'
    } else {
        _Oup-SetStatus "AD eingelesen ($modeText)."
    }
}

function _Oup-SetEntryField {
    <#  .SYNOPSIS  Setzt/erzeugt eine NoteProperty auf einem (Klon-)Eintrag.  #>
    param($Entry, [string]$Name, $Value)
    if ($Entry.PSObject.Properties[$Name]) { $Entry.$Name = $Value }
    else { $Entry | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force }
}

function _Oup-RdnValue {
    <#  .SYNOPSIS  Wert der ersten RDN eines DN (z. B. "OU=Berlin,..." -> "Berlin").  #>
    param([string]$Dn)
    if (-not $Dn) { return '' }
    return (($Dn -split ',')[0] -replace '^[^=]+=', '')
}

function _Oup-OnNodeSelected {
    param($Node)
    $script:oupSelectedNode = $Node
    $btn = $script:oupWindow.FindName('BtnImport')

    if ($Node -and $Node.NodeType -eq 'Group') {
        $script:oupImportMode = 'Group'
        $btn.Content   = "In gewählte Gruppe importieren..."
        $btn.IsEnabled = $true
        $script:oupWindow.FindName('TxtGroupName').Text = $Node.Name
        $script:oupWindow.FindName('TxtGroupGuid').Text = "GUID: $($Node.Guid)"
        $script:oupWindow.FindName('TxtGroupDn').Text   = $Node.DistinguishedName

        # Bereits importierte Einträge dieser Gruppe (per GUID) anzeigen.
        $script:oupImportItems.Clear()
        if ($script:oupStore.groups.Contains($Node.Guid)) {
            foreach ($e in @($script:oupStore.groups[$Node.Guid].imports)) {
                $script:oupImportItems.Add([PSCustomObject]$e)
            }
        }
        _Oup-SetStatus "Gruppe gewählt: $($Node.Name) — $($script:oupImportItems.Count) Eintrag/Einträge."
    }
    elseif ($Node -and $Node.NodeType -eq 'OU' -and (@($Node.Children | Where-Object { $_.NodeType -eq 'Group' }).Count -gt 0)) {
        # SubOU (Unterstandort) mit Software-Gruppen -> Geräte-Import möglich.
        $script:oupImportMode = 'SubOU'
        $grpCount = @($Node.Children | Where-Object { $_.NodeType -eq 'Group' }).Count
        $btn.Content   = "Geräte-JSON in SubOU '$($Node.Name)' importieren..."
        $btn.IsEnabled = $true
        $script:oupWindow.FindName('TxtGroupName').Text = "SubOU: $($Node.Name)"
        $script:oupWindow.FindName('TxtGroupGuid').Text = "$grpCount Software-Gruppen (Policy/Job)"
        $script:oupWindow.FindName('TxtGroupDn').Text   = $Node.DistinguishedName
        $script:oupImportItems.Clear()
        _Oup-SetStatus "SubOU gewählt: $($Node.Name) ($grpCount Gruppen) — bereit für Geräte-Import."
    }
    else {
        $script:oupImportMode = 'Group'
        $btn.Content   = "In gewählte Gruppe importieren..."
        $btn.IsEnabled = $false
        $label = if ($Node) { "OU gewählt: $($Node.Name) (keine direkten Gruppen)" } else { "Keine Auswahl" }
        $script:oupWindow.FindName('TxtGroupName').Text = if ($Node) { $Node.Name } else { 'Keine Gruppe gewählt' }
        $script:oupWindow.FindName('TxtGroupGuid').Text = ''
        $script:oupWindow.FindName('TxtGroupDn').Text   = ''
        $script:oupImportItems.Clear()
        _Oup-SetStatus $label
    }

    _Oup-UpdateRemoveEnabled
}

function _Oup-UpdateRemoveEnabled {
    <#  .SYNOPSIS  Aktiviert „Ausgewählte entfernen" nur, wenn eine Gruppe gewählt
                   ist und im Grid mindestens eine Zeile markiert wurde.  #>
    if (-not $script:oupWindow) { return }
    $btn  = $script:oupWindow.FindName('BtnRemove')
    $grid = $script:oupWindow.FindName('GridImports')
    if (-not $btn -or -not $grid) { return }
    $btn.IsEnabled = ($script:oupImportMode -eq 'Group' -and
                      $script:oupSelectedNode -and $script:oupSelectedNode.NodeType -eq 'Group' -and
                      $grid.SelectedItems.Count -gt 0)
}

function _Oup-OnRemoveMembers {
    <#
        .SYNOPSIS  Entfernt die im Grid markierten Rechner aus der gewählten
                   Gruppe — aus dem AD (Modul/ADSI/Mock) und aus dem Store.
        .DESCRIPTION  Nur im Gruppen-Modus. Destruktiv -> Bestätigung (außer im
                      Testlauf). Persistiert nur, was danach kein Mitglied mehr
                      ist (Removed/NotMember/Simuliert).
    #>
    if (-not $script:oupSelectedNode -or $script:oupSelectedNode.NodeType -ne 'Group') {
        _Oup-SetStatus 'Zum Entfernen bitte eine Gruppe wählen.' 'WARN'; return
    }
    $group = $script:oupSelectedNode
    $grid  = $script:oupWindow.FindName('GridImports')
    $sel   = @($grid.SelectedItems)
    if ($sel.Count -eq 0) { _Oup-SetStatus 'Keine Zeile markiert.' 'WARN'; return }

    # Markierte Zeilen -> Einträge (identifier/type) für den AD-Aufruf.
    $entries = @($sel | ForEach-Object {
        [PSCustomObject]@{ identifier = [string]$_.identifier; type = [string]$_.type }
    } | Where-Object { $_.identifier })
    if ($entries.Count -eq 0) { _Oup-SetStatus 'Markierte Zeilen ohne Identifier.' 'WARN'; return }

    $whatIf = [bool]$script:oupWindow.FindName('ChkWhatIf').IsChecked
    $isMock = ($script:oupAdModeUsed -eq 'Mock')

    # Bestätigung — Entfernen ist ein wirksamer, destruktiver Eingriff.
    if (-not $whatIf) {
        $head = if ($isMock) { "ACHTUNG: Quelle ist Mock (keine Domäne) — es wird nur simuliert.`n`n" } else { '' }
        $q = "$head$($entries.Count) Mitglied(er) aus der Gruppe`n'$($group.Name)'`nENTFERNEN?"
        $ans = [System.Windows.MessageBox]::Show($script:oupWindow, $q, 'Mitglieder entfernen',
                   [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
        if ($ans -ne [System.Windows.MessageBoxResult]::Yes) { _Oup-SetStatus 'Entfernen abgebrochen.'; return }
    }

    $adMode = if ($isMock) { 'Mock' } else { 'Auto' }
    $tag    = if ($whatIf) { "$adMode/Testlauf" } else { $adMode }
    _Oup-SetStatus "Entferne $($entries.Count) Mitglied(er) aus '$($group.Name)' ($tag)..."
    $results = @(Remove-OupGroupMembers -GroupNode $group -Entries $entries `
                    -Mode $adMode -Server $script:oupSettings.AdServer -WhatIf:$whatIf)

    # Ergebnis zählen.
    $counts = @{}
    foreach ($r in $results) {
        $counts[$r.status] = 1 + $(if ($counts.ContainsKey($r.status)) { $counts[$r.status] } else { 0 })
    }
    $summary = (($counts.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ')

    $purged = 0
    if (-not $whatIf) {
        # Aus dem Store nehmen, was tatsächlich kein Mitglied mehr ist.
        $ids = @($results | Where-Object { $_.status -in @('Removed', 'NotMember', 'Simuliert') } | ForEach-Object { $_.identifier })
        if ($ids.Count -gt 0) {
            $purged = (Remove-OupImportEntries -Store $script:oupStore -GroupNode $group -Identifiers $ids)
        }
        Save-OupMapping -Store $script:oupStore -Path $script:oupMappingPath
        _Oup-OnNodeSelected -Node $group        # Grid aus Store neu laden
        _Oup-UpdateGroupHeader -Node $group     # Zähler im Baum korrigieren
    }

    $prefix = if ($whatIf) { 'Testlauf (Entfernen)' } else { 'Entfernt' }
    $tail   = if ($whatIf) { '' } else { ", $purged aus Store entfernt" }
    $lvl    = if ($counts.ContainsKey('Error') -or $counts.ContainsKey('NotFound')) { 'WARN' } else { 'INFO' }
    _Oup-SetStatus "${prefix}: $summary ($($entries.Count) gewählt$tail)." $lvl
}

function _Oup-OnImport {
    if (-not $script:oupSelectedNode -or $script:oupSelectedNode.NodeType -ne 'Group') { return }
    $group = $script:oupSelectedNode

    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Filter      = 'JSON-Exporte (*.json)|*.json|Alle Dateien (*.*)|*.*'
    $dlg.Multiselect = $true
    $dlg.Title       = "JSON-Export(e) für Software-Gruppe '$($group.Name)' wählen"
    if ($script:oupSettings.LastImportDir -and (Test-Path $script:oupSettings.LastImportDir)) {
        $dlg.InitialDirectory = $script:oupSettings.LastImportDir
    }
    if (-not $dlg.ShowDialog()) { return }

    # 1) Dateien parsen.
    $entries = New-Object System.Collections.Generic.List[object]
    $errors  = @()
    foreach ($file in $dlg.FileNames) {
        $parsed = Read-OupExportFile -Path $file
        if ($parsed.Error) { $errors += "$(Split-Path -Leaf $file): $($parsed.Error)"; continue }
        foreach ($e in $parsed.Entries) { $entries.Add($e) }
    }
    if ($entries.Count -eq 0) {
        $m = "Keine verwertbaren Einträge gefunden."
        if ($errors.Count -gt 0) { $m += " Fehler: " + ($errors -join ' | ') }
        _Oup-SetStatus $m 'WARN'
        return
    }

    $whatIf = [bool]$script:oupWindow.FindName('ChkWhatIf').IsChecked
    $isMock = ($script:oupAdModeUsed -eq 'Mock')

    # 2) Bestätigung — AD-Schreiben ist ein wirksamer Eingriff.
    if (-not $whatIf) {
        $head = if ($isMock) { "ACHTUNG: Quelle ist Mock (keine Domäne) — es wird nur simuliert.`n`n" } else { '' }
        $q = "$head$($entries.Count) Rechner in die AD-Gruppe`n'$($group.Name)'`nschreiben?"
        $ans = [System.Windows.MessageBox]::Show($script:oupWindow, $q, 'Mitglieder schreiben',
                   [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
        if ($ans -ne [System.Windows.MessageBoxResult]::Yes) { _Oup-SetStatus 'Import abgebrochen.'; return }
    }

    # 3) In AD schreiben (Modul -> ADSI -> bei Mock-Quelle simuliert).
    $adMode = if ($isMock) { 'Mock' } else { 'Auto' }
    $tag    = if ($whatIf) { "$adMode/Testlauf" } else { $adMode }
    _Oup-SetStatus "Schreibe $($entries.Count) Mitglied(er) in '$($group.Name)' ($tag)..."
    $results = @(Add-OupGroupMembers -GroupNode $group -Entries $entries.ToArray() `
                    -Mode $adMode -Server $script:oupSettings.AdServer -WhatIf:$whatIf)

    # 4) AD-Status je Eintrag anheften.
    $statusById = @{}
    foreach ($r in $results) { if ($r.identifier) { $statusById[$r.identifier] = $r.status } }
    foreach ($e in $entries) {
        $st = if ($statusById.ContainsKey($e.identifier)) { $statusById[$e.identifier] } else { 'Unbekannt' }
        if ($e.PSObject.Properties['adStatus'])    { $e.adStatus    = $st }          else { $e | Add-Member -NotePropertyName adStatus    -NotePropertyValue $st }
        if ($e.PSObject.Properties['targetGroup']) { $e.targetGroup = $group.Name }  else { $e | Add-Member -NotePropertyName targetGroup -NotePropertyValue $group.Name }
    }

    # 5) Ergebnis zählen.
    $counts = @{}
    foreach ($r in $results) {
        $counts[$r.status] = 1 + $(if ($counts.ContainsKey($r.status)) { $counts[$r.status] } else { 0 })
    }
    $summary = (($counts.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ')

    # 6) Persistieren: nur echte/simulierte Mitgliedschaften, kein Testlauf.
    $newStored = 0
    if (-not $whatIf) {
        $persist = @($entries | Where-Object { $_.adStatus -in @('Added', 'AlreadyMember', 'Simuliert') })
        if ($persist.Count -gt 0) {
            $newStored = (Add-OupImportEntries -Store $script:oupStore -GroupNode $group -Entries $persist)
        }
        Save-OupMapping -Store $script:oupStore -Path $script:oupMappingPath
    }

    # 7) Einstellungen merken + Anzeige aktualisieren.
    $script:oupSettings.LastImportDir = Split-Path -Parent $dlg.FileNames[0]
    Export-OupSettings -Settings $script:oupSettings -ConfigPath $script:oupConfigPath

    if ($whatIf) {
        # Probe-Ergebnisse anzeigen (nicht gespeichert).
        $script:oupImportItems.Clear()
        foreach ($e in $entries) { $script:oupImportItems.Add([PSCustomObject]$e) }
    } else {
        _Oup-OnNodeSelected -Node $group   # aus Store neu laden
        _Oup-UpdateGroupHeader -Node $group  # Zähler im Baum aktualisieren
    }

    $prefix = if ($whatIf) { 'Testlauf' } else { 'Import' }
    $msg = "${prefix}: $summary ($($entries.Count) gesamt, $newStored neu gespeichert)."
    if ($errors.Count -gt 0) { $msg += " Datei-Fehler: " + ($errors -join ' | ') }
    $lvl = if (($errors.Count -gt 0) -or $counts.ContainsKey('Error') -or $counts.ContainsKey('NotFound')) { 'WARN' } else { 'INFO' }
    _Oup-SetStatus $msg $lvl
}

function _Oup-OnImportSubOU {
    <#
        .SYNOPSIS  Geräte-Import in die gewählte SubOU. Jede Rechner-Zuweisung
                   (Software + Typ Job/Policy) wird in die Gruppe
                   <SubOU>-<Software>-<Typ> DIESER SubOU einsortiert.
        .DESCRIPTION  Passt der Standort am Rechner nicht zur gewählten SubOU bzw.
                      deren Standort, wird der Rechner übersprungen und in einen
                      CSV-Report dokumentiert. Fehlt die Zielgruppe in der SubOU,
                      erscheint Status 'Gruppe fehlt'.
    #>
    $ou = $script:oupSelectedNode
    if (-not $ou -or $ou.NodeType -ne 'OU') { _Oup-SetStatus 'Bitte eine SubOU wählen.' 'WARN'; return }

    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Filter      = 'JSON-Gerätelisten (*.json)|*.json|Alle Dateien (*.*)|*.*'
    $dlg.Multiselect = $true
    $dlg.Title       = "Geräte-JSON für SubOU '$($ou.Name)' wählen"
    if ($script:oupSettings.LastImportDir -and (Test-Path $script:oupSettings.LastImportDir)) {
        $dlg.InitialDirectory = $script:oupSettings.LastImportDir
    }
    if (-not $dlg.ShowDialog()) { return }

    $subName     = $ou.Name
    $subStandort = _Oup-RdnValue $ou.ParentDn          # Standort = Eltern-OU
    $subIndex    = Get-OupGroupIndex -Roots @($ou)      # Gruppen DIESER SubOU per Name

    # 1) Dateien parsen.
    $errors  = @()
    $devices = New-Object System.Collections.Generic.List[object]
    foreach ($file in $dlg.FileNames) {
        $r = Read-OupDeviceAssignmentFile -Path $file
        if ($r.Error) { $errors += "$(Split-Path -Leaf $file): $($r.Error)"; continue }
        if (-not $r.IsDeviceAssignment) { $errors += "$(Split-Path -Leaf $file): kein Geräte-Zuweisungsformat erkannt"; continue }
        foreach ($d in $r.Devices) { $devices.Add($d) }
    }
    if ($devices.Count -eq 0) {
        $m = 'Keine verwertbaren Geräte gefunden.'
        if ($errors.Count -gt 0) { $m += ' ' + ($errors -join ' | ') }
        [void][System.Windows.MessageBox]::Show($script:oupWindow, $m, 'Geräte-Import', 'OK', 'Warning')
        _Oup-SetStatus $m 'WARN'
        return
    }

    $whatIf = [bool]$script:oupWindow.FindName('ChkWhatIf').IsChecked
    $isMock = ($script:oupAdModeUsed -eq 'Mock')

    # 2) Standort-Abgleich + Auflösung Software/Typ -> Gruppe der SubOU.
    $buckets      = @{}    # GruppenGuid -> @{ node; entries }
    $computers    = @{}
    $missing      = @{}    # erwarteter Gruppenname -> $true
    $conflictRows = New-Object System.Collections.Generic.List[object]
    $allResults   = New-Object System.Collections.Generic.List[object]
    $counts       = @{}

    foreach ($d in $devices) {
        $id = $d.entry.identifier
        $computers[$id] = $true

        # Standort am Rechner muss zur SubOU bzw. deren Standort passen.
        if ($d.standort -and -not (($d.standort -ieq $subName) -or ($d.standort -ieq $subStandort))) {
            $conflictRows.Add([PSCustomObject]@{ Rechner = $id; Standort_Datei = $d.standort; Ziel_SubOU = $subName; Standort_SubOU = $subStandort })
            $row = $d.entry.PSObject.Copy()
            _Oup-SetEntryField $row 'targetGroup' "(Standort '$($d.standort)' != '$subName')"
            _Oup-SetEntryField $row 'adStatus' 'Konflikt'
            [void]$allResults.Add($row)
            $counts['Konflikt'] = 1 + $(if ($counts.ContainsKey('Konflikt')) { $counts['Konflikt'] } else { 0 })
            continue
        }

        foreach ($a in $d.assignments) {
            $type   = if ($a.type) { $a.type } else { 'Policy' }
            $target = "$subName-$($a.software)-$type"
            $node   = $subIndex.ByName[$target.ToLowerInvariant()]
            if (-not $node) {
                $missing[$target] = $true
                $row = $d.entry.PSObject.Copy()
                _Oup-SetEntryField $row 'targetGroup' $target
                _Oup-SetEntryField $row 'adStatus' 'Gruppe fehlt'
                [void]$allResults.Add($row)
                $counts['Gruppe fehlt'] = 1 + $(if ($counts.ContainsKey('Gruppe fehlt')) { $counts['Gruppe fehlt'] } else { 0 })
                continue
            }
            if (-not $buckets.ContainsKey($node.Guid)) {
                $buckets[$node.Guid] = [PSCustomObject]@{ node = $node; entries = (New-Object System.Collections.Generic.List[object]) }
            }
            $copy = $d.entry.PSObject.Copy()
            _Oup-SetEntryField $copy 'targetGroup' $node.Name
            $buckets[$node.Guid].entries.Add($copy)
        }
    }

    $totalMemberships = (@($buckets.Values | ForEach-Object { $_.entries.Count }) | Measure-Object -Sum).Sum

    # 3) Bestätigung.
    if (-not $whatIf) {
        $head = if ($isMock) { "ACHTUNG: Quelle ist Mock (keine Domäne) — es wird nur simuliert.`n`n" } else { '' }
        $extra = ''
        if ($conflictRows.Count -gt 0) { $extra += "`n$($conflictRows.Count) Rechner mit Standort-Konflikt werden übersprungen." }
        if ($missing.Count -gt 0)      { $extra += "`n$($missing.Count) Zielgruppen fehlen in der SubOU." }
        $q = "$head$($computers.Count) Rechner in SubOU '$subName' einsortieren`n($totalMemberships Mitgliedschaften)?$extra"
        $ans = [System.Windows.MessageBox]::Show($script:oupWindow, $q, 'Geräte-Import',
                   [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
        if ($ans -ne [System.Windows.MessageBoxResult]::Yes) { _Oup-SetStatus 'Geräte-Import abgebrochen.'; return }
    }

    # 4) Schreiben je Zielgruppe (Modul -> ADSI -> bei Mock simuliert).
    $adMode        = if ($isMock) { 'Mock' } else { 'Auto' }
    $groupsTouched = 0
    $stored        = 0
    _Oup-SetStatus "Geräte-Import: $($computers.Count) Rechner in '$subName' ($adMode$(if($whatIf){'/Testlauf'}))..."

    foreach ($b in $buckets.Values) {
        $entries = $b.entries.ToArray()
        $results = @(Add-OupGroupMembers -GroupNode $b.node -Entries $entries `
                        -Mode $adMode -Server $script:oupSettings.AdServer -WhatIf:$whatIf)
        $byId = @{}; foreach ($x in $results) { if ($x.identifier) { $byId[$x.identifier] = $x.status } }
        foreach ($e in $entries) {
            $st = if ($byId.ContainsKey($e.identifier)) { $byId[$e.identifier] } else { 'Unbekannt' }
            _Oup-SetEntryField $e 'adStatus' $st
            [void]$allResults.Add($e)
        }
        foreach ($x in $results) { $counts[$x.status] = 1 + $(if ($counts.ContainsKey($x.status)) { $counts[$x.status] } else { 0 }) }
        $groupsTouched++
        if (-not $whatIf) {
            $persist = @($entries | Where-Object { $_.adStatus -in @('Added', 'AlreadyMember', 'Simuliert') })
            if ($persist.Count -gt 0) { $stored += (Add-OupImportEntries -Store $script:oupStore -GroupNode $b.node -Entries $persist) }
        }
    }
    if (-not $whatIf) { Save-OupMapping -Store $script:oupStore -Path $script:oupMappingPath }

    # 5) Konflikte dokumentieren.
    $conflictReportPath = $null
    if ($conflictRows.Count -gt 0) {
        $conflictReportPath = _Oup-WriteConflictReport -Rows $conflictRows.ToArray() -AppRoot $script:oupAppRoot
    }

    # 6) Anzeige aktualisieren.
    $script:oupSettings.LastImportDir = Split-Path -Parent $dlg.FileNames[0]
    Export-OupSettings -Settings $script:oupSettings -ConfigPath $script:oupConfigPath
    $script:oupImportItems.Clear()
    foreach ($e in $allResults) { $script:oupImportItems.Add([PSCustomObject]$e) }
    if (-not $whatIf) { foreach ($b in $buckets.Values) { _Oup-UpdateGroupHeader -Node $b.node } }

    # 7) Ergebnis-Dialog.
    $summary = (($counts.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ')
    $prefix  = if ($whatIf) { 'Testlauf (SubOU)' } else { 'Geräte-Import' }
    $lines = @("SubOU '$subName': $($computers.Count) Rechner, $groupsTouched Zielgruppen, $totalMemberships Mitgliedschaften.", "Status: $summary")
    if (-not $whatIf -and $stored -gt 0) { $lines += "$stored neu im Store gespeichert." }
    if ($conflictRows.Count -gt 0) {
        $lines += "Standort-Konflikt übersprungen: $($conflictRows.Count) Rechner."
        if ($conflictReportPath) { $lines += "Dokumentiert in: $conflictReportPath" }
    }
    if ($missing.Count -gt 0) {
        $lines += "Fehlende Zielgruppen ($($missing.Count)): " + ((@($missing.Keys) | Select-Object -First 12) -join ', ')
    }
    if ($errors.Count -gt 0) { $lines += "Datei-Fehler: " + ($errors -join ' | ') }
    [void][System.Windows.MessageBox]::Show($script:oupWindow, ($lines -join "`n"), $prefix,
              [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)

    $lvl = if (($conflictRows.Count -gt 0) -or ($missing.Count -gt 0) -or $errors.Count -gt 0 -or $counts.ContainsKey('Error')) { 'WARN' } else { 'INFO' }
    _Oup-SetStatus "${prefix}: $($lines[0]) Status: $summary" $lvl
}

function _Oup-WriteConflictReport {
    <#  .SYNOPSIS  Schreibt übersprungene Standort-Konflikte als CSV nach Logs\,
                   damit der Admin die Clients nacharbeiten kann.  #>
    param([object[]]$Rows, [string]$AppRoot)
    $dir = Join-Path $AppRoot 'Logs'
    if (-not (Test-Path $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
    $path = Join-Path $dir ("konflikte-{0}.csv" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    try {
        $Rows | Export-Csv -Path $path -NoTypeInformation -Encoding UTF8
        foreach ($r in $Rows) { Write-OupLog "Standort-Konflikt übersprungen: $($r.Rechner)" 'WARN' }
        return $path
    } catch {
        Write-OupLog "Konflikt-Report konnte nicht geschrieben werden: $($_.Exception.Message)" 'ERROR'
        return $null
    }
}

function _Oup-OnImportAssign {
    <#
        .SYNOPSIS  Sammelimport (Form B): pro Rechner stehen seine Zielgruppen in
                   der JSON. Das Tool sortiert jeden Rechner in alle genannten
                   Gruppen ein — eine Datei fächert auf viele Gruppen.
        .DESCRIPTION  Standort-Regel: ein Rechner darf nur in Gruppen EINES
                      Standorts. Würde er über mehrere Standorte streuen (neue +
                      bereits gespeicherte), wird er komplett übersprungen
                      (Status 'Konflikt') und in einen CSV-Report dokumentiert.
    #>
    if (-not $script:oupRoots) { _Oup-SetStatus 'Kein Baum geladen.' 'WARN'; return }

    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Filter      = 'JSON-Sammellisten (*.json)|*.json|Alle Dateien (*.*)|*.*'
    $dlg.Multiselect = $true
    $dlg.Title       = 'Sammelliste(n) wählen — Rechner mit ihren Gruppen'
    if ($script:oupSettings.LastImportDir -and (Test-Path $script:oupSettings.LastImportDir)) {
        $dlg.InitialDirectory = $script:oupSettings.LastImportDir
    }
    if (-not $dlg.ShowDialog()) { return }

    # 1) Gruppen-Index + Standorte + Dateien einlesen, Rechner pro Gruppe sammeln.
    $index            = Get-OupGroupIndex -Roots $script:oupRoots
    $locations        = Get-OupGroupLocations -Roots $script:oupRoots
    $errors           = @()
    $unresolvedGroups = @{}      # Gruppenname -> $true (im Baum nicht gefunden)
    $buckets          = @{}      # GruppenGuid -> @{ node; entries(List) }
    $computers        = @{}      # Identifier -> $true (eindeutige Rechner)
    $clientStandorte  = @{}      # Identifier -> @{ Standort -> $true }
    $clientGroups     = @{}      # Identifier -> @{ Gruppenname -> $true }  (für Report)

    foreach ($file in $dlg.FileNames) {
        $r = Read-OupAssignmentFile -Path $file
        if ($r.Error) { $errors += "$(Split-Path -Leaf $file): $($r.Error)"; continue }
        if (-not $r.IsAssignment) { $errors += "$(Split-Path -Leaf $file): keine Rechner→Gruppen-Zuordnung erkannt"; continue }

        foreach ($a in $r.Assignments) {
            $id = $a.entry.identifier
            $computers[$id] = $true
            foreach ($gname in $a.groups) {
                $key = $gname.ToLowerInvariant()
                if (-not $index.ByName.ContainsKey($key)) { $unresolvedGroups[$gname] = $true; continue }
                $node = $index.ByName[$key]
                if (-not $buckets.ContainsKey($node.Guid)) {
                    $buckets[$node.Guid] = [PSCustomObject]@{ node = $node; entries = (New-Object System.Collections.Generic.List[object]) }
                }
                # Klon je Gruppe: ein Rechner kann in viele Gruppen -> jede Kopie
                # trägt ihre eigene Zielgruppe und ihren eigenen AD-Status.
                $copy = $a.entry.PSObject.Copy()
                if ($copy.PSObject.Properties['targetGroup']) { $copy.targetGroup = $node.Name }
                else { $copy | Add-Member -NotePropertyName targetGroup -NotePropertyValue $node.Name }
                $buckets[$node.Guid].entries.Add($copy)

                # Standort/Gruppe je Rechner für die Konfliktprüfung merken.
                if (-not $clientGroups.ContainsKey($id)) { $clientGroups[$id] = @{} }
                $clientGroups[$id][$node.Name] = $true
                $loc = $locations.ByGuid[$node.Guid]
                if ($loc -and $loc.Standort) {
                    if (-not $clientStandorte.ContainsKey($id)) { $clientStandorte[$id] = @{} }
                    $clientStandorte[$id][$loc.Standort] = $true
                }
            }
        }
    }

    $totalMemberships = (@($buckets.Values | ForEach-Object { $_.entries.Count }) | Measure-Object -Sum).Sum
    if ($buckets.Count -eq 0) {
        $lines = @('Keine Gruppe aus der Datei konnte einer AD-Gruppe zugeordnet werden.')
        $lines += 'Die Gruppennamen in der JSON müssen exakt den Namen im Baum entsprechen.'
        if ($unresolvedGroups.Count -gt 0) {
            $lines += "Unbekannte Gruppen ($($unresolvedGroups.Count)): " + ((@($unresolvedGroups.Keys) | Select-Object -First 15) -join ', ')
        }
        if ($errors.Count -gt 0) { $lines += "Datei-Fehler: " + ($errors -join ' | ') }
        [void][System.Windows.MessageBox]::Show($script:oupWindow, ($lines -join "`n"), 'Sammelimport — nichts zugeordnet',
                  [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        _Oup-SetStatus ($lines -join ' ') 'WARN'
        return
    }

    # 1b) Standort-Konflikte: bereits gespeicherte Mitgliedschaften einbeziehen,
    # dann Rechner mit >1 Standort markieren (werden übersprungen + dokumentiert).
    foreach ($id in @($computers.Keys)) {
        foreach ($m in (Get-OupClientMemberships -Store $script:oupStore -Identifier $id)) {
            $loc = $locations.ByGuid[$m.guid]
            if ($loc -and $loc.Standort) {
                if (-not $clientStandorte.ContainsKey($id)) { $clientStandorte[$id] = @{} }
                $clientStandorte[$id][$loc.Standort] = $true
            }
        }
    }
    $conflicted = @{}   # Identifier -> string[] Standorte
    foreach ($id in @($clientStandorte.Keys)) {
        if ($clientStandorte[$id].Count -gt 1) { $conflicted[$id] = @($clientStandorte[$id].Keys) }
    }

    $whatIf = [bool]$script:oupWindow.FindName('ChkWhatIf').IsChecked
    $isMock = ($script:oupAdModeUsed -eq 'Mock')

    # 2) Bestätigung.
    if (-not $whatIf) {
        $head = if ($isMock) { "ACHTUNG: Quelle ist Mock (keine Domäne) — es wird nur simuliert.`n`n" } else { '' }
        $conf = if ($conflicted.Count -gt 0) { "`n`n$($conflicted.Count) Rechner mit Standort-Konflikt werden übersprungen und dokumentiert." } else { '' }
        $q = "$head$($computers.Count) Rechner auf $($buckets.Count) Gruppen verteilen`n($totalMemberships Mitgliedschaften)?$conf"
        $ans = [System.Windows.MessageBox]::Show($script:oupWindow, $q, 'Sammelimport',
                   [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
        if ($ans -ne [System.Windows.MessageBoxResult]::Yes) { _Oup-SetStatus 'Sammelimport abgebrochen.'; return }
    }

    # 3) Je Gruppe schreiben (Modul -> ADSI -> bei Mock simuliert).
    $adMode       = if ($isMock) { 'Mock' } else { 'Auto' }
    $counts       = @{}
    $groupsTouched = 0
    $stored       = 0
    $allResults   = New-Object System.Collections.Generic.List[object]   # alle Zeilen fürs Grid
    _Oup-SetStatus "Sammelimport: verteile $($computers.Count) Rechner auf $($buckets.Count) Gruppen ($adMode$(if($whatIf){'/Testlauf'}))..."

    foreach ($b in $buckets.Values) {
        $all   = $b.entries.ToArray()
        $clean = @($all | Where-Object { -not $conflicted.ContainsKey($_.identifier) })
        $bad   = @($all | Where-Object {     $conflicted.ContainsKey($_.identifier) })

        # Konflikt-Rechner werden NICHT geschrieben, nur als 'Konflikt' angezeigt.
        foreach ($e in $bad) {
            if ($e.PSObject.Properties['adStatus']) { $e.adStatus = 'Konflikt' } else { $e | Add-Member -NotePropertyName adStatus -NotePropertyValue 'Konflikt' -Force }
            [void]$allResults.Add($e)
            $counts['Konflikt'] = 1 + $(if ($counts.ContainsKey('Konflikt')) { $counts['Konflikt'] } else { 0 })
        }

        if ($clean.Count -gt 0) {
            $results = @(Add-OupGroupMembers -GroupNode $b.node -Entries $clean `
                            -Mode $adMode -Server $script:oupSettings.AdServer -WhatIf:$whatIf)
            $byId = @{}; foreach ($x in $results) { if ($x.identifier) { $byId[$x.identifier] = $x.status } }
            foreach ($e in $clean) {
                $st = if ($byId.ContainsKey($e.identifier)) { $byId[$e.identifier] } else { 'Unbekannt' }
                if ($e.PSObject.Properties['adStatus']) { $e.adStatus = $st } else { $e | Add-Member -NotePropertyName adStatus -NotePropertyValue $st -Force }
                [void]$allResults.Add($e)
            }
            foreach ($x in $results) { $counts[$x.status] = 1 + $(if ($counts.ContainsKey($x.status)) { $counts[$x.status] } else { 0 }) }
            $groupsTouched++

            if (-not $whatIf) {
                $persist = @($clean | Where-Object { $_.adStatus -in @('Added', 'AlreadyMember', 'Simuliert') })
                if ($persist.Count -gt 0) { $stored += (Add-OupImportEntries -Store $script:oupStore -GroupNode $b.node -Entries $persist) }
            }
        }
    }
    if (-not $whatIf) { Save-OupMapping -Store $script:oupStore -Path $script:oupMappingPath }

    # Konflikt-Rechner dokumentieren (auch im Testlauf, zur Vorab-Kontrolle).
    $conflictReportPath = $null
    if ($conflicted.Count -gt 0) {
        $rows = foreach ($id in $conflicted.Keys) {
            [PSCustomObject]@{
                Rechner   = $id
                Standorte = ($conflicted[$id] -join '; ')
                Gruppen   = (@($clientGroups[$id].Keys) -join '; ')
            }
        }
        $conflictReportPath = _Oup-WriteConflictReport -Rows @($rows) -AppRoot $script:oupAppRoot
    }

    # 4) Einstellungen + Anzeige aktualisieren.
    $script:oupSettings.LastImportDir = Split-Path -Parent $dlg.FileNames[0]
    Export-OupSettings -Settings $script:oupSettings -ConfigPath $script:oupConfigPath

    # Ergebnisse sichtbar machen: alle Zeilen ins Grid (mit Gruppe + AD-Status),
    # Zähler der betroffenen Gruppen im Baum hochsetzen.
    $script:oupImportItems.Clear()
    foreach ($e in $allResults) { $script:oupImportItems.Add([PSCustomObject]$e) }
    if (-not $whatIf) { foreach ($b in $buckets.Values) { _Oup-UpdateGroupHeader -Node $b.node } }
    $script:oupSelectedNode = $null
    $script:oupWindow.FindName('BtnImport').IsEnabled = $false
    $script:oupWindow.FindName('TxtGroupName').Text = "Sammelimport-Ergebnis"
    $script:oupWindow.FindName('TxtGroupGuid').Text = "$($computers.Count) Rechner · $groupsTouched Gruppen · $totalMemberships Mitgliedschaften"
    $script:oupWindow.FindName('TxtGroupDn').Text   = ''

    # 5) Ergebnis als Dialog (umfasst viele Gruppen -> Statuszeile reicht nicht).
    $summary = (($counts.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ')
    $prefix  = if ($whatIf) { 'Testlauf (Sammel)' } else { 'Sammelimport' }
    $lines = @()
    $lines += "$($computers.Count) Rechner -> $groupsTouched Gruppen, $totalMemberships Mitgliedschaften."
    $lines += "Status: $summary"
    if (-not $whatIf -and $stored -gt 0) { $lines += "$stored neu im Store gespeichert." }
    if ($conflicted.Count -gt 0) {
        $lines += "Standort-Konflikt übersprungen: $($conflicted.Count) Rechner (" + ((@($conflicted.Keys) | Select-Object -First 10) -join ', ') + ")."
        if ($conflictReportPath) { $lines += "Dokumentiert in: $conflictReportPath" }
    }
    if ($unresolvedGroups.Count -gt 0) {
        $lines += "Unbekannte Gruppen ($($unresolvedGroups.Count)): " + ((@($unresolvedGroups.Keys) | Select-Object -First 15) -join ', ')
    }
    if ($errors.Count -gt 0) { $lines += "Datei-Fehler: " + ($errors -join ' | ') }
    [void][System.Windows.MessageBox]::Show($script:oupWindow, ($lines -join "`n"), $prefix,
              [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)

    $lvl = if (($conflicted.Count -gt 0) -or ($unresolvedGroups.Count -gt 0) -or $errors.Count -gt 0 -or $counts.ContainsKey('Error') -or $counts.ContainsKey('NotFound')) { 'WARN' } else { 'INFO' }
    _Oup-SetStatus "${prefix}: $($lines[0]) Status: $summary" $lvl
}

$script:OupLookupXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Rechner-Übersicht" Width="740" Height="520"
        WindowStartupLocation="CenterOwner" FontFamily="Segoe UI" FontSize="13"
        Background="{DynamicResource Theme.Background}"
        TextElement.Foreground="{DynamicResource Theme.TextPrimary}">
  <DockPanel Margin="12">
    <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="0,0,0,8">
      <TextBlock Text="Rechner:" VerticalAlignment="Center" Margin="0,0,6,0"/>
      <TextBox x:Name="TxtClient" Width="260" VerticalAlignment="Center"/>
      <Button x:Name="BtnSearch" Content="Suchen" Padding="12,3" Margin="8,0,0,0" IsDefault="True"/>
    </StackPanel>
    <Border x:Name="WarnBanner" DockPanel.Dock="Top" Background="#FFF4CE" BorderBrush="#E6C200"
            BorderThickness="1" Padding="8,5" Margin="0,0,0,8" Visibility="Collapsed">
      <TextBlock x:Name="WarnText" TextWrapping="Wrap" Foreground="#7A5C00"/>
    </Border>
    <TextBlock x:Name="LblSummary" DockPanel.Dock="Top" Margin="0,0,0,6" Foreground="{DynamicResource Theme.TextSecondary}"
               Text="Rechnernamen eingeben und Suchen."/>
    <DataGrid x:Name="GridGroups" AutoGenerateColumns="False" IsReadOnly="True"
              CanUserAddRows="False" HeadersVisibility="Column" GridLinesVisibility="Horizontal">
      <DataGrid.Columns>
        <DataGridTextColumn Header="Standort"      Binding="{Binding Standort}"      Width="1*"/>
        <DataGridTextColumn Header="Unterstandort" Binding="{Binding Unterstandort}" Width="1.2*"/>
        <DataGridTextColumn Header="Gruppe"        Binding="{Binding Gruppe}"        Width="2*"/>
        <DataGridTextColumn Header="AD-Status"     Binding="{Binding adStatus}"      Width="100"/>
        <DataGridTextColumn Header="Quelle"        Binding="{Binding sourceFile}"    Width="1.2*"/>
      </DataGrid.Columns>
    </DataGrid>
  </DockPanel>
</Window>
'@

function _Oup-DoClientLookup {
    <#  .SYNOPSIS  Sucht die Gruppen eines Rechners und warnt bei mehreren Standorten.  #>
    $id = ([string]$script:oupLookupWin.FindName('TxtClient').Text).Trim()
    $script:oupLookupItems.Clear()
    $script:oupLookupWin.FindName('WarnBanner').Visibility = 'Collapsed'
    if (-not $id) { $script:oupLookupWin.FindName('LblSummary').Text = 'Bitte einen Rechnernamen eingeben.'; return }

    $memb      = @(Get-OupClientMemberships -Store $script:oupStore -Identifier $id)
    $standorte = @{}
    foreach ($m in $memb) {
        $loc = $script:oupLookupLocs.ByGuid[$m.guid]
        $st  = if ($loc) { $loc.Standort } else { '' }
        $ust = if ($loc) { $loc.Unterstandort } else { '' }
        if ($st) { $standorte[$st] = $true }
        $script:oupLookupItems.Add([PSCustomObject]@{
            Standort = $st; Unterstandort = $ust; Gruppe = $m.name; adStatus = $m.adStatus; sourceFile = $m.sourceFile
        })
    }

    $script:oupLookupWin.FindName('LblSummary').Text =
        "${id}: $($memb.Count) Gruppe(n) in $($standorte.Count) Standort(en)."
    if ($standorte.Count -gt 1) {
        $script:oupLookupWin.FindName('WarnText').Text =
            "Achtung: Dieser Rechner ist in mehreren Standorten (" + ((@($standorte.Keys)) -join ', ') +
            "). Laut Regel sollte er nur an einem Standort sein — bitte nacharbeiten."
        $script:oupLookupWin.FindName('WarnBanner').Visibility = 'Visible'
    }
}

function _Oup-OnClientLookup {
    <#  .SYNOPSIS  Öffnet die Rechner-Übersicht (in welchen Gruppen ist ein Client).  #>
    if (-not $script:oupStore) { return }

    $reader = New-Object System.Xml.XmlNodeReader ([xml]$script:OupLookupXaml)
    $script:oupLookupWin   = [System.Windows.Markup.XamlReader]::Load($reader)
    $script:oupLookupItems = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
    $script:oupLookupLocs  = if ($script:oupRoots) { Get-OupGroupLocations -Roots $script:oupRoots } else { [PSCustomObject]@{ ByGuid = @{} } }

    $script:oupLookupWin.FindName('GridGroups').ItemsSource = $script:oupLookupItems
    $script:oupLookupWin.FindName('BtnSearch').Add_Click({ _Oup-DoClientLookup })
    if ($script:oupWindow) { $script:oupLookupWin.Owner = $script:oupWindow }

    [void]$script:oupLookupWin.ShowDialog()
}

function _Oup-SetTheme {
    <#  .SYNOPSIS  Wechselt Stil/Palette live (Switch-Theme), persistiert die Wahl
                   in settings.json und aktualisiert die Menü-Häkchen.  #>
    param([string]$Style, [string]$Palette)
    try {
        [void](Switch-Theme -Style $Style -Palette $Palette)
    } catch {
        _Oup-SetStatus "Theme-Wechsel fehlgeschlagen: $($_.Exception.Message)" 'WARN'
        return
    }
    if ($Style)   { $script:oupSettings.UiStyle   = $Style }
    if ($Palette) { $script:oupSettings.UiPalette = $Palette }
    Export-OupSettings -Settings $script:oupSettings -ConfigPath $script:oupConfigPath
    _Oup-RefreshViewMenuChecks
    _Oup-SetStatus "Ansicht: Stil $($script:oupSettings.UiStyle), Palette $($script:oupSettings.UiPalette)."
}

function _Oup-RefreshViewMenuChecks {
    <#  .SYNOPSIS  Setzt die Häkchen im Ansicht-Menü auf die aktive Wahl.  #>
    if ($script:oupPaletteItems) {
        foreach ($k in @($script:oupPaletteItems.Keys)) {
            $script:oupPaletteItems[$k].IsChecked = ($k -ieq $script:oupSettings.UiPalette)
        }
    }
    if ($script:oupStyleItems) {
        foreach ($k in @($script:oupStyleItems.Keys)) {
            $script:oupStyleItems[$k].IsChecked = ($k -ieq $script:oupSettings.UiStyle)
        }
    }
}

function _Oup-BuildViewMenu {
    <#  .SYNOPSIS  Baut das Ansicht-Menü: Untermenüs 'Farbschema' (Paletten) und
                   'Stil' (Sharp/Soft), je Eintrag abhakbar + Live-Umschaltung.  #>
    $menu = $script:oupWindow.FindName('MenuView')
    if (-not $menu) { return }
    $menu.Items.Clear()
    $script:oupPaletteItems = @{}
    $script:oupStyleItems   = @{}

    # Farbschema (Palette)
    $palRoot = New-Object System.Windows.Controls.MenuItem
    $palRoot.Header = 'Farbschema'
    foreach ($p in (Get-AvailablePalettes)) {
        $mi = New-Object System.Windows.Controls.MenuItem
        $mi.Header      = $p
        $mi.IsCheckable = $true
        $mi.IsChecked   = ($p -ieq $script:oupSettings.UiPalette)
        $mi.Tag         = $p
        # Kein GetNewClosure: Handler bleibt an den Modulkontext gebunden, damit
        # _Oup-SetTheme und $script:-State auflösbar sind. Wert kommt aus $s.Tag.
        $mi.Add_Click({ param($s, $e) _Oup-SetTheme -Palette ([string]$s.Tag) })
        [void]$palRoot.Items.Add($mi)
        $script:oupPaletteItems[$p] = $mi
    }
    [void]$menu.Items.Add($palRoot)

    # Stil (Geometrie)
    $styleRoot = New-Object System.Windows.Controls.MenuItem
    $styleRoot.Header = 'Stil'
    foreach ($st in (Get-AvailableStyles)) {
        $mi = New-Object System.Windows.Controls.MenuItem
        $mi.Header      = $st
        $mi.IsCheckable = $true
        $mi.IsChecked   = ($st -ieq $script:oupSettings.UiStyle)
        $mi.Tag         = $st
        $mi.Add_Click({ param($s, $e) _Oup-SetTheme -Style ([string]$s.Tag) })
        [void]$styleRoot.Items.Add($mi)
        $script:oupStyleItems[$st] = $mi
    }
    [void]$menu.Items.Add($styleRoot)
}

function Show-OupMainWindow {
    <#
        .SYNOPSIS  Baut das Hauptfenster, lädt AD + Store und zeigt es modal an.
        .PARAMETER AppRoot     Wurzelverzeichnis (wo main.ps1 liegt).
        .PARAMETER ConfigPath  Pfad zu settings.json.
    #>
    param(
        [Parameter(Mandatory)][string]$AppRoot,
        [Parameter(Mandatory)][string]$ConfigPath,
        [int]$SelfTestMs = 0   # >0: Fenster nach N ms automatisch schließen (Test)
    )

    $script:oupAppRoot     = $AppRoot
    $script:oupConfigPath  = $ConfigPath
    $script:oupSettings    = Import-OupSettings -ConfigPath $ConfigPath
    $script:oupMappingPath = Get-OupMappingPath -ConfiguredPath $script:oupSettings.MappingPath -AppRoot $AppRoot
    $script:oupStore       = Import-OupMapping -Path $script:oupMappingPath

    # Feld-Map (optional) laden und anwenden — erweitert die Parser-Feldnamen um
    # site-spezifische aus fieldmap.json (falls vorhanden). Vor jedem Import wirksam.
    $script:oupFieldMapNote = $null
    try {
        $fmPath = Get-OupFieldMapPath -ConfiguredPath $script:oupSettings.FieldMapPath -AppRoot $AppRoot
        $fmCfg  = Import-OupFieldMap -Path $fmPath
        if ($fmCfg) {
            $fm = Set-OupFieldMap -Config $fmCfg
            if ($fm.CustomCount -gt 0) {
                Write-OupLog ("Feld-Map aktiv: {0} eigene Feldname(n) aus {1} ({2})." -f `
                    $fm.CustomCount, (Split-Path -Leaf $fmPath), ($fm.Keys -join ', '))
                $script:oupFieldMapNote = "Feld-Map: $($fm.CustomCount) eigene Feldnamen aktiv."
            }
        }
    } catch {
        Write-OupLog "Feld-Map konnte nicht angewendet werden: $($_.Exception.Message)" 'WARN'
    }

    # Theme (Palette + Stil) laden — MUSS vor XamlReader.Load stehen, damit die
    # DynamicResource-Referenzen im Fenster aufgelöst werden. Legt bei Bedarf ein
    # Application-Objekt an und merged die ResourceDictionaries app-weit.
    try {
        [void](Initialize-Theme -Style $script:oupSettings.UiStyle `
                                -Palette $script:oupSettings.UiPalette -ScriptRoot $AppRoot)
    } catch {
        Write-OupLog "Theme konnte nicht geladen werden: $($_.Exception.Message)" 'WARN'
    }

    # Fenster aus XAML.
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$script:OupMainXaml)
    $script:oupWindow = [System.Windows.Markup.XamlReader]::Load($reader)

    $script:oupTree        = $script:oupWindow.FindName('TreeAd')
    $script:oupImportItems = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
    $script:oupWindow.FindName('GridImports').ItemsSource = $script:oupImportItems

    # Events.
    $script:oupTree.Add_SelectedItemChanged({
        param($s, $e)
        # Items sind TreeViewItem-Objekte; der AD-Knoten hängt an .Tag.
        $node = if ($e.NewValue -is [System.Windows.Controls.TreeViewItem]) { $e.NewValue.Tag } else { $e.NewValue }
        _Oup-OnNodeSelected -Node $node
    })
    $script:oupWindow.FindName('BtnReload').Add_Click({ _Oup-LoadTree })
    $script:oupWindow.FindName('BtnImport').Add_Click({
        if ($script:oupImportMode -eq 'SubOU') { _Oup-OnImportSubOU } else { _Oup-OnImport }
    })
    $script:oupWindow.FindName('BtnImportAssign').Add_Click({ _Oup-OnImportAssign })
    $script:oupWindow.FindName('BtnRemove').Add_Click({ _Oup-OnRemoveMembers })
    # Grid-Auswahl steuert die Verfügbarkeit von „Ausgewählte entfernen".
    $script:oupWindow.FindName('GridImports').Add_SelectionChanged({ _Oup-UpdateRemoveEnabled })

    # Baum-Filter: bei jeder Eingabe neu zeichnen; ✕-Button leert das Feld
    # (das TextChanged-Event zeichnet dann den vollen Baum).
    $script:oupWindow.FindName('TxtFilter').Add_TextChanged({ param($s, $e) _Oup-OnFilterChanged -Text $s.Text })
    $script:oupWindow.FindName('BtnFilterClear').Add_Click({ $script:oupWindow.FindName('TxtFilter').Text = '' })

    # Menü.
    $script:oupWindow.FindName('MenuReload').Add_Click({ _Oup-LoadTree })
    $script:oupWindow.FindName('MenuExit').Add_Click({ $script:oupWindow.Close() })
    $script:oupWindow.FindName('MenuClientLookup').Add_Click({ _Oup-OnClientLookup })
    $script:oupWindow.FindName('MenuInfo').Add_Click({
        if (Get-Command Show-OupAboutDialog -ErrorAction SilentlyContinue) {
            Show-OupAboutDialog -Version '1.4.0' -Settings $script:oupSettings -Owner $script:oupWindow
        }
    })

    # Ansicht-Menü (Farbschema/Stil) dynamisch aus dem Theme-Loader aufbauen.
    _Oup-BuildViewMenu

    # Erstbefüllung.
    _Oup-LoadTree
    if ($script:oupFieldMapNote) {
        $st = $script:oupWindow.FindName('TxtStatus')
        if ($st) { $st.Text = "$($st.Text)  ·  $($script:oupFieldMapNote)" }
    }

    # Optionaler Selbsttest: nach SelfTestMs automatisch schließen.
    if ($SelfTestMs -gt 0) {
        $timer = New-Object System.Windows.Threading.DispatcherTimer
        $timer.Interval = [TimeSpan]::FromMilliseconds($SelfTestMs)
        # Kein GetNewClosure: so bleibt der $script:-Modulkontext erhalten.
        # Den Timer selbst stoppen wir über $sender (Tick-Sender).
        $timer.Add_Tick({ param($sender, $e) $sender.Stop(); $script:oupWindow.Close() })
        $timer.Start()
    }

    [void]$script:oupWindow.ShowDialog()
}

Export-ModuleMember -Function Show-OupMainWindow
