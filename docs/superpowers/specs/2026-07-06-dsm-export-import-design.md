# Design: DSM-Export-Import (Ivanti-DSM-Gruppendateien verarbeiten)

Datum: 2026-07-06 · Status: freigegeben · Spec-Grundlage: `int_jsonStructure.md`

## Kontext & Ziel

Ein Export-Skript liefert **eine JSON-Datei pro DSM-Gruppe** (Dateiname
`<RBSSt>_<Gruppenname>.txt`, Inhalt JSON nach `int_jsonStructure.md`,
`SchemaVersion 1.0`). Jede Datei enthält die Gruppenmitglieder (Rechner) und
die DSM-Policy-Zuweisungen (Software) der Gruppe.

OUPilot soll daraus die Rechner in die **AD-Software-Gruppen des Standorts**
einsortieren: jedes Mitglied wird für jede relevante Policy-Zuweisung Mitglied
der zugehörigen AD-Gruppe. Die AD-Struktur: pro Standort eine OU (Name =
RBSSt-Wert), darunter je Anwendung eine Sub-OU mit den Software-Gruppen.
Jeder Standortadmin sieht nur seine eigene OU.

Der Export liefert bewusst mehr Felder, als aktuell gebraucht werden
(Reserve für spätere Funktionen) — diese Spec verarbeitet nur die unten
genannten Felder; alles andere bleibt ungenutzt.

## Entscheidungen (mit Nutzer abgestimmt)

| Thema | Entscheidung |
|---|---|
| Verarbeitung | Mitglieder × relevante Policy-Zuweisungen → AD-Gruppenmitgliedschaften |
| Namensbrücke Software | Mapping-Datei `dsm-mapping.json` (DSM-Paketname → AD-App-Name), exakt, case-insensitiv; ohne Eintrag → Report |
| Standort-Brücke | `RBSSt` = Name der AD-Standort-OU, direkter Abgleich gegen die gewählte OU |
| Zielgruppen-Endung | Kombination aus PolicySchemaTag × AssignmentMode (vier Endungen, s. u.) |
| Deny-Policies | Nicht automatisieren — nur im Report ausweisen (Deny-Gruppen existieren im AD noch nicht) |
| Fehlende Zielgruppe | Nur Report, kein Anlegen (OUPilot bleibt reines Mitglieder-Werkzeug) |
| Available-Zuweisungen | Eigene Zielgruppen (`-Policy-Available` / `-Job-Available`) |
| Dynamische Gruppen | `ResolvedSnapshot`-Mitglieder verwenden, Hinweis im Report; `DynamicRules` ungenutzt |
| Umsetzungsansatz | Eigenes Modul `core/dsm-import.psm1` + neuer Workflow am Standort-Knoten; `import-engine.psm1` bleibt unberührt |

## Architektur & Datenfluss

Neues Modul **`core/dsm-import.psm1`**, UI-frei, dreistufige Pipeline:

```
DSM-Dateien (*.txt, JSON)
   │
   ▼
Read-OupDsmGroupFile          je Datei: JSON parsen, SchemaVersion prüfen,
   │                          Validation-Gate, Mitglieder extrahieren
   │                          (nur SchemaTag=Computer, Rest → Report)
   ▼
Resolve-OupDsmAssignments     Policy-Filter, Deny → Report,
   │                          Mapping DSM-Name → App-Name,
   │                          Endung aus PolicySchemaTag × AssignmentMode, Dedupe
   ▼
New-OupDsmImportPlan          RBSSt-Abgleich gegen gewählte Standort-OU,
   │                          Zielgruppen-Lookup im Gruppen-Index der OU
   │                          (Get-OupGroupIndex; fehlende Gruppe → Report)
   ▼
Import-Plan:  { Memberships: Rechner×Gruppe;  ReportRows: übersprungen + Grund }
```

Die UI (`main-window.psm1`) nutzt den Plan und die vorhandenen Bausteine:
`Add-OupGroupMembers` (ad-writer), `Add-OupImportEntries` (mapping-store),
CSV-Report-Muster, Bestätigungsdialog, Testlauf (WhatIf).

### Verwertete Felder

`SchemaVersion`, `DSMGroup.RBSSt`, `DSMGroup.Name` (Anzeige/Report),
`Membership.MembershipType`, `Membership.Members[]` (`Name`, `SchemaTag`),
`PolicyAssignments[].Policy` (`PolicySchemaTag`, `IsActive`,
`ActivationStartDate`, `ActivationEndDate`, `PolicyName` für den Report),
`PolicyAssignments[].Assignment.AssignmentMode`,
`PolicyAssignments[].Software.Name`, `Validation.*`.

Bewusst ungenutzt (spätere Funktionen): `DynamicRules` komplett,
`InstallationOrder`, `Priority`, `InstanceCreationMode(-Text)`,
`TargetSelectionMode` (nur Computer-Targeting wird verarbeitet), `Revision`,
DSM-IDs, `ParentContainerId`, `OUPath(-Parts)`, `ExportInfo` (nur Log),
`SoftwareSetHandling` (SwSets werden wie Pakete behandelt — eine Gruppe je Set).

## Mapping-Datei

`dsm-mapping.json` im App-Root; Pfad per Settings-Key `DsmMappingPath`
überschreibbar (gleiches Muster wie `fieldmap.json`). Beispiel unter
`samples\dsm-mapping.example.json`.

```json
{
  "_hinweis": "DSM-Paketname -> AD-App-Name. Abgleich case-insensitiv, exakt.",
  "Software": {
    "7-Zip 24.09 x64":     "7Zip",
    "Mozilla Firefox ESR": "Firefox",
    "SWSET_Client_Basis":  "ClientBasis"
  }
}
```

Nur diese eine Tabelle (YAGNI): RBSSt braucht kein Mapping (= OU-Name), die
Endungen sind fest kodiert. Kein Fuzzy-Matching. Fehlt die Datei komplett,
bricht der Import vor der Dateiauswahl mit klarer Meldung ab.

## Zielgruppen-Name

`<RBSSt>-<AppName>-<Endung>`:

| PolicySchemaTag | AssignmentMode | Endung |
|---|---|---|
| `SwPolicy` | `Required` | `-Policy` |
| `JobPolicy` | `Required` | `-Job` |
| `SwPolicy` | `Available` | `-Policy-Available` |
| `JobPolicy` | `Available` | `-Job-Available` |
| `DenyPolicy` | (egal) | keine — nur Report |
| sonstiger Tag | — | keine — Report („unbekannter Policy-Typ") |

## Filterregeln (je Policy-Zuweisung, Reihenfolge bindend)

Erster Treffer entscheidet und landet mit Grund im Report:

1. `PolicySchemaTag = DenyPolicy` → `Deny-Policy (nicht automatisiert)`
2. `IsActive = false` oder `AssignmentMode = Disabled` → `Policy deaktiviert`
3. `AssignmentMode = NoDeployment` → `Keine Instanz-Erzeugung`
4. `ActivationEndDate` in der Vergangenheit → `Policy abgelaufen`
5. `ActivationStartDate` in der Zukunft → `Policy noch nicht aktiv`
6. `AssignmentMode` ∉ {`Required`, `Available`} → `Unbekannter Zuweisungsmodus`
7. Kein Mapping-Eintrag → `Kein Mapping für DSM-Software`

Dedupe **nach** der Filterung: mehrere verbleibende Policies derselben App auf
dieselbe Endung ergeben genau eine Mitgliedschaft (deckt Beispiel 5 der Spec ab:
Edge Rev21 disabled + Rev22 aktiv → eine Mitgliedschaft in der Edge-Gruppe).

Datumsvergleiche zeitzonenbewusst über `[DateTimeOffset]::Parse` (Timestamps
kommen mit Offset bzw. `Z`).

## Validation-Gate & Datei-Ablehnung

Eine Datei wird komplett abgelehnt (nur Report-Zeilen, keine Verarbeitung) bei:
ungültigem JSON, `SchemaVersion ≠ 1.0`, `Validation.IsValidForMigration =
false`, `Validation.Errors` nicht leer, `DSMGroup.RBSSt ≠ Name der gewählten
Standort-OU`. **Dateien sind unabhängig** — eine abgelehnte Datei blockiert die
übrigen nicht.

`Validation.Warnings` des Exports werden informativ in den Report übernommen;
verarbeitet wird trotzdem. Mitglieder mit `SchemaTag ≠ Computer` (User, Group,
ExternalGroup) werden übersprungen und im Report ausgewiesen. Dynamische
Gruppen erhalten eine Hinweis-Zeile (Snapshot-Stand).

## Report

Eine CSV je Import unter `Logs\` (Muster der bestehenden
Standort-Konflikt-CSV). Spalten:

```
Datei, Ebene (Datei|Mitglied|Policy|Gruppe), Betroffen, Grund, Detail
```

- Ebene `Datei`: Ablehnungsgründe (JSON/Schema/Validation/RBSSt), Export-Warnings, Dynamik-Hinweis
- Ebene `Mitglied`: übersprungene Nicht-Computer-Mitglieder
- Ebene `Policy`: Filterregel-Treffer (inkl. Deny), `Betroffen` = PolicyName, `Detail` = Software/Grund-Daten
- Ebene `Gruppe`: Zielgruppe im AD nicht gefunden

## UI-Workflow

1. Admin wählt im Baum seinen **Standort-Knoten** (oberste OU-Ebene). Neuer
   Modus `oupImportMode = 'Standort'` (neben `Group`/`SubOU`); der Import-Knopf
   wechselt auf „DSM-Export in Standort ‚<Name>' importieren…".
2. Dateiauswahl mit Mehrfachauswahl, Filter `DSM-Export (*.txt;*.json)`.
3. Plan bauen; Bestätigungsdialog: X Rechner, Y Zielgruppen, Z Mitgliedschaften,
   N übersprungene Einträge (Grund-Kategorien), Hinweis auf Report-CSV.
   Testlauf (WhatIf) wie bisher.
4. Ausführung je Zielgruppe über `Add-OupGroupMembers`; Protokoll über
   `Add-OupImportEntries`; Statuszeile mit Zusammenfassung; Report-CSV schreiben
   (immer, wenn Zeilen vorhanden — auch bei erfolgreichem Import).

AD-Schreibfehler laufen über das bestehende Ergebnis-Handling von
`Add-OupGroupMembers` (je Mitglied Erfolg/Fehler, aggregiert) — kein neuer
Mechanismus.

## Verifikation

Projekt hat bewusst keine Test-Suite; Dev-Client ist AD-abgekoppelt. Daher:

- Neue Beispieldateien unter `samples\`, benannt nach dem Mock-Baum, damit der
  komplette Flow ohne Domäne durchspielbar ist: gültige statische Gruppe,
  dynamische Gruppe (Snapshot), Gruppe mit Deny-/Disabled-/abgelaufener Policy,
  Gruppe ohne Policies, Datei mit `Validation.Errors`, plus
  `dsm-mapping.example.json`.
- Durchstich im Mock-Modus mit Testlauf: Plan-Zahlen und Report-Inhalt gegen
  die erwarteten Werte der Beispieldateien prüfen.
- Nach jedem `.ps1`/`.psm1`-Edit `tools\Ensure-Utf8Bom.ps1` (Projektregel).
- Doku nachziehen: README, Doku-Site (Referenz/Architektur-Diagramm), Changelog.

## Bewusst außerhalb des Scopes

- Übersetzung von `DynamicRules` in MECM Query Rules (Collection-Design, nicht
  AD-Gruppenpflege)
- Anlegen fehlender AD-Gruppen (inkl. der neuen `-Available`-Gruppen)
- Deny-Automatisierung (`<RBSSt>-<App>-Deny`-Gruppen + MECM-Exclude-Collections)
  — dafür beim Lieferanten ein Beispiel 6 (DenyPolicy) nachfordern, bevor das
  konzipiert wird
- Benutzerbasiertes Targeting (`TargetSelectionMode ≠ Computer`,
  `GroupType = User`)
- Entfernen von Mitgliedschaften (Export beschreibt nur Soll-Zugänge)
