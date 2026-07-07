# OUPilot

WPF-Anwendung (Windows PowerShell 5.1) zum Hinzufügen von **Rechnern** zu
**AD-(Software-)Gruppen** entlang der OU-Struktur — Architektur nach Vorbild des
*CodeSigningCommander* (XAML als Here-String, Module je Komponente, JSON-State).

**Aktuelle Version:** [v1.4.0](https://github.com/monoeagle/lucent-job-OUPilot/releases/latest)
· [📖 Doku](https://monoeagle.github.io/lucent-job-OUPilot/)
· [alle Releases](https://github.com/monoeagle/lucent-job-OUPilot/releases)
· [Changelog](CHANGELOG.md)

## Zweck

Jede AD-Gruppe repräsentiert ein Softwarepaket (z. B. `StandortA-SoftwareXYZ`).
MECM spiegelt diese Gruppen in Collections; die Gruppenmitgliedschaft eines
Rechners steuert damit, welche Softwarepakete auf ihn ausgerollt werden. OUPilot
ist das Werkzeug, mit dem der Admin Rechner zuverlässig in die richtige
Software-Gruppe einträgt.

## Ablauf

1. Die App liest die **OU-Struktur** und alle **AD-Gruppen** ein und zeigt sie
   als Baum.
2. Der Admin wählt eine Sub-OU, darin die passende Software-Gruppe.
3. Er importiert einen oder mehrere **JSON-Exporte** (Einzelrechner, Namenslisten
   …). Die enthaltenen Rechner werden als **Gruppenmitglieder ins AD geschrieben**
   (`Add-ADGroupMember`, ADSI-Fallback) und im lokalen Store protokolliert.

### Warum Umbenennen unkritisch ist

Jede Gruppe wird intern über ihre **`objectGUID`** identifiziert — nicht über
den Namen. Die GUID ist forest-weit eindeutig und überlebt **Umbenennen** und
**OU-Verschieben**. Beim erneuten Einlesen wird die Gruppe darüber zuverlässig
wiedererkannt; der Name ist reine Anzeige und wird jedes Mal frisch geholt.
(`objectSID` wird zusätzlich gespeichert — als Fallback/Lesbarkeit in Logs.)

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

## Start

```powershell
.\run.ps1
```

`run.ps1` startet `main.ps1` in Windows PowerShell 5.1 (Desktop, `-STA`) — WPF
benötigt die Desktop-Edition. **Ohne Domäne** fällt das Einlesen automatisch auf
**Mock-Daten** zurück, sodass die Oberfläche sofort bedienbar ist
(Beispieldateien unter `samples\`).

Fertige App als Zip: **[neuestes Release](https://github.com/monoeagle/lucent-job-OUPilot/releases/latest)**
(`OUPilot-1.4.0.zip` entpacken, `run.ps1` starten) — oder das Repo klonen.

## Dokumentation

**Online:** <https://monoeagle.github.io/lucent-job-OUPilot/>

Ausführliche Doku als Website (**zensical/Material**, Layout identisch zu den
anderen Lucent-Projekten — Icon-Rail-Navigation, Aktivitäts-Heatmap, Diagramme):

```powershell
.\run-docs.ps1            # baut die Site (OUPilot-docs\) und öffnet sie
.\run-docs.ps1 -Serve     # lokaler Server auf http://127.0.0.1:8047
```

(oder `bash OUPilot-docs\run_OUPilot_docs.sh`). Beim ersten Start wird ein eigenes
`.venv-docs` angelegt und **zensical** installiert (Python 3). Die Diagramme
(AP-Übersicht, Architektur, Roadmap) sind gerenderte SVGs unter
`OUPilot-docs\docs\images\mermaid\` (Quellen in `OUPilot-docs\mermaid-sources\`,
Rendern via `bash OUPilot-docs\tools\render_mermaid.sh`, benötigt Node/`npx`).
`font=false` hält die Site **CDN-frei**; die gebaute `site/` wird als **gh-pages**
veröffentlicht.

## AD-Auslesen (mit Fallback)

Einstellung `AdMode` in `settings.json`:

| Wert     | Verhalten                                                        |
|----------|------------------------------------------------------------------|
| `Auto`   | ActiveDirectory-Modul → ADSI → Mock (erster Erfolg gewinnt)      |
| `Module` | nur RSAT-Modul `ActiveDirectory`                                 |
| `Adsi`   | nur `System.DirectoryServices` (kein RSAT nötig)                 |
| `Mock`   | Testbaum ohne Domäne: Standorte → Unterstandorte → 20–30 Gruppen |

`AdSearchBase` (DN) begrenzt die Baumwurzel; leer = `defaultNamingContext`.
`AdServer` setzt optional einen DC; leer = automatisch.

## AD-Schreiben (Mitglieder hinzufügen)

Beim Import werden die Rechner als Mitglieder in die gewählte Gruppe geschrieben
(`core/ad-writer.psm1`):

- **Pfad 1** `Add-ADGroupMember` (RSAT) → **Pfad 2** ADSI (`member`-Attribut +
  `CommitChanges`) als Fallback. Wurde der Baum aus **Mock** gelesen, wird nur
  **simuliert** (kein echter Schreibvorgang).
- **Auflösung der Rechner:** über den Identifier des Exports (SID > GUID >
  sAMAccountName > Name). Bevorzugt werden **Computer**objekte; `PC-0001` und
  `PC-0001$` lösen auf denselben Rechner auf.
- **Vorab-Dedupe:** bestehende Mitglieder werden gelesen → bereits enthaltene
  Rechner ergeben Status `AlreadyMember` (locale-unabhängig, ohne Fehlertext).
- **Testlauf (WhatIf):** Checkbox „Nur Testlauf" — zeigt pro Rechner, was
  passieren *würde*, ohne ins AD zu schreiben und ohne zu speichern.
- **Bestätigung:** vor echtem Schreiben fragt eine Ja/Nein-Box mit Gruppenname
  und Anzahl.

Status je Rechner (Spalte **AD-Status**, auch im Store gespeichert):
`Added`, `AlreadyMember`, `Removed`, `NotMember`, `NotFound`, `Would` (Testlauf),
`Simuliert` (Mock), `Error`.

### Import-Wege

**1. In gewählte SubOU (Hauptworkflow)** — der Admin wählt im Baum eine
**SubOU (Unterstandort)** und importiert eine **Geräte-JSON**. Pro Rechner stehen
sein Standort und seine Zuweisungen (Software + Typ **Job**/**Policy**) drin; das
Tool sortiert jede Zuweisung in die Gruppe **`<SubOU>-<Software>-<Typ>`** *dieser*
SubOU ein. Alle SubOUs haben denselben Software-Gruppensatz (je Software zwei
Gruppen: `-Policy` und `-Job`).
```json
[
  { "computer": "PC-1001$", "standort": "RBSSt02-Nord",
    "assignments": [ {"software":"Office","type":"Policy"},
                     {"software":"7Zip","type":"Job"} ] }
]
```
- **Standort-Abgleich:** Passt der Standort am Rechner nicht zur gewählten SubOU
  (bzw. deren Standort), wird der Rechner **übersprungen + dokumentiert**
  (`Logs\konflikte-*.csv`). Fehlt die Zielgruppe in der SubOU → Status
  `Gruppe fehlt`.
- Beispiel: `samples\devices-rbsst02-nord.json`. Feldaliasse: Rechner über
  `computer`/`rechner`/`name`/…, Standort über `standort`/`site`/`subou`/…,
  Zuweisungen über `assignments`/`zuweisungen`/…, je Zuweisung `software` + `type`.

**2. In gewählte Gruppe** (Einzelliste) — eine Gruppe im Baum wählen, flache
Rechnerliste importieren:
```json
["PC-0001$", "PC-0002$"]
```

**3. Sammelliste „Rechner→Gruppen"** (voll qualifizierte Namen) — eine Datei
fächert auf viele Gruppen über **exakte Gruppennamen** (kein SubOU-Bezug). Für
Sonderfälle; der Hauptworkflow ist Weg 1.
```json
[
  { "computer": "PC-1010$",
    "groups": ["RBSSt02-Nord-Office-Policy", "RBSSt02-Nord-7Zip-Job"] }
]
```
Unbekannte Gruppennamen werden gesammelt gemeldet (nichts wird halb geschrieben).
Ein Ergebnis-Dialog fasst zusammen: Rechner → Gruppen, Mitgliedschaften, Status.
Beispiel: `samples\assign-sammelliste.json`. Feldaliasse: Rechner über
`computer`/`rechner`/`name`/…, Gruppen über `groups`/`gruppen`/`apps`/….

### Feld-Map (exotische Export-Formate)

Die Parser suchen Werte in einer Liste bekannter Feldnamen (z. B. Rechnername in
`name`/`cn`/`computerName`/…). Bringt ein Export **abweichende** Feldnamen mit,
lassen sie sich **ohne Code-Änderung** ergänzen: eine optionale `fieldmap.json`
im App-Root (Pfad via `FieldMapPath` in `settings.json` überschreibbar). Die
eigenen Namen werden den eingebauten **vorangestellt** (gewinnen bei Konflikt),
case-insensitiv dedupliziert — bestehende Formate bleiben unberührt. Fehlt die
Datei, gelten nur die eingebauten Namen.

Vorlage: **`samples\fieldmap.example.json`** → nach `fieldmap.json` kopieren und
nur die benötigten Schlüssel füllen. Verfügbare Schlüssel: `Name`, `Sid`, `Guid`,
`Dn`, `Sam`, `ObjectType` (Identifier-Auflösung) sowie `AssignGroupFields`,
`AssignCompFields`, `DevStandortFields`, `DevAssignFields`, `SoftwareFields`,
`TypeFields` (Sammelliste / Geräte-Import). Beim Start meldet die Statuszeile,
wie viele eigene Feldnamen aktiv sind.

### Standort-Eindeutigkeit (Konflikte)

Ein Rechner darf nur in Gruppen **eines** Standorts sein (mehrere Gruppen/
Unterstandorte desselben Standorts sind erlaubt). Würde ein Rechner durch den
Import über **mehrere Standorte** streuen — gerechnet aus neuen *und* bereits
gespeicherten Mitgliedschaften — wird er **komplett übersprungen** (Status
`Konflikt`, nichts wird für ihn geschrieben) und in `Logs\konflikte-<ts>.csv`
dokumentiert (Rechner, Standorte, Gruppen), damit du die Clients nacharbeiten
kannst. Beispiel zum Ausprobieren: `samples\assign-konflikt.json`.

### Rechner-Übersicht (Menü „Rechner suchen…")

Zeigt zu einem Rechnernamen alle Gruppen, in denen er laut Store steckt — mit
Standort/Unterstandort, AD-Status und Quelle. Ist er in mehreren Standorten,
erscheint eine Warnung. (Quelle ist der lokale Store; echte AD-`memberOf`-Abfrage
ist als Erweiterung vorgesehen.)

### Mitglieder entfernen

Ist im Baum eine **Gruppe** gewählt, zeigt das Grid ihre gespeicherten
Mitglieder. Eine oder mehrere Zeilen markieren (Mehrfachauswahl) und **Ausgewählte
entfernen…** klicken: die Rechner werden aus der AD-Gruppe genommen
(`Remove-ADGroupMember` → ADSI-Fallback, bei Mock nur simuliert) **und** aus dem
lokalen Store gelöscht. Vor dem echten Schreiben fragt eine Ja/Nein-Box; mit
**Nur Testlauf (WhatIf)** wird nur gemeldet, was passieren *würde*
(Status `Would`), ohne etwas zu ändern. Aus dem Store entfernt wird nur, was
danach tatsächlich kein Mitglied mehr ist (`Removed`/`NotMember`/`Simuliert`);
war der Rechner gar nicht (mehr) drin, erscheint `NotMember`. Der Button ist nur
aktiv, wenn eine Gruppe gewählt und mindestens eine Zeile markiert ist.

### Baum-Filter

Über dem Baum filtert ein Suchfeld die Struktur **live** nach OU- oder
Gruppennamen (Teiltext, Groß-/Kleinschreibung egal). Angezeigt wird ein Knoten,
wenn sein Name passt **oder** ein Nachfahre passt — die Vorfahren bleiben also
sichtbar, damit Treffer erreichbar sind; matcht ein OU-Name selbst, erscheint
sein kompletter Teilbaum. Bei aktivem Filter werden OU-Knoten automatisch
aufgeklappt; die Statuszeile nennt die Trefferzahl. Der **✕**-Button leert das
Feld und stellt den vollen Baum wieder her.

### Info-Dialog

Menü **_Info** öffnet den Über-Dialog (Tabs *Info* mit System-/Projekt-/
Komponenten-Angaben und *Changelog*).

### Darstellung (Theme)

Menü **_Ansicht** schaltet das Erscheinungsbild **live** um (Muster wie im
*CodeSigningCommander*, `ui/theme-loader.psm1`):

- **Farbschema** — 12 Paletten (`Gray`, `Slate`, `Blue`, `Ocean`, `Teal`, `Mint`,
  `Sage`, `Forest`, `Amber`, `Coral`, `Rose`, `Purple`).
- **Stil** — `Sharp` (scharfe Ecken, kompakt) oder `Soft` (3px-Ecken, luftiger).

Das Theme besteht aus zwei ResourceDictionaries, die app-weit gemergt werden:
`ui/themes/palettes/<farbe>.xaml` (nur Farb-Brushes) zuerst, dann
`ui/themes/<stil>.xaml` (Geometrie + Control-Styles, die die Farben per
`DynamicResource` ziehen). Die Wahl wird sofort in `settings.json` gespeichert
(`UiStyle`, `UiPalette`) und beim nächsten Start übernommen. Farbwechsel greifen
sofort; ein Stilwechsel (Geometrie) zieht vollständig erst beim nächsten Start
durch.

## Persistenz

Lokale JSON-Dateien:

- `settings.json` — App-Einstellungen.
- `data\mapping.json` — der eigentliche Zustand: pro Gruppen-**GUID** die Liste
  der importierten Einträge plus zuletzt bekannter Name/DN/SID. Einträge werden
  über ihren stabilen `identifier` (SID > GUID > sAMAccountName > Name)
  dedupliziert.

## Projektstruktur

```
run.ps1                 Launcher (PS 5.1, STA)
main.ps1                Bootstrap: Module laden, Fenster öffnen
core/
  log.psm1              Logging -> Logs\oupilot.log
  settings.psm1         settings.json laden/speichern
  ad-reader.psm1        OU/Gruppen lesen (Modul/ADSI/Mock), GUID als Schlüssel
  ad-writer.psm1        Rechner als Gruppenmitglieder schreiben (Modul/ADSI/Mock)
  mapping-store.psm1    GUID-Mapping-Store (data\mapping.json)
  import-engine.psm1    JSON-Exporte parsen & normalisieren (+ Feld-Map)
  dsm-import.psm1       DSM-Export-Dateien -> Import-Plan (Standort-Import, + Mapping-Loader)
ui/
  main-window.psm1      Hauptfenster: OU-TreeView + Import-Panel
  about-dialog.psm1     Info-/Über-Dialog (Tabs Info + Changelog)
  theme-loader.psm1     Theme-System: Palette + Stil mergen, live umschalten
  themes/
    sharp.xaml          Stil „Sharp" (scharfe Ecken) — Geometrie + Control-Styles
    soft.xaml           Stil „Soft" (3px-Ecken) — Geometrie + Control-Styles
    palettes/*.xaml     12 Farbschemata (nur Brushes)
run-docs.ps1            Doku-Site bauen/öffnen (zensical; Windows-Wrapper)
OUPilot-docs/           Doku-Site (zensical/Material, wie andere Lucent-Projekte)
  zensical.toml         Site-Konfig + Navigation
  build_docs.py         Pipeline: Aktivitäts-JSON + zensical build
  run_OUPilot_docs.sh   venv-Bootstrap + Serve/Build (bash)
  docs/                 Inhalt (index, grundlagen, referenz, betrieb, entwicklung)
  mermaid-sources/      Diagramm-Quellen (.mmd) -> docs/images/mermaid/*.svg
tools/
  Ensure-Utf8Bom.ps1    Quelldateien als UTF-8 mit BOM sichern + Parsecheck
  test-dsm-import.ps1   Testet dsm-import.psm1 gegen samples\RBSSt0*.txt
samples/                Beispiel-Exporte + fieldmap.example.json + dsm-mapping.example.json + RBSSt0*.txt
fieldmap.json           optional (App-Root): eigene Feldnamen; nicht eingecheckt
dsm-mapping.json        optional (App-Root): DSM-Paketname -> AD-App-Name; nicht eingecheckt
```

## Entwicklung ohne Domäne / Test am Testclient

Der Entwicklungs-Client ist bewusst vom AD abgekoppelt. Deshalb:

- **Hier (kein AD):** `Auto`/`Mock` zeigt den Mock-Baum; Importe werden
  **simuliert** (Status `Simuliert`). UI, Parsing, Dedupe und Store sind so voll
  testbar.
- **Am Testclient (mit AD):** Skripte hinüberkopieren, `.\run.ps1`. `Auto` nutzt
  dann automatisch das RSAT-Modul bzw. ADSI. Erst mit `Nur Testlauf` (WhatIf)
  einen Export einlesen → die Spalte **AD-Status** zeigt `Would`/`AlreadyMember`/
  `NotFound`, ohne etwas zu schreiben. Stimmt das Bild, Haken entfernen und echt
  importieren. `Logs\oupilot.log` protokolliert den genutzten Lese-/Schreibpfad.

Schritt-für-Schritt zum Gegentest: **[docs/Testclient-Checkliste.md](docs/Testclient-Checkliste.md)**.

## Stand & nächste Schritte

Erledigt: Baum, Auswahl, JSON-Parsing, **echtes AD-Membership-Schreiben**
(`Add-ADGroupMember` + ADSI-Fallback) mit WhatIf/Bestätigung, Store mit AD-Status,
**Theme-System** (12 Paletten + 2 Stile, live umschaltbar, Menü *Ansicht*),
**Baum-Filter** (Live-Suche nach OU-/Gruppennamen),
**Mitglieder entfernen** (aus AD + Store, mit WhatIf/Bestätigung),
**konfigurierbare Feld-Map** (`fieldmap.json` für exotische Export-Formate).

Noch offen / bewusst später:
- Echtes AD (Modul/ADSI) am Domänen-Testclient gegenprüfen — hier ist bislang
  nur der Mock-Pfad verifiziert (siehe Abschnitt *Entwicklung ohne Domäne*).
```
