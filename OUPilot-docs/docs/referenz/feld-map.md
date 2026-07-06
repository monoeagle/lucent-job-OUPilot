# Feld-Map (exotische Export-Formate)

Die Parser suchen Werte in einer Liste bekannter Feldnamen (z. B. Rechnername in
`name`/`cn`/`computerName`/…). Bringt ein Export **abweichende** Feldnamen mit,
lassen sie sich **ohne Code-Änderung** ergänzen: eine optionale `fieldmap.json` im
App-Root (Pfad via `FieldMapPath` in `settings.json` überschreibbar).

- Eigene Namen werden den eingebauten **vorangestellt** (gewinnen bei Konflikt),
  case-insensitiv dedupliziert — bestehende Formate bleiben unberührt.
- Fehlt die Datei, gelten nur die eingebauten Namen.
- Beim Start meldet die Statuszeile, wie viele eigene Feldnamen aktiv sind.

Vorlage: **`samples\fieldmap.example.json`** → nach `fieldmap.json` kopieren und nur
die benötigten Schlüssel füllen.

## Schlüssel

`Name`, `Sid`, `Guid`, `Dn`, `Sam`, `ObjectType` (Identifier-Auflösung) sowie
`AssignGroupFields`, `AssignCompFields`, `DevStandortFields`, `DevAssignFields`,
`SoftwareFields`, `TypeFields` (Sammelliste / Geräte-Import).

```json
{
  "Name": ["assetTag"],
  "AssignCompFields": ["geraet"],
  "DevAssignFields": ["pakete"],
  "SoftwareFields": ["produkt"],
  "TypeFields": ["kategorie"]
}
```

Kern: `Get-OupFieldMapPath` / `Import-OupFieldMap` / `Set-OupFieldMap`
(`core/import-engine.psm1`).
