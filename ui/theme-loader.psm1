# Theme-Loader für CSC v5.0 WPF-UI.
# Lädt zwei ResourceDictionaries nacheinander in Application.Current.Resources:
#   1. Palette (ui/themes/palettes/<palette>.xaml) — Farb-Brushes
#   2. Style   (ui/themes/<style>.xaml)            — Geometrie + Control-Styles (via DynamicResource)
#
# Nutzung aus main.ps1 vor Show-MainWindow:
#   Initialize-Theme -Style $settings.UiStyle -Palette $settings.UiPalette -ScriptRoot $scriptDir

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# Mapping: Settings-Wert → Datei-Basename (ohne .xaml)
$script:validStyles = @{
    'Sharp' = 'sharp'
    'Soft'  = 'soft'
}
$script:validPalettes = @{
    'Gray'   = 'gray'
    'Blue'   = 'blue'
    'Mint'   = 'mint'
    'Amber'  = 'amber'
    'Rose'   = 'rose'
    'Purple' = 'purple'
    'Teal'   = 'teal'
    'Sage'   = 'sage'
    'Slate'  = 'slate'
    'Coral'  = 'coral'
    'Ocean'  = 'ocean'
    'Forest' = 'forest'
}

function Get-AvailableThemes {
    # Für Kompatibilität: Style-Liste wie vorher
    return @($script:validStyles.Keys | Sort-Object)
}
function Get-AvailableStyles {
    return @($script:validStyles.Keys | Sort-Object)
}
function Get-AvailablePalettes {
    # Definierte Reihenfolge (nicht alphabetisch) — nach Wärme/Kühle gruppiert
    return @('Gray','Slate','Blue','Ocean','Teal','Mint','Sage','Forest','Amber','Coral','Rose','Purple')
}

function _Resolve-PaletteFile {
    param([string]$Palette, [string]$ScriptRoot)
    $baseName = $script:validPalettes[$Palette]
    if (-not $baseName) {
        Write-Warning "Unbekannte UiPalette '$Palette' — fallback auf 'Gray'"
        $baseName = 'gray'
    }
    $path = Join-Path $ScriptRoot "ui\themes\palettes\$baseName.xaml"
    if (-not (Test-Path $path)) { throw "Palette-Datei nicht gefunden: $path" }
    return $path
}

function _Resolve-StyleFile {
    param([string]$Style, [string]$ScriptRoot)
    $baseName = $script:validStyles[$Style]
    if (-not $baseName) {
        Write-Warning "Unbekannter UiStyle '$Style' — fallback auf 'Sharp'"
        $baseName = 'sharp'
    }
    $path = Join-Path $ScriptRoot "ui\themes\$baseName.xaml"
    if (-not (Test-Path $path)) { throw "Style-Datei nicht gefunden: $path" }
    return $path
}

# Kompatibilitäts-Wrapper für alten Einzelargument-Aufruf (bleibt für Tests/Scripts)
function Resolve-ThemeFile {
    param([string]$Style, [string]$ScriptRoot)
    return (_Resolve-StyleFile -Style $Style -ScriptRoot $ScriptRoot)
}

function _Load-Dict {
    param([string]$Path)
    $stream = [System.IO.File]::OpenRead((Resolve-Path $Path).Path)
    try {
        return [System.Windows.Markup.XamlReader]::Load($stream)
    } finally { $stream.Close() }
}

# Modul-Scope: gemerkter ScriptRoot für Switch-Theme-Live-Reload ohne expliziten Parameter
$script:activeScriptRoot = $null
$script:activeStyle      = $null
$script:activePalette    = $null

function Initialize-Theme {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Style,
        [string]$Palette = 'Gray',
        [Parameter(Mandatory)] [string]$ScriptRoot
    )
    # WPF-XAML-Parser reagiert auf CurrentCulture (Komma vs. Punkt in Thickness)
    [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('en-US')

    if ($null -eq [System.Windows.Application]::Current) {
        $null = New-Object System.Windows.Application
    }
    $app = [System.Windows.Application]::Current

    $palettePath = _Resolve-PaletteFile -Palette $Palette -ScriptRoot $ScriptRoot
    $stylePath   = _Resolve-StyleFile   -Style   $Style   -ScriptRoot $ScriptRoot

    $paletteDict = _Load-Dict $palettePath
    $styleDict   = _Load-Dict $stylePath

    # Alte Theme-Dicts entfernen: alles mit Theme.PaletteMarker ODER Theme.StyleMarker
    $toRemove = @()
    foreach ($rd in $app.Resources.MergedDictionaries) {
        if ($rd.Contains('Theme.PaletteMarker') -or $rd.Contains('Theme.StyleMarker') -or $rd.Contains('Theme.Accent')) {
            $toRemove += $rd
        }
    }
    foreach ($rd in $toRemove) { [void]$app.Resources.MergedDictionaries.Remove($rd) }

    # Palette ZUERST — damit DynamicResources im Style aufgelöst werden können
    [void]$app.Resources.MergedDictionaries.Add($paletteDict)
    [void]$app.Resources.MergedDictionaries.Add($styleDict)

    # State merken für späteres Switch-Theme
    $script:activeScriptRoot = $ScriptRoot
    $script:activeStyle      = $Style
    $script:activePalette    = $Palette

    return @{ Style = $Style; Palette = $Palette }
}

# Live-Reload: Theme tauschen, ohne ScriptRoot explizit angeben zu müssen.
# Nutzt den beim Initialize-Theme-Aufruf gemerkten ScriptRoot.
function Switch-Theme {
    [CmdletBinding()]
    param(
        [string]$Style,
        [string]$Palette
    )
    if ([string]::IsNullOrWhiteSpace($script:activeScriptRoot)) {
        throw "Switch-Theme aufgerufen bevor Initialize-Theme lief — ScriptRoot unbekannt"
    }
    $useStyle   = if ($Style)   { $Style }   else { $script:activeStyle }
    $usePalette = if ($Palette) { $Palette } else { $script:activePalette }
    return Initialize-Theme -Style $useStyle -Palette $usePalette -ScriptRoot $script:activeScriptRoot
}

function Get-ActiveTheme {
    return @{ Style = $script:activeStyle; Palette = $script:activePalette; ScriptRoot = $script:activeScriptRoot }
}

Export-ModuleMember -Function Initialize-Theme, Switch-Theme, Get-ActiveTheme, Resolve-ThemeFile, Get-AvailableThemes, Get-AvailableStyles, Get-AvailablePalettes
