# Changelog — OUPilot

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
