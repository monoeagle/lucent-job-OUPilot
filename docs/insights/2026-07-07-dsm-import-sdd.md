# Insight 2026-07-07 — DSM-Export-Import per Subagent-Driven Development

Session 3: kompletter Feature-Zyklus (Brainstorm → Spec → Plan → 7 SDD-Tasks →
Final-Review) für den DSM-Export-Import, plus Mock-Verallgemeinerung auf das
RBSSt-Schema. Destillierte, nicht-offensichtliche Erkenntnisse:

## 1. pwsh 7.4.6/.NET 8.0.10: `@(<generische List>)` wirft „Argument types do not match"

Auf der Linux-Dev-Box (pwsh 7.4.6) scheitert `@()` um eine
`System.Collections.Generic.List[object]` mit **„Argument types do not match"**
— eine Upstream-Regression, kein Code-Fehler. **Workaround:** `ArrayList`
(bietet ebenfalls `.ToArray()`, auf PS 5.1 identisch nutzbar; `[void]` beim
`.Add()` nötig). Konsequenz für alle PS-Projekte auf dieser Maschine: generische
Lists nie roh durch `@()` schicken — vorher `.ToArray()` oder ArrayList nehmen.
Wichtig war: die **Behauptung des Subagenten empirisch nachprüfen** (Minimal-Repro
im Terminal), statt sie zu glauben oder abzutun — sie stimmte.

## 2. Verbatim-Code-Pläne + billige Modelle: Abweichungen treffen genau die Integrationsverträge

Haiku-Implementierer transkribieren Brief-Code zuverlässig — wenn sie abweichen,
dann „gut gemeint" an Schnittstellen (hier: Buckets-`entries` in Arrays
konvertiert → hätte das `.ToArray()` des nächsten Tasks gebrochen). **Was es
gefangen hat:** der Task-Reviewer bekam den Integrationsvertrag („entries muss
`.ToArray()` können, Task 6 ruft das auf") explizit als Constraint in den
Prompt. Verträge zwischen Tasks gehören wörtlich in Implementierer- UND
Reviewer-Dispatches, nicht nur in den Plan.

## 3. Plan-interne Widersprüche zeigen sich erst auf der „falschen" Plattform

Der Plan enthielt `Join-Path $AppRoot 'dsm-mapping.json'` UND einen Test, der
`C:\App\dsm-mapping.json` (Backslash) asserted — unter Windows konsistent, unter
pwsh/Linux unvereinbar (`Join-Path` liefert dort `/`). Lehre: Wenn der
Test-Harness eines Windows-Tools auch auf Linux laufen soll, sind
**Pfadkonstruktionen explizite Design-Entscheidungen** (fester `\` für
Windows-Semantik), keine Selbstverständlichkeiten.

## 4. Invertierte Datenrichtung ⇒ eigenes Modul statt Workflow-Verbiegen

Der DSM-Export ist gruppen-zentriert (Datei = Gruppe + Mitglieder + Policies),
alle Alt-Importe sind rechner-zentriert. Der Versuch, das durchs bestehende
Geräteformat zu quetschen (Ansatz C), wäre an drei Stellen (Ebene, Endungen,
Report-Arten) gescheitert. Die Kopplung „streng spezifiziertes Schema =
eigener Parser, tolerantes Feld-Raten = import-engine" hat sich als saubere
Modulgrenze bewährt.

## 5. Mock muss die Ziel-Topologie können, sonst ist das Feature offline nicht führbar

Der Alt-Mock (Standort → Unterstandort → Gruppen) konnte die DSM-Welt
(Standort=RBSSt → App-Sub-OUs) nicht abbilden — ohne Mock-Erweiterung wäre der
komplette Workflow auf dem AD-losen Dev-Client unsichtbar geblieben. Bewusste
Details: `RBSSt01-VLC-Policy` fehlt absichtlich (reproduzierbarer
„Gruppe fehlt"-Report), und nach der RBSSt-Verallgemeinerung existiert `RBSSt02`
als Mock-Standort, wodurch die „Fremd-RBSSt"-Fixture natürlich koexistiert.
