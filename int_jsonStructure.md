
Das Export-Skript arbeitet nach diesen Regeln:

1.	Es exportiert eine Datei pro DSM-Gruppe.
2.	Der Dateiname beginnt mit der RBSSt. Die RBSSt wird aus der DSM-ORG-Struktur ermittelt:
ORG/<RBSSt>/.../<Gruppe>.
3.	Maßgeblich ist die erste OU direkt unterhalb des Roots ORG.
4.	Der Dateiname folgt dem Muster:
<RBSSt>_<DSM-Gruppenname>.txt.
5.	In der Datei steht JSON, keine Freitextliste.
6.	Pro Gruppe werden die DSM-Gruppendaten ausgegeben:
Name, DSM Group ID, SchemaTag, GroupType, RBSSt, OU-Pfad, OU-Pfadbestandteile und ParentContainerId.
7.	Die Mitgliedschaft wird mit aufgenommen:
statische Gruppen als DirectMembers, dynamische Gruppen als ResolvedSnapshot.
8.	Bei dynamischen Gruppen wird der zum Exportzeitpunkt aufgelöste Mitgliederstand exportiert sowie die DSM-Regellogik.
9.	Pro Mitglied werden nur belastbare DSM-Standardinformationen ausgegeben:
Clientname, DSMObjectId und SchemaTag.
10.	Zuweisungen werden als PolicyAssignments exportiert, nicht als reine Paketliste.
11.	Es können mehrere Policies pro Gruppe enthalten sein.
12.	Jede Policy bleibt ein eigener Eintrag, auch wenn dasselbe Paket mehrfach zugewiesen ist.
13.	SwSet-Zuweisungen werden als SwSet exportiert, aber ohne SwSet-Komponenten.
14.	Zu jeder Softwarezuweisung werden Name, DSMObjectId, SchemaTag, Revision und IsSoftwareSet ausgegeben.
15.	Zu jeder Policy werden PolicyId, PolicyName, PolicySchemaTag, Aktivstatus, Installationsreihenfolge, Priorität und Aktivierungszeitraum ausgegeben.
16.	Der Zuweisungstyp wird zusätzlich zu SCCM Logik normalisiert:
Required, Available, Disabled oder NoDeployment.
17.	Es werden keine Zielnamen für AD-Gruppen oder SCCM Collections erzeugt. Diese Namensbildung bleibt Aufgabe des Kundenskripts.
18.	Jede Datei enthält Export-Metadaten und eine SchemaVersion.
19.	Jede Datei enthält eine Validierung mit IsValidForMigration, Warnings und Errors, damit ein Folgeskript automatisiert entscheiden kann, ob die Datei verarbeitet werden darf.

Untenstehend die folgenden Beispiel-JSON-Dateien:

•	Beispiel 1: statische Clientgruppe mit mehreren aktiven Policies
•	Beispiel 2: dynamische Clientgruppe mit aufgelöster Mitgliedschaft zum Exportzeitpunkt
•	Beispiel 3: Gruppe mit deaktivierter und abgelaufener Policy
•	Beispiel 4: Gruppe ohne direkte Policy-Zuweisung
•	Beispiel 5: mehrere Policies auf dasselbe Paket mit unterschiedlichen Revisionen, evtl. mit deaktivierten Policies


Feldlogik 

Feld	Typ	Pflicht	Beschreibung / Verwendung
SchemaVersion	String	Ja	Version des JSON-Schemas, damit Folgeskripte kompatibel bleiben. Beispiel: 1.0
ExportInfo	Object	Ja	Metadaten zum Exportlauf
ExportInfo.ExportTimestamp	String	Ja	Zeitpunkt des Exports mit Zeitzone
ExportInfo.SourceSystem	String	Ja	Quellsystem, zum Beispiel Ivanti DSM
ExportInfo.SourceEnvironment	String	Ja	DSM-Umgebung, zum Beispiel DSM-PROD
ExportInfo.ExportTool	String	Ja	Name des Export-Skripts
ExportInfo.ExportToolVersion	String	Ja	Version des Export-Skripts
DSMGroup	Object	Ja	Informationen zur exportierten DSM-Gruppe
DSMGroup.Name	String	Ja	Name der DSM-Gruppe
DSMGroup.DSMGroupId	Integer	Ja	Eindeutige DSM-ID der Gruppe
DSMGroup.SchemaTag	String	Ja	DSM-Schema der Gruppe, zum Beispiel Group oder DynamicGroup
DSMGroup.GroupType	String	Ja	Typ der Gruppe, typischerweise Computer oder User
DSMGroup.RBSSt	String	Ja	Ermittelter RBSSt-Wert aus der ORG-Struktur
DSMGroup.OUPath	String	Ja	Vollständiger DSM-OU-Pfad als lesbare Zeichenkette
DSMGroup.OUPathParts	Array[String]	Ja	OU-Pfad als Array für robuste maschinelle Auswertung
DSMGroup.ParentContainerId	Integer	Ja	DSM-ID des übergeordneten Containers
Membership	Object	Ja	Mitgliedschaftsinformationen der DSM-Gruppe
Membership.MembershipType	String	Ja	Static oder Dynamic
Membership.ExportMode	String	Ja	DirectMembers bei statischen Gruppen, ResolvedSnapshot bei dynamischen Gruppen
Membership.Members	Array[Object]	Ja	Aufgelöste Gruppenmitglieder
Membership.Members[].Name	String	Ja	DSM-Name des Mitglieds, bei Computern typischerweise Client- oder Servername
Membership.Members[].DSMObjectId	Integer	Ja	Eindeutige DSM-ID des Mitglieds
Membership.Members[].SchemaTag	String	Ja	DSM-Schema des Mitglieds, zum Beispiel Computer, User, Group, ExternalGroup
DynamicRules	Object oder Null	Ja	Regeldefinition bei dynamischen Gruppen. Bei statischen Gruppen null
DynamicRules.RuleExported	Boolean	Ja, wenn dynamisch	Gibt an, ob dynamische Regeln exportiert wurden
DynamicRules.RuleSource	String	Ja, wenn dynamisch	Quelle der Regel, zum Beispiel DynamicGroupProps
DynamicRules.ParentDynamicGroupId	Integer oder Null	Ja, wenn dynamisch	ID der übergeordneten DynamicGroup, falls verschachtelt
DynamicRules.OwnFilter	String	Ja, wenn dynamisch	Eigener DSM-/LDAP-Filter der dynamischen Gruppe
DynamicRules.EffectiveLdapFilter	String oder Null	Ja, wenn dynamisch	Zusammengesetzter wirksamer Filter, soweit rekonstruierbar
DynamicRules.RuleChain	Array[Object]	Ja, wenn dynamisch	Regelkette bei verschachtelten dynamischen Gruppen
DynamicRules.RuleChain[].Level	Integer	Ja, wenn dynamisch	Ebene innerhalb der Regelkette, beginnend bei 0
DynamicRules.RuleChain[].DSMGroupId	Integer	Ja, wenn dynamisch	DSM-ID der DynamicGroup in dieser Regelstufe
DynamicRules.RuleChain[].Name	String	Ja, wenn dynamisch	Name der DynamicGroup in dieser Regelstufe
DynamicRules.RuleChain[].ParentDynamicGroupId	Integer oder Null	Ja, wenn dynamisch	Parent-DynamicGroup-ID dieser Regelstufe
DynamicRules.RuleChain[].Filter	String	Ja, wenn dynamisch	Filter der jeweiligen Regelstufe
DynamicRules.EvaluationHint	Object	Ja, wenn dynamisch	Hinweise zur Bewertung und Migration der dynamischen Regel
DynamicRules.EvaluationHint.RuleMeaning	String	Ja, wenn dynamisch	Fachliche Kurzbeschreibung der Regelwirkung
DynamicRules.EvaluationHint.CanBeConvertedToSccmQueryRule	Boolean	Ja, wenn dynamisch	Einschätzung, ob eine SCCM Query Rule prinzipiell ableitbar ist
DynamicRules.EvaluationHint.ManualReviewRecommended	Boolean	Ja, wenn dynamisch	Gibt an, ob eine manuelle Prüfung empfohlen wird
PolicyAssignments	Array[Object]	Ja	Liste der DSM-Policy-Zuweisungen an die Gruppe
PolicyAssignments[].Policy	Object	Ja	Technische DSM-Policy-Daten
PolicyAssignments[].Policy.PolicyId	Integer	Ja	Eindeutige DSM-ID der Policy
PolicyAssignments[].Policy.PolicyName	String	Ja	Name der DSM-Policy
PolicyAssignments[].Policy.PolicySchemaTag	String	Ja	DSM-Policy-Schema, zum Beispiel SwPolicy, JobPolicy, DenyPolicy
PolicyAssignments[].Policy.IsActive	Boolean	Ja	Aktivstatus der Policy
PolicyAssignments[].Policy.InstallationOrder	Integer oder Null	Ja	Installationsreihenfolge, soweit für den Policy-Typ vorhanden
PolicyAssignments[].Policy.Priority	Integer oder Null	Ja	DSM-Priorität der Policy, soweit vorhanden
PolicyAssignments[].Policy.ActivationStartDate	String oder Null	Ja	Aktivierungsbeginn der Policy
PolicyAssignments[].Policy.ActivationEndDate	String oder Null	Ja	Aktivierungsende der Policy
PolicyAssignments[].Assignment	Object	Ja	Normalisierte Zuweisungslogik
PolicyAssignments[].Assignment.AssignmentMode	String	Ja	Normalisierte Zielinterpretation: Required, Available, Disabled oder NoDeployment
PolicyAssignments[].Assignment.InstanceCreationMode	Integer oder Null	Ja	DSM-Wert für Instanzerzeugung
PolicyAssignments[].Assignment.InstanceCreationModeText	String oder Null	Ja	Lesbare Interpretation von InstanceCreationMode, zum Beispiel Automatic, OnDemand, NoInstanceCreation
PolicyAssignments[].Assignment.TargetSelectionMode	String oder Null	Ja	DSM-Zielmodus, zum Beispiel Computer, CurrentComputerOfUser, AssociatedComputerOfUser
PolicyAssignments[].Software	Object	Ja	Zugewiesenes Softwareobjekt
PolicyAssignments[].Software.Name	String	Ja	Name des zugewiesenen Pakets oder Software Sets
PolicyAssignments[].Software.DSMObjectId	Integer	Ja	DSM-ID des zugewiesenen Softwareobjekts
PolicyAssignments[].Software.SchemaTag	String	Ja	DSM-Schema des Softwareobjekts, zum Beispiel SwSet, MsiPackage, eScriptPackage
PolicyAssignments[].Software.Revision	Integer oder String oder Null	Ja	Zugewiesene DSM-Revision
PolicyAssignments[].Software.IsSoftwareSet	Boolean	Ja	Kennzeichnet, ob das Softwareobjekt ein DSM Software Set ist
PolicyAssignments[].Software.SoftwareSetHandling	Object	Ja	Verhalten beim Export von Software Sets
PolicyAssignments[].Software.SoftwareSetHandling.ComponentsExported	Boolean	Ja	Immer false, da SwSet-Komponenten nicht exportiert werden
PolicyAssignments[].Software.SoftwareSetHandling.MigrationHint	String	Ja	Migrationshinweis, zum Beispiel SoftwareSetOnly oder Package
Validation	Object	Ja	Ergebnis der Exportvalidierung
Validation.IsValidForMigration	Boolean	Ja	Gibt an, ob die Datei grundsätzlich automatisiert weiterverarbeitet werden kann
Validation.Warnings	Array[String]	Ja	Hinweise, die eine Verarbeitung nicht zwingend verhindern
Validation.Errors	Array[String]	Ja	Fehler, bei denen ein Folgeskript die Datei nicht automatisch verarbeiten sollte

Die Clientinformationen bleiben bewusst schlank. Aus DSM-Standarddaten sind Name, DSM-ID und SchemaTag belastbar. FQDN, SID oder AD-Domain werden nur aufgenommen, wenn sie im konkreten DSM-Objekt zuverlässig als Standard- oder gepflegte Inventareigenschaft vorhanden sind.

Beispiel 1: statische Clientgruppe mit mehreren aktiven Policies

Dateiname:

RBSSt01_Clients_Basissoftware.txt

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
    "Name": "Clients_Basissoftware",
    "DSMGroupId": 4711001,
    "SchemaTag": "Group",
    "GroupType": "Computer",
    "RBSSt": "RBSSt01",
    "OUPath": "ORG/RBSSt01/Clients/Gruppen/Basis",
    "OUPathParts": [
      "ORG",
      "RBSSt01",
      "Clients",
      "Gruppen",
      "Basis"
    ],
    "ParentContainerId": 310045
  },
  "Membership": {
    "MembershipType": "Static",
    "ExportMode": "DirectMembers",
    "Members": [
      {
        "Name": "PC-010145",
        "DSMObjectId": 9100145,
        "SchemaTag": "Computer"
      },
      {
        "Name": "PC-010188",
        "DSMObjectId": 9100188,
        "SchemaTag": "Computer"
      },
      {
        "Name": "PC-010231",
        "DSMObjectId": 9100231,
        "SchemaTag": "Computer"
      }
    ]
  },
  "PolicyAssignments": [
    {
      "Policy": {
        "PolicyId": 9300101,
        "PolicyName": "SWSET_Client_Basis -> Clients_Basissoftware",
        "PolicySchemaTag": "SwPolicy",
        "IsActive": true,
        "InstallationOrder": 1000,
        "Priority": 50,
        "ActivationStartDate": "2026-06-01T18:00:00Z",
        "ActivationEndDate": null
      },
      "Assignment": {
        "AssignmentMode": "Required",
        "InstanceCreationMode": 0,
        "InstanceCreationModeText": "Automatic",
       "TargetSelectionMode": "Computer"
      },
      "Software": {
        "Name": "SWSET_Client_Basis",
        "DSMObjectId": 6200100,
        "SchemaTag": "SwSet",
        "Revision": 8,
        "IsSoftwareSet": true,
        "SoftwareSetHandling": {
          "ComponentsExported": false,
          "MigrationHint": "SoftwareSetOnly"
        }
      }
    },
    {
      "Policy": {
        "PolicyId": 9300102,
        "PolicyName": "7-Zip 24.09 x64 -> Clients_Basissoftware",
        "PolicySchemaTag": "SwPolicy",
        "IsActive": true,
        "InstallationOrder": 1100,
        "Priority": 50,
        "ActivationStartDate": "2026-06-01T18:00:00Z",
        "ActivationEndDate": null
      },
      "Assignment": {
        "AssignmentMode": "Required",
        "InstanceCreationMode": 0,
        "InstanceCreationModeText": "Automatic",
        "TargetSelectionMode": "Computer"
      },
      "Software": {
        "Name": "7-Zip 24.09 x64",
        "DSMObjectId": 6200115,
        "SchemaTag": "eScriptPackage",
        "Revision": 3,
        "IsSoftwareSet": false,
        "SoftwareSetHandling": {
          "ComponentsExported": false,
          "MigrationHint": "Package"
        }
      }
    },
    {
      "Policy": {
        "PolicyId": 9300103,
        "PolicyName": "Mozilla Firefox ESR -> Clients_Basissoftware",
        "PolicySchemaTag": "SwPolicy",
        "IsActive": true,
        "InstallationOrder": 1200,
        "Priority": 50,
        "ActivationStartDate": "2026-06-01T18:00:00Z",
        "ActivationEndDate": null
      },
      "Assignment": {
        "AssignmentMode": "Required",
        "InstanceCreationMode": 0,
        "InstanceCreationModeText": "Automatic",
        "TargetSelectionMode": "Computer"
      },
      "Software": {
        "Name": "Mozilla Firefox ESR",
        "DSMObjectId": 6200130,
        "SchemaTag": "MsiPackage",
        "Revision": 17,
        "IsSoftwareSet": false,
        "SoftwareSetHandling": {
          "ComponentsExported": false,
          "MigrationHint": "Package"
        }
      }
    }
  ],
  "Validation": {
    "IsValidForMigration": true,
    "Warnings": [],
    "Errors": []
  }
}

Erläuterung:
Diese Datei beschreibt eine statische DSM-Computergruppe. Die Mitgliederliste kann vom Kunden direkt als Grundlage für AD-Gruppenmitglieder oder SCCM Direct Membership Rules verwendet werden. Die drei Einträge unter PolicyAssignments entsprechen drei separaten DSM-Policies. Das Software Set wird als eigenes Zielobjekt exportiert, seine Komponenten werden bewusst nicht ausgegeben.

Beispiel 2: dynamische Clientgruppe mit aufgelöster Mitgliedschaft zum Exportzeitpunkt

Dateiname:

RBSSt02_Clients_Fachverfahren_X.txt

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
    "Name": "Clients_Fachverfahren_X",
    "DSMGroupId": 4712055,
    "SchemaTag": "DynamicGroup",
    "GroupType": "Computer",
    "RBSSt": "RBSSt02",
    "OUPath": "ORG/RBSSt02/Clients/Fachverfahren/Gruppen",
    "OUPathParts": [
      "ORG",
      "RBSSt02",
      "Clients",
      "Fachverfahren",
      "Gruppen"
    ],
    "ParentContainerId": 320081
  },
  "Membership": {
    "MembershipType": "Dynamic",
    "ExportMode": "ResolvedSnapshot",
    "Members": [
      {
        "Name": "PC-020145",
        "DSMObjectId": 9101145,
        "SchemaTag": "Computer"
      },
      {
        "Name": "PC-020188",
        "DSMObjectId": 9101188,
        "SchemaTag": "Computer"
      },
      {
        "Name": "PC-020231",
        "DSMObjectId": 9101231,
        "SchemaTag": "Computer"
      },
      {
        "Name": "PC-020244",
        "DSMObjectId": 9101244,
        "SchemaTag": "Computer"
      }
    ]
  },
  "DynamicRules": {
    "RuleExported": true,
    "RuleSource": "DynamicGroupProps",
    "ParentDynamicGroupId": 4712000,
    "OwnFilter": "(&(SchemaTag=Computer)(Name=PC-02*))",
    "EffectiveLdapFilter": "(&(SchemaTag=Computer)(ParentContId=320081)(BasicInventory.InstalledOSFriendlyName=*Windows 11*)(Name=PC-02*))",
    "RuleChain": [
      {
        "Level": 0,
        "DSMGroupId": 4712000,
        "Name": "Clients_Windows11",
        "ParentDynamicGroupId": null,
        "Filter": "(&(SchemaTag=Computer)(BasicInventory.InstalledOSFriendlyName=*Windows 11*))"
      },
      {
        "Level": 1,
        "DSMGroupId": 4712055,
        "Name": "Clients_Fachverfahren_X",
        "ParentDynamicGroupId": 4712000,
        "Filter": "(&(SchemaTag=Computer)(Name=PC-02*))"
      }
    ],
    "EvaluationHint": {
      "RuleMeaning": "Die Gruppe ist dynamisch. Die Mitglieder ergeben sich aus dem eigenen Filter kombiniert mit den Filtern der Parent-DynamicGroups und dem gemeinsamen ParentContainerId.",
      "CanBeConvertedToSccmQueryRule": true,
      "ManualReviewRecommended": true
    }
  },
  "PolicyAssignments": [
    {
      "Policy": {
        "PolicyId": 9400780,
        "PolicyName": "Fachverfahren X Client -> Clients_Fachverfahren_X",
        "PolicySchemaTag": "SwPolicy",
        "IsActive": true,
        "InstallationOrder": 2000,
        "Priority": 70,
        "ActivationStartDate": "2026-05-15T18:00:00Z",
        "ActivationEndDate": null
      },
      "Assignment": {
        "AssignmentMode": "Required",
        "InstanceCreationMode": 0,
        "InstanceCreationModeText": "Automatic",
        "TargetSelectionMode": "Computer"
      },
      "Software": {
        "Name": "Fachverfahren X Client",
        "DSMObjectId": 6300440,
        "SchemaTag": "MsiPackage",
        "Revision": 12,
        "IsSoftwareSet": false,
        "SoftwareSetHandling": {
          "ComponentsExported": false,
          "MigrationHint": "Package"
        }
      }
    },
    {
      "Policy": {
        "PolicyId": 9400782,
        "PolicyName": "Fachverfahren X Benutzerhilfe -> Clients_Fachverfahren_X",
        "PolicySchemaTag": "SwPolicy",
        "IsActive": true,
        "InstallationOrder": 2010,
        "Priority": 50,
        "ActivationStartDate": "2026-05-15T18:00:00Z",
        "ActivationEndDate": null
      },
      "Assignment": {
        "AssignmentMode": "Available",
        "InstanceCreationMode": 1,
        "InstanceCreationModeText": "OnDemand",
        "TargetSelectionMode": "Computer"
      },
      "Software": {
        "Name": "Fachverfahren X Benutzerhilfe",
        "DSMObjectId": 6300441,
        "SchemaTag": "eScriptPackage",
        "Revision": 5,
        "IsSoftwareSet": false,
        "SoftwareSetHandling": {
          "ComponentsExported": false,
          "MigrationHint": "Package"
        }
      }
    },
    {
      "Policy": {
        "PolicyId": 9400783,
        "PolicyName": "Fachverfahren X Druckkomponente -> Clients_Fachverfahren_X",
        "PolicySchemaTag": "SwPolicy",
        "IsActive": true,
        "InstallationOrder": 2020,
        "Priority": 60,
        "ActivationStartDate": "2026-05-15T18:00:00Z",
        "ActivationEndDate": null
      },
      "Assignment": {
        "AssignmentMode": "Required",
        "InstanceCreationMode": 0,
        "InstanceCreationModeText": "Automatic",
        "TargetSelectionMode": "Computer"
      },
      "Software": {
        "Name": "Fachverfahren X Druckkomponente",
        "DSMObjectId": 6300442,
        "SchemaTag": "eScriptPackage",
        "Revision": 4,
        "IsSoftwareSet": false,
        "SoftwareSetHandling": {
          "ComponentsExported": false,
          "MigrationHint": "Package"
        }
      }
    }
  ],
  "Validation": {
    "IsValidForMigration": true,
    "Warnings": [
      "Die DSM-Gruppe ist dynamisch. Die exportierten Mitglieder bilden den aufgelösten Stand zum Exportzeitpunkt ab.",
      "Die dynamischen Regeln wurden zusätzlich exportiert. Eine automatische Übersetzung nach SCCM Query Rules muss fachlich geprüft werden.",
      "Die Gruppe ist Teil einer verschachtelten DynamicGroup-Struktur. Die RuleChain muss bei einer Regelmigration berücksichtigt werden."
    ],
    "Errors": []
  }
}

Erläuterung:

Diese Datei zeigt eine dynamische DSM-Gruppe. Members bleibt auch bei dynamischen Gruppen enthalten, weil es dem Kunden einen prüfbaren Snapshot liefert. DynamicRules liefert zusätzlich die fachliche Grundlage, um daraus bei Bedarf SCCM Query Membership Rules oder andere Zielregeln abzuleiten. Das Kundenskript kann selbst entscheiden, ob es den Snapshot, die Regel oder beides nutzt.

Beispiel 3: Gruppe mit deaktivierter und abgelaufener Policy

Dateiname:

RBSSt03_Clients_Altverfahren_Y.txt

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
    "Name": "Clients_Altverfahren_Y",
    "DSMGroupId": 4713099,
    "SchemaTag": "Group",
    "GroupType": "Computer",
    "RBSSt": "RBSSt03",
    "OUPath": "ORG/RBSSt03/Clients/Altverfahren/Gruppen",
   "OUPathParts": [
      "ORG",
      "RBSSt03",
      "Clients",
      "Altverfahren",
      "Gruppen"
    ],
    "ParentContainerId": 330091
  },
  "Membership": {
    "MembershipType": "Static",
    "ExportMode": "DirectMembers",
    "Members": [
      {
        "Name": "PC-030041",
        "DSMObjectId": 9103041,
        "SchemaTag": "Computer"
      },
      {
        "Name": "PC-030052",
        "DSMObjectId": 9103052,
        "SchemaTag": "Computer"
      }
    ]
  },
  "PolicyAssignments": [
    {
      "Policy": {
        "PolicyId": 9500201,
        "PolicyName": "Altverfahren Y Client -> Clients_Altverfahren_Y",
        "PolicySchemaTag": "SwPolicy",
        "IsActive": true,
        "InstallationOrder": 3000,
        "Priority": 50,
        "ActivationStartDate": "2024-09-01T18:00:00Z",
        "ActivationEndDate": null
      },
      "Assignment": {
        "AssignmentMode": "Required",
        "InstanceCreationMode": 0,
        "InstanceCreationModeText": "Automatic",
        "TargetSelectionMode": "Computer"
      },
      "Software": {
        "Name": "Altverfahren Y Client",
        "DSMObjectId": 6400200,
        "SchemaTag": "MsiPackage",
        "Revision": 9,
        "IsSoftwareSet": false,
        "SoftwareSetHandling": {
          "ComponentsExported": false,
          "MigrationHint": "Package"
        }
      }
    },
    {
      "Policy": {
        "PolicyId": 9500202,
        "PolicyName": "Altverfahren Y Legacy Plugin -> Clients_Altverfahren_Y",
        "PolicySchemaTag": "SwPolicy",
        "IsActive": false,
        "InstallationOrder": 3010,
        "Priority": 50,
        "ActivationStartDate": "2024-09-01T18:00:00Z",
        "ActivationEndDate": null
      },
      "Assignment": {
        "AssignmentMode": "Disabled",
        "InstanceCreationMode": 0,
        "InstanceCreationModeText": "Automatic",
        "TargetSelectionMode": "Computer"
      },
      "Software": {
        "Name": "Altverfahren Y Legacy Plugin",
        "DSMObjectId": 6400201,
        "SchemaTag": "eScriptPackage",
        "Revision": 2,
        "IsSoftwareSet": false,
        "SoftwareSetHandling": {
          "ComponentsExported": false,
          "MigrationHint": "Package"
        }
      }
    },
    {
      "Policy": {
        "PolicyId": 9500203,
        "PolicyName": "Altverfahren Y Migrationspaket -> Clients_Altverfahren_Y",
        "PolicySchemaTag": "SwPolicy",
        "IsActive": true,
        "InstallationOrder": 3020,
        "Priority": 80,
        "ActivationStartDate": "2025-01-10T18:00:00Z",
        "ActivationEndDate": "2025-12-31T22:59:59Z"
      },
      "Assignment": {
        "AssignmentMode": "NoDeployment",
        "InstanceCreationMode": 2,
        "InstanceCreationModeText": "NoInstanceCreation",
        "TargetSelectionMode": "Computer"
      },
      "Software": {
        "Name": "Altverfahren Y Migrationspaket",
        "DSMObjectId": 6400202,
        "SchemaTag": "eScriptPackage",
        "Revision": 1,
        "IsSoftwareSet": false,
        "SoftwareSetHandling": {
          "ComponentsExported": false,
          "MigrationHint": "Package"
        }
      }
    }
  ],
  "Validation": {
    "IsValidForMigration": true,
    "Warnings": [
      "Eine Policy ist deaktiviert.",
      "Eine Policy erzeugt keine Policy-Instanzen und sollte nicht automatisch als verpflichtendes SCCM Deployment übernommen werden.",
      "Eine Policy besitzt ein ActivationEndDate in der Vergangenheit."
    ],
    "Errors": []
  }
}

Erläuterung:
Diese Datei zeigt, warum das normalisierte Assignment wichtig ist. Nicht jede DSM-Policy sollte automatisch zu einem aktiven SCCM Deployment werden. Eine deaktivierte Policy erhält AssignmentMode = Disabled. Eine Policy mit InstanceCreationMode = 2 erhält AssignmentMode = NoDeployment. Dadurch kann das Kundenskript solche Einträge bewusst überspringen oder gesondert protokollieren oder diese werden direkt im Export ausgeschlossen.

Beispiel 4: Gruppe ohne direkte Policy-Zuweisung

Dateiname:

RBSSt04_Clients_Nur_Inventarisierung.txt

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
    "Name": "Clients_Nur_Inventarisierung",
    "DSMGroupId": 4714120,
    "SchemaTag": "Group",
    "GroupType": "Computer",
    "RBSSt": "RBSSt04",
    "OUPath": "ORG/RBSSt04/Clients/Inventarisierung/Gruppen",
    "OUPathParts": [
      "ORG",
      "RBSSt04",
      "Clients",
      "Inventarisierung",
      "Gruppen"
    ],
    "ParentContainerId": 340077
  },
  "Membership": {
    "MembershipType": "Static",
    "ExportMode": "DirectMembers",
    "Members": [
      {
        "Name": "PC-040011",
        "DSMObjectId": 9104011,
        "SchemaTag": "Computer"
      },
      {
        "Name": "PC-040012",
        "DSMObjectId": 9104012,
        "SchemaTag": "Computer"
      },
      {
        "Name": "PC-040013",
        "DSMObjectId": 9104013,
        "SchemaTag": "Computer"
      }
    ]
  },
  "PolicyAssignments": [],
  "Validation": {
    "IsValidForMigration": true,
    "Warnings": [
      "Die Gruppe enthält keine direkte DSM-Policy-Zuweisung."
    ],
    "Errors": []
  }
}
Erläuterung:
Diese Datei ist trotzdem gültig. Das Kundenskript kann daraus eine AD-Gruppe oder SCCM Collection mit Mitgliedern erzeugen, aber keine Deployments ableiten. PolicyAssignments bleibt bewusst als leeres Array vorhanden, damit die Struktur stabil bleibt und Skripte keine Sonderbehandlung für fehlende Felder brauchen.

Beispiel 5: mehrere Policies auf dasselbe Paket mit unterschiedlicher Revision

Dateiname:

RBSSt05_Clients_Browser_Testgruppe.txt

{
  "SchemaVersion": "1.0",
  "ExportInfo": {
    "ExportTimestamp": "2026-07-02T14:52:18+02:00",
    "SourceSystem": "Ivanti DSM",
    "SourceEnvironment": "DSM-PROD",
    "ExportTool": "Export-DsmGroupsAndPolicies.ps1",
    "ExportToolVersion": "1.0"
  },
  "DSMGroup": {
    "Name": "Clients_Browser_Testgruppe",
    "DSMGroupId": 4715090,
    "SchemaTag": "Group",
    "GroupType": "Computer",
    "RBSSt": "RBSSt05",
    "OUPath": "ORG/RBSSt05/Clients/Test/Gruppen",
    "OUPathParts": [
      "ORG",
      "RBSSt05",
      "Clients",
      "Test",
      "Gruppen"
    ],
    "ParentContainerId": 350063
  },
  "Membership": {
    "MembershipType": "Static",
    "ExportMode": "DirectMembers",
    "Members": [
      {
        "Name": "PC-050101",
        "DSMObjectId": 9105101,
        "SchemaTag": "Computer"
      },
      {
        "Name": "PC-050102",
        "DSMObjectId": 9105102,
        "SchemaTag": "Computer"
      }
    ]
  },
  "PolicyAssignments": [
    {
      "Policy": {
        "PolicyId": 9600101,
        "PolicyName": "Microsoft Edge Enterprise Rev21 -> Clients_Browser_Testgruppe",
        "PolicySchemaTag": "SwPolicy",
        "IsActive": false,
        "InstallationOrder": 1000,
        "Priority": 40,
        "ActivationStartDate": "2026-04-01T18:00:00Z",
        "ActivationEndDate": null
      },
      "Assignment": {
        "AssignmentMode": "Disabled",
        "InstanceCreationMode": 0,
        "InstanceCreationModeText": "Automatic",
        "TargetSelectionMode": "Computer"
      },
      "Software": {
        "Name": "Microsoft Edge Enterprise",
        "DSMObjectId": 6500100,
        "SchemaTag": "MsiPackage",
        "Revision": 21,
        "IsSoftwareSet": false,
        "SoftwareSetHandling": {
          "ComponentsExported": false,
          "MigrationHint": "Package"
        }
      }
    },
    {
      "Policy": {
        "PolicyId": 9600102,
        "PolicyName": "Microsoft Edge Enterprise Rev22 Pilot -> Clients_Browser_Testgruppe",
        "PolicySchemaTag": "SwPolicy",
        "IsActive": true,
        "InstallationOrder": 1000,
        "Priority": 90,
        "ActivationStartDate": "2026-06-15T18:00:00Z",
        "ActivationEndDate": null
      },
      "Assignment": {
        "AssignmentMode": "Required",
        "InstanceCreationMode": 0,
        "InstanceCreationModeText": "Automatic",
        "TargetSelectionMode": "Computer"
      },
      "Software": {
        "Name": "Microsoft Edge Enterprise",
        "DSMObjectId": 6500101,
        "SchemaTag": "MsiPackage",
        "Revision": 22,
        "IsSoftwareSet": false,
        "SoftwareSetHandling": {
          "ComponentsExported": false,
          "MigrationHint": "Package"
        }
      }
    }
  ],
  "Validation": {
    "IsValidForMigration": true,
    "Warnings": [
      "Dasselbe Softwareprodukt ist mehrfach mit unterschiedlichen Revisionen oder Policies zugewiesen.",
      "Eine der Policies ist deaktiviert."
    ],
    "Errors": []
  }
}
Erläuterung:
Dieses Beispiel zeigt, warum PolicyAssignments eine Liste von Zuweisungen sein muss und nicht nur eine Paketliste. Der Paketname ist zweimal gleich, aber Policy-ID, Revision und Aktivierungsstatus unterscheiden sich. Ein Kundenskript darf solche Einträge nicht deduplizieren, ohne die Policy- und Revisionsdaten zu berücksichtigen.

