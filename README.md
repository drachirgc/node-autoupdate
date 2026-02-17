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
| `setup-auto-updater.sh` | Instalador interactivo del auto-updater (recomendado para empezar) |
| `first-run.sh` | Instalación inicial del repo monitoreado (npm install + build) |
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

---

## Primera instalación en una máquina nueva

Antes de arrancar el auto-updater por primera vez, el repositorio monitoreado necesita tener sus dependencias instaladas y el build generado. De lo contrario el servicio va a fallar al arrancar.

Usá el script `first-run.sh` para hacer todo esto de una sola vez:

```bash
# Uso básico (solo instala deps y hace build)
bash first-run.sh /ruta/al/repositorio

# Con nombre de servicio (también arranca el servicio al terminar)
bash first-run.sh /ruta/al/repositorio 3speakencoder.service
```

El script hace en orden: `npm install` → `npm run build` (si existe el script) → arranca el servicio systemd si se especificó.

> **Nota:** El auto-updater también detecta automáticamente si falta el build al arrancar y lo genera solo. Pero usar `first-run.sh` es más explícito y permite ver el output completo del build antes de arrancar el servicio.

## Variables de entorno

Podés configurar el updater sin editar el código fuente usando variables de entorno. Tienen prioridad sobre los valores en `CONFIG`.

| Variable | Descripción | Ejemplo |
|---|---|---|
| `REPO_PATH` | Ruta al repositorio | `/home/user/mi-app` |
| `BRANCH` | Rama a monitorear | `main` |
| `INTERVAL_MINUTES` | Intervalo de polling | `60` |
| `RESTART_CMD` | Comando de reinicio | `systemctl restart mi-app` |
| `RUN_NPM_INSTALL` | Ejecutar npm install | `true` / `false` |
| `RUN_NPM_BUILD` | Ejecutar npm run build (TypeScript/build script) | `true` / `false` |
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

## Troubleshooting

Problemas reales encontrados durante la instalación y cómo resolverlos.

---

### ❌ `Interactive authentication required` al reiniciar el servicio

**Error en los logs:**
```
Failed to restart mi-servicio.service: Interactive authentication required.
```

**Causa:** El auto-updater corre como servicio de sistema y no tiene permisos para ejecutar `systemctl restart` sin contraseña.

**Solución:** Darle permiso al usuario para reiniciar ese servicio específico sin sudo:

```bash
sudo visudo
```

Agregá esta línea al final del archivo (reemplazá los valores):
```
tu-usuario ALL=(ALL) NOPASSWD: /bin/systemctl restart nombre-de-tu-servicio.service
```

Luego editá el `.auto-updater.env` para agregar `sudo` al comando:

```bash
nano ~/auto-updater/.auto-updater.env
```

Cambiá la línea `RESTART_CMD`:
```
RESTART_CMD=sudo systemctl restart nombre-de-tu-servicio.service
```

Reiniciá el auto-updater para que tome los cambios:
```bash
sudo systemctl restart auto-updater
sudo journalctl -u auto-updater -f
```

---

### ❌ `src refspec main does not match any` al hacer git push

**Error:**
```
error: src refspec main does not match any
error: failed to push some refs to '...'
```

**Causa:** Git inicializó el repo con la rama `master` en lugar de `main`, o no se hizo el commit inicial antes del push.

**Solución:**
```bash
# Verificar el estado
git status

# Si hay archivos sin commitear
git add .
git commit -m "Initial commit"

# Renombrar la rama
git branch -M main

# Push
git push -u origin main
```

---

### ❌ `Repository not found` al hacer git push

**Error:**
```
remote: Repository not found.
fatal: repository 'https://github.com/...' not found
```

**Causa:** La URL del remote apunta a un repositorio que no existe, o se usó la URL de ejemplo sin reemplazarla.

**Solución:** Actualizá la URL con la de tu repo real:

```bash
git remote set-url origin https://github.com/tu-usuario/tu-repo-real.git
git push -u origin main
```

Podés verificar la URL configurada con:
```bash
git remote -v
```

---

### ❓ ¿Cuál es la ruta absoluta del repositorio a monitorear?

El setup pide una **ruta local en el disco**, no una URL de GitHub. Es la carpeta donde está clonado el repo en tu máquina.

Para encontrarla:
```bash
# Buscar todos los repos git en el sistema
find / -name ".git" -type d 2>/dev/null

# O buscar en las carpetas más comunes
ls /home/
ls /var/www/
ls /opt/
```

---

### ❓ ¿Cuál es la rama correcta?

Entrá a la carpeta del repo que querés monitorear y ejecutá:

```bash
cd /ruta/del/repo
git branch
```

La rama activa aparece marcada con `*`. Normalmente es `main` o `master`.

---

### ❓ Los archivos `.sh` fallan en Linux/macOS después de editarlos en Windows

**Causa:** Windows guarda los archivos con saltos de línea CRLF (`\r\n`) en lugar de LF (`\n`), lo que rompe los scripts bash en Unix.

**Solución:** Creá un archivo `.gitattributes` en la raíz del repo con este contenido:

```
*.sh text eol=lf
*.service text eol=lf
*.js text eol=lf
*.md text eol=lf
.gitignore text eol=lf
```

Esto le indica a Git que siempre guarde esos archivos con LF sin importar desde qué sistema operativo se suban.

Si el archivo ya fue subido con CRLF, corregilo así (en Linux/macOS):
```bash
sed -i 's/\r//' setup-auto-updater.sh
```

---

### ❓ El auto-updater detectó cambios en el primer arranque sin haber hecho push

**Comportamiento:** Al instalar, el auto-updater aplicó un pull y reinició el servicio aunque no se haya hecho ningún push nuevo.

**Causa:** Es normal. El repo local estaba desactualizado respecto al remoto (había commits en GitHub que aún no se habían bajado). El auto-updater simplemente sincronizó el estado.

---

## Licencia

MIT

---

### ❌ El servicio falla con "Worker file not found" o similar al arrancar

**Error en los logs:**
```
Worker file not found at /path/dist/workers/....js. Run "npm run build" first.
```

**Causa:** El repositorio fue clonado pero nunca se generó el build. La carpeta `dist/` no existe.

**Solución rápida:**
```bash
sudo systemctl stop nombre-servicio.service
cd /ruta/al/repositorio
npm install
npm run build
sudo systemctl start nombre-servicio.service
```

**Solución permanente:** Usá `first-run.sh` en futuras instalaciones:
```bash
bash first-run.sh /ruta/al/repositorio nombre-servicio.service
```

---

### ❌ El sudoers en Ubuntu 24 necesita `/usr/bin/systemctl` en vez de `/bin/systemctl`

**Error en los logs:**
```
sudo: a terminal is required to read the password
```

A pesar de tener la línea en sudoers, sigue pidiendo contraseña porque en Ubuntu 24 `systemctl` está en `/usr/bin/systemctl` y no en `/bin/systemctl`.

**Solución:** Verificar la ruta correcta y corregir sudoers:
```bash
# Verificar dónde está systemctl en tu sistema
which systemctl
```

La línea en sudoers debe usar la ruta que devolvió ese comando:
```
# Ubuntu 22 y anteriores
tu-usuario ALL=(ALL) NOPASSWD: /bin/systemctl restart nombre-servicio.service

# Ubuntu 24+
tu-usuario ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart nombre-servicio.service
```


---

### ❓ No sé el nombre exacto del servicio en mi máquina

El nombre del servicio puede variar entre máquinas aunque sea el mismo software (por ejemplo `3speakencoder.service` en una y `3speak-encoder.service` en otra).

Para encontrar el nombre correcto:

```bash
sudo systemctl list-units --type=service --state=running | grep -iE "speak|encoder|ipfs|node"
```

Usá el nombre exacto que aparece en la primera columna para el `RESTART_CMD` y para el sudoers.
