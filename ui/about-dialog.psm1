# ui/about-dialog.psm1 — Info-/Über-Dialog (äquivalent zum CodeSigningCommander).
# Modaler WPF-Dialog mit zwei Tabs (Info, Changelog), per XAML-Here-String.

Add-Type -AssemblyName PresentationFramework

$script:OupAboutXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Über OUPilot" Width="620" Height="560"
        MinWidth="520" MinHeight="420"
        WindowStartupLocation="CenterOwner" ResizeMode="CanResize"
        ShowInTaskbar="False" FontFamily="Segoe UI" FontSize="13">
  <DockPanel Margin="22,18,22,14">

    <!-- Schließen-Button unten -->
    <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
      <Button x:Name="BtnOk" Content="Schließen" MinWidth="100" Padding="10,4" IsDefault="True" IsCancel="True"/>
    </StackPanel>

    <!-- Header: Icon + Titel -->
    <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="0,0,0,14">
      <TextBlock FontSize="40" Margin="0,0,14,0" VerticalAlignment="Center" Text="&#x1F4E6;"/>
      <StackPanel VerticalAlignment="Center">
        <TextBlock Text="OUPilot" FontSize="20" FontWeight="SemiBold"/>
        <TextBlock x:Name="LblVersion" FontSize="13" Foreground="#777"/>
        <TextBlock Text="AD-Software-Gruppen · MECM-Deployment · Rechner-Einsortierung"
                   FontSize="12" Margin="0,2,0,0" Foreground="#777"/>
      </StackPanel>
    </StackPanel>

    <TabControl x:Name="Tabs" Background="Transparent">
      <TabItem Header="Info">
        <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="8,10,8,8">
          <StackPanel>

            <TextBlock Text="System" FontSize="13" FontWeight="SemiBold" Margin="0,0,0,6" Foreground="#0078D4"/>
            <Grid Margin="0,0,0,14">
              <Grid.ColumnDefinitions><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
              <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
              <TextBlock Grid.Row="0" Grid.Column="0" Text="AD-Quelle:"  Margin="0,2" Foreground="#777"/>
              <TextBlock Grid.Row="0" Grid.Column="1" x:Name="LblAdMode" Margin="0,2"/>
              <TextBlock Grid.Row="1" Grid.Column="0" Text="PowerShell:" Margin="0,2" Foreground="#777"/>
              <TextBlock Grid.Row="1" Grid.Column="1" x:Name="LblPwsh"   Margin="0,2"/>
              <TextBlock Grid.Row="2" Grid.Column="0" Text="OS:"         Margin="0,2" Foreground="#777"/>
              <TextBlock Grid.Row="2" Grid.Column="1" x:Name="LblOs"     Margin="0,2" TextWrapping="Wrap"/>
            </Grid>

            <TextBlock Text="Projekt" FontSize="13" FontWeight="SemiBold" Margin="0,0,0,6" Foreground="#0078D4"/>
            <Grid Margin="0,0,0,14">
              <Grid.ColumnDefinitions><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
              <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
              <TextBlock Grid.Row="0" Grid.Column="0" Text="Entwickler:" Margin="0,2" Foreground="#777"/>
              <TextBlock Grid.Row="0" Grid.Column="1" x:Name="LblDeveloper" Margin="0,2"/>
              <TextBlock Grid.Row="1" Grid.Column="0" Text="E-Mail:"     Margin="0,2" Foreground="#777"/>
              <TextBlock Grid.Row="1" Grid.Column="1" x:Name="LblEmail"  Margin="0,2"/>
              <TextBlock Grid.Row="2" Grid.Column="0" Text="App-Pfad:"   Margin="0,2" Foreground="#777"/>
              <TextBlock Grid.Row="2" Grid.Column="1" x:Name="LblAppPath" Margin="0,2" TextWrapping="Wrap"/>
            </Grid>

            <TextBlock Text="Komponenten" FontSize="13" FontWeight="SemiBold" Margin="0,0,0,6" Foreground="#0078D4"/>
            <TextBlock TextWrapping="Wrap" Foreground="#555" FontSize="12">
              · AD-Lesen: ActiveDirectory-Modul &#8594; ADSI &#8594; Mock (Fallback)<LineBreak/>
              · AD-Schreiben: Add-ADGroupMember &#8594; ADSI, mit WhatIf-Testlauf<LineBreak/>
              · Stabile Gruppen-Identität über objectGUID<LineBreak/>
              · GUID-Mapping-Store (lokale JSON) mit AD-Status je Eintrag<LineBreak/>
              · Einzel- und Sammelimport (Rechner&#8594;Gruppen)<LineBreak/>
              · WPF auf Windows PowerShell 5.1 (Quelldateien UTF-8 mit BOM)
            </TextBlock>

          </StackPanel>
        </ScrollViewer>
      </TabItem>

      <TabItem Header="Changelog">
        <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" Padding="8,10,8,8">
          <TextBlock x:Name="LblChangelog" FontFamily="Consolas, Courier New" FontSize="12" TextWrapping="NoWrap"/>
        </ScrollViewer>
      </TabItem>
    </TabControl>
  </DockPanel>
</Window>
'@

function _OupAbout-GetGitConfig {
    param([string]$Key)
    try {
        $val = & git config --get $Key 2>$null
        if ($LASTEXITCODE -eq 0 -and $val) { return [string]$val.Trim() }
    } catch { }
    return $null
}

function _OupAbout-LoadChangelog {
    param([string]$AppDir, [int]$MaxBytes = 200000)
    $path = Join-Path $AppDir 'CHANGELOG.md'
    if (-not (Test-Path -LiteralPath $path)) { return "(CHANGELOG.md nicht gefunden in $AppDir)" }
    try {
        $content = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        if ($content.Length -gt $MaxBytes) {
            $content = $content.Substring(0, $MaxBytes) + "`n`n... (gekürzt — siehe CHANGELOG.md)"
        }
        return $content
    } catch {
        return "(CHANGELOG.md konnte nicht gelesen werden: $($_.Exception.Message))"
    }
}

function Show-OupAboutDialog {
    <#
        .SYNOPSIS  Zeigt den Info-/Über-Dialog modal an.
        .PARAMETER Version   Anzeige-Version.
        .PARAMETER Settings  App-Einstellungen (für AD-Quelle).
        .PARAMETER Owner     Besitzerfenster (für CenterOwner).
    #>
    param(
        [string]$Version = '1.0.0',
        $Settings,
        [System.Windows.Window]$Owner,
        [int]$SelfTestMs = 0   # >0: Dialog nach N ms automatisch schließen (Test)
    )

    $reader = New-Object System.Xml.XmlNodeReader ([xml]$script:OupAboutXaml)
    $win    = [System.Windows.Markup.XamlReader]::Load($reader)

    $win.FindName('LblVersion').Text = "Version $Version"

    # System
    $adMode = if ($Settings -and $Settings.AdMode) { [string]$Settings.AdMode } else { 'Auto' }
    $win.FindName('LblAdMode').Text = $adMode

    $edition = [string]$PSVersionTable.PSEdition
    if ([string]::IsNullOrWhiteSpace($edition)) { $edition = 'Desktop' }
    $win.FindName('LblPwsh').Text = "$($PSVersionTable.PSVersion) ($edition)"

    try   { $os = (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).Caption }
    catch { $os = [string][System.Environment]::OSVersion.VersionString }
    $win.FindName('LblOs').Text = $os

    # Projekt
    $appDir   = Split-Path -Parent $PSScriptRoot   # ui/ -> App-Root
    $devName  = _OupAbout-GetGitConfig -Key 'user.name'
    $devEmail = _OupAbout-GetGitConfig -Key 'user.email'
    if (-not $devName)  { $devName  = 'Tobias Philipp' }
    if (-not $devEmail) { $devEmail = '—' }
    $win.FindName('LblDeveloper').Text = $devName
    $win.FindName('LblEmail').Text     = $devEmail
    $win.FindName('LblAppPath').Text   = $appDir

    # Changelog
    $win.FindName('LblChangelog').Text = _OupAbout-LoadChangelog -AppDir $appDir

    $win.FindName('BtnOk').Add_Click({ $win.DialogResult = $true; $win.Close() }.GetNewClosure())

    if (-not $Owner) {
        $app = [System.Windows.Application]::Current
        if ($app) {
            foreach ($w in $app.Windows) { if ($w.IsActive) { $Owner = $w; break } }
            if (-not $Owner) { $Owner = $app.MainWindow }
        }
    }
    if ($Owner) { $win.Owner = $Owner }

    if ($SelfTestMs -gt 0) {
        $timer = New-Object System.Windows.Threading.DispatcherTimer
        $timer.Interval = [TimeSpan]::FromMilliseconds($SelfTestMs)
        $timer.Add_Tick({ param($s, $e) $s.Stop(); $win.Close() }.GetNewClosure())
        $timer.Start()
    }

    [void]$win.ShowDialog()
}

Export-ModuleMember -Function Show-OupAboutDialog
