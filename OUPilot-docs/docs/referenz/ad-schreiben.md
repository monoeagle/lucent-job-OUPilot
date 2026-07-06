# AD-Schreiben (Mitglieder hinzufügen)

Beim Import werden die Rechner als Mitglieder in die gewählte Gruppe geschrieben
(`core/ad-writer.psm1`):

- **Pfad 1** `Add-ADGroupMember` (RSAT) → **Pfad 2** ADSI (`member`-Attribut +
  `CommitChanges`) als Fallback. Wurde der Baum aus **Mock** gelesen, wird nur
  **simuliert** (kein echter Schreibvorgang).
- **Auflösung der Rechner:** über den Identifier des Exports (SID > GUID >
  sAMAccountName > Name). Bevorzugt werden **Computer**objekte.
- **Vorab-Dedupe:** bestehende Mitglieder werden gelesen → bereits enthaltene
  Rechner ergeben Status `AlreadyMember` (locale-unabhängig, ohne Fehlertext).
- **Testlauf (WhatIf):** Checkbox „Nur Testlauf" — zeigt pro Rechner, was passieren
  *würde*, ohne ins AD zu schreiben und ohne zu speichern.
- **Bestätigung:** vor echtem Schreiben fragt eine Ja/Nein-Box mit Gruppenname und
  Anzahl.

## Statuswerte (Spalte AD-Status)

| Status          | Bedeutung                                              |
|-----------------|--------------------------------------------------------|
| `Added`         | hinzugefügt                                            |
| `AlreadyMember` | war bereits Mitglied                                   |
| `Removed`       | entfernt (siehe [Mitglieder entfernen](mitglieder-entfernen.md)) |
| `NotMember`     | war (nicht mehr) Mitglied                              |
| `NotFound`      | Objekt im AD nicht auffindbar                          |
| `Would`         | Testlauf: würde geschrieben/entfernt                   |
| `Simuliert`     | Mock-Quelle — kein echter Schreibvorgang               |
| `Error`         | Schreibfehler (Details in `Logs\oupilot.log`)          |

Der AD-Status wird auch im [GUID-Mapping-Store](../entwicklung/projektstruktur.md)
je Eintrag gespeichert.
