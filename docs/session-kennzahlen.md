# Session-Kennzahlen — OUPilot

Eine Zeile je Session (Schema: `.pattern/session-handoff-kpi.pattern`, angepasst:
PowerShell-Projekt — „Tests" = Assertions des pwsh-Harness `tools\test-dsm-import.ps1`,
kein Analyzer/APK; LOC-Code = `core`/`ui`/`tools`/`main.ps1`/`samples`, LOC-Docs = `*.md`).
Sessions 1–2 rückwirkend ergänzt, soweit rekonstruierbar (Tokens damals nicht erhoben).

| # | Datum | Modell (Hauptschleife) | Tokens gesamt | Tokens je Modell (Subagenten) | Commits | Tests (von→bis) | Version (von→bis) | Subagent-Dispatches | Features/APs | Windows-verifiziert | LOC Code (netto) | LOC Docs (netto) | Dateien | feat / fix+chore | Review-Bugs | Escape-Bugs | Notiz |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 2026-07-05/06 | n. e. | n. e. | n. e. | 10 | – | 0 → 1.4.0 | n. e. | App komplett (AD-Kern, Baum, 3 Import-Wege, Store, Theme) | nein (nur Mock) | n. e. | n. e. | n. e. | n. e. | n. e. | n. e. | Projektstart, rückwirkend erfasst |
| 2 | 2026-07-06 | n. e. | n. e. | n. e. | 8 | – | 1.4.0 | n. e. | Doku-Site → zensical/gh-pages, History-Bereinigung | nein | n. e. | n. e. | n. e. | n. e. | n. e. | n. e. | rückwirkend erfasst (inkl. 2 Nach-Handoff-Commits, 1 davon GitHub-Web) |
| 3 | 2026-07-07 | Fable 5 | n. e. (Hauptschleife nicht erhoben) + ≈1.118k Subagenten | Haiku ≈338k · Sonnet ≈636k · Fable ≈144k | 14 (inkl. Handoff) | 0 → 61 Assertions | 1.4.0 (Feature in Unreleased) | 17 (+2 Fix-Resumes) | DSM-Export-Import komplett (Spec+Plan+7 Tasks), Mock→RBSSt-Schema | nein — Windows-Durchstich offen | +954/−23 (17 Dateien) | +1647/−8 | 28 | 6 / 1 | 3 (Buckets-Array-Bruch, .gitignore, Doku-Key) | n. a. (kein Gerätetest) | pwsh-7.4.6-Regression `@(List)` → ArrayList; SDD mit Verbatim-Plänen |

## Ableitbare KPIs (Stand Session 3)

- **Tokens/Commit (nur Subagenten, S3):** ≈1.118k / 13 Feature-Commits ≈ **86k**
- **Assertions je 100k Subagent-Tokens (S3):** 61 / 11,2 ≈ **5,5**
- **Modell-Mix (S3):** ≈30 % Haiku / 57 % Sonnet / 13 % Fable der Subagent-Tokens —
  Implementierung lief fast vollständig auf den günstigen Tiers
- **Fang-Quote:** 3 Review-Bugs / (3 + n. a.) — Escape-Messung erst nach Windows-Durchstich möglich
