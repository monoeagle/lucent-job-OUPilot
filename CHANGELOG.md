# Changelog — OUPilot

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
