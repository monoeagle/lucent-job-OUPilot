# OUPilot — Testclient-Checkliste (echtes AD)

Ziel: Die real schreibenden AD-Pfade (`Add-ADGroupMember` / `Remove-ADGroupMember`
→ ADSI-Fallback) auf einem **domänenverbundenen Testclient** gegenprüfen. Auf dem
Entwicklungs-Client ist bislang nur der **Mock**-Pfad verifiziert.

**Grundregel:** immer erst **„Nur Testlauf (WhatIf)"**, dann — nach Sichtprüfung —
echt schreiben. Nur an **Test-OUs / Test-Gruppen / Test-Rechnern** arbeiten.

---

## 0. Voraussetzungen

- [ ] Testclient ist **Domänenmitglied** (oder hat Leitungssicht auf einen DC).
- [ ] Angemeldeter Benutzer darf **Gruppenmitgliedschaften ändern** (Schreibrecht
      auf `member` der Zielgruppen). Für Pfad 1 zusätzlich **RSAT / AD-Modul**
      (`Get-Module -ListAvailable ActiveDirectory`). Ohne RSAT greift automatisch
      **ADSI** (Pfad 2, kein RSAT nötig).
- [ ] **Test-Struktur** vorhanden: mind. ein Standort → Unterstandort mit einigen
      `-Policy`/`-Job`-Softwaregruppen und ein paar **Test-Computerobjekten**.
- [ ] Windows **PowerShell 5.1** (Desktop) verfügbar (`$PSVersionTable`), WPF läuft
      darüber (`run.ps1` startet mit `-STA`).

## 1. Übertragen & Konfigurieren

- [ ] Projektordner auf den Testclient kopieren (ohne `data\mapping.json` und
      `Logs\` — frisch starten, damit der Store leer ist).
- [ ] `settings.json` prüfen/setzen:
  - [ ] `AdMode` = `Auto` (empfohlen). Für gezielten Test: `Module` **oder** `Adsi`
        erzwingen. **Nicht** `Mock` — sonst wird nur simuliert.
  - [ ] `AdSearchBase` = DN der gewünschten Baumwurzel (leer = `defaultNamingContext`).
  - [ ] `AdServer` = DC-Name, falls ein bestimmter DC gewünscht ist (sonst leer).
- [ ] Optional: eigene `fieldmap.json` anlegen, falls die echten Exporte
      abweichende Feldnamen haben (Vorlage `samples\fieldmap.example.json`).

## 2. Start & Lese-Pfad (nicht-destruktiv)

- [ ] `.\run.ps1` starten.
- [ ] **Baum lädt echte OUs/Gruppen** (nicht die Mock-Standorte).
- [ ] Toolbar-Zeile **„Quelle:"** zeigt `Module` **oder** `Adsi` —
      **NICHT** „Mock-Daten (keine Domäne)".
      > Steht dort Mock, schlug das AD-Lesen fehl → **STOP**, erst Rechte/RSAT/DC
      > klären (`Logs\oupilot.log` nennt den Grund je Pfad). Kein Schreibtest, bis
      > die Quelle echt ist.
- [ ] Wird eine Feld-Map genutzt: Statuszeile meldet „Feld-Map: N eigene Feldnamen
      aktiv."

## 3. Hinzufügen — Testlauf (WhatIf)

- [ ] Haken **„Nur Testlauf (WhatIf)"** setzen.
- [ ] Eine Gruppe wählen → **„In gewählte Gruppe importieren…"**, kleine Testliste
      (bekannte Test-Rechner + bewusst einen nicht existierenden Namen).
- [ ] Erwartete **AD-Status** im Grid:
  - `Would` = würde hinzugefügt (existiert, noch kein Mitglied)
  - `AlreadyMember` = ist bereits drin
  - `NotFound` = im AD nicht auffindbar (der Fake-Name)
- [ ] **Keine** Änderung im AD (mit ADUC / `Get-ADGroupMember` gegenprüfen).
      Store (`data\mapping.json`) bleibt **unverändert** (Testlauf speichert nicht).

## 4. Hinzufügen — echt

- [ ] Haken **entfernen** → **„In gewählte Gruppe importieren…"**.
- [ ] Bestätigungsdialog (Gruppenname + Anzahl) mit **Ja**.
- [ ] Erwartete Status: `Added` (neu), `AlreadyMember` (schon drin),
      ggf. `NotFound`/`Error`.
- [ ] **Verifikation im AD**:
      ```powershell
      Get-ADGroupMember -Identity '<GruppenName-oder-GUID>' | Select-Object name
      ```
      Die Test-Rechner müssen jetzt Mitglied sein.
- [ ] Mitglieder-**Zähler am Baumknoten** ist hochgesprungen.
- [ ] `data\mapping.json` enthält die Gruppe (Schlüssel = **objectGUID**) mit den
      Einträgen und `adStatus`.

## 5. Entfernen — Testlauf, dann echt

- [ ] Gruppe wählen, im Grid **eine/mehrere Zeilen markieren**.
- [ ] Mit **WhatIf**: **„Ausgewählte entfernen…"** → Status `Would` (würde entfernt)
      bzw. `NotMember` (war nicht drin). **Keine** AD-Änderung.
- [ ] Ohne WhatIf: erneut **„Ausgewählte entfernen…"** → Warn-Dialog mit **Ja**.
  - [ ] Status `Removed` (entfernt) / `NotMember` (war nicht mehr drin).
  - [ ] **Verifikation**: `Get-ADGroupMember …` zeigt die Rechner **nicht mehr**.
  - [ ] Aus `data\mapping.json` sind die Einträge **entfernt**, Baumzähler
        korrigiert.

## 6. Stabilität der objectGUID (Umbenennen/Verschieben)

- [ ] Eine bereits genutzte Gruppe im AD **umbenennen** (oder in andere OU
      verschieben).
- [ ] In OUPilot **„AD neu einlesen"**.
- [ ] Die Gruppe wird über die **GUID wiedererkannt**; der neue Name erscheint,
      die im Store hinterlegten Mitglieder bleiben zugeordnet (kein Doppel-Eintrag).

## 7. Hauptworkflow: Geräte-Import in SubOU

- [ ] Eine **SubOU (Unterstandort)** im Baum wählen.
- [ ] **„Geräte-JSON in SubOU '…' importieren…"** mit einer realen/Test-Geräteliste
      (`computer` + `standort` + `assignments[software,type]`).
- [ ] Jede Zuweisung landet in `<SubOU>-<Software>-<Typ>` **dieser** SubOU.
- [ ] Passt der **Standort** am Rechner nicht → Rechner **übersprungen** (`Konflikt`)
      und in `Logs\konflikte-<ts>.csv` dokumentiert.
- [ ] Fehlt die Zielgruppe → Status `Gruppe fehlt`.
- [ ] Erst WhatIf, dann echt (wie oben).

## 8. Sammelliste (Rechner→Gruppen) + Standort-Eindeutigkeit

- [ ] **„Sammelliste importieren (Rechner→Gruppen)…"** mit voll qualifizierten
      Gruppennamen.
- [ ] Ein Rechner, der über **mehrere Standorte** streuen würde (neue + bereits
      gespeicherte Mitgliedschaften), wird **komplett übersprungen** (`Konflikt`)
      und in `Logs\konflikte-<ts>.csv` dokumentiert — **nichts** wird für ihn
      geschrieben.
- [ ] Unbekannte Gruppennamen werden gesammelt gemeldet (nichts halb geschrieben).

## 9. Rechner-Übersicht (Verifikation aus dem Store)

- [ ] Menü **„Rechner suchen…"**, einen Testrechner eingeben.
- [ ] Zeigt alle Gruppen (Standort/Unterstandort/AD-Status/Quelle); bei mehreren
      Standorten erscheint die **Warnung**.

## 9b. DSM-Export-Import (Standort-Ebene)

- [ ] `samples\dsm-mapping.example.json` nach `dsm-mapping.json` (App-Root)
      kopieren; Test-Standort-OU mit Gruppen nach `<RBSSt>-<App>-<Endung>`
      vorhanden (RBSSt = OU-Name).
- [ ] **Standort-OU** (ohne direkte Gruppen) wählen → Knopf wechselt auf
      „DSM-Export in Standort '…' importieren…".
- [ ] Erst **Testlauf** mit den `samples\RBSSt0*.txt`-Dateien: Bestätigungs-/
      Ergebniszahlen prüfen (9 Rechner, 11 Mitgliedschaften, 4 Gruppen,
      2 abgelehnte Dateien, `RBSSt01-VLC-Policy` fehlt), dann echt.
- [ ] `Logs\dsm-report-*.csv` prüfen: abgelehnte Dateien (Validation/fremder
      RBSSt), Deny-/deaktivierte/abgelaufene Policies, fehlende Mappings/
      Zielgruppen, Nicht-Computer-Mitglieder.
- [ ] Ohne `dsm-mapping.json` bricht der Import mit klarer Meldung ab.

## 10. Logs & Aufräumen

- [ ] `Logs\oupilot.log` durchsehen: genutzter **Lese-/Schreibpfad** (Module/Adsi),
      Warnungen, Fehler.
- [ ] `Logs\konflikte-*.csv` gegen die erwarteten Konflikte prüfen.
- [ ] **Testdaten zurückbauen**: hinzugefügte Test-Mitgliedschaften wieder
      entfernen (über OUPilot oder AD), Testgruppen ggf. zurückbenennen.

---

## Statuswerte (Spalte „AD-Status")

| Status          | Bedeutung                                              |
|-----------------|--------------------------------------------------------|
| `Added`         | hinzugefügt                                            |
| `Removed`       | entfernt                                               |
| `AlreadyMember` | war bereits Mitglied (Add)                             |
| `NotMember`     | war (nicht mehr) Mitglied (Remove)                     |
| `Would`         | Testlauf: würde hinzugefügt/entfernt                   |
| `NotFound`      | Objekt im AD nicht auffindbar                          |
| `Simuliert`     | Mock-Quelle — **kein echter Schreibvorgang**           |
| `Error`         | Schreibfehler (Details in `Logs\oupilot.log`)          |
| `Konflikt`      | Standort-Konflikt — übersprungen + CSV dokumentiert    |
| `Gruppe fehlt`  | Zielgruppe in der SubOU nicht vorhanden                |

## Abnahme

| Bereich                         | OK | Bemerkung |
|---------------------------------|----|-----------|
| Lesen zeigt echte Quelle        |    |           |
| Hinzufügen WhatIf → echt        |    |           |
| Entfernen WhatIf → echt         |    |           |
| GUID-Wiedererkennung            |    |           |
| SubOU-Geräte-Import             |    |           |
| Sammelliste + Standort-Konflikt |    |           |
| Rechner-Übersicht               |    |           |
| DSM-Export-Import (Standort)    |    |           |

Getestet von: _______________  Datum: __________  App-Version: 1.4.0
