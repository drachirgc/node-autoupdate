#!/bin/bash
# setup-auto-updater.sh
#
# Script de configuración interactiva del auto-updater.
# Funciona en Linux (systemd) y macOS (launchd / manual).
#
# Uso: bash setup-auto-updater.sh

set -e

# ─── Colores ───────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠ $1${NC}"; }
err()  { echo -e "${RED}✗ $1${NC}"; exit 1; }

echo ""
echo "═══════════════════════════════════════════════════"
echo "       Auto-Updater — Setup interactivo"
echo "═══════════════════════════════════════════════════"
echo ""

# ─── Detectar OS ───────────────────────────────────────────────
OS="linux"
if [[ "$OSTYPE" == "darwin"* ]]; then
  OS="mac"
  warn "Sistema: macOS detectado. Se instalará como proceso de fondo (sin systemd)."
else
  ok "Sistema: Linux detectado."
fi

# ─── Verificar Node.js ─────────────────────────────────────────
if ! command -v node &> /dev/null; then
  err "Node.js no está instalado o no está en el PATH."
fi
NODE_PATH=$(which node)
ok "Node.js encontrado en: $NODE_PATH"

# ─── Preguntar configuración ───────────────────────────────────
echo ""
echo "Responde las siguientes preguntas (Enter para usar el valor por defecto):"
echo ""

read -rp "📁 Ruta ABSOLUTA al repositorio a monitorear: " REPO_PATH
[[ -z "$REPO_PATH" ]] && err "La ruta al repositorio es obligatoria."
[[ ! -d "$REPO_PATH/.git" ]] && err "No es un repositorio git válido: $REPO_PATH"

read -rp "🌿 Rama a monitorear [main]: " BRANCH
BRANCH=${BRANCH:-main}

read -rp "⏱  Intervalo de polling en minutos [30]: " INTERVAL
INTERVAL=${INTERVAL:-30}

read -rp "🔁 Comando para reiniciar tu servicio (ej: systemctl restart mi-app) [dejar vacío para no reiniciar]: " RESTART_CMD

read -rp "📦 ¿Ejecutar npm install cuando cambien dependencias? [s/n, defecto: s]: " NPM
NPM_INSTALL=$( [[ "$NPM" == "n" || "$NPM" == "N" ]] && echo "false" || echo "true" )

read -rp "🔨 ¿Ejecutar make build si hay Makefile? [s/n, defecto: s]: " MAKE
MAKE_BUILD=$( [[ "$MAKE" == "n" || "$MAKE" == "N" ]] && echo "false" || echo "true" )

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/auto-updater.log"

echo ""
echo "─── Resumen de configuración ──────────────────────────"
echo "  Repo:          $REPO_PATH"
echo "  Rama:          $BRANCH"
echo "  Intervalo:     $INTERVAL minutos"
echo "  Restart cmd:   ${RESTART_CMD:-'(ninguno)'}"
echo "  npm install:   $NPM_INSTALL"
echo "  make build:    $MAKE_BUILD"
echo "  Log:           $LOG_FILE"
echo "───────────────────────────────────────────────────────"
echo ""
read -rp "¿Continuar con esta configuración? [s/n]: " CONFIRM
[[ "$CONFIRM" != "s" && "$CONFIRM" != "S" && "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]] && err "Configuración cancelada."

# ─── Generar .env de configuración ────────────────────────────
ENV_FILE="$SCRIPT_DIR/.auto-updater.env"
cat > "$ENV_FILE" << EOF
REPO_PATH=$REPO_PATH
BRANCH=$BRANCH
INTERVAL_MINUTES=$INTERVAL
RESTART_CMD=$RESTART_CMD
RUN_NPM_INSTALL=$NPM_INSTALL
RUN_MAKE_BUILD=$MAKE_BUILD
LOG_FILE=$LOG_FILE
EOF
ok "Configuración guardada en: $ENV_FILE"

# ─── Exportar vars al script ────────────────────────────────────
# Inyectar variables en auto-updater.js via env al arrancar
START_SCRIPT="$SCRIPT_DIR/start-updater.sh"
cat > "$START_SCRIPT" << EOF
#!/bin/bash
# Generado automáticamente por setup-auto-updater.sh
set -a
source "$ENV_FILE"
set +a
exec $NODE_PATH "$SCRIPT_DIR/auto-updater.js"
EOF
chmod +x "$START_SCRIPT"
ok "Script de arranque creado: $START_SCRIPT"

# ─── Instalar según OS ─────────────────────────────────────────
echo ""
if [[ "$OS" == "linux" ]]; then

  if ! command -v systemctl &> /dev/null; then
    warn "systemd no encontrado. Ejecutá manualmente: bash $START_SCRIPT"
    exit 0
  fi

  SERVICE_NAME="auto-updater"
  SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"
  CURRENT_USER=$(whoami)

  sudo tee "$SERVICE_FILE" > /dev/null << EOF
[Unit]
Description=Auto-Updater Node.js — $REPO_PATH
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$CURRENT_USER
WorkingDirectory=$SCRIPT_DIR
EnvironmentFile=$ENV_FILE
ExecStart=$NODE_PATH $SCRIPT_DIR/auto-updater.js
Restart=on-failure
RestartSec=30s
ExecStartPre=/bin/sleep 5

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable "$SERVICE_NAME"
  sudo systemctl start "$SERVICE_NAME"

  ok "Servicio systemd instalado y arrancado."
  echo ""
  echo "  Comandos útiles:"
  echo "    sudo systemctl status $SERVICE_NAME"
  echo "    sudo journalctl -u $SERVICE_NAME -f"
  echo "    sudo systemctl stop $SERVICE_NAME"
  echo "    sudo systemctl restart $SERVICE_NAME"

elif [[ "$OS" == "mac" ]]; then

  PLIST_NAME="com.auto-updater"
  PLIST_FILE="$HOME/Library/LaunchAgents/$PLIST_NAME.plist"

  cat > "$PLIST_FILE" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$PLIST_NAME</string>
  <key>ProgramArguments</key>
  <array>
    <string>$START_SCRIPT</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$LOG_FILE</string>
  <key>StandardErrorPath</key>
  <string>$LOG_FILE</string>
</dict>
</plist>
EOF

  launchctl load "$PLIST_FILE"
  ok "LaunchAgent instalado y arrancado (macOS)."
  echo ""
  echo "  Comandos útiles:"
  echo "    launchctl list | grep auto-updater"
  echo "    launchctl unload $PLIST_FILE      # detener"
  echo "    launchctl load $PLIST_FILE        # arrancar"
  echo "    tail -f $LOG_FILE                 # ver logs"
fi

echo ""
ok "¡Setup completado! El auto-updater ya está corriendo."
echo ""
