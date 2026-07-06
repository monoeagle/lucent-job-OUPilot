# Projektstruktur

```
run.ps1                 Launcher (PS 5.1, STA)
main.ps1                Bootstrap: Module laden, Fenster öffnen
core/
  log.psm1              Logging -> Logs\oupilot.log
  settings.psm1         settings.json laden/speichern
  ad-reader.psm1        OU/Gruppen lesen (Modul/ADSI/Mock), GUID als Schlüssel
  ad-writer.psm1        Rechner als Gruppenmitglieder schreiben/entfernen
  mapping-store.psm1    GUID-Mapping-Store (data\mapping.json)
  import-engine.psm1    JSON-Exporte parsen & normalisieren (+ Feld-Map)
  dsm-import.psm1       DSM-Export-Dateien -> Import-Plan (Standort-Import, + Mapping-Loader)
ui/
  main-window.psm1      Hauptfenster: OU-TreeView + Import-Panel + Filter
  about-dialog.psm1     Info-/Über-Dialog (Tabs Info + Changelog)
  theme-loader.psm1     Theme-System: Palette + Stil mergen, live umschalten
  themes/               sharp.xaml / soft.xaml + palettes/*.xaml (12 Schemata)
tools/
  Ensure-Utf8Bom.ps1    Quelldateien als UTF-8 mit BOM sichern + Parsecheck
  test-dsm-import.ps1   Testet dsm-import.psm1 gegen samples\RBSSt0*.txt
run-docs.ps1            diese Doku-Site bauen/servieren (zensical)
OUPilot-docs/           Doku-Site (zensical), identisch zu anderen Lucent-Projekten
samples/                Beispiel-Exporte + fieldmap.example.json + dsm-mapping.example.json + RBSSt0*.txt
fieldmap.json           optional (App-Root): eigene Feldnamen; nicht eingecheckt
dsm-mapping.json        optional (App-Root): DSM-Paketname -> AD-App-Name; nicht eingecheckt
```

## Persistenz

- `settings.json` — App-Einstellungen (`AdMode`, `AdSearchBase`, `AdServer`,
  `MappingPath`, `FieldMapPath`, `DsmMappingPath`, `UiStyle`, `UiPalette`,
  `LastImportDir`).
- `data\mapping.json` — der eigentliche Zustand: pro Gruppen-**GUID** die Liste
  der importierten Einträge plus zuletzt bekannter Name/DN/SID.

## Workflow-Pflicht

Nach jeder Änderung an `.ps1`/`.psm1` `tools\Ensure-Utf8Bom.ps1` laufen lassen
(UTF-8 + BOM + Parsecheck). Headless-Tests als `samples\__*.ps1` (PS 5.1),
danach löschen; UI via `Show-OupMainWindow -SelfTestMs <ms>`.
