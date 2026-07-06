# Schnellstart

1. **Starten:** `.\run.ps1`. Ohne Domäne fällt das Einlesen automatisch auf
   **Mock-Daten** zurück, sodass die Oberfläche sofort bedienbar ist
   (Beispieldateien unter `samples\`).
2. **Baum:** Links erscheint die OU-Struktur (Standorte → Unterstandorte →
   `<SubOU>-<Software>-<Typ>`-Gruppen). Über dem Baum filtert ein Suchfeld live
   nach Namen (siehe [Baum-Filter](../referenz/baum-filter.md)).
3. **Auswählen:** Eine **SubOU** (Hauptworkflow) oder eine einzelne **Gruppe**
   wählen.
4. **Importieren:** Über die Buttons einen JSON-Export einlesen. Mit
   **„Nur Testlauf (WhatIf)"** wird zunächst nur simuliert.
5. **Prüfen:** Das Grid rechts zeigt je Rechner den **AD-Status**; der Baum-Zähler
   an der Gruppe springt nach dem Import hoch.

Die verschiedenen Importformate sind unter [Import-Wege](../referenz/import-wege.md)
beschrieben; das echte AD-Vorgehen unter
[Testclient-Checkliste](../betrieb/testclient.md).
