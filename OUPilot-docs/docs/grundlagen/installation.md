# Installation

## Voraussetzungen

- **Windows PowerShell 5.1** (Desktop-Edition) — WPF benötigt die Desktop-Edition;
  `pwsh` (Core) wird bewusst nicht genutzt.
- Für echtes AD: **RSAT / ActiveDirectory-Modul** *oder* ADSI (kein RSAT nötig).
  Ohne Domäne läuft alles im **Mock**-Modus.

## Bezugswege

**Release-Zip:** das [neueste Release](https://github.com/monoeagle/lucent-job-OUPilot/releases/latest)
herunterladen, `OUPilot-1.4.0.zip` entpacken.

**Repo klonen:**

```powershell
git clone https://github.com/monoeagle/lucent-job-OUPilot.git
```

## Starten

```powershell
.\run.ps1
```

`run.ps1` startet `main.ps1` in Windows PowerShell 5.1 (Desktop, `-STA`).

## Hinweis zu den Quelldateien

Alle `.ps1`/`.psm1` sind **UTF-8 mit BOM** — Pflicht für PS 5.1 (ohne BOM würden
Umlaute als ANSI fehlinterpretiert). Nach Änderungen sichert
`tools\Ensure-Utf8Bom.ps1` die Kodierung und prüft die Syntax.
