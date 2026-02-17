# 🔄 auto-updater

Servicio independiente que monitorea un repositorio git remoto y aplica actualizaciones automáticamente: hace `git pull`, instala dependencias y reinicia el servicio sin intervención manual.

Está pensado para usarse **fuera** del repositorio que querés monitorear, como un proceso de infraestructura propio de cada máquina.

---

## ¿Qué hace exactamente?

1. Cada X minutos ejecuta `git fetch` para consultar si hay commits nuevos en el remoto
2. Si detecta cambios, hace `git pull origin <rama>`
3. Si `package.json` o el lockfile cambiaron, ejecuta `npm install`
4. Si existe un `Makefile`, ejecuta `make build`
5. Reinicia el servicio con el comando que vos configures (`systemctl`, `pm2`, etc.)
6. Registra todo en un archivo de log con timestamps

Si no hay cambios, no hace nada y espera al siguiente intervalo. Si hay cambios locales en el repo, hace `git stash` antes de aplicar el pull para evitar conflictos.

---

## Archivos incluidos

| Archivo | Descripción |
|---|---|
| `auto-updater.js` | Script principal. Es el único que corre |
| `setup-auto-updater.sh` | Instalador interactivo (recomendado para empezar) |
| `auto-updater.service` | Archivo de unidad para systemd (Linux) — referencia manual |

---

## Instalación

### Opción A — Setup interactivo (recomendado)

Funciona en **Linux** y **macOS**. El script te hace las preguntas y configura todo solo.

```bash
# 1. Clonar este repo en una carpeta fuera del repo que querés monitorear
git clone https://github.com/tu-usuario/auto-updater.git ~/auto-updater
cd ~/auto-updater

# 2. Dar permisos de ejecución
chmod +x setup-auto-updater.sh

# 3. Correr el setup
bash setup-auto-updater.sh
```

El script te va a preguntar:
- Ruta absoluta al repositorio a monitorear
- Rama (`main`, `master`, etc.)
- Intervalo en minutos
- Comando para reiniciar tu servicio
- Si querés que corra `npm install` y `make build`

Al terminar, el auto-updater queda corriendo como:
- **Linux**: servicio systemd (`auto-updater.service`)
- **macOS**: LaunchAgent (`~/Library/LaunchAgents/com.auto-updater.plist`)

---

### Opción B — Configuración manual

Si preferís no usar el script de setup, podés configurar todo editando directamente `auto-updater.js`.

#### 1. Editar la sección CONFIG

Abrí `auto-updater.js` y modificá el bloque `CONFIG` al principio del archivo:

```js
const CONFIG = {
  repoPath:        "/ruta/absoluta/al/repositorio",  // ← OBLIGATORIO
  branch:          "main",                            // rama a monitorear
  intervalMinutes: 30,                               // cada cuántos minutos checar
  restartCmd:      "systemctl restart mi-servicio",  // comando para reiniciar
  runNpmInstall:   true,                             // ejecutar npm install si cambian deps
  runMakeBuild:    true,                             // ejecutar make build si hay Makefile
  logFile:         "./auto-updater.log",             // ruta del log (null = solo consola)
};
```

#### 2. Correrlo manualmente

```bash
node auto-updater.js
```

Para dejarlo corriendo en segundo plano sin systemd:

```bash
nohup node auto-updater.js &
```

#### 3. Instalarlo como servicio systemd (Linux)

```bash
# Editar el archivo de servicio
nano auto-updater.service

# Instalar
sudo cp auto-updater.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable auto-updater
sudo systemctl start auto-updater
```

---

## Variables de entorno

Podés configurar el updater sin editar el código fuente usando variables de entorno. Tienen prioridad sobre los valores en `CONFIG`.

| Variable | Descripción | Ejemplo |
|---|---|---|
| `REPO_PATH` | Ruta al repositorio | `/home/user/mi-app` |
| `BRANCH` | Rama a monitorear | `main` |
| `INTERVAL_MINUTES` | Intervalo de polling | `60` |
| `RESTART_CMD` | Comando de reinicio | `systemctl restart mi-app` |
| `RUN_NPM_INSTALL` | Ejecutar npm install | `true` / `false` |
| `RUN_MAKE_BUILD` | Ejecutar make build | `true` / `false` |
| `LOG_FILE` | Ruta del archivo de log | `/var/log/auto-updater.log` |

Ejemplo de uso directo:

```bash
REPO_PATH=/home/user/mi-app BRANCH=main INTERVAL_MINUTES=15 node auto-updater.js
```

---

## Comandos útiles

### Linux (systemd)

```bash
# Ver estado
sudo systemctl status auto-updater

# Ver logs en vivo
sudo journalctl -u auto-updater -f

# Detener
sudo systemctl stop auto-updater

# Reiniciar
sudo systemctl restart auto-updater

# Desinstalar
sudo systemctl disable --now auto-updater
sudo rm /etc/systemd/system/auto-updater.service
sudo systemctl daemon-reload
```

### macOS (LaunchAgent)

```bash
# Ver si está corriendo
launchctl list | grep auto-updater

# Ver logs en vivo
tail -f ~/auto-updater/auto-updater.log

# Detener
launchctl unload ~/Library/LaunchAgents/com.auto-updater.plist

# Arrancar
launchctl load ~/Library/LaunchAgents/com.auto-updater.plist

# Desinstalar
launchctl unload ~/Library/LaunchAgents/com.auto-updater.plist
rm ~/Library/LaunchAgents/com.auto-updater.plist
```

---

## Ejemplos de `restartCmd` según tu setup

| Setup | Comando |
|---|---|
| systemd | `systemctl restart nombre-servicio` |
| PM2 (por nombre) | `pm2 restart nombre-app` |
| PM2 (por ID) | `pm2 restart 0` |
| Script custom | `/home/user/scripts/restart-app.sh` |
| Sin reinicio automático | dejar en `null` o vacío |

> **Nota para systemd:** Si el auto-updater corre como usuario sin privilegios de sudo, necesitás que el usuario pueda ejecutar el comando de restart sin contraseña. Configuralo en `/etc/sudoers` con:
> ```
> tu-usuario ALL=(ALL) NOPASSWD: /bin/systemctl restart nombre-servicio
> ```

---

## Estructura de archivos después del setup

```
~/auto-updater/
├── auto-updater.js          # Script principal
├── setup-auto-updater.sh    # Setup interactivo
├── auto-updater.service     # Referencia para systemd
├── .auto-updater.env        # Configuración generada (no subir a git)
├── start-updater.sh         # Script de arranque generado
└── auto-updater.log         # Log de ejecución (generado automáticamente)
```

> `.auto-updater.env` y `auto-updater.log` están en `.gitignore` porque contienen rutas y datos específicos de cada máquina.

---

## Requisitos

- Node.js 14 o superior
- Git instalado y configurado con acceso al repositorio remoto (SSH o credenciales cacheadas)
- El usuario que ejecuta el script debe tener permisos de lectura/escritura sobre el repositorio

---

## Licencia

MIT
