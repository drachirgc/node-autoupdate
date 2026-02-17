#!/bin/bash
# first-run.sh
#
# Script de primera instalación para el repositorio monitoreado.
# Ejecutar UNA SOLA VEZ en cada máquina nueva antes de arrancar los servicios.
#
# Hace:
#   1. npm install
#   2. npm run build (si existe script "build" en package.json)
#   3. Arranca el servicio systemd (si se proporciona el nombre)
#
# Uso:
#   bash first-run.sh /ruta/al/repo
#   bash first-run.sh /ruta/al/repo 3speakencoder.service

set -e

# ─── Colores ───────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠ $1${NC}"; }
err()  { echo -e "${RED}✗ $1${NC}"; exit 1; }

echo ""
echo "═══════════════════════════════════════════════════"
echo "       First Run — Instalación inicial"
echo "═══════════════════════════════════════════════════"
echo ""

# ─── Argumentos ────────────────────────────────────────────────
REPO_PATH="${1:-}"
SERVICE_NAME="${2:-}"

# Si no se pasó la ruta, preguntar
if [[ -z "$REPO_PATH" ]]; then
  read -rp "📁 Ruta absoluta al repositorio: " REPO_PATH
fi

[[ -z "$REPO_PATH" ]] && err "La ruta al repositorio es obligatoria."
[[ ! -d "$REPO_PATH" ]] && err "El directorio no existe: $REPO_PATH"
[[ ! -d "$REPO_PATH/.git" ]] && err "No es un repositorio git válido: $REPO_PATH"
[[ ! -f "$REPO_PATH/package.json" ]] && err "No se encontró package.json en: $REPO_PATH"

ok "Repositorio encontrado: $REPO_PATH"

# ─── Verificar Node.js y npm ───────────────────────────────────
command -v node &>/dev/null || err "Node.js no está instalado."
command -v npm &>/dev/null || err "npm no está instalado."
ok "Node.js $(node --version) / npm $(npm --version)"

# ─── npm install ───────────────────────────────────────────────
echo ""
echo "📦 Ejecutando npm install..."
cd "$REPO_PATH"
npm install
ok "npm install completado."

# ─── npm run build (si existe) ────────────────────────────────
HAS_BUILD=$(node -e "
  try {
    const p = require('./package.json');
    console.log(p.scripts && p.scripts.build ? 'yes' : 'no');
  } catch(e) { console.log('no'); }
")

if [[ "$HAS_BUILD" == "yes" ]]; then
  echo ""
  echo "🔨 Script 'build' encontrado → ejecutando npm run build..."
  npm run build
  ok "npm run build completado."

  # Verificar que el build generó archivos
  if [[ -d "$REPO_PATH/dist" ]]; then
    DIST_FILES=$(find "$REPO_PATH/dist" -type f | wc -l)
    ok "Carpeta dist/ generada con $DIST_FILES archivos."
  else
    warn "No se encontró carpeta dist/ después del build. Verificá el output del build."
  fi
else
  warn "No se encontró script 'build' en package.json. Saltando npm run build."
fi

# ─── Arrancar servicio systemd (si se proporcionó) ────────────
if [[ -n "$SERVICE_NAME" ]]; then
  echo ""
  if systemctl list-unit-files | grep -q "^$SERVICE_NAME"; then
    echo "🔁 Arrancando servicio: $SERVICE_NAME"
    sudo systemctl start "$SERVICE_NAME"
    sleep 3
    if systemctl is-active --quiet "$SERVICE_NAME"; then
      ok "Servicio $SERVICE_NAME arrancado correctamente."
    else
      warn "El servicio arrancó pero puede tener problemas. Verificá con:"
      echo "    sudo journalctl -u $SERVICE_NAME -n 30 --no-pager"
    fi
  else
    warn "Servicio '$SERVICE_NAME' no encontrado en systemd. Arrancalo manualmente cuando estés listo."
  fi
else
  echo ""
  warn "No se especificó nombre de servicio. Arrancá el servicio manualmente cuando estés listo."
  echo "  Ejemplo: sudo systemctl start nombre-servicio.service"
fi

echo ""
ok "¡First run completado! El repositorio está listo para funcionar."
echo ""
echo "  Próximos pasos:"
echo "    • Verificar estado:  sudo systemctl status $SERVICE_NAME"
echo "    • Ver logs en vivo:  sudo journalctl -u $SERVICE_NAME -f"
echo "    • El auto-updater se encargará de mantenerlo actualizado automáticamente."
echo ""
