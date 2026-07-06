# Import-Wege

## 1. In gewählte SubOU (Hauptworkflow)

Der Admin wählt im Baum eine **SubOU (Unterstandort)** und importiert eine
**Geräte-JSON**. Pro Rechner stehen sein Standort und seine Zuweisungen (Software +
Typ **Job**/**Policy**) drin; das Tool sortiert jede Zuweisung in die Gruppe
**`<SubOU>-<Software>-<Typ>`** *dieser* SubOU ein.

```json
[
  { "computer": "PC-1001$", "standort": "Berlin-Nord",
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
    "groups": ["Berlin-Nord-Office-Policy", "Berlin-Nord-7Zip-Job"] }
]
```

Unbekannte Gruppennamen werden gesammelt gemeldet (nichts wird halb geschrieben).

## Standort-Eindeutigkeit (Konflikte)

Ein Rechner darf nur in Gruppen **eines** Standorts sein. Würde ein Rechner durch
den Import über **mehrere Standorte** streuen — gerechnet aus neuen *und* bereits
gespeicherten Mitgliedschaften — wird er **komplett übersprungen** (Status
`Konflikt`) und in `Logs\konflikte-<ts>.csv` dokumentiert, damit der Admin die
Clients nacharbeiten kann.

Abweichende Feldnamen? Siehe [Feld-Map](feld-map.md).
