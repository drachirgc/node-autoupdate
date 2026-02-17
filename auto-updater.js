#!/usr/bin/env node

/**
 * auto-updater.js
 *
 * Monitorea un repositorio git y aplica actualizaciones automáticamente.
 * Funciona con systemd, PM2, o ejecución manual (npm start).
 *
 * Uso:
 *   node auto-updater.js
 *   node auto-updater.js --interval 60 --branch main --restart-cmd "systemctl restart mi-servicio"
 */

const { execSync } = require("child_process");
const fs = require("fs");
const path = require("path");

// ─────────────────────────────────────────────────────────────
// CONFIGURACIÓN — Editar según tu entorno
// ─────────────────────────────────────────────────────────────
const CONFIG = {
  // Ruta absoluta al repositorio que querés monitorear
  repoPath: process.env.REPO_PATH || "/ruta/a/tu/repositorio",

  // Rama a monitorear
  branch: process.env.BRANCH || "main",

  // Intervalo de polling en minutos
  intervalMinutes: parseInt(process.env.INTERVAL_MINUTES || "30"),

  // Cómo reiniciar el servicio. Opciones:
  //   "systemctl restart nombre-servicio"  → para systemd
  //   "pm2 restart nombre-o-id"            → para PM2
  //   null                                 → no reinicia
  restartCmd: process.env.RESTART_CMD || null,

  // ¿Ejecutar npm install si cambia package.json o lockfile?
  runNpmInstall: process.env.RUN_NPM_INSTALL !== "false",

  // ¿Ejecutar npm run build si existe tsconfig.json o script "build" en package.json?
  runNpmBuild: process.env.RUN_NPM_BUILD !== "false",

  // ¿Ejecutar make build si existe un Makefile?
  runMakeBuild: process.env.RUN_MAKE_BUILD !== "false",

  // Archivo de log (null = solo consola)
  logFile: process.env.LOG_FILE || "./auto-updater.log",
};
// ─────────────────────────────────────────────────────────────

// Soporte para argumentos por CLI (sobrescriben CONFIG)
const args = process.argv.slice(2);
for (let i = 0; i < args.length; i++) {
  if (args[i] === "--repo" && args[i + 1]) CONFIG.repoPath = args[++i];
  if (args[i] === "--branch" && args[i + 1]) CONFIG.branch = args[++i];
  if (args[i] === "--interval" && args[i + 1])
    CONFIG.intervalMinutes = parseInt(args[++i]);
  if (args[i] === "--restart-cmd" && args[i + 1])
    CONFIG.restartCmd = args[++i];
  if (args[i] === "--log" && args[i + 1]) CONFIG.logFile = args[++i];
}

// ─────────────────────────────────────────────────────────────
// LOGGER
// ─────────────────────────────────────────────────────────────
function log(level, message) {
  const timestamp = new Date().toISOString();
  const line = `[${timestamp}] [${level.toUpperCase()}] ${message}`;
  console.log(line);
  if (CONFIG.logFile) {
    fs.appendFileSync(CONFIG.logFile, line + "\n");
  }
}

const logger = {
  info: (msg) => log("info", msg),
  warn: (msg) => log("warn", msg),
  error: (msg) => log("error", msg),
  success: (msg) => log("ok", msg),
};

// ─────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────
function run(cmd, cwd) {
  logger.info(`$ ${cmd}`);
  return execSync(cmd, {
    cwd: cwd || CONFIG.repoPath,
    encoding: "utf8",
    stdio: ["pipe", "pipe", "pipe"],
  }).trim();
}

function fileExistsInRepo(filename) {
  return fs.existsSync(path.join(CONFIG.repoPath, filename));
}

// Detecta si algún archivo clave cambió en el último pull
function changedFiles(beforeHash, afterHash) {
  try {
    const diff = run(
      `git diff --name-only ${beforeHash} ${afterHash}`,
      CONFIG.repoPath
    );
    return diff ? diff.split("\n") : [];
  } catch {
    return [];
  }
}

// Detecta si el proyecto tiene script "build" en package.json
function hasBuildScript() {
  try {
    const pkgPath = path.join(CONFIG.repoPath, "package.json");
    if (!fs.existsSync(pkgPath)) return false;
    const pkg = JSON.parse(fs.readFileSync(pkgPath, "utf8"));
    return !!(pkg.scripts && pkg.scripts.build);
  } catch {
    return false;
  }
}

// Verifica si la carpeta dist/ existe y tiene contenido
function buildExiste() {
  const distPath = path.join(CONFIG.repoPath, "dist");
  return fs.existsSync(distPath) && fs.readdirSync(distPath).length > 0;
}

// Detecta si cambiaron archivos que requieren rebuild
function requiereBuild(archivosModificados) {
  return archivosModificados.some(
    (f) =>
      f.endsWith(".ts") ||
      f.endsWith(".tsx") ||
      f === "tsconfig.json" ||
      f === "tsconfig.build.json" ||
      f.startsWith("src/")
  );
}

// ─────────────────────────────────────────────────────────────
// LÓGICA PRINCIPAL
// ─────────────────────────────────────────────────────────────
async function checkForUpdates() {
  logger.info("─── Verificando actualizaciones ───────────────────────");

  // 1. Verificar que el repo existe
  if (!fs.existsSync(path.join(CONFIG.repoPath, ".git"))) {
    logger.error(
      `No se encontró un repo git en: ${CONFIG.repoPath}. Verificá CONFIG.repoPath`
    );
    return;
  }

  // 2. Verificar que el build existe antes de cualquier cosa
  //    Esto soluciona el caso de primera instalación sin build previo
  if (CONFIG.runNpmBuild && hasBuildScript() && !buildExiste()) {
    logger.warn("⚠ Carpeta dist/ no encontrada o vacía. Ejecutando build inicial...");
    try {
      if (fileExistsInRepo("package.json")) {
        logger.info("📦 Ejecutando npm install...");
        run("npm install");
        logger.success("npm install completado.");
      }
      logger.info("🔨 Ejecutando npm run build...");
      run("npm run build");
      logger.success("✅ Build inicial completado. El servicio puede arrancar.");
    } catch (err) {
      logger.error(`Error en build inicial: ${err.message}`);
      return;
    }
  }

  try {
    // 3. Guardar el hash actual
    const hashAntes = run("git rev-parse HEAD");
    logger.info(`Hash actual: ${hashAntes.slice(0, 8)}`);

    // 4. Fetch del remoto (solo descarga, no aplica)
    run(`git fetch origin ${CONFIG.branch}`);

    // 5. Comparar con el remoto
    const hashRemoto = run(`git rev-parse origin/${CONFIG.branch}`);
    logger.info(`Hash remoto: ${hashRemoto.slice(0, 8)}`);

    if (hashAntes === hashRemoto) {
      logger.info("✓ Sin cambios. El servicio está actualizado.");
      return;
    }

    // 6. Hay cambios → aplicar
    logger.success(
      `🔄 Cambios detectados! Actualizando ${hashAntes.slice(0, 8)} → ${hashRemoto.slice(0, 8)}`
    );

    // Guardar cambios locales si los hubiera (para no perderlos)
    const statusOutput = run("git status --porcelain");
    if (statusOutput) {
      logger.warn("Hay cambios locales. Haciendo stash temporal...");
      run("git stash");
    }

    // 7. Git pull
    const pullOutput = run(`git pull origin ${CONFIG.branch}`);
    logger.info(`git pull: ${pullOutput}`);

    const archivosModificados = changedFiles(hashAntes, hashRemoto);
    logger.info(`Archivos modificados: ${archivosModificados.join(", ")}`);

    // 8. npm install (si cambiaron dependencias)
    const dependenciasModificadas = archivosModificados.some(
      (f) =>
        f === "package.json" ||
        f === "package-lock.json" ||
        f === "yarn.lock" ||
        f === "pnpm-lock.yaml"
    );

    if (CONFIG.runNpmInstall && fileExistsInRepo("package.json")) {
      if (dependenciasModificadas) {
        logger.info("📦 package.json cambió → ejecutando npm install...");
        run("npm install --omit=dev");
        logger.success("npm install completado.");
      } else {
        logger.info("package.json sin cambios → saltando npm install.");
      }
    }

    // 9. npm run build (si cambiaron archivos TypeScript o src/)
    if (CONFIG.runNpmBuild && hasBuildScript()) {
      if (requiereBuild(archivosModificados)) {
        logger.info("🔨 Archivos fuente cambiaron → ejecutando npm run build...");
        run("npm run build");
        logger.success("npm run build completado.");
      } else {
        logger.info("Sin cambios en src/ o .ts → saltando npm run build.");
      }
    }

    // 10. make build (si existe Makefile)
    if (CONFIG.runMakeBuild && fileExistsInRepo("Makefile")) {
      logger.info("🔨 Makefile encontrado → ejecutando make build...");
      run("make build");
      logger.success("make build completado.");
    }

    // 11. Reiniciar el servicio
    if (CONFIG.restartCmd) {
      logger.info(`🔁 Reiniciando servicio: ${CONFIG.restartCmd}`);
      run(CONFIG.restartCmd, "/");
      logger.success("Servicio reiniciado exitosamente.");
    } else {
      logger.warn(
        "⚠ No se configuró RESTART_CMD. Reiniciá el servicio manualmente."
      );
    }

    logger.success("✅ Actualización completada correctamente.\n");
  } catch (err) {
    logger.error(`Error durante la actualización: ${err.message}`);
    if (err.stderr) logger.error(`stderr: ${err.stderr}`);
  }
}

// ─────────────────────────────────────────────────────────────
// ARRANQUE
// ─────────────────────────────────────────────────────────────
logger.info("══════════════════════════════════════════════════════");
logger.info("  auto-updater iniciado");
logger.info(`  Repo:     ${CONFIG.repoPath}`);
logger.info(`  Rama:     ${CONFIG.branch}`);
logger.info(`  Intervalo: cada ${CONFIG.intervalMinutes} minutos`);
logger.info(`  Restart:  ${CONFIG.restartCmd || "(no configurado)"}`);
logger.info("══════════════════════════════════════════════════════");

// Ejecutar inmediatamente al iniciar
checkForUpdates();

// Luego, en loop según el intervalo configurado
setInterval(checkForUpdates, CONFIG.intervalMinutes * 60 * 1000);
