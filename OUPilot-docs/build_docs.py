#!/usr/bin/env python3
"""
build_docs.py — OUPilot Doku-Pipeline (identisch zu anderen Lucent-Projekten).

    zensical build  →  statische Site nach site/

Nutzung:
    python build_docs.py                  # voller Build
    python build_docs.py --serve          # build + lokaler HTTP-Server
    python build_docs.py --serve --port 8047
    python build_docs.py --check          # nur Doku-Struktur pruefen
    python build_docs.py --ci             # strikt (Exit-Code bei Warnungen)
"""
from __future__ import annotations
import argparse
import http.server
import shutil
import socketserver
import subprocess
import sys
from pathlib import Path

# Windows-Konsole (cp1252) auf UTF-8 stellen, sonst scheitern ▸/✓-Glyphs.
for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8")
    except Exception:
        pass

BASE_DIR    = Path(__file__).resolve().parent
DOCS_DIR    = BASE_DIR / "docs"
SITE_DIR    = BASE_DIR / "site"
CONFIG_FILE = BASE_DIR / "zensical.toml"

GREEN = "\033[0;32m"; CYAN = "\033[0;36m"; YELLOW = "\033[1;33m"; RED = "\033[0;31m"; RESET = "\033[0m"


def step(m: str) -> None: print(f"\n{CYAN}▸ {m}{RESET}")
def ok(m: str)   -> None: print(f"{GREEN}  ✓ {m}{RESET}")
def warn(m: str) -> None: print(f"{YELLOW}  ⚠ {m}{RESET}")
def fail(m: str) -> None: print(f"{RED}  ✗ {m}{RESET}")


def check_zensical() -> None:
    try:
        subprocess.run([sys.executable, "-m", "zensical", "--version"],
                       capture_output=True, check=True)
    except (subprocess.CalledProcessError, FileNotFoundError):
        fail("Zensical nicht im aktiven Python-Env gefunden.")
        print(f"  Installieren mit: {sys.executable} -m pip install zensical")
        sys.exit(1)


def check_structure(strict: bool = False) -> int:
    step("Doku-Struktur pruefen")
    errors = 0
    for req in [CONFIG_FILE, DOCS_DIR, DOCS_DIR / "index.md",
                DOCS_DIR / "stylesheets" / "extra.css"]:
        if not req.exists():
            fail(f"fehlt: {req.relative_to(BASE_DIR)}"); errors += 1
    md = list(DOCS_DIR.rglob("*.md")) if DOCS_DIR.exists() else []
    ok(f"{len(md)} Markdown-Dateien")
    if errors:
        fail(f"{errors} Probleme")
        if strict: sys.exit(1)
        return errors
    ok("Struktur OK")
    return 0


def step_generate_activity() -> None:
    script = BASE_DIR / "tools" / "generate_project_activity.py"
    if not script.is_file():
        warn("generate_project_activity.py fehlt — uebersprungen")
        return
    step("Aktivitaets-JSON aus git log generieren")
    r = subprocess.run([sys.executable, str(script)], cwd=BASE_DIR)
    if r.returncode == 0:
        ok("project-activity.json aktualisiert")
    else:
        warn(f"generate_project_activity.py exit {r.returncode} (nicht-fatal)")


def zensical_build() -> None:
    step("Zensical-Build (site/)")
    if SITE_DIR.exists():
        shutil.rmtree(SITE_DIR)
    print(f"  $ {sys.executable} -m zensical build")
    r = subprocess.run([sys.executable, "-m", "zensical", "build"], cwd=BASE_DIR)
    if r.returncode != 0 or not (SITE_DIR / "index.html").is_file():
        fail("site/index.html nicht erzeugt"); sys.exit(1)
    ok(f"site/ unter {SITE_DIR}")


def serve(port: int) -> None:
    if not SITE_DIR.is_dir():
        fail("site/ fehlt — vorher Build laufen lassen"); sys.exit(1)
    step(f"HTTP-Server auf Port {port}")
    print(f"  {GREEN}http://127.0.0.1:{port}{RESET}  (Ctrl+C zum Beenden)")
    handler = lambda *a, **k: http.server.SimpleHTTPRequestHandler(*a, directory=str(SITE_DIR), **k)
    try:
        with socketserver.TCPServer(("127.0.0.1", port), handler) as httpd:
            httpd.serve_forever()
    except KeyboardInterrupt:
        print(); ok("Server beendet")


def main() -> None:
    p = argparse.ArgumentParser(description="OUPilot Docs — zensical build/serve",
                                formatter_class=argparse.RawDescriptionHelpFormatter, epilog=__doc__)
    p.add_argument("--serve", action="store_true", help="Nach Build HTTP-Server starten")
    p.add_argument("--port", type=int, default=8047, help="Port fuer --serve (Default: 8047)")
    p.add_argument("--check", action="store_true", help="Nur Struktur pruefen")
    p.add_argument("--ci", action="store_true", help="Strict-Mode")
    args = p.parse_args()

    check_zensical()
    check_structure(strict=args.ci)
    if args.check:
        return
    step_generate_activity()
    zensical_build()
    if args.serve:
        serve(args.port); return
    print(); ok(f"Build fertig — site/ unter {SITE_DIR}")
    print(f"  Browser-Test: {CYAN}python build_docs.py --serve{RESET}")


if __name__ == "__main__":
    main()
