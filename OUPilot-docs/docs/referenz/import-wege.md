# Import-Wege

## 1. In gewählte SubOU (Hauptworkflow)

Der Admin wählt im Baum eine **SubOU (Unterstandort)** und importiert eine
**Geräte-JSON**. Pro Rechner stehen sein Standort und seine Zuweisungen (Software +
Typ **Job**/**Policy**) drin; das Tool sortiert jede Zuweisung in die Gruppe
**`<SubOU>-<Software>-<Typ>`** *dieser* SubOU ein.

```json
[
  { "computer": "PC-1001$", "standort": "RBSSt02-Nord",
    "assignments": [ {"software":"Office","type":"Policy"},
                     {"software":"7Zip","type":"Job"} ] }
]
```

- **Standort-Abgleich:** Passt der Standort am Rechner nicht zur gewählten SubOU,
  wird der Rechner **übersprungen + dokumentiert** (`Logs\konflikte-*.csv`). Fehlt
  die Zielgruppe → Status `Gruppe fehlt`.

## 2. In gewählte Gruppe (Einzelliste)

Eine Gruppe im Baum wählen, flache Rechnerliste importieren:

```json
["PC-0001$", "PC-0002$"]
```

## 3. Sammelliste „Rechner→Gruppen"

Eine Datei fächert auf viele Gruppen über **exakte Gruppennamen** (kein SubOU-Bezug):

```json
[
  { "computer": "PC-1010$",
    "groups": ["RBSSt02-Nord-Office-Policy", "RBSSt02-Nord-7Zip-Job"] }
]
```

Unbekannte Gruppennamen werden gesammelt gemeldet (nichts wird halb geschrieben).

## 4. DSM-Export-Import (Standort-Ebene)

Kern: `core/dsm-import.psm1` (UI-frei). Wählt der Admin im Baum eine
**Standort-OU** (eine OU ohne direkte Gruppen, aber mit Gruppen in Sub-OUs —
reales Muster: Standort → je Anwendung eine Sub-OU), schaltet die UI in den
Import-Modus `Standort` und zeigt den Knopf „DSM-Export in Standort '<Name>'
importieren…". Importiert werden ein oder mehrere DSM-Exportdateien —
**eine JSON-Datei je DSM-Gruppe**, Namensmuster `<RBSSt>_<DSM-Gruppenname>.txt`
(RBSSt = Name der gewählten OU), Inhalt nach `int_jsonStructure.md`,
`SchemaVersion` `1.0`.

Jedes Gruppenmitglied wird für jede relevante Policy-Zuweisung in die AD-Gruppe
**`<RBSSt>-<App>-<Endung>`** einsortiert. Die Endung ergibt sich aus
`PolicySchemaTag` × `AssignmentMode`:

| PolicySchemaTag | AssignmentMode | Endung             |
|------------------|----------------|---------------------|
| `SwPolicy`       | `Required`     | `-Policy`            |
| `JobPolicy`      | `Required`     | `-Job`               |
| `SwPolicy`       | `Available`    | `-Policy-Available`  |
| `JobPolicy`      | `Available`    | `-Job-Available`     |
| `DenyPolicy`     | (jeder)        | *nur Report, keine Gruppe* |

**Filterregeln** (erster Treffer entscheidet, Rest landet im Report):
Deny-Policy → deaktiviert (`IsActive=false`/`AssignmentMode=Disabled`) →
`NoDeployment` → Aktivierungsfenster abgelaufen → Aktivierungsfenster noch
nicht aktiv → unbekannter Zuweisungsmodus → unbekannter Policy-Typ → fehlendes
Mapping (siehe unten). Danach wird je Zielname dedupliziert.

**Namensbrücke `dsm-mapping.json`** (App-Root, Pfad per Settings-Key
`DsmMappingPath`, Vorlage `samples\dsm-mapping.example.json`): bildet den
DSM-Paketnamen auf den AD-App-Namen ab (exakter, case-insensitiver Abgleich,
kein Fuzzy-Match). Fehlt ein Eintrag, wird die Software **nicht** einsortiert,
sondern im Report ausgewiesen.

**Validation-Gate / RBSSt-Gate:** eine Datei wird komplett abgelehnt bei
ungültigem JSON, `SchemaVersion` ≠ `1.0`, `IsValidForMigration = false`,
vorhandenen `Validation.Errors` oder wenn ihre RBSSt nicht zur gewählten
Standort-OU passt. Eine abgelehnte Datei blockiert die übrigen nicht.
`Validation.Warnings` sind rein informativ und werden trotzdem verarbeitet.
Dynamische Gruppen (`MembershipType = Dynamic`) werden über den exportierten
Snapshot der Mitgliedschaft (`ExportMode = ResolvedSnapshot`) einsortiert.

Alles, was nicht automatisch einsortiert werden konnte — Deny-Policies,
gefilterte Policies, Nicht-Computer-Mitglieder, fehlende Mappings, fehlende
Zielgruppen im AD sowie abgelehnte Dateien — landet im CSV-Report
`Logs\dsm-report-*.csv` mit den Spalten `Datei, Ebene, Betroffen, Grund, Detail`
(`Ebene` ∈ `Datei`/`Mitglied`/`Policy`/`Gruppe`).

Beispieldateien: `samples\RBSSt0*.txt`, Mapping-Vorlage
`samples\dsm-mapping.example.json`.

## Standort-Eindeutigkeit (Konflikte)

Ein Rechner darf nur in Gruppen **eines** Standorts sein. Würde ein Rechner durch
den Import über **mehrere Standorte** streuen — gerechnet aus neuen *und* bereits
gespeicherten Mitgliedschaften — wird er **komplett übersprungen** (Status
`Konflikt`) und in `Logs\konflikte-<ts>.csv` dokumentiert, damit der Admin die
Clients nacharbeiten kann.

Abweichende Feldnamen? Siehe [Feld-Map](feld-map.md).
