#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
# run_OUPilot_docs.sh – OUPilot Dokumentation (zensical)
#
# Eigenes .venv-docs, unabhaengig von anderen venvs. Identisches Muster
# wie in den anderen Lucent-Projekten.
#
# Verwendung:
#   ./run_OUPilot_docs.sh                → Live-Server (Port 8047)
#   ./run_OUPilot_docs.sh --port=8047    → Live-Server auf Port 8047
#   ./run_OUPilot_docs.sh --build        → Statisches HTML nach site/
#   ./run_OUPilot_docs.sh --check        → Nur Struktur pruefen
#   ./run_OUPilot_docs.sh --clean        → .venv-docs loeschen und neu
# ══════════════════════════════════════════════════════════════
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$SCRIPT_DIR/.venv-docs"
PYTHON="python3"
PORT=8047

for arg in "$@"; do
  case "$arg" in
    --port=*)  PORT="${arg#*=}" ;;
    --build)   BUILD=true ;;
    --check)   CHECK=true ;;
    --clean)   CLEAN=true ;;
  esac
done

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo -e "${CYAN}  ▸ $*${NC}"; }
success() { echo -e "${GREEN}  ✓ $*${NC}"; }
error()   { echo -e "${RED}  ✗ $*${NC}"; exit 1; }

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║        OUPilot – Dokumentation           ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""

if [[ "${CLEAN:-}" == "true" ]]; then
  [ -d "$VENV_DIR" ] && rm -rf "$VENV_DIR" && success ".venv-docs geloescht."
fi

command -v "$PYTHON" &>/dev/null || error "python3 nicht gefunden."
PY_VERSION=$("$PYTHON" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
info "Python $PY_VERSION gefunden"

if [ ! -d "$VENV_DIR" ]; then
  info "Erstelle .venv-docs …"
  "$PYTHON" -m venv "$VENV_DIR"
  success ".venv-docs erstellt."
fi

# venv-Python direkt ansprechen (plattformunabhaengig: bin/ oder Scripts/).
VENV_PY="$VENV_DIR/bin/python"
[ -x "$VENV_PY" ] || VENV_PY="$VENV_DIR/Scripts/python.exe"

if ! "$VENV_PY" -m pip show zensical &>/dev/null 2>&1; then
  info "Installiere Zensical …"
  "$VENV_PY" -m pip install --quiet --upgrade pip
  "$VENV_PY" -m pip install --quiet zensical
  success "Zensical installiert."
else
  success "Zensical bereits vorhanden."
fi
info "Zensical: $("$VENV_PY" -m zensical --version 2>/dev/null | head -1)"
echo ""

cd "$SCRIPT_DIR"
if [[ "${CHECK:-}" == "true" ]]; then
  "$VENV_PY" build_docs.py --check
elif [[ "${BUILD:-}" == "true" ]]; then
  info "Baue statische Dokumentation …"
  "$VENV_PY" build_docs.py
  echo -e "   Oeffnen: ${CYAN}file://$SCRIPT_DIR/site/index.html${NC}"
else
  info "Starte Live-Server auf Port $PORT …"
  echo ""
  echo -e "   ${GREEN}http://127.0.0.1:$PORT${NC}  (Ctrl+C zum Beenden)"
  echo ""
  "$VENV_PY" build_docs.py --serve --port "$PORT"
fi
