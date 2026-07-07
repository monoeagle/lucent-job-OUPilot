# Changelog — OUPilot

## Unreleased
- DSM-Export-Import (Standort-Ebene): eine JSON-Datei je DSM-Gruppe
  (`<RBSSt>_<Gruppe>.txt` nach `int_jsonStructure.md`, SchemaVersion 1.0) wird
  in AD-Mitgliedschaften `<RBSSt>-<App>-<Endung>` übersetzt (Endungen `Policy`,
  `Job`, `Policy-Available`, `Job-Available` aus PolicySchemaTag × AssignmentMode).
  Namensbrücke über `dsm-mapping.json` (DSM-Paketname → AD-App-Name, Settings-Key
  `DsmMappingPath`, Vorlage `samples\dsm-mapping.example.json`). Deny-Policies,
  deaktivierte/abgelaufene/noch-nicht-aktive Policies, Nicht-Computer-Mitglieder,
  fehlende Mappings/Zielgruppen und abgelehnte Dateien (Validation-Gate, fremder
  RBSSt) landen im CSV-Report `Logs\dsm-report-*.csv`. Dynamische Gruppen werden
  über den exportierten Snapshot einsortiert.
- core: neues Modul `dsm-import.psm1` (`Read-OupDsmGroupFile`,
  `Resolve-OupDsmAssignments`, `New-OupDsmImportPlan`, Mapping-Loader); UI:
  dritter Import-Modus `Standort` (OU ohne direkte Gruppen, mit Gruppen in
  Sub-OUs); Mock um Standort `RBSSt01` nach realem AD-Muster erweitert;
  Test-Harness `tools\test-dsm-import.ps1`.
- Mock-Standorte auf generisches **RBSSt-Schema** vereinheitlicht (RBSSt02–04
  mit Unterstandorten statt Städtenamen) — inkl. gekoppelter Samples
  (`devices-rbsst02-nord.json` u. a.) und Doku-Beispiele.
- Doku-Site auf **zensical/Material** (`OUPilot-docs\`) — Layout identisch zu den
  anderen Lucent-Projekten: Icon-Rail-Navigation, Aktivitäts-Heatmap + Insights aus
  der Git-Historie, gerenderte Diagramme (AP-Übersicht, Architektur, Roadmap als
  SVG). Start via `run-docs.ps1` bzw. `run_OUPilot_docs.sh` (eigenes `.venv-docs`,
  `font=false` = CDN-frei). Als **gh-pages** veröffentlicht. Ersetzt den früheren
  PowerShell-Generator.

## 1.4.0
- Konfigurierbare Feld-Map: optionale `fieldmap.json` (App-Root, Pfad via
  Settings-Key `FieldMapPath`) ergänzt die Parser-Feldnamen um site-spezifische
  für exotische Export-Formate — eigene Namen werden vorangestellt (gewinnen),
  case-insensitiv dedupliziert; bestehende Formate bleiben unberührt.
- Beim Start geladen/angewandt (`Set-OupFieldMap`); Statuszeile + Log melden die
  Zahl aktiver eigener Feldnamen. Vorlage: `samples/fieldmap.example.json`.
- core: `Get-OupFieldMapPath`, `Import-OupFieldMap`, `Set-OupFieldMap`
  (import-engine); Schlüssel für Identifier-Map und Sammel-/Geräte-Parser.
- Doku: Testclient-Checkliste für den echten AD-Gegentest
  (`docs/Testclient-Checkliste.md`, aus README verlinkt) — Add/Remove je erst
  WhatIf dann echt, GUID-Wiedererkennung, Standort-Konflikt, Status-Tabelle,
  Abnahme.

## 1.3.0
- Mitglieder entfernen: bei gewählter Gruppe im Grid markierte Rechner per
  „Ausgewählte entfernen…" aus der AD-Gruppe (Remove-ADGroupMember → ADSI, bei
  Mock simuliert) UND aus dem Store nehmen. Mehrfachauswahl, WhatIf-Testlauf,
  Ja/Nein-Bestätigung vor echtem Schreiben.
- Neue Statuswerte `Removed`/`NotMember`; aus dem Store entfernt wird nur, was
  danach kein Mitglied mehr ist. Baum-Zähler wird korrigiert.
- core: `Remove-OupGroupMembers` (ad-writer, Modul/ADSI/Mock) und
  `Remove-OupImportEntries` (mapping-store, $-/case-tolerant).

## 1.2.0
- Baum-Filter: Suchfeld über dem OU-/Gruppen-Baum filtert live nach Namen
  (Teiltext, case-insensitiv). Vorfahren von Treffern bleiben sichtbar, matcht
  ein OU-Name selbst, erscheint der ganze Teilbaum; OU-Knoten werden bei aktivem
  Filter aufgeklappt. Statuszeile zeigt die Trefferzahl, ✕-Button leert den Filter.

## 1.1.0
- Theme-System (Muster wie CodeSigningCommander): Menü **Ansicht** schaltet
  **Farbschema** (12 Paletten: Gray, Slate, Blue, Ocean, Teal, Mint, Sage,
  Forest, Amber, Coral, Rose, Purple) und **Stil** (Sharp/Soft) live um.
- Palette + Stil als getrennte ResourceDictionaries (`ui/theme-loader.psm1`,
  `ui/themes/`); Control-Styles ziehen Farben per DynamicResource.
- Auswahl wird in `settings.json` persistiert (`UiStyle`, `UiPalette`).
- Haupt-, Rechner-Übersicht- und Info-Fenster nutzen jetzt Theme-Farben statt
  hartkodierter Werte.

## 1.0.0
- OU-/Gruppen-TreeView mit Standorten → Unterstandorten → Anwendungs-Gruppen.
- AD-Lesen mit Fallback: ActiveDirectory-Modul → ADSI → Mock (ohne Domäne).
- Stabile Gruppen-Identität über objectGUID (überlebt Umbenennen/Verschieben).
- AD-Schreiben: Rechner als Gruppenmitglieder via Add-ADGroupMember → ADSI,
  mit Vorab-Dedupe, WhatIf-Testlauf und Bestätigung.
- Zwei Importwege:
  - In gewählte Gruppe (eine Liste = eine Gruppe).
  - Sammelliste „Rechner→Gruppen" (eine Datei fächert auf viele Gruppen).
- GUID-Mapping-Store (lokale JSON) mit AD-Status und Zielgruppe je Eintrag.
- Sichtbares Feedback: Mitglieder-Zähler im Baum, Ergebniszeilen im Grid.
- Info-/Über-Dialog.
- Windows PowerShell 5.1 (WPF), Quelldateien als UTF-8 mit BOM.
