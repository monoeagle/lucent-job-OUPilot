# Mitglieder entfernen

Ist im Baum eine **Gruppe** gewählt, zeigt das Grid ihre gespeicherten Mitglieder.
Eine oder mehrere Zeilen markieren (Mehrfachauswahl) und **Ausgewählte entfernen…**
klicken: die Rechner werden aus der AD-Gruppe genommen (`Remove-ADGroupMember` →
ADSI-Fallback, bei Mock nur simuliert) **und** aus dem lokalen Store gelöscht.

- Vor dem echten Schreiben fragt eine Ja/Nein-Box (destruktiver Eingriff).
- Mit **Nur Testlauf (WhatIf)** wird nur gemeldet, was passieren *würde*
  (Status `Would`), ohne etwas zu ändern.
- Aus dem Store entfernt wird nur, was danach tatsächlich kein Mitglied mehr ist
  (`Removed`/`NotMember`/`Simuliert`); war der Rechner gar nicht (mehr) drin,
  erscheint `NotMember`.
- Der Button ist nur aktiv, wenn eine Gruppe gewählt und mindestens eine Zeile
  markiert ist.

Kern: `Remove-OupGroupMembers` (`core/ad-writer.psm1`) und `Remove-OupImportEntries`
(`core/mapping-store.psm1`, `$`-/case-tolerant). Der Baum-Zähler wird nach dem
Entfernen korrigiert.
