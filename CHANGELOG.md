# Changelog — OUPilot

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
