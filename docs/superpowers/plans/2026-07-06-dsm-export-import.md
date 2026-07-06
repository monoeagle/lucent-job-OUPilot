# DSM-Export-Import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** OUPilot verarbeitet DSM-Export-Dateien (eine JSON-Datei je DSM-Gruppe nach `int_jsonStructure.md`) und sortiert die Mitglieder je relevanter Policy-Zuweisung in die AD-Gruppen `<RBSSt>-<App>-<Endung>` des gewählten Standorts ein.

**Architecture:** Neues UI-freies Modul `core/dsm-import.psm1` mit dreistufiger Pipeline (`Read-OupDsmGroupFile` → `Resolve-OupDsmAssignments` → `New-OupDsmImportPlan`), dazu ein neuer UI-Workflow `_Oup-OnImportDsm` am Standort-Knoten (Modus `'Standort'`), der die vorhandenen Bausteine (`Get-OupGroupIndex`, `Add-OupGroupMembers`, `Add-OupImportEntries`, CSV-Report-Muster) wiederverwendet. Spec: `docs/superpowers/specs/2026-07-06-dsm-export-import-design.md`.

**Tech Stack:** Windows PowerShell 5.1 (WPF-App), Test-Harness läuft zusätzlich unter pwsh 7 (Linux-Dev-Box). Kein Framework, kein neues Tooling.

## Global Constraints

- **PS-5.1-kompatibel:** kein `??`, kein Ternary, kein `-AsHashtable`, keine PS7-only-Syntax — in ALLEN `.ps1`/`.psm1`.
- **UTF-8 BOM:** nach jedem `.ps1`/`.psm1`-Edit `pwsh -NoProfile -File tools/Ensure-Utf8Bom.ps1` ausführen (formatiert + Parser-Check; Erwartung: `0 mit Parserfehlern`).
- **Tests:** `pwsh -NoProfile -File tools/test-dsm-import.ps1` — Exit-Code 0, keine `FAIL`-Zeile.
- **Commits ohne Attributions-Trailer** (kein `Co-Authored-By`/Tool-Trailer), Autor = Projekt-Autor. Deutsche Commit-Messages im Stil `feat(dsm): …` / `docs: …`.
- **Konventionen:** Funktions-Präfix `Oup`/`_Oup-`, deutsche Kommentare und UI-Texte, Kommentar-Kopfzeile je Moduldatei (Muster siehe `core/import-engine.psm1`).
- **Namensschema & Filterreihenfolge exakt nach Spec** (Endungen `-Policy`, `-Job`, `-Policy-Available`, `-Job-Available`; Deny/fehlende Gruppe/fehlendes Mapping → nur Report).
- **Keine CDNs**, keine neuen externen Abhängigkeiten.

---

### Task 1: Beispieldateien + Mapping-Vorlage (`samples\`)

Testdaten zuerst — alle späteren Tasks testen gegen diese Dateien. Die Dateien decken die 5 Spec-Beispiele plus RBSSt-Fremddatei ab und sind auf den Mock-Baum (Task 4: Standort `RBSSt01`) abgestimmt.

**Files:**
- Create: `samples/RBSSt01_Clients_Basis.txt`
- Create: `samples/RBSSt01_Clients_Fach_X.txt`
- Create: `samples/RBSSt01_Clients_Alt.txt`
- Create: `samples/RBSSt01_Clients_Inventar.txt`
- Create: `samples/RBSSt01_Clients_Defekt.txt`
- Create: `samples/RBSSt02_Clients_Fremd.txt`
- Create: `samples/dsm-mapping.example.json`

**Interfaces:**
- Produces: Feste Testdaten mit exakt den unten definierten Zahlen (3/2/2/2 Computer-Mitglieder; Ziele siehe Task 3/5). Spätere Tasks asserten gegen genau diese Werte — Inhalte nicht abwandeln.

- [ ] **Step 1: `samples/RBSSt01_Clients_Basis.txt` anlegen** — statische Gruppe, 3 Mitglieder, 4 Policies (davon ein Paket doppelt in zwei Revisionen → Dedupe-Fall, Spec-Beispiel 5):

```json
{
  "SchemaVersion": "1.0",
  "ExportInfo": {
    "ExportTimestamp": "2026-07-02T14:45:12+02:00",
    "SourceSystem": "Ivanti DSM",
    "SourceEnvironment": "DSM-PROD",
    "ExportTool": "Export-DsmGroupsAndPolicies.ps1",
    "ExportToolVersion": "1.0"
  },
  "DSMGroup": {
    "Name": "Clients_Basis",
    "DSMGroupId": 4711001,
    "SchemaTag": "Group",
    "GroupType": "Computer",
    "RBSSt": "RBSSt01",
    "OUPath": "ORG/RBSSt01/Clients/Gruppen/Basis",
    "OUPathParts": ["ORG", "RBSSt01", "Clients", "Gruppen", "Basis"],
    "ParentContainerId": 310045
  },
  "Membership": {
    "MembershipType": "Static",
    "ExportMode": "DirectMembers",
    "Members": [
      { "Name": "PC-010001", "DSMObjectId": 9100001, "SchemaTag": "Computer" },
      { "Name": "PC-010002", "DSMObjectId": 9100002, "SchemaTag": "Computer" },
      { "Name": "PC-010003", "DSMObjectId": 9100003, "SchemaTag": "Computer" }
    ]
  },
  "DynamicRules": null,
  "PolicyAssignments": [
    {
      "Policy": { "PolicyId": 9300101, "PolicyName": "SWSET_Client_Basis -> Clients_Basis", "PolicySchemaTag": "SwPolicy", "IsActive": true, "InstallationOrder": 1000, "Priority": 50, "ActivationStartDate": "2026-06-01T18:00:00Z", "ActivationEndDate": null },
      "Assignment": { "AssignmentMode": "Required", "InstanceCreationMode": 0, "InstanceCreationModeText": "Automatic", "TargetSelectionMode": "Computer" },
      "Software": { "Name": "SWSET_Client_Basis", "DSMObjectId": 6200100, "SchemaTag": "SwSet", "Revision": 8, "IsSoftwareSet": true, "SoftwareSetHandling": { "ComponentsExported": false, "MigrationHint": "SoftwareSetOnly" } }
    },
    {
      "Policy": { "PolicyId": 9300102, "PolicyName": "7-Zip 24.09 x64 -> Clients_Basis", "PolicySchemaTag": "SwPolicy", "IsActive": true, "InstallationOrder": 1100, "Priority": 50, "ActivationStartDate": "2026-06-01T18:00:00Z", "ActivationEndDate": null },
      "Assignment": { "AssignmentMode": "Required", "InstanceCreationMode": 0, "InstanceCreationModeText": "Automatic", "TargetSelectionMode": "Computer" },
      "Software": { "Name": "7-Zip 24.09 x64", "DSMObjectId": 6200115, "SchemaTag": "eScriptPackage", "Revision": 3, "IsSoftwareSet": false, "SoftwareSetHandling": { "ComponentsExported": false, "MigrationHint": "Package" } }
    },
    {
      "Policy": { "PolicyId": 9300103, "PolicyName": "7-Zip 24.09 x64 Rev4 Pilot -> Clients_Basis", "PolicySchemaTag": "SwPolicy", "IsActive": true, "InstallationOrder": 1100, "Priority": 90, "ActivationStartDate": "2026-06-15T18:00:00Z", "ActivationEndDate": null },
      "Assignment": { "AssignmentMode": "Required", "InstanceCreationMode": 0, "InstanceCreationModeText": "Automatic", "TargetSelectionMode": "Computer" },
      "Software": { "Name": "7-Zip 24.09 x64", "DSMObjectId": 6200116, "SchemaTag": "eScriptPackage", "Revision": 4, "IsSoftwareSet": false, "SoftwareSetHandling": { "ComponentsExported": false, "MigrationHint": "Package" } }
    },
    {
      "Policy": { "PolicyId": 9300104, "PolicyName": "Mozilla Firefox ESR -> Clients_Basis", "PolicySchemaTag": "JobPolicy", "IsActive": true, "InstallationOrder": 1200, "Priority": 50, "ActivationStartDate": "2026-06-01T18:00:00Z", "ActivationEndDate": null },
      "Assignment": { "AssignmentMode": "Required", "InstanceCreationMode": 0, "InstanceCreationModeText": "Automatic", "TargetSelectionMode": "Computer" },
      "Software": { "Name": "Mozilla Firefox ESR", "DSMObjectId": 6200130, "SchemaTag": "MsiPackage", "Revision": 17, "IsSoftwareSet": false, "SoftwareSetHandling": { "ComponentsExported": false, "MigrationHint": "Package" } }
    }
  ],
  "Validation": { "IsValidForMigration": true, "Warnings": [], "Errors": [] }
}
```

- [ ] **Step 2: `samples/RBSSt01_Clients_Fach_X.txt` anlegen** — dynamische Gruppe (Snapshot), 2 Mitglieder, 1 Available-Policy, 2 Export-Warnungen:

```json
{
  "SchemaVersion": "1.0",
  "ExportInfo": {
    "ExportTimestamp": "2026-07-02T14:47:30+02:00",
    "SourceSystem": "Ivanti DSM",
    "SourceEnvironment": "DSM-PROD",
    "ExportTool": "Export-DsmGroupsAndPolicies.ps1",
    "ExportToolVersion": "1.0"
  },
  "DSMGroup": {
    "Name": "Clients_Fach_X",
    "DSMGroupId": 4712055,
    "SchemaTag": "DynamicGroup",
    "GroupType": "Computer",
    "RBSSt": "RBSSt01",
    "OUPath": "ORG/RBSSt01/Clients/Fachverfahren/Gruppen",
    "OUPathParts": ["ORG", "RBSSt01", "Clients", "Fachverfahren", "Gruppen"],
    "ParentContainerId": 320081
  },
  "Membership": {
    "MembershipType": "Dynamic",
    "ExportMode": "ResolvedSnapshot",
    "Members": [
      { "Name": "PC-010101", "DSMObjectId": 9101101, "SchemaTag": "Computer" },
      { "Name": "PC-010102", "DSMObjectId": 9101102, "SchemaTag": "Computer" }
    ]
  },
  "DynamicRules": {
    "RuleExported": true,
    "RuleSource": "DynamicGroupProps",
    "ParentDynamicGroupId": null,
    "OwnFilter": "(&(SchemaTag=Computer)(Name=PC-0101*))",
    "EffectiveLdapFilter": "(&(SchemaTag=Computer)(ParentContId=320081)(Name=PC-0101*))",
    "RuleChain": [
      { "Level": 0, "DSMGroupId": 4712055, "Name": "Clients_Fach_X", "ParentDynamicGroupId": null, "Filter": "(&(SchemaTag=Computer)(Name=PC-0101*))" }
    ],
    "EvaluationHint": { "RuleMeaning": "Mitglieder ergeben sich aus dem eigenen Filter.", "CanBeConvertedToSccmQueryRule": true, "ManualReviewRecommended": true }
  },
  "PolicyAssignments": [
    {
      "Policy": { "PolicyId": 9400780, "PolicyName": "Microsoft Office LTSC -> Clients_Fach_X", "PolicySchemaTag": "SwPolicy", "IsActive": true, "InstallationOrder": 2000, "Priority": 70, "ActivationStartDate": "2026-05-15T18:00:00Z", "ActivationEndDate": null },
      "Assignment": { "AssignmentMode": "Available", "InstanceCreationMode": 1, "InstanceCreationModeText": "OnDemand", "TargetSelectionMode": "Computer" },
      "Software": { "Name": "Microsoft Office LTSC", "DSMObjectId": 6300440, "SchemaTag": "MsiPackage", "Revision": 12, "IsSoftwareSet": false, "SoftwareSetHandling": { "ComponentsExported": false, "MigrationHint": "Package" } }
    }
  ],
  "Validation": {
    "IsValidForMigration": true,
    "Warnings": [
      "Die DSM-Gruppe ist dynamisch. Die exportierten Mitglieder bilden den aufgeloesten Stand zum Exportzeitpunkt ab.",
      "Die dynamischen Regeln wurden zusaetzlich exportiert. Eine automatische Uebersetzung nach SCCM Query Rules muss fachlich geprueft werden."
    ],
    "Errors": []
  }
}
```

- [ ] **Step 3: `samples/RBSSt01_Clients_Alt.txt` anlegen** — 2 Mitglieder, 7 Policies: deaktiviert / NoDeployment / abgelaufen / noch nicht aktiv / Deny / gültig-aber-Gruppe-fehlt (VLC) / ohne Mapping:

```json
{
  "SchemaVersion": "1.0",
  "ExportInfo": {
    "ExportTimestamp": "2026-07-02T14:49:02+02:00",
    "SourceSystem": "Ivanti DSM",
    "SourceEnvironment": "DSM-PROD",
    "ExportTool": "Export-DsmGroupsAndPolicies.ps1",
    "ExportToolVersion": "1.0"
  },
  "DSMGroup": {
    "Name": "Clients_Alt",
    "DSMGroupId": 4713099,
    "SchemaTag": "Group",
    "GroupType": "Computer",
    "RBSSt": "RBSSt01",
    "OUPath": "ORG/RBSSt01/Clients/Altverfahren/Gruppen",
    "OUPathParts": ["ORG", "RBSSt01", "Clients", "Altverfahren", "Gruppen"],
    "ParentContainerId": 330091
  },
  "Membership": {
    "MembershipType": "Static",
    "ExportMode": "DirectMembers",
    "Members": [
      { "Name": "PC-010201", "DSMObjectId": 9103201, "SchemaTag": "Computer" },
      { "Name": "PC-010202", "DSMObjectId": 9103202, "SchemaTag": "Computer" }
    ]
  },
  "DynamicRules": null,
  "PolicyAssignments": [
    {
      "Policy": { "PolicyId": 9500201, "PolicyName": "Altverfahren Y Client -> Clients_Alt", "PolicySchemaTag": "SwPolicy", "IsActive": false, "InstallationOrder": 3000, "Priority": 50, "ActivationStartDate": "2024-09-01T18:00:00Z", "ActivationEndDate": null },
      "Assignment": { "AssignmentMode": "Disabled", "InstanceCreationMode": 0, "InstanceCreationModeText": "Automatic", "TargetSelectionMode": "Computer" },
      "Software": { "Name": "Altverfahren Y Client", "DSMObjectId": 6400200, "SchemaTag": "MsiPackage", "Revision": 9, "IsSoftwareSet": false, "SoftwareSetHandling": { "ComponentsExported": false, "MigrationHint": "Package" } }
    },
    {
      "Policy": { "PolicyId": 9500202, "PolicyName": "Altverfahren Y Migrationspaket -> Clients_Alt", "PolicySchemaTag": "SwPolicy", "IsActive": true, "InstallationOrder": 3010, "Priority": 80, "ActivationStartDate": "2025-01-10T18:00:00Z", "ActivationEndDate": null },
      "Assignment": { "AssignmentMode": "NoDeployment", "InstanceCreationMode": 2, "InstanceCreationModeText": "NoInstanceCreation", "TargetSelectionMode": "Computer" },
      "Software": { "Name": "Altverfahren Y Migrationspaket", "DSMObjectId": 6400202, "SchemaTag": "eScriptPackage", "Revision": 1, "IsSoftwareSet": false, "SoftwareSetHandling": { "ComponentsExported": false, "MigrationHint": "Package" } }
    },
    {
      "Policy": { "PolicyId": 9500203, "PolicyName": "AltTool -> Clients_Alt", "PolicySchemaTag": "SwPolicy", "IsActive": true, "InstallationOrder": 3020, "Priority": 50, "ActivationStartDate": "2025-01-10T18:00:00Z", "ActivationEndDate": "2025-12-31T22:59:59Z" },
      "Assignment": { "AssignmentMode": "Required", "InstanceCreationMode": 0, "InstanceCreationModeText": "Automatic", "TargetSelectionMode": "Computer" },
      "Software": { "Name": "AltTool", "DSMObjectId": 6400203, "SchemaTag": "eScriptPackage", "Revision": 2, "IsSoftwareSet": false, "SoftwareSetHandling": { "ComponentsExported": false, "MigrationHint": "Package" } }
    },
    {
      "Policy": { "PolicyId": 9500204, "PolicyName": "ZukunftsTool 2.0 -> Clients_Alt", "PolicySchemaTag": "SwPolicy", "IsActive": true, "InstallationOrder": 3030, "Priority": 50, "ActivationStartDate": "2027-01-01T18:00:00Z", "ActivationEndDate": null },
      "Assignment": { "AssignmentMode": "Required", "InstanceCreationMode": 0, "InstanceCreationModeText": "Automatic", "TargetSelectionMode": "Computer" },
      "Software": { "Name": "ZukunftsTool 2.0", "DSMObjectId": 6400204, "SchemaTag": "MsiPackage", "Revision": 1, "IsSoftwareSet": false, "SoftwareSetHandling": { "ComponentsExported": false, "MigrationHint": "Package" } }
    },
    {
      "Policy": { "PolicyId": 9500205, "PolicyName": "VLC Deny -> Clients_Alt", "PolicySchemaTag": "DenyPolicy", "IsActive": true, "InstallationOrder": null, "Priority": null, "ActivationStartDate": null, "ActivationEndDate": null },
      "Assignment": { "AssignmentMode": "Required", "InstanceCreationMode": 0, "InstanceCreationModeText": "Automatic", "TargetSelectionMode": "Computer" },
      "Software": { "Name": "VLC Media Player 3", "DSMObjectId": 6400205, "SchemaTag": "MsiPackage", "Revision": 5, "IsSoftwareSet": false, "SoftwareSetHandling": { "ComponentsExported": false, "MigrationHint": "Package" } }
    },
    {
      "Policy": { "PolicyId": 9500206, "PolicyName": "VLC Media Player 3 -> Clients_Alt", "PolicySchemaTag": "SwPolicy", "IsActive": true, "InstallationOrder": 3040, "Priority": 50, "ActivationStartDate": "2026-01-10T18:00:00Z", "ActivationEndDate": null },
      "Assignment": { "AssignmentMode": "Required", "InstanceCreationMode": 0, "InstanceCreationModeText": "Automatic", "TargetSelectionMode": "Computer" },
      "Software": { "Name": "VLC Media Player 3", "DSMObjectId": 6400205, "SchemaTag": "MsiPackage", "Revision": 5, "IsSoftwareSet": false, "SoftwareSetHandling": { "ComponentsExported": false, "MigrationHint": "Package" } }
    },
    {
      "Policy": { "PolicyId": 9500207, "PolicyName": "ExotenTool 1.0 -> Clients_Alt", "PolicySchemaTag": "SwPolicy", "IsActive": true, "InstallationOrder": 3050, "Priority": 50, "ActivationStartDate": "2026-01-10T18:00:00Z", "ActivationEndDate": null },
      "Assignment": { "AssignmentMode": "Required", "InstanceCreationMode": 0, "InstanceCreationModeText": "Automatic", "TargetSelectionMode": "Computer" },
      "Software": { "Name": "ExotenTool 1.0", "DSMObjectId": 6400206, "SchemaTag": "eScriptPackage", "Revision": 1, "IsSoftwareSet": false, "SoftwareSetHandling": { "ComponentsExported": false, "MigrationHint": "Package" } }
    }
  ],
  "Validation": {
    "IsValidForMigration": true,
    "Warnings": ["Eine Policy ist deaktiviert.", "Eine Policy besitzt ein ActivationEndDate in der Vergangenheit."],
    "Errors": []
  }
}
```

- [ ] **Step 4: `samples/RBSSt01_Clients_Inventar.txt` anlegen** — keine Policies, ein Nicht-Computer-Mitglied:

```json
{
  "SchemaVersion": "1.0",
  "ExportInfo": {
    "ExportTimestamp": "2026-07-02T14:50:44+02:00",
    "SourceSystem": "Ivanti DSM",
    "SourceEnvironment": "DSM-PROD",
    "ExportTool": "Export-DsmGroupsAndPolicies.ps1",
    "ExportToolVersion": "1.0"
  },
  "DSMGroup": {
    "Name": "Clients_Inventar",
    "DSMGroupId": 4714120,
    "SchemaTag": "Group",
    "GroupType": "Computer",
    "RBSSt": "RBSSt01",
    "OUPath": "ORG/RBSSt01/Clients/Inventarisierung/Gruppen",
    "OUPathParts": ["ORG", "RBSSt01", "Clients", "Inventarisierung", "Gruppen"],
    "ParentContainerId": 340077
  },
  "Membership": {
    "MembershipType": "Static",
    "ExportMode": "DirectMembers",
    "Members": [
      { "Name": "PC-010301", "DSMObjectId": 9104301, "SchemaTag": "Computer" },
      { "Name": "PC-010302", "DSMObjectId": 9104302, "SchemaTag": "Computer" },
      { "Name": "Untergruppe_Inventar", "DSMObjectId": 9104999, "SchemaTag": "Group" }
    ]
  },
  "DynamicRules": null,
  "PolicyAssignments": [],
  "Validation": {
    "IsValidForMigration": true,
    "Warnings": ["Die Gruppe enthaelt keine direkte DSM-Policy-Zuweisung."],
    "Errors": []
  }
}
```

- [ ] **Step 5: `samples/RBSSt01_Clients_Defekt.txt` anlegen** — Validation-Fehler → Datei wird abgelehnt:

```json
{
  "SchemaVersion": "1.0",
  "ExportInfo": {
    "ExportTimestamp": "2026-07-02T14:52:00+02:00",
    "SourceSystem": "Ivanti DSM",
    "SourceEnvironment": "DSM-PROD",
    "ExportTool": "Export-DsmGroupsAndPolicies.ps1",
    "ExportToolVersion": "1.0"
  },
  "DSMGroup": {
    "Name": "Clients_Defekt",
    "DSMGroupId": 4715000,
    "SchemaTag": "Group",
    "GroupType": "Computer",
    "RBSSt": "RBSSt01",
    "OUPath": "ORG/RBSSt01/Clients/Defekt",
    "OUPathParts": ["ORG", "RBSSt01", "Clients", "Defekt"],
    "ParentContainerId": 350000
  },
  "Membership": {
    "MembershipType": "Static",
    "ExportMode": "DirectMembers",
    "Members": [
      { "Name": "PC-010401", "DSMObjectId": 9105401, "SchemaTag": "Computer" }
    ]
  },
  "DynamicRules": null,
  "PolicyAssignments": [],
  "Validation": {
    "IsValidForMigration": false,
    "Warnings": [],
    "Errors": ["Der OU-Pfad der Gruppe konnte nicht eindeutig aufgeloest werden."]
  }
}
```

- [ ] **Step 6: `samples/RBSSt02_Clients_Fremd.txt` anlegen** — gültig, aber fremder RBSSt (Ablehnung erfolgt erst beim Plan-Bau gegen die gewählte OU):

```json
{
  "SchemaVersion": "1.0",
  "ExportInfo": {
    "ExportTimestamp": "2026-07-02T14:53:10+02:00",
    "SourceSystem": "Ivanti DSM",
    "SourceEnvironment": "DSM-PROD",
    "ExportTool": "Export-DsmGroupsAndPolicies.ps1",
    "ExportToolVersion": "1.0"
  },
  "DSMGroup": {
    "Name": "Clients_Fremd",
    "DSMGroupId": 4720001,
    "SchemaTag": "Group",
    "GroupType": "Computer",
    "RBSSt": "RBSSt02",
    "OUPath": "ORG/RBSSt02/Clients/Gruppen",
    "OUPathParts": ["ORG", "RBSSt02", "Clients", "Gruppen"],
    "ParentContainerId": 360001
  },
  "Membership": {
    "MembershipType": "Static",
    "ExportMode": "DirectMembers",
    "Members": [
      { "Name": "PC-020001", "DSMObjectId": 9200001, "SchemaTag": "Computer" }
    ]
  },
  "DynamicRules": null,
  "PolicyAssignments": [
    {
      "Policy": { "PolicyId": 9600001, "PolicyName": "7-Zip 24.09 x64 -> Clients_Fremd", "PolicySchemaTag": "SwPolicy", "IsActive": true, "InstallationOrder": 1000, "Priority": 50, "ActivationStartDate": "2026-06-01T18:00:00Z", "ActivationEndDate": null },
      "Assignment": { "AssignmentMode": "Required", "InstanceCreationMode": 0, "InstanceCreationModeText": "Automatic", "TargetSelectionMode": "Computer" },
      "Software": { "Name": "7-Zip 24.09 x64", "DSMObjectId": 6200115, "SchemaTag": "eScriptPackage", "Revision": 3, "IsSoftwareSet": false, "SoftwareSetHandling": { "ComponentsExported": false, "MigrationHint": "Package" } }
    }
  ],
  "Validation": { "IsValidForMigration": true, "Warnings": [], "Errors": [] }
}
```

- [ ] **Step 7: `samples/dsm-mapping.example.json` anlegen** (`ExotenTool 1.0` und `ZukunftsTool 2.0` fehlen ABSICHTLICH):

```json
{
  "_hinweis": "Kopiere diese Datei nach ..\\dsm-mapping.json (App-Root; Pfad via Settings-Key DsmMappingPath ueberschreibbar). DSM-Paketname -> AD-App-Name, Abgleich exakt und case-insensitiv. DSM-Software ohne Eintrag wird NICHT einsortiert, sondern im Report ausgewiesen.",
  "Software": {
    "SWSET_Client_Basis": "ClientBasis",
    "7-Zip 24.09 x64": "7Zip",
    "Mozilla Firefox ESR": "Firefox",
    "Microsoft Office LTSC": "Office",
    "VLC Media Player 3": "VLC"
  }
}
```

- [ ] **Step 8: JSON-Validität prüfen**

Run: `for f in samples/RBSSt0*.txt samples/dsm-mapping.example.json; do pwsh -NoProfile -Command "Get-Content '$f' -Raw | ConvertFrom-Json | Out-Null; 'OK $f'"; done`
Expected: 7× `OK`

- [ ] **Step 9: Commit**

```bash
git add samples/RBSSt01_Clients_Basis.txt samples/RBSSt01_Clients_Fach_X.txt samples/RBSSt01_Clients_Alt.txt samples/RBSSt01_Clients_Inventar.txt samples/RBSSt01_Clients_Defekt.txt samples/RBSSt02_Clients_Fremd.txt samples/dsm-mapping.example.json
git commit -m "feat(dsm): Beispiel-Exportdateien + Mapping-Vorlage (Spec-Faelle 1-5, fremder RBSSt)"
```

---

### Task 2: `Read-OupDsmGroupFile` — Parser mit Validation-Gate

**Files:**
- Create: `core/dsm-import.psm1`
- Create: `tools/test-dsm-import.ps1`

**Interfaces:**
- Consumes: Beispieldateien aus Task 1.
- Produces: `Read-OupDsmGroupFile -Path <string>` → `PSCustomObject @{ File; Rejected(bool); Rbsst; GroupName; MembershipType; Members(object[]); Assignments(object[]); ReportRows(object[]) }`. Member-Einträge haben die Form der import-engine-Einträge: `@{ importedAt; sourceFile; type='computer'; identifier; raw }`. Report-Zeilen: `@{ Datei; Ebene; Betroffen; Grund; Detail }` (Ebenen: `Datei|Mitglied|Policy|Gruppe`). Interner Helfer `_Oup-DsmRow`.

- [ ] **Step 1: Test-Harness mit fehlschlagenden Tests anlegen** — `tools/test-dsm-import.ps1`:

```powershell
# tools/test-dsm-import.ps1 — Prüft das DSM-Import-Modul (core\dsm-import.psm1)
# gegen die Beispieldateien unter samples\. Läuft unter Windows PowerShell 5.1
# und pwsh 7:   pwsh -NoProfile -File tools/test-dsm-import.ps1
# Exit-Code 0 = alle Assertions grün.

$ErrorActionPreference = 'Stop'
$root    = Split-Path -Parent $PSScriptRoot
$samples = Join-Path $root 'samples'
Import-Module (Join-Path $root 'core/dsm-import.psm1') -Force -DisableNameChecking

$script:fails = 0
function Assert {
    param([bool]$Cond, [string]$Msg)
    if ($Cond) { Write-Host "OK   $Msg" -ForegroundColor Green }
    else       { $script:fails++; Write-Host "FAIL $Msg" -ForegroundColor Red }
}

# ── Read-OupDsmGroupFile ────────────────────────────────────────────────────
$r = Read-OupDsmGroupFile -Path (Join-Path $samples 'RBSSt01_Clients_Basis.txt')
Assert (-not $r.Rejected) 'Basis: nicht abgelehnt'
Assert ($r.Rbsst -eq 'RBSSt01') 'Basis: RBSSt erkannt'
Assert ($r.GroupName -eq 'Clients_Basis') 'Basis: Gruppenname erkannt'
Assert (@($r.Members).Count -eq 3) 'Basis: 3 Computer-Mitglieder'
Assert ($r.Members[0].identifier -eq 'PC-010001') 'Basis: identifier = DSM-Name'
Assert ($r.Members[0].type -eq 'computer') 'Basis: type = computer'
Assert (@($r.Assignments).Count -eq 4) 'Basis: 4 Policy-Zuweisungen durchgereicht'
Assert (@($r.ReportRows).Count -eq 0) 'Basis: keine Report-Zeilen'

$r = Read-OupDsmGroupFile -Path (Join-Path $samples 'RBSSt01_Clients_Fach_X.txt')
Assert (-not $r.Rejected) 'FachX: nicht abgelehnt'
Assert ($r.MembershipType -eq 'Dynamic') 'FachX: MembershipType Dynamic'
Assert (@($r.Members).Count -eq 2) 'FachX: 2 Snapshot-Mitglieder'
Assert (@($r.ReportRows | Where-Object { $_.Grund -eq 'Dynamische Gruppe' }).Count -eq 1) 'FachX: Dynamik-Hinweis'
Assert (@($r.ReportRows | Where-Object { $_.Grund -eq 'Export-Warnung' }).Count -eq 2) 'FachX: 2 Export-Warnungen uebernommen'

$r = Read-OupDsmGroupFile -Path (Join-Path $samples 'RBSSt01_Clients_Inventar.txt')
Assert (-not $r.Rejected) 'Inventar: nicht abgelehnt'
Assert (@($r.Members).Count -eq 2) 'Inventar: Nicht-Computer-Mitglied uebersprungen'
Assert (@($r.ReportRows | Where-Object { $_.Ebene -eq 'Mitglied' -and $_.Betroffen -eq 'Untergruppe_Inventar' }).Count -eq 1) 'Inventar: Mitglied-Report-Zeile'
Assert (@($r.Assignments).Count -eq 0) 'Inventar: keine Zuweisungen'

$r = Read-OupDsmGroupFile -Path (Join-Path $samples 'RBSSt01_Clients_Defekt.txt')
Assert ($r.Rejected) 'Defekt: abgelehnt (IsValidForMigration=false / Errors)'
Assert (@($r.ReportRows | Where-Object { $_.Ebene -eq 'Datei' -and $_.Grund -eq 'Datei abgelehnt' }).Count -eq 1) 'Defekt: Ablehnungszeile'

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) 'oup-dsm-kaputt.txt'
Set-Content -Path $tmp -Value '{ kein json' -Encoding UTF8
$r = Read-OupDsmGroupFile -Path $tmp
Assert ($r.Rejected) 'Kaputtes JSON: abgelehnt'
Assert (@($r.ReportRows | Where-Object { $_.Grund -eq 'Ungueltiges JSON' }).Count -eq 1) 'Kaputtes JSON: Report-Zeile'
Remove-Item $tmp -Force

# ── Ergebnis ────────────────────────────────────────────────────────────────
Write-Host ''
if ($script:fails -gt 0) { Write-Host "$script:fails Assertion(s) fehlgeschlagen." -ForegroundColor Red; exit 1 }
Write-Host 'Alle Tests gruen.' -ForegroundColor Green
```

- [ ] **Step 2: Tests laufen lassen — muss fehlschlagen**

Run: `pwsh -NoProfile -File tools/test-dsm-import.ps1`
Expected: Abbruch mit Fehler (Modul `core/dsm-import.psm1` existiert nicht).

- [ ] **Step 3: `core/dsm-import.psm1` anlegen** (Parser-Stufe):

```powershell
# core/dsm-import.psm1 — Verarbeitet DSM-Export-Dateien (eine JSON-Datei je
# DSM-Gruppe nach int_jsonStructure.md, SchemaVersion 1.0) zu einem Import-Plan:
# jedes Gruppenmitglied wird für jede relevante Policy-Zuweisung der AD-Gruppe
# <RBSSt>-<App>-<Endung> zugeordnet (Endungen: Policy, Job, Policy-Available,
# Job-Available). Deny-/deaktivierte/abgelaufene Policies, fehlende Mappings
# und fehlende Zielgruppen werden NICHT einsortiert, sondern als Report-Zeilen
# geliefert. UI-frei; Spec: docs/superpowers/specs/2026-07-06-dsm-export-import-design.md
#
# Pipeline:  Read-OupDsmGroupFile -> Resolve-OupDsmAssignments -> New-OupDsmImportPlan
# Report-Zeile: @{ Datei; Ebene (Datei|Mitglied|Policy|Gruppe); Betroffen; Grund; Detail }

$script:OupDsmSchemaVersion = '1.0'

function _Oup-DsmRow {
    param([string]$Datei, [string]$Ebene, [string]$Betroffen, [string]$Grund, [string]$Detail = '')
    return [PSCustomObject]@{ Datei = $Datei; Ebene = $Ebene; Betroffen = $Betroffen; Grund = $Grund; Detail = $Detail }
}

function _Oup-DsmRejected {
    <#  .SYNOPSIS  Einheitliches Ergebnisobjekt für abgelehnte Dateien.  #>
    param([string]$File, [object[]]$Rows)
    return [PSCustomObject]@{
        File = $File; Rejected = $true
        Rbsst = $null; GroupName = $null; MembershipType = $null
        Members = @(); Assignments = @(); ReportRows = @($Rows)
    }
}

function Read-OupDsmGroupFile {
    <#
        .SYNOPSIS  Liest eine DSM-Exportdatei: JSON, SchemaVersion, Validation-Gate,
                   Computer-Mitglieder (Nicht-Computer -> Report-Zeile).
        .OUTPUTS   PSCustomObject @{ File; Rejected; Rbsst; GroupName; MembershipType;
                   Members; Assignments; ReportRows }
    #>
    param([Parameter(Mandatory)][string]$Path)

    $file = Split-Path -Leaf $Path
    $rows = New-Object System.Collections.Generic.List[object]

    try {
        $data = Get-Content $Path -Raw | ConvertFrom-Json
    } catch {
        $rows.Add((_Oup-DsmRow $file 'Datei' $file 'Ungueltiges JSON' $_.Exception.Message))
        return (_Oup-DsmRejected -File $file -Rows $rows.ToArray())
    }

    # Gate: SchemaVersion, Validation, Pflichtfelder — erster Treffer lehnt ab.
    $reject = $null
    if ("$($data.SchemaVersion)" -ne $script:OupDsmSchemaVersion) {
        $reject = "SchemaVersion '$($data.SchemaVersion)' wird nicht unterstuetzt (erwartet $($script:OupDsmSchemaVersion))"
    } elseif (-not $data.Validation) {
        $reject = 'Validation-Block fehlt'
    } elseif (-not $data.Validation.IsValidForMigration) {
        $reject = 'IsValidForMigration = false'
    } elseif (@($data.Validation.Errors | Where-Object { $_ }).Count -gt 0) {
        $reject = 'Validation-Errors: ' + (@($data.Validation.Errors) -join ' | ')
    } elseif (-not $data.DSMGroup -or -not $data.DSMGroup.RBSSt) {
        $reject = 'DSMGroup.RBSSt fehlt'
    } elseif (-not $data.Membership) {
        $reject = 'Membership-Block fehlt'
    }
    if ($reject) {
        $rows.Add((_Oup-DsmRow $file 'Datei' "$($data.DSMGroup.Name)" 'Datei abgelehnt' $reject))
        return (_Oup-DsmRejected -File $file -Rows $rows.ToArray())
    }

    # Export-Warnungen informativ übernehmen; verarbeitet wird trotzdem.
    foreach ($w in @($data.Validation.Warnings | Where-Object { $_ })) {
        $rows.Add((_Oup-DsmRow $file 'Datei' "$($data.DSMGroup.Name)" 'Export-Warnung' "$w"))
    }
    if ("$($data.Membership.MembershipType)" -ieq 'Dynamic') {
        $rows.Add((_Oup-DsmRow $file 'Datei' "$($data.DSMGroup.Name)" 'Dynamische Gruppe' 'Mitglieder = aufgeloester Snapshot zum Exportzeitpunkt'))
    }

    # Mitglieder: nur Computer werden einsortiert (Eintragsform wie import-engine).
    $members = New-Object System.Collections.Generic.List[object]
    foreach ($m in @($data.Membership.Members)) {
        if (-not $m) { continue }
        if ("$($m.SchemaTag)" -ine 'Computer') {
            $rows.Add((_Oup-DsmRow $file 'Mitglied' "$($m.Name)" 'Kein Computer-Objekt' "SchemaTag=$($m.SchemaTag)"))
            continue
        }
        if (-not $m.Name) { continue }
        $members.Add([PSCustomObject]@{
            importedAt = (Get-Date -Format 'o'); sourceFile = $file
            type = 'computer'; identifier = "$($m.Name)"; raw = $m
        })
    }

    return [PSCustomObject]@{
        File = $file; Rejected = $false
        Rbsst = "$($data.DSMGroup.RBSSt)"; GroupName = "$($data.DSMGroup.Name)"
        MembershipType = "$($data.Membership.MembershipType)"
        Members = $members.ToArray()
        Assignments = @($data.PolicyAssignments | Where-Object { $_ })
        ReportRows = $rows.ToArray()
    }
}

Export-ModuleMember -Function Read-OupDsmGroupFile
```

- [ ] **Step 4: Tests laufen lassen — muss grün sein**

Run: `pwsh -NoProfile -File tools/test-dsm-import.ps1`
Expected: alle `OK`, letzte Zeile `Alle Tests gruen.`, Exit-Code 0.

- [ ] **Step 5: BOM/Parser-Check**

Run: `pwsh -NoProfile -File tools/Ensure-Utf8Bom.ps1`
Expected: alle Dateien `OK`, `0 mit Parserfehlern`.

- [ ] **Step 6: Commit**

```bash
git add core/dsm-import.psm1 tools/test-dsm-import.ps1
git commit -m "feat(dsm): Read-OupDsmGroupFile - Parser mit SchemaVersion-/Validation-Gate + Test-Harness"
```

---

### Task 3: Mapping-Loader + `Resolve-OupDsmAssignments` — Filterregeln & Namensschema

**Files:**
- Modify: `core/dsm-import.psm1` (Funktionen ergänzen, Export-Zeile erweitern)
- Modify: `tools/test-dsm-import.ps1` (Tests ergänzen)

**Interfaces:**
- Consumes: `Read-OupDsmGroupFile`-Ergebnis (Task 2); `samples/dsm-mapping.example.json` (Task 1).
- Produces:
  - `Get-OupDsmMappingPath -ConfiguredPath <string> -AppRoot <string>` → `string` (Default `<AppRoot>\dsm-mapping.json`)
  - `Import-OupDsmMapping -Path <string>` → `hashtable` (Key = DSM-Name lowercase, Value = AD-App-Name) oder `$null` (fehlt/unlesbar)
  - `Resolve-OupDsmAssignments -FileResult <obj> -Mapping <hashtable> [-Now <DateTimeOffset>]` → `PSCustomObject @{ Targets; ReportRows }`; Target = `@{ TargetName; App; Software; Mode; PolicySchemaTag }`

- [ ] **Step 1: Tests ergänzen** — in `tools/test-dsm-import.ps1` vor dem `# ── Ergebnis`-Block einfügen:

```powershell
# ── Mapping-Loader ──────────────────────────────────────────────────────────
$map = Import-OupDsmMapping -Path (Join-Path $samples 'dsm-mapping.example.json')
Assert ($null -ne $map) 'Mapping: Beispieldatei geladen'
Assert ($map.Count -eq 5) 'Mapping: 5 Eintraege'
Assert ($map['7-zip 24.09 x64'] -eq '7Zip') 'Mapping: Schluessel lowercase (case-insensitiv)'
Assert ($null -eq (Import-OupDsmMapping -Path (Join-Path $samples 'gibt-es-nicht.json'))) 'Mapping: fehlende Datei -> $null'
Assert ((Get-OupDsmMappingPath -ConfiguredPath '' -AppRoot 'C:\App') -eq 'C:\App\dsm-mapping.json') 'Mapping: Default-Pfad'
Assert ((Get-OupDsmMappingPath -ConfiguredPath 'D:\x.json' -AppRoot 'C:\App') -eq 'D:\x.json') 'Mapping: konfigurierter Pfad gewinnt'

# ── Resolve-OupDsmAssignments ───────────────────────────────────────────────
$now = [DateTimeOffset]::Parse('2026-07-06T12:00:00+02:00', [System.Globalization.CultureInfo]::InvariantCulture)

$r   = Read-OupDsmGroupFile -Path (Join-Path $samples 'RBSSt01_Clients_Basis.txt')
$res = Resolve-OupDsmAssignments -FileResult $r -Mapping $map -Now $now
$names = @($res.Targets | ForEach-Object { $_.TargetName })
Assert (@($res.Targets).Count -eq 3) 'Basis: 3 Ziele (7-Zip-Doppelzuweisung dedupliziert)'
Assert ($names -contains 'RBSSt01-ClientBasis-Policy') 'Basis: SwSet -> RBSSt01-ClientBasis-Policy'
Assert ($names -contains 'RBSSt01-7Zip-Policy') 'Basis: SwPolicy+Required -> RBSSt01-7Zip-Policy'
Assert ($names -contains 'RBSSt01-Firefox-Job') 'Basis: JobPolicy+Required -> RBSSt01-Firefox-Job'
Assert (@($res.ReportRows).Count -eq 0) 'Basis: keine Filter-Zeilen'

$r   = Read-OupDsmGroupFile -Path (Join-Path $samples 'RBSSt01_Clients_Fach_X.txt')
$res = Resolve-OupDsmAssignments -FileResult $r -Mapping $map -Now $now
Assert (@($res.Targets).Count -eq 1) 'FachX: 1 Ziel'
Assert ($res.Targets[0].TargetName -eq 'RBSSt01-Office-Policy-Available') 'FachX: SwPolicy+Available -> -Policy-Available'

$r   = Read-OupDsmGroupFile -Path (Join-Path $samples 'RBSSt01_Clients_Alt.txt')
$res = Resolve-OupDsmAssignments -FileResult $r -Mapping $map -Now $now
Assert (@($res.Targets).Count -eq 1) 'Alt: nur VLC bleibt uebrig'
Assert ($res.Targets[0].TargetName -eq 'RBSSt01-VLC-Policy') 'Alt: VLC -> RBSSt01-VLC-Policy'
$g = @($res.ReportRows | ForEach-Object { $_.Grund })
Assert ($g -contains 'Deny-Policy (nicht automatisiert)') 'Alt: Deny im Report'
Assert ($g -contains 'Policy deaktiviert') 'Alt: deaktiviert im Report'
Assert ($g -contains 'Keine Instanz-Erzeugung') 'Alt: NoDeployment im Report'
Assert ($g -contains 'Policy abgelaufen') 'Alt: abgelaufen im Report'
Assert ($g -contains 'Policy noch nicht aktiv') 'Alt: Zukunfts-Start im Report'
Assert ($g -contains 'Kein Mapping fuer DSM-Software') 'Alt: fehlendes Mapping im Report'
Assert (@($res.ReportRows).Count -eq 6) 'Alt: genau 6 Filter-Zeilen'
```

- [ ] **Step 2: Tests laufen lassen — die neuen Assertions müssen fehlschlagen**

Run: `pwsh -NoProfile -File tools/test-dsm-import.ps1`
Expected: Abbruch/FAIL ab dem Mapping-Block (`Import-OupDsmMapping` unbekannt).

- [ ] **Step 3: Funktionen in `core/dsm-import.psm1` ergänzen** (vor der `Export-ModuleMember`-Zeile):

```powershell
# ─────────────────────────────────────────────────────────────────────────────
# Namensbrücke: dsm-mapping.json (App-Root) — DSM-Paketname -> AD-App-Name.
# Ohne Eintrag wird eine Software NICHT einsortiert (Report), kein Fuzzy-Match.
# ─────────────────────────────────────────────────────────────────────────────
function Get-OupDsmMappingPath {
    <#  .SYNOPSIS  Effektiver Pfad zur DSM-Mapping-Datei (Default: <AppRoot>\dsm-mapping.json).  #>
    param([string]$ConfiguredPath, [Parameter(Mandatory)][string]$AppRoot)
    if ($ConfiguredPath) { return $ConfiguredPath }
    return Join-Path $AppRoot 'dsm-mapping.json'
}

function Import-OupDsmMapping {
    <#  .SYNOPSIS  Lädt dsm-mapping.json als Hashtable (Key lowercase) — $null, wenn fehlt/unlesbar.  #>
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    try {
        $cfg = Get-Content $Path -Raw | ConvertFrom-Json
    } catch {
        if (Get-Command Write-OupLog -ErrorAction SilentlyContinue) {
            Write-OupLog "dsm-mapping.json unlesbar: $($_.Exception.Message)" 'WARN'
        }
        return $null
    }
    $map = @{}
    if ($cfg.Software) {
        foreach ($p in $cfg.Software.PSObject.Properties) {
            if ($p.Name -and $p.Value) { $map[$p.Name.ToLowerInvariant()] = "$($p.Value)" }
        }
    }
    return $map
}

function _Oup-DsmDate {
    <#  .SYNOPSIS  Parst einen Export-Zeitstempel (mit Offset/Z) — $null bei leer/unlesbar.  #>
    param($Value)
    if ($null -eq $Value -or "$Value" -eq '') { return $null }
    try { return [DateTimeOffset]::Parse("$Value", [System.Globalization.CultureInfo]::InvariantCulture) }
    catch { return $null }
}

function Resolve-OupDsmAssignments {
    <#
        .SYNOPSIS  Filtert die Policy-Zuweisungen einer Datei und bildet die
                   Zielgruppen-Namen <RBSSt>-<App>-<Endung>.
        .DESCRIPTION  Filterreihenfolge (Spec, erster Treffer -> Report-Zeile):
                      Deny -> deaktiviert -> NoDeployment -> abgelaufen ->
                      noch nicht aktiv -> unbekannter Modus -> unbekannter
                      Policy-Typ -> fehlendes Mapping. Danach Dedupe je Zielname.
        .OUTPUTS   PSCustomObject @{ Targets; ReportRows }
    #>
    param(
        [Parameter(Mandatory)]$FileResult,
        [Parameter(Mandatory)][hashtable]$Mapping,
        [Nullable[DateTimeOffset]]$Now
    )
    if ($null -eq $Now) { $Now = [DateTimeOffset]::Now }

    $file    = $FileResult.File
    $rows    = New-Object System.Collections.Generic.List[object]
    $targets = [ordered]@{}    # Zielname lowercase -> Target (Dedupe NACH Filterung)

    foreach ($pa in @($FileResult.Assignments)) {
        if (-not $pa -or -not $pa.Policy) { continue }
        $p    = $pa.Policy
        $sw   = $pa.Software
        $pn   = "$($p.PolicyName)"
        $swn  = "$($sw.Name)"
        $tag  = "$($p.PolicySchemaTag)"
        $mode = "$($pa.Assignment.AssignmentMode)"

        # 1) Deny wird bewusst nicht automatisiert (keine Deny-Gruppen im AD).
        if ($tag -ieq 'DenyPolicy') {
            $rows.Add((_Oup-DsmRow $file 'Policy' $pn 'Deny-Policy (nicht automatisiert)' "Software=$swn"))
            continue
        }
        # 2) deaktiviert
        if ((-not $p.IsActive) -or ($mode -ieq 'Disabled')) {
            $rows.Add((_Oup-DsmRow $file 'Policy' $pn 'Policy deaktiviert' "Software=$swn"))
            continue
        }
        # 3) keine Instanz-Erzeugung
        if ($mode -ieq 'NoDeployment') {
            $rows.Add((_Oup-DsmRow $file 'Policy' $pn 'Keine Instanz-Erzeugung' "Software=$swn"))
            continue
        }
        # 4/5) Aktivierungsfenster (steckt NICHT im AssignmentMode -> selbst prüfen).
        $end   = _Oup-DsmDate $p.ActivationEndDate
        $start = _Oup-DsmDate $p.ActivationStartDate
        if ($end -and $end -lt $Now) {
            $rows.Add((_Oup-DsmRow $file 'Policy' $pn 'Policy abgelaufen' "Ende=$($p.ActivationEndDate), Software=$swn"))
            continue
        }
        if ($start -and $start -gt $Now) {
            $rows.Add((_Oup-DsmRow $file 'Policy' $pn 'Policy noch nicht aktiv' "Start=$($p.ActivationStartDate), Software=$swn"))
            continue
        }
        # 6) Modus muss Required oder Available sein.
        if (@('Required', 'Available') -notcontains $mode) {
            $rows.Add((_Oup-DsmRow $file 'Policy' $pn "Unbekannter Zuweisungsmodus '$mode'" "Software=$swn"))
            continue
        }
        # Endung aus PolicySchemaTag x AssignmentMode (Spec-Namensschema).
        $suffix = $null
        if     ($tag -ieq 'SwPolicy'  -and $mode -ieq 'Required')  { $suffix = 'Policy' }
        elseif ($tag -ieq 'JobPolicy' -and $mode -ieq 'Required')  { $suffix = 'Job' }
        elseif ($tag -ieq 'SwPolicy'  -and $mode -ieq 'Available') { $suffix = 'Policy-Available' }
        elseif ($tag -ieq 'JobPolicy' -and $mode -ieq 'Available') { $suffix = 'Job-Available' }
        if (-not $suffix) {
            $rows.Add((_Oup-DsmRow $file 'Policy' $pn "Unbekannter Policy-Typ '$tag'" "Software=$swn"))
            continue
        }
        # 7) Namensbrücke: DSM-Paketname -> AD-App-Name.
        $app = $null
        if ($swn) { $app = $Mapping[$swn.ToLowerInvariant()] }
        if (-not $app) {
            $rows.Add((_Oup-DsmRow $file 'Policy' $pn 'Kein Mapping fuer DSM-Software' "Software=$swn"))
            continue
        }

        $name = "$($FileResult.Rbsst)-$app-$suffix"
        $key  = $name.ToLowerInvariant()
        if (-not $targets.Contains($key)) {
            $targets[$key] = [PSCustomObject]@{
                TargetName = $name; App = $app; Software = $swn
                Mode = $mode; PolicySchemaTag = $tag
            }
        }
    }

    return [PSCustomObject]@{ Targets = @($targets.Values); ReportRows = $rows.ToArray() }
}
```

Export-Zeile am Dateiende ersetzen durch:

```powershell
Export-ModuleMember -Function Read-OupDsmGroupFile, Get-OupDsmMappingPath, Import-OupDsmMapping, `
    Resolve-OupDsmAssignments
```

- [ ] **Step 4: Tests laufen lassen — grün**

Run: `pwsh -NoProfile -File tools/test-dsm-import.ps1`
Expected: alle `OK`, Exit-Code 0.

- [ ] **Step 5: BOM/Parser-Check**

Run: `pwsh -NoProfile -File tools/Ensure-Utf8Bom.ps1`
Expected: `0 mit Parserfehlern`.

- [ ] **Step 6: Commit**

```bash
git add core/dsm-import.psm1 tools/test-dsm-import.ps1
git commit -m "feat(dsm): Filterregeln, Namensschema und dsm-mapping.json-Loader (Resolve-OupDsmAssignments)"
```

---

### Task 4: Mock-Erweiterung — Standort `RBSSt01` nach realem AD-Muster

**Files:**
- Modify: `core/ad-reader.psm1` (in `_Oup-ReadMock`, vor `return ,(_Oup-BuildHierarchy -Flat $flat.ToArray())`, Zeile ~226)
- Modify: `tools/test-dsm-import.ps1` (Tests ergänzen)

**Interfaces:**
- Consumes: `New-OupTreeNode`, `_Oup-DnGuid`, `_Oup-ParentDn` (bestehende ad-reader-Helfer).
- Produces: Mock-Standort-OU `RBSSt01` (direkt unter `Standorte`, OHNE direkte Gruppen-Kinder → löst später den `'Standort'`-Modus aus) mit App-Sub-OUs und genau 7 Gruppen: `RBSSt01-7Zip-Policy`, `RBSSt01-7Zip-Job`, `RBSSt01-Firefox-Policy`, `RBSSt01-Firefox-Job`, `RBSSt01-ClientBasis-Policy`, `RBSSt01-Office-Policy`, `RBSSt01-Office-Policy-Available`. `VLC` fehlt ABSICHTLICH (Gruppe-fehlt-Report reproduzierbar).

- [ ] **Step 1: Tests ergänzen** — in `tools/test-dsm-import.ps1` vor dem `# ── Ergebnis`-Block:

```powershell
# ── Mock: DSM-Standort RBSSt01 ──────────────────────────────────────────────
Import-Module (Join-Path $root 'core/ad-reader.psm1') -Force -DisableNameChecking
$tree    = Get-OupAdTree -Mode Mock
$rbsst01 = @($tree.Roots[0].Children | Where-Object { $_.Name -eq 'RBSSt01' }) | Select-Object -First 1
Assert ($null -ne $rbsst01) 'Mock: Standort RBSSt01 vorhanden'
Assert (@($rbsst01.Children | Where-Object { $_.NodeType -eq 'Group' }).Count -eq 0) 'Mock: RBSSt01 ohne direkte Gruppen (Standort-Modus)'
$index = Get-OupGroupIndex -Roots @($rbsst01)
Assert ($index.ByName.Count -eq 7) 'Mock: 7 Gruppen unter RBSSt01'
Assert ($index.ByName.ContainsKey('rbsst01-office-policy-available')) 'Mock: Available-Gruppe vorhanden'
Assert ($index.ByName.ContainsKey('rbsst01-clientbasis-policy')) 'Mock: ClientBasis-Gruppe vorhanden'
Assert (-not $index.ByName.ContainsKey('rbsst01-vlc-policy')) 'Mock: VLC-Gruppe fehlt absichtlich'
```

- [ ] **Step 2: Tests laufen lassen — die Mock-Assertions müssen fehlschlagen**

Run: `pwsh -NoProfile -File tools/test-dsm-import.ps1`
Expected: `FAIL Mock: Standort RBSSt01 vorhanden` (Rest des Mock-Blocks ebenfalls FAIL/Fehler).

- [ ] **Step 3: Mock erweitern** — in `core/ad-reader.psm1`, in `_Oup-ReadMock` direkt vor `return ,(_Oup-BuildHierarchy -Flat $flat.ToArray())` einfügen:

```powershell
    # DSM-Fall: Standort-OU nach realem Muster (RBSSt = OU-Name; je Anwendung
    # eine Sub-OU mit <RBSSt>-<App>-<Endung>-Gruppen). VLC fehlt absichtlich,
    # damit der 'Gruppe fehlt'-Report ohne Domäne reproduzierbar ist.
    $rbsst   = 'RBSSt01'
    $rbsstDn = "OU=$rbsst,$rootDn"
    $flat.Add( (New-OupTreeNode 'OU' $rbsst (_Oup-DnGuid $rbsstDn) '' $rbsstDn (_Oup-ParentDn $rbsstDn)) )
    $dsmApps = [ordered]@{
        '7Zip'        = @('Policy', 'Job')
        'Firefox'     = @('Policy', 'Job')
        'ClientBasis' = @('Policy')
        'Office'      = @('Policy', 'Policy-Available')
    }
    $rid = 9000
    foreach ($app in $dsmApps.Keys) {
        $appDn = "OU=$app,$rbsstDn"
        $flat.Add( (New-OupTreeNode 'OU' $app (_Oup-DnGuid $appDn) '' $appDn (_Oup-ParentDn $appDn)) )
        foreach ($t in $dsmApps[$app]) {
            $gName = "$rbsst-$app-$t"
            $gDn   = "CN=$gName,$appDn"
            $sid   = "S-1-5-21-1234567890-1234567890-1234567890-$rid"
            $flat.Add( (New-OupTreeNode 'Group' $gName (_Oup-DnGuid $gDn) $sid $gDn (_Oup-ParentDn $gDn) 0) )
            $rid++
        }
    }
```

- [ ] **Step 4: Tests laufen lassen — grün**

Run: `pwsh -NoProfile -File tools/test-dsm-import.ps1`
Expected: alle `OK`, Exit-Code 0.

- [ ] **Step 5: BOM/Parser-Check**

Run: `pwsh -NoProfile -File tools/Ensure-Utf8Bom.ps1`
Expected: `0 mit Parserfehlern`.

- [ ] **Step 6: Commit**

```bash
git add core/ad-reader.psm1 tools/test-dsm-import.ps1
git commit -m "feat(dsm): Mock-Standort RBSSt01 mit App-Sub-OUs nach realem AD-Muster"
```

---

### Task 5: `New-OupDsmImportPlan` — RBSSt-Abgleich, Gruppen-Lookup, Plan

**Files:**
- Modify: `core/dsm-import.psm1` (Funktion ergänzen, Export-Zeile erweitern)
- Modify: `tools/test-dsm-import.ps1` (End-to-End-Test ergänzen)

**Interfaces:**
- Consumes: `Read-OupDsmGroupFile`, `Resolve-OupDsmAssignments` (Tasks 2/3); `GroupIndex` = Ergebnis von `Get-OupGroupIndex` (`.ByName` hashtable, Key = Gruppenname lowercase, Value = Gruppenknoten mit `.Guid`/`.Name`); Mock `RBSSt01` (Task 4).
- Produces: `New-OupDsmImportPlan -Paths <string[]> -Mapping <hashtable> -GroupIndex <obj> -StandortName <string> [-Now <DateTimeOffset>]` → `PSCustomObject @{ Buckets(hashtable Guid -> @{node; entries}); ReportRows; Files; FilesProcessed; FilesRejected; ComputerCount; GroupCount; MembershipCount; MissingGroups(string[]) }`. Bucket-Entries sind Mitglieds-Kopien mit gesetzter NoteProperty `targetGroup` — direkt verwendbar für `Add-OupGroupMembers`/Grid/Store.

- [ ] **Step 1: End-to-End-Test ergänzen** — in `tools/test-dsm-import.ps1` vor dem `# ── Ergebnis`-Block (nutzt `$map`, `$now`, `$index` aus den vorigen Blöcken):

```powershell
# ── New-OupDsmImportPlan: End-to-End ueber alle 6 Beispieldateien ───────────
$paths = @('RBSSt01_Clients_Basis.txt', 'RBSSt01_Clients_Fach_X.txt', 'RBSSt01_Clients_Alt.txt',
           'RBSSt01_Clients_Inventar.txt', 'RBSSt01_Clients_Defekt.txt', 'RBSSt02_Clients_Fremd.txt' |
           ForEach-Object { Join-Path $samples $_ })
$plan = New-OupDsmImportPlan -Paths $paths -Mapping $map -GroupIndex $index -StandortName 'RBSSt01' -Now $now

Assert ($plan.Files -eq 6) 'Plan: 6 Dateien'
Assert ($plan.FilesProcessed -eq 4) 'Plan: 4 verarbeitet'
Assert ($plan.FilesRejected -eq 2) 'Plan: 2 abgelehnt (Defekt + fremder RBSSt)'
Assert ($plan.ComputerCount -eq 9) 'Plan: 9 Rechner (3+2+2+2)'
Assert ($plan.GroupCount -eq 4) 'Plan: 4 Zielgruppen'
Assert ($plan.MembershipCount -eq 11) 'Plan: 11 Mitgliedschaften (9 Basis + 2 FachX)'
Assert (@($plan.MissingGroups).Count -eq 1 -and $plan.MissingGroups[0] -eq 'RBSSt01-VLC-Policy') 'Plan: VLC-Gruppe fehlt'
Assert (@($plan.ReportRows | Where-Object { $_.Datei -eq 'RBSSt02_Clients_Fremd.txt' -and $_.Grund -eq 'Datei abgelehnt' }).Count -eq 1) 'Plan: RBSSt-Fremddatei abgelehnt'
Assert (@($plan.ReportRows | Where-Object { $_.Ebene -eq 'Gruppe' }).Count -eq 1) 'Plan: 1 Gruppe-fehlt-Zeile'

$bucketNames = @($plan.Buckets.Values | ForEach-Object { $_.node.Name }) | Sort-Object
Assert (($bucketNames -join ',') -eq 'RBSSt01-7Zip-Policy,RBSSt01-ClientBasis-Policy,RBSSt01-Firefox-Job,RBSSt01-Office-Policy-Available') 'Plan: richtige Ziel-Buckets'
$firstBucket = @($plan.Buckets.Values | Where-Object { $_.node.Name -eq 'RBSSt01-7Zip-Policy' })[0]
Assert (@($firstBucket.entries).Count -eq 3) 'Plan: 3 Eintraege im 7Zip-Bucket'
Assert ($firstBucket.entries[0].targetGroup -eq 'RBSSt01-7Zip-Policy') 'Plan: targetGroup am Eintrag gesetzt'
```

- [ ] **Step 2: Tests laufen lassen — Plan-Assertions müssen fehlschlagen**

Run: `pwsh -NoProfile -File tools/test-dsm-import.ps1`
Expected: Fehler ab `New-OupDsmImportPlan` (Funktion unbekannt).

- [ ] **Step 3: Funktion in `core/dsm-import.psm1` ergänzen** (vor `Export-ModuleMember`):

```powershell
function New-OupDsmImportPlan {
    <#
        .SYNOPSIS  Baut aus DSM-Exportdateien den Import-Plan für einen Standort:
                   Buckets (Zielgruppe -> Einträge) + Report-Zeilen + Kennzahlen.
        .DESCRIPTION  Dateien sind unabhängig: eine abgelehnte Datei (Gate,
                      fremder RBSSt) blockiert die übrigen nicht. Fehlende
                      Zielgruppen werden nicht angelegt, nur berichtet.
        .PARAMETER GroupIndex  Ergebnis von Get-OupGroupIndex über die gewählte
                               Standort-OU (.ByName: Name lowercase -> Knoten).
        .OUTPUTS   PSCustomObject @{ Buckets; ReportRows; Files; FilesProcessed;
                   FilesRejected; ComputerCount; GroupCount; MembershipCount;
                   MissingGroups }
    #>
    param(
        [Parameter(Mandatory)][string[]]$Paths,
        [Parameter(Mandatory)][hashtable]$Mapping,
        [Parameter(Mandatory)]$GroupIndex,
        [Parameter(Mandatory)][string]$StandortName,
        [Nullable[DateTimeOffset]]$Now
    )

    $rows        = New-Object System.Collections.Generic.List[object]
    $buckets     = @{}     # GruppenGuid -> @{ node; entries }
    $computers   = @{}     # identifier -> $true
    $missing     = @{}     # Zielname -> $true
    $processed   = 0
    $rejected    = 0
    $memberships = 0

    foreach ($path in $Paths) {
        $fr = Read-OupDsmGroupFile -Path $path
        foreach ($r in @($fr.ReportRows)) { $rows.Add($r) }
        if ($fr.Rejected) { $rejected++; continue }

        # Standort-Gate: RBSSt muss der gewählten OU entsprechen (RBSSt = OU-Name).
        if ($fr.Rbsst -ine $StandortName) {
            $rows.Add((_Oup-DsmRow $fr.File 'Datei' $fr.GroupName 'Datei abgelehnt' "RBSSt '$($fr.Rbsst)' passt nicht zur gewaehlten OU '$StandortName'"))
            $rejected++
            continue
        }
        $processed++
        foreach ($m in @($fr.Members)) { $computers[$m.identifier] = $true }

        $res = Resolve-OupDsmAssignments -FileResult $fr -Mapping $Mapping -Now $Now
        foreach ($r in @($res.ReportRows)) { $rows.Add($r) }

        foreach ($t in @($res.Targets)) {
            $node = $GroupIndex.ByName[$t.TargetName.ToLowerInvariant()]
            if (-not $node) {
                if (-not $missing.ContainsKey($t.TargetName)) {
                    $missing[$t.TargetName] = $true
                    $rows.Add((_Oup-DsmRow $fr.File 'Gruppe' $t.TargetName 'Zielgruppe im AD nicht gefunden' "$(@($fr.Members).Count) Rechner (DSM-Software: $($t.Software))"))
                }
                continue
            }
            if (-not $buckets.ContainsKey($node.Guid)) {
                $buckets[$node.Guid] = [PSCustomObject]@{ node = $node; entries = (New-Object System.Collections.Generic.List[object]) }
            }
            foreach ($m in @($fr.Members)) {
                $copy = $m.PSObject.Copy()
                $copy | Add-Member -NotePropertyName targetGroup -NotePropertyValue $node.Name -Force
                $buckets[$node.Guid].entries.Add($copy)
                $memberships++
            }
        }
    }

    return [PSCustomObject]@{
        Buckets         = $buckets
        ReportRows      = $rows.ToArray()
        Files           = @($Paths).Count
        FilesProcessed  = $processed
        FilesRejected   = $rejected
        ComputerCount   = $computers.Count
        GroupCount      = $buckets.Count
        MembershipCount = $memberships
        MissingGroups   = @($missing.Keys)
    }
}
```

Export-Zeile ersetzen durch:

```powershell
Export-ModuleMember -Function Read-OupDsmGroupFile, Get-OupDsmMappingPath, Import-OupDsmMapping, `
    Resolve-OupDsmAssignments, New-OupDsmImportPlan
```

- [ ] **Step 4: Tests laufen lassen — grün**

Run: `pwsh -NoProfile -File tools/test-dsm-import.ps1`
Expected: alle `OK`, Exit-Code 0.

- [ ] **Step 5: BOM/Parser-Check**

Run: `pwsh -NoProfile -File tools/Ensure-Utf8Bom.ps1`
Expected: `0 mit Parserfehlern`.

- [ ] **Step 6: Commit**

```bash
git add core/dsm-import.psm1 tools/test-dsm-import.ps1
git commit -m "feat(dsm): New-OupDsmImportPlan - RBSSt-Gate, Gruppen-Lookup, Import-Plan"
```

---

### Task 6: UI-Workflow `'Standort'` + Settings + Modul-Registrierung

**Files:**
- Modify: `main.ps1` (Modulliste, Zeile ~21: `core/dsm-import.psm1` NACH `core/import-engine.psm1` einfügen)
- Modify: `core/settings.psm1` (Default `DsmMappingPath` ergänzen)
- Modify: `ui/main-window.psm1` (Kommentar Zeile 30, neuer elseif-Zweig in `_Oup-OnNodeSelected`, Dispatch Zeile ~1108, neue Funktionen `_Oup-HasGroupBelow`, `_Oup-OnImportDsm`, `_Oup-WriteDsmReport`)

**Interfaces:**
- Consumes: `Get-OupDsmMappingPath`, `Import-OupDsmMapping`, `New-OupDsmImportPlan` (Modul); vorhandene UI-Bausteine: `_Oup-SetStatus`, `_Oup-SetEntryField`, `_Oup-UpdateGroupHeader`, `Get-OupGroupIndex`, `Add-OupGroupMembers`, `Add-OupImportEntries`, `Save-OupMapping`, `Export-OupSettings`, `$script:oupSettings/oupStore/oupAppRoot/oupConfigPath/oupMappingPath/oupAdModeUsed/oupImportItems`.
- Produces: Dritter Import-Modus `'Standort'`; Report-CSV `Logs\dsm-report-<Zeitstempel>.csv`.

- [ ] **Step 1: `main.ps1` — Modul registrieren.** In der Modulliste nach `'core/import-engine.psm1',` einfügen:

```powershell
    'core/dsm-import.psm1',
```

- [ ] **Step 2: `core/settings.psm1` — Default ergänzen.** In `Get-OupDefaultSettings` nach dem `FieldMapPath`-Block einfügen:

```powershell
        # Pfad zur DSM-Mapping-Datei (DSM-Paketname -> AD-App-Name) für den
        # DSM-Export-Import (leer = <AppRoot>\dsm-mapping.json; fehlt die Datei,
        # ist kein DSM-Import möglich). Vorlage: samples\dsm-mapping.example.json.
        DsmMappingPath = ''
```

- [ ] **Step 3: `ui/main-window.psm1` — Modus-Kommentar aktualisieren.** Zeile 30 ersetzen:

```powershell
$script:oupImportMode   = 'Group' # 'Group' (Gruppe) | 'SubOU' (Unterstandort) | 'Standort' (DSM-Import)
```

- [ ] **Step 4: `_Oup-HasGroupBelow` einfügen** (direkt vor `_Oup-OnNodeSelected`):

```powershell
function _Oup-HasGroupBelow {
    <#  .SYNOPSIS  True, wenn irgendwo unterhalb des Knotens eine Gruppe liegt
                   (Kennzeichen einer Standort-OU mit App-Sub-OUs).  #>
    param($Node)
    $stack = New-Object System.Collections.Stack
    foreach ($c in @($Node.Children)) { $stack.Push($c) }
    while ($stack.Count -gt 0) {
        $n = $stack.Pop()
        if ($n.NodeType -eq 'Group') { return $true }
        foreach ($c in @($n.Children)) { $stack.Push($c) }
    }
    return $false
}
```

- [ ] **Step 5: Standort-Zweig in `_Oup-OnNodeSelected` einfügen** — NACH dem SubOU-`elseif` (endet Zeile 330) und VOR dem `else`:

```powershell
    elseif ($Node -and $Node.NodeType -eq 'OU' -and (_Oup-HasGroupBelow $Node)) {
        # OU ohne direkte Gruppen, aber mit Gruppen in Sub-OUs -> Standort-OU
        # (reales Muster: Standort -> je Anwendung eine Sub-OU) -> DSM-Import.
        $script:oupImportMode = 'Standort'
        $btn.Content   = "DSM-Export in Standort '$($Node.Name)' importieren..."
        $btn.IsEnabled = $true
        $script:oupWindow.FindName('TxtGroupName').Text = "Standort: $($Node.Name)"
        $script:oupWindow.FindName('TxtGroupGuid').Text = 'DSM-Gruppendateien (<RBSSt>_<Gruppe>.txt)'
        $script:oupWindow.FindName('TxtGroupDn').Text   = $Node.DistinguishedName
        $script:oupImportItems.Clear()
        _Oup-SetStatus "Standort gewählt: $($Node.Name) — bereit für DSM-Import."
    }
```

- [ ] **Step 6: Dispatch erweitern** — Zeile ~1108 ersetzen:

```powershell
        if     ($script:oupImportMode -eq 'SubOU')    { _Oup-OnImportSubOU }
        elseif ($script:oupImportMode -eq 'Standort') { _Oup-OnImportDsm }
        else                                          { _Oup-OnImport }
```

- [ ] **Step 7: `_Oup-OnImportDsm` + `_Oup-WriteDsmReport` einfügen** (nach `_Oup-WriteConflictReport`):

```powershell
function _Oup-OnImportDsm {
    <#
        .SYNOPSIS  DSM-Import in den gewählten Standort: eine Datei je DSM-Gruppe
                   (JSON nach int_jsonStructure.md). Jedes Mitglied wird für jede
                   relevante Policy-Zuweisung in <RBSSt>-<App>-<Endung> einsortiert.
        .DESCRIPTION  Deny-/deaktivierte/abgelaufene Policies, fremde RBSSt,
                      fehlende Mappings und fehlende Zielgruppen werden übersprungen
                      und im CSV-Report (Logs\dsm-report-*.csv) dokumentiert.
    #>
    $ou = $script:oupSelectedNode
    if (-not $ou -or $ou.NodeType -ne 'OU') { _Oup-SetStatus 'Bitte einen Standort wählen.' 'WARN'; return }

    # Mapping-Datei ist Pflicht — ohne sie ist keine Zuordnung möglich.
    $mapPath = Get-OupDsmMappingPath -ConfiguredPath $script:oupSettings.DsmMappingPath -AppRoot $script:oupAppRoot
    $mapping = Import-OupDsmMapping -Path $mapPath
    if (-not $mapping -or $mapping.Count -eq 0) {
        $m = "Mapping-Datei fehlt, ist leer oder unlesbar:`n$mapPath`n`nOhne DSM->AD-Mapping ist kein DSM-Import möglich.`nVorlage: samples\dsm-mapping.example.json"
        [void][System.Windows.MessageBox]::Show($script:oupWindow, $m, 'DSM-Import', 'OK', 'Warning')
        _Oup-SetStatus 'DSM-Import: Mapping-Datei fehlt.' 'WARN'
        return
    }

    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Filter      = 'DSM-Export (*.txt;*.json)|*.txt;*.json|Alle Dateien (*.*)|*.*'
    $dlg.Multiselect = $true
    $dlg.Title       = "DSM-Export(e) für Standort '$($ou.Name)' wählen"
    if ($script:oupSettings.LastImportDir -and (Test-Path $script:oupSettings.LastImportDir)) {
        $dlg.InitialDirectory = $script:oupSettings.LastImportDir
    }
    if (-not $dlg.ShowDialog()) { return }

    # 1) Plan bauen (Parsen, Gates, Filter, Mapping, Gruppen-Lookup — UI-frei im Modul).
    $index = Get-OupGroupIndex -Roots @($ou)
    $plan  = New-OupDsmImportPlan -Paths $dlg.FileNames -Mapping $mapping -GroupIndex $index -StandortName $ou.Name

    if ($plan.MembershipCount -eq 0) {
        $reportPath = $null
        if (@($plan.ReportRows).Count -gt 0) { $reportPath = _Oup-WriteDsmReport -Rows @($plan.ReportRows) -AppRoot $script:oupAppRoot }
        $m = "Keine einsortierbaren Mitgliedschaften gefunden ($($plan.FilesRejected) von $($plan.Files) Datei(en) abgelehnt)."
        if ($reportPath) { $m += "`nDetails: $reportPath" }
        [void][System.Windows.MessageBox]::Show($script:oupWindow, $m, 'DSM-Import', 'OK', 'Warning')
        _Oup-SetStatus 'DSM-Import: nichts einzusortieren.' 'WARN'
        return
    }

    $whatIf = [bool]$script:oupWindow.FindName('ChkWhatIf').IsChecked
    $isMock = ($script:oupAdModeUsed -eq 'Mock')

    # 2) Bestätigung.
    if (-not $whatIf) {
        $head = if ($isMock) { "ACHTUNG: Quelle ist Mock (keine Domäne) — es wird nur simuliert.`n`n" } else { '' }
        $extra = ''
        if ($plan.FilesRejected -gt 0)          { $extra += "`n$($plan.FilesRejected) Datei(en) abgelehnt." }
        if (@($plan.MissingGroups).Count -gt 0) { $extra += "`n$(@($plan.MissingGroups).Count) Zielgruppe(n) fehlen im AD." }
        if (@($plan.ReportRows).Count -gt 0)    { $extra += "`nDetails im Report (Logs\dsm-report-*.csv)." }
        $q = "$head$($plan.ComputerCount) Rechner in Standort '$($ou.Name)' einsortieren`n($($plan.MembershipCount) Mitgliedschaften in $($plan.GroupCount) Gruppen)?$extra"
        $ans = [System.Windows.MessageBox]::Show($script:oupWindow, $q, 'DSM-Import',
                   [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
        if ($ans -ne [System.Windows.MessageBoxResult]::Yes) { _Oup-SetStatus 'DSM-Import abgebrochen.'; return }
    }

    # 3) Schreiben je Zielgruppe (Muster wie Geräte-Import).
    $adMode        = if ($isMock) { 'Mock' } else { 'Auto' }
    $counts        = @{}
    $allResults    = New-Object System.Collections.Generic.List[object]
    $stored        = 0
    $groupsTouched = 0
    _Oup-SetStatus "DSM-Import: $($plan.ComputerCount) Rechner in '$($ou.Name)' ($adMode$(if($whatIf){'/Testlauf'}))..."

    foreach ($b in $plan.Buckets.Values) {
        $entries = $b.entries.ToArray()
        $results = @(Add-OupGroupMembers -GroupNode $b.node -Entries $entries `
                        -Mode $adMode -Server $script:oupSettings.AdServer -WhatIf:$whatIf)
        $byId = @{}; foreach ($x in $results) { if ($x.identifier) { $byId[$x.identifier] = $x.status } }
        foreach ($e in $entries) {
            $st = if ($byId.ContainsKey($e.identifier)) { $byId[$e.identifier] } else { 'Unbekannt' }
            _Oup-SetEntryField $e 'adStatus' $st
            [void]$allResults.Add($e)
        }
        foreach ($x in $results) { $counts[$x.status] = 1 + $(if ($counts.ContainsKey($x.status)) { $counts[$x.status] } else { 0 }) }
        $groupsTouched++
        if (-not $whatIf) {
            $persist = @($entries | Where-Object { $_.adStatus -in @('Added', 'AlreadyMember', 'Simuliert') })
            if ($persist.Count -gt 0) { $stored += (Add-OupImportEntries -Store $script:oupStore -GroupNode $b.node -Entries $persist) }
        }
    }
    if (-not $whatIf) { Save-OupMapping -Store $script:oupStore -Path $script:oupMappingPath }

    # 4) Report schreiben (immer, wenn Zeilen vorhanden — auch bei Erfolg).
    $reportPath = $null
    if (@($plan.ReportRows).Count -gt 0) { $reportPath = _Oup-WriteDsmReport -Rows @($plan.ReportRows) -AppRoot $script:oupAppRoot }

    # 5) Einstellungen + Anzeige.
    $script:oupSettings.LastImportDir = Split-Path -Parent $dlg.FileNames[0]
    Export-OupSettings -Settings $script:oupSettings -ConfigPath $script:oupConfigPath
    $script:oupImportItems.Clear()
    foreach ($e in $allResults) { $script:oupImportItems.Add([PSCustomObject]$e) }
    if (-not $whatIf) { foreach ($b in $plan.Buckets.Values) { _Oup-UpdateGroupHeader -Node $b.node } }

    # 6) Ergebnis-Dialog.
    $summary = (($counts.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ')
    $prefix  = if ($whatIf) { 'Testlauf (DSM)' } else { 'DSM-Import' }
    $lines = @("Standort '$($ou.Name)': $($plan.ComputerCount) Rechner, $groupsTouched Zielgruppen, $($plan.MembershipCount) Mitgliedschaften.", "Status: $summary")
    if (-not $whatIf -and $stored -gt 0) { $lines += "$stored neu im Store gespeichert." }
    if ($plan.FilesRejected -gt 0) { $lines += "Abgelehnte Dateien: $($plan.FilesRejected) von $($plan.Files)." }
    if (@($plan.MissingGroups).Count -gt 0) {
        $lines += "Fehlende Zielgruppen ($(@($plan.MissingGroups).Count)): " + ((@($plan.MissingGroups) | Select-Object -First 12) -join ', ')
    }
    if ($reportPath) { $lines += "Report: $reportPath" }
    [void][System.Windows.MessageBox]::Show($script:oupWindow, ($lines -join "`n"), $prefix,
              [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)

    $lvl = if (($plan.FilesRejected -gt 0) -or (@($plan.MissingGroups).Count -gt 0) -or $counts.ContainsKey('Error')) { 'WARN' } else { 'INFO' }
    _Oup-SetStatus "${prefix}: $($lines[0]) Status: $summary" $lvl
}

function _Oup-WriteDsmReport {
    <#  .SYNOPSIS  Schreibt die DSM-Import-Report-Zeilen (übersprungene Dateien/
                   Mitglieder/Policies/Gruppen inkl. Grund) als CSV nach Logs\.  #>
    param([object[]]$Rows, [string]$AppRoot)
    $dir = Join-Path $AppRoot 'Logs'
    if (-not (Test-Path $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
    $path = Join-Path $dir ("dsm-report-{0}.csv" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    try {
        $Rows | Export-Csv -Path $path -NoTypeInformation -Encoding UTF8
        Write-OupLog "DSM-Import-Report geschrieben: $path ($(@($Rows).Count) Zeile(n))" 'INFO'
        return $path
    } catch {
        Write-OupLog "DSM-Report konnte nicht geschrieben werden: $($_.Exception.Message)" 'ERROR'
        return $null
    }
}
```

- [ ] **Step 8: BOM/Parser-Check + Tests**

Run: `pwsh -NoProfile -File tools/Ensure-Utf8Bom.ps1` — Expected: `0 mit Parserfehlern`.
Run: `pwsh -NoProfile -File tools/test-dsm-import.ps1` — Expected: grün (Regressionscheck).

- [ ] **Step 9: Manuelle Verifikation auf dem Windows-Dev-Client** (WPF läuft nicht auf der Linux-Box; dieser Schritt ist beim nächsten Windows-Lauf fällig — im Commit-Text NICHT als verifiziert behaupten):
  1. `Copy-Item samples\dsm-mapping.example.json dsm-mapping.json`
  2. `.\run.ps1` (Mock-Modus greift ohne Domäne), im Baum `Standorte → RBSSt01` wählen → Knopf zeigt „DSM-Export in Standort 'RBSSt01' importieren...".
  3. Testlauf-Häkchen setzen, alle 6 `samples\RBSSt0*.txt` importieren → Grid zeigt 11 Einträge mit `adStatus=Would`; `Logs\dsm-report-*.csv` enthält die Ablehnungs-/Filter-/Gruppe-fehlt-Zeilen.
  4. Ohne Testlauf wiederholen → Bestätigungsdialog nennt 9 Rechner / 11 Mitgliedschaften / 4 Gruppen, 2 abgelehnte Dateien, 1 fehlende Zielgruppe; Status `Simuliert` (Mock); Zähler an den 4 Gruppen steigen.
  5. `Berlin → Berlin-Nord` wählen → weiterhin SubOU-Modus (Regression Geräte-Import); eine Gruppe wählen → weiterhin Gruppen-Modus.

- [ ] **Step 10: Commit**

```bash
git add main.ps1 core/settings.psm1 ui/main-window.psm1
git commit -m "feat(dsm): Standort-Modus in der UI - DSM-Import mit Plan, Bestaetigung und CSV-Report"
```

---

### Task 7: Doku nachziehen

**Files:**
- Modify: `CHANGELOG.md` (Abschnitt `## Unreleased`)
- Modify: `README.md` (neuer Abschnitt nach „Ablauf")
- Modify: `OUPilot-docs/docs/referenz/import-wege.md` (DSM-Import als vierter Import-Weg)
- Modify: `OUPilot-docs/docs/entwicklung/projektstruktur.md` (`core/dsm-import.psm1`, `tools/test-dsm-import.ps1`, neue Samples)
- Modify: `OUPilot-docs/mermaid-sources/referenz-architektur-1.mmd` (+ Rendern)

**Interfaces:**
- Consumes: fertiges Feature (Tasks 1–6).
- Produces: konsistente Doku; gerendertes Architektur-SVG.

- [ ] **Step 1: `CHANGELOG.md`** — unter `## Unreleased` ergänzen:

```markdown
- DSM-Export-Import (Standort-Ebene): eine JSON-Datei je DSM-Gruppe
  (`<RBSSt>_<Gruppe>.txt` nach `int_jsonStructure.md`, SchemaVersion 1.0) wird
  in AD-Mitgliedschaften `<RBSSt>-<App>-<Endung>` übersetzt (Endungen `Policy`,
  `Job`, `Policy-Available`, `Job-Available` aus PolicySchemaTag × AssignmentMode).
  Namensbrücke über `dsm-mapping.json` (DSM-Paketname → AD-App-Name, Settings-Key
  `DsmMappingPath`, Vorlage `samples\dsm-mapping.example.json`). Deny-Policies,
  deaktivierte/abgelaufene/noch-nicht-aktive Policies, Nicht-Computer-Mitglieder,
  fehlende Mappings/Zielgruppen und abgelehnte Dateien (Validation-Gate, fremder
  RBSSt) landen im CSV-Report `Logs\dsm-report-*.csv`. Dynamische Gruppen werden
  über den exportierten Snapshot einsortiert.
- core: neues Modul `dsm-import.psm1` (`Read-OupDsmGroupFile`,
  `Resolve-OupDsmAssignments`, `New-OupDsmImportPlan`, Mapping-Loader); UI:
  dritter Import-Modus `Standort` (OU ohne direkte Gruppen, mit Gruppen in
  Sub-OUs); Mock um Standort `RBSSt01` nach realem AD-Muster erweitert;
  Test-Harness `tools\test-dsm-import.ps1`.
```

- [ ] **Step 2: `README.md`** — nach dem Abschnitt „Ablauf" einfügen:

```markdown
## DSM-Export-Import (Standort-Ebene)

Für die DSM→MECM-Migration verarbeitet OUPilot Exportdateien des DSM-Skripts
(eine JSON-Datei je DSM-Gruppe, `<RBSSt>_<Gruppe>.txt`): Standort-OU im Baum
wählen (RBSSt = OU-Name), Dateien importieren — jedes Gruppenmitglied wird für
jede relevante Policy-Zuweisung in die AD-Gruppe `<RBSSt>-<App>-<Endung>`
einsortiert (`-Policy`, `-Job`, `-Policy-Available`, `-Job-Available`).

Voraussetzung ist die Namensbrücke `dsm-mapping.json` im App-Root (DSM-Paketname
→ AD-App-Name; Vorlage `samples\dsm-mapping.example.json`, Pfad per Settings-Key
`DsmMappingPath`). Nicht Einsortierbares — Deny-Policies, deaktivierte/abgelaufene
Policies, fehlende Mappings oder Zielgruppen, abgelehnte Dateien — dokumentiert
der CSV-Report `Logs\dsm-report-*.csv`. Beispieldateien: `samples\RBSSt0*.txt`.
```

- [ ] **Step 3: `OUPilot-docs/docs/referenz/import-wege.md`** — Datei lesen und den DSM-Import im Stil der bestehenden drei Import-Wege als vierten Abschnitt ergänzen. Inhaltliche Pflichtpunkte: Standort-Modus (wann der Knopf erscheint), Dateiformat/Namensmuster, Namensschema-Tabelle (4 Endungen + Deny→Report), Filterregeln-Reihenfolge, `dsm-mapping.json`, Validation-Gate/RBSSt-Gate, Report-CSV-Spalten (`Datei, Ebene, Betroffen, Grund, Detail`), Verweis auf `samples\`.

- [ ] **Step 4: `OUPilot-docs/docs/entwicklung/projektstruktur.md`** — Datei lesen; `core/dsm-import.psm1`, `tools/test-dsm-import.ps1` und die neuen Samples an den passenden Stellen der Struktur-Übersicht ergänzen (Beschreibung je eine Zeile, Stil der Datei übernehmen).

- [ ] **Step 5: Architektur-Diagramm** — `OUPilot-docs/mermaid-sources/referenz-architektur-1.mmd` lesen; Knoten für `dsm-import.psm1` im core-Bereich ergänzen mit Kanten analog zur `import-engine` (UI → dsm-import → ad-writer/ad-reader-Index). Klassen-/Style-Zuweisung der bestehenden core-Knoten übernehmen. Danach rendern:

Run: `bash OUPilot-docs/tools/render_mermaid.sh`
Expected: SVGs unter `OUPilot-docs/docs/images/mermaid/` neu erzeugt, ohne Fehler.

- [ ] **Step 6: Grep-Gegenprüfung (Doku-Pflicht „geprüft, nicht geraten")**

Run: `grep -rl "dsm-import" CHANGELOG.md README.md OUPilot-docs/docs/referenz/import-wege.md OUPilot-docs/docs/entwicklung/projektstruktur.md OUPilot-docs/mermaid-sources/referenz-architektur-1.mmd`
Expected: alle 5 Dateien werden gelistet.

- [ ] **Step 7: Commit**

```bash
git add CHANGELOG.md README.md OUPilot-docs/docs/referenz/import-wege.md OUPilot-docs/docs/entwicklung/projektstruktur.md OUPilot-docs/mermaid-sources/referenz-architektur-1.mmd OUPilot-docs/docs/images/mermaid/
git commit -m "docs: DSM-Export-Import dokumentieren (README, Changelog, Referenz, Architektur-Diagramm)"
```

---

## Nicht Teil dieses Plans (bewusst)

- Release/Versions-Bump auf 1.5.0 + gh-pages-Redeploy (eigener Schritt beim Release; dann auch `icon-rail.js`-Version).
- Deny-Automatisierung, Anlegen fehlender Gruppen, `DynamicRules`→MECM, User-Targeting (siehe Spec „außerhalb des Scopes").
- Der echte AD-Gegentest am Domänen-Testclient (offener Punkt aus `docs/handoffs/`, gilt auch für dieses Feature).
