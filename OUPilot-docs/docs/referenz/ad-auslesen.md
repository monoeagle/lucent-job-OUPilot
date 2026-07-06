# AD-Auslesen (mit Fallback)

Der Lesepfad wird über die Einstellung `AdMode` in `settings.json` gesteuert:

| Wert     | Verhalten                                                        |
|----------|------------------------------------------------------------------|
| `Auto`   | ActiveDirectory-Modul → ADSI → Mock (erster Erfolg gewinnt)      |
| `Module` | nur RSAT-Modul `ActiveDirectory`                                 |
| `Adsi`   | nur `System.DirectoryServices` (kein RSAT nötig)                 |
| `Mock`   | Testbaum ohne Domäne: Standorte → Unterstandorte → 20–30 Gruppen |

- `AdSearchBase` (DN) begrenzt die Baumwurzel; leer = `defaultNamingContext`.
- `AdServer` setzt optional einen DC; leer = automatisch.

Die Toolbar-Zeile **„Quelle:"** zeigt den tatsächlich genutzten Modus. Steht dort
„Mock-Daten (keine Domäne)", schlug das echte Lesen fehl — der Grund je Pfad steht
in `Logs\oupilot.log`.

## Stabile Identität über objectGUID

Gruppen werden über ihre **`objectGUID`** verschlüsselt (forest-weit eindeutig,
überlebt Umbenennen/Verschieben). `objectSID` wird zusätzlich gespeichert — als
Fallback und für die Lesbarkeit in Logs. Rechner werden beim Schreiben über SID >
GUID > sAMAccountName > Name aufgelöst, bevorzugt als Computerobjekt; `PC-0001` und
`PC-0001$` treffen denselben Rechner.
