# core/settings.psm1 — App-Einstellungen als flache settings.json im App-Root.
# Muster wie CodeSigningCommander: Import-Settings / Export-Settings, Defaults
# wenn die Datei fehlt. (Noch ohne DPAPI — hier sind keine Geheimnisse nötig.)

function Get-OupDefaultSettings {
    <#  .SYNOPSIS  Standardwerte, falls settings.json fehlt.  #>
    return [ordered]@{
        # AD-Auslesemodus: 'Auto' = ActiveDirectory-Modul, sonst ADSI, sonst Mock.
        #                  'Module' / 'Adsi' / 'Mock' erzwingen einen Pfad.
        AdMode        = 'Auto'
        # SearchBase (DN) für die OU-Baumwurzel. Leer = defaultNamingContext der Domäne.
        AdSearchBase  = ''
        # Optionaler Domänencontroller/Server. Leer = automatisch.
        AdServer      = ''
        # Pfad zum GUID-Mapping-Store (leer = <AppRoot>\data\mapping.json).
        MappingPath   = ''
        # Pfad zur optionalen Feld-Map für exotische Export-Formate
        # (leer = <AppRoot>\fieldmap.json; fehlt die Datei, gelten nur die
        # eingebauten Feldnamen). Siehe samples\fieldmap.example.json.
        FieldMapPath  = ''
        # Pfad zur DSM-Mapping-Datei (DSM-Paketname -> AD-App-Name) für den
        # DSM-Export-Import (leer = <AppRoot>\dsm-mapping.json; fehlt die Datei,
        # ist kein DSM-Import möglich). Vorlage: samples\dsm-mapping.example.json.
        DsmMappingPath = ''
        # UI — Theme-System (Muster wie CodeSigningCommander):
        #   UiStyle   = Geometrie 'Sharp' (scharfe Ecken) | 'Soft' (3px, luftiger)
        #   UiPalette = Farbschema (Gray, Slate, Blue, Ocean, Teal, Mint, Sage,
        #               Forest, Amber, Coral, Rose, Purple)
        UiStyle       = 'Sharp'
        UiPalette     = 'Gray'
        # Zuletzt genutztes Verzeichnis für JSON-Importe.
        LastImportDir = ''
    }
}

function Import-OupSettings {
    <#  .SYNOPSIS  Lädt settings.json (oder Defaults) als Hashtable.  #>
    param([Parameter(Mandatory)][string]$ConfigPath)

    $defaults = Get-OupDefaultSettings
    if (-not (Test-Path $ConfigPath)) { return $defaults }

    try {
        $json = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    } catch {
        return $defaults
    }

    # Defaults mit gespeicherten Werten überschreiben (vorwärtskompatibel:
    # neue Default-Keys bleiben erhalten, unbekannte alte Keys werden ignoriert).
    $merged = [ordered]@{}
    foreach ($k in $defaults.Keys) {
        if ($json.PSObject.Properties[$k]) { $merged[$k] = $json.$k }
        else                                { $merged[$k] = $defaults[$k] }
    }
    return $merged
}

function Export-OupSettings {
    <#  .SYNOPSIS  Schreibt Einstellungen nach settings.json (UTF-8).  #>
    param(
        [Parameter(Mandatory)]$Settings,
        [Parameter(Mandatory)][string]$ConfigPath
    )
    $Settings | ConvertTo-Json -Depth 4 | Out-File $ConfigPath -Encoding UTF8 -Force
}

Export-ModuleMember -Function Get-OupDefaultSettings, Import-OupSettings, Export-OupSettings
