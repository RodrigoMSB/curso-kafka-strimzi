#!/usr/bin/env bash
# Puente de kcat para Windows + Git Bash.
#
# kcat no tiene binario para Windows (no está en Chocolatey ni en WinGet, y
# compilarlo exige Build Tools de Visual Studio). Pero el Lab 04 lo necesita EN
# EL HOST: es la única herramienta del curso que corre fuera del clúster, para
# demostrar acceso externo real contra los nodePorts 32000-32007.
#
# Las VMs del curso traen Ubuntu en WSL2 con kcat ya instalado, y WSL2 alcanza
# el 127.0.0.1 de Windows. Este script instala en $HOME/bin/kcat un wrapper que
# traduce las rutas de Git Bash a rutas de WSL y delega la ejecución, y deja
# $HOME/bin en el PATH del ~/.bashrc para que kcat siga disponible mañana.
#
# En macOS y Linux no hace nada: informa y sale 0.
# Es idempotente: correrlo dos veces no rompe nada (ni duplica el .bashrc).
set -euo pipefail
DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"

DESTINO="$HOME/bin/kcat"
BASHRC="$HOME/.bashrc"
LINEA_PATH='export PATH="$HOME/bin:$PATH"'

# ¿El ~/.bashrc ya mete $HOME/bin en el PATH? Se aceptan las tres formas
# habituales de escribirlo para no duplicar la línea en corridas sucesivas.
bashrc_ya_tiene_bin() {
  [ -f "$BASHRC" ] || return 1
  grep -Eq "PATH=.*(\\\$HOME/bin|\\\$\\{HOME\\}/bin|${HOME}/bin)" "$BASHRC"
}

# El mensaje del error accionable, en un solo lugar: lo usan los pasos 3 y 4.
explicar_sin_wsl() {
  msg_error "kcat no está disponible y no se pudo crear el puente."
  msg_error ""
  msg_error "  kcat no tiene binario para Windows, así que en Git Bash lo usamos desde WSL2."
  msg_error "  Este equipo no tiene WSL2 con Ubuntu disponible."
  msg_error ""
  msg_error "  Opciones:"
  msg_error "    1) Instalar WSL2:  wsl --install -d Ubuntu   (PowerShell como administrador)"
  msg_error "       y luego:        wsl -d Ubuntu -e sudo apt-get install -y kcat"
  msg_error "    2) Avisar al instructor: el Lab 04 se puede seguir sin kcat;"
  msg_error "       solo 2 de 8 verificaciones lo requieren."
}

# --- 1. Solo aplica a Git Bash (MSYS2). -------------------------------------
case "$(uname -s 2>/dev/null || true)" in
  MINGW*|MSYS*) ;;
  *)
    msg_info "No estás en Git Bash: este puente no hace falta aquí."
    msg_info "Instala kcat de forma nativa: brew install kcat (macOS) o sudo apt-get install -y kcat (Debian/Ubuntu)."
    exit 0
    ;;
esac

# --- 2. ¿kcat ya responde? ---------------------------------------------------
# Ojo: si el puente ya está instalado y $HOME/bin está en el PATH, 'command -v'
# lo encuentra. Distinguimos ese caso del kcat nativo para no reinstalar a ciegas.
if verificar_comando kcat && kcat -V >/dev/null 2>&1; then
  ruta_kcat="$(command -v kcat)"
  if [ "$ruta_kcat" = "$DESTINO" ]; then
    msg_ok "El puente ya está instalado y operativo: $(kcat -V 2>&1 | head -1)"
  else
    msg_ok "kcat ya funciona de forma nativa en ${ruta_kcat}: $(kcat -V 2>&1 | head -1)"
    msg_info "No hace falta el puente."
  fi
  exit 0
fi

msg_info "kcat no responde en esta terminal. Preparando el puente hacia WSL2..."

# --- 3. ¿Hay WSL con Ubuntu? -------------------------------------------------
# 'wsl.exe -l -q' emite UTF-16LE: sin quitar los bytes nulos, el grep nunca
# encuentra nada aunque Ubuntu esté instalado.
if ! command -v wsl.exe >/dev/null 2>&1; then
  explicar_sin_wsl
  exit 1
fi
distros="$(wsl.exe -l -q 2>/dev/null | tr -d '\000\r' || true)"
if ! printf '%s\n' "$distros" | grep -qi '^Ubuntu'; then
  msg_error "WSL está presente, pero no encontré una distribución 'Ubuntu'."
  msg_error "Distribuciones detectadas: $(printf '%s' "$distros" | tr '\n' ' ')"
  explicar_sin_wsl
  exit 1
fi
msg_ok "WSL2 con Ubuntu detectado."

# --- 4. ¿kcat está instalado dentro de Ubuntu? -------------------------------
if ! wsl.exe -d Ubuntu -e bash -c 'command -v kcat' >/dev/null 2>&1; then
  msg_error "Ubuntu (WSL2) está disponible, pero kcat no está instalado ahí."
  msg_error "Instálalo con:"
  msg_error "  wsl -d Ubuntu -e sudo apt-get install -y kcat"
  msg_error "y vuelve a ejecutar este script."
  exit 1
fi
msg_ok "kcat encontrado dentro de Ubuntu (WSL2)."

# --- 5. Instalar el wrapper. -------------------------------------------------
mkdir -p "$HOME/bin"
cat > "$DESTINO" <<'WRAPPER'
#!/usr/bin/env bash
# Puente: kcat vive en Ubuntu (WSL2). Traduce rutas de Git Bash a WSL.
# MSYS_NO_PATHCONV en línea: las rutas ya son de Linux, Git Bash no debe tocarlas.
traducir() {
  case "$1" in
    /[a-zA-Z]/*)   printf '/mnt%s' "$1" ;;
    *=/[a-zA-Z]/*) printf '%s=/mnt%s' "${1%%=*}" "${1#*=}" ;;
    *)             printf '%s' "$1" ;;
  esac
}
args=()
for a in "$@"; do args+=("$(traducir "$a")"); done
MSYS_NO_PATHCONV=1 exec wsl.exe -d Ubuntu kcat "${args[@]}"
WRAPPER
chmod +x "$DESTINO"
msg_ok "Puente instalado en ${DESTINO}."

# --- 6. ¿Quedó operativo? ----------------------------------------------------
# Se invoca por ruta absoluta: el PATH puede no incluir aún $HOME/bin.
if ! "$DESTINO" -V >/dev/null 2>&1; then
  msg_error "El puente quedó instalado pero kcat no respondió a través de él."
  msg_error "Diagnostica a mano con:  wsl -d Ubuntu -e kcat -V"
  exit 1
fi
msg_ok "kcat operativo vía WSL2: $("$DESTINO" -V 2>&1 | head -1)"

# --- 7. Dejar $HOME/bin en el PATH, ahora y en las próximas terminales. ------
# Se toca el ~/.bashrc a propósito: sin esto el alumno ve el verificador en
# verde y acto seguido 'kcat: command not found' al teclear los comandos de la
# guía 03, que es fricción pura en medio de la clase.
case ":${PATH}:" in
  *":${HOME}/bin:"*) en_path_ahora=1 ;;
  *)                 en_path_ahora=0 ;;
esac

if bashrc_ya_tiene_bin; then
  msg_ok "Tu ~/.bashrc ya deja \$HOME/bin en el PATH: no modifiqué nada."
else
  printf '\n# Añadido por el curso (Lab 04): kcat vive en $HOME/bin, vía el puente a WSL2.\n%s\n' \
    "$LINEA_PATH" >> "$BASHRC"
  msg_ok "Añadí esta línea al final de tu ~/.bashrc:  ${LINEA_PATH}"
fi

if [ "$en_path_ahora" -eq 1 ]; then
  msg_ok "\$HOME/bin ya estaba en el PATH de esta terminal: kcat funciona aquí y ahora."
else
  msg_info "Esta terminal se abrió antes del cambio, así que aún no ve \$HOME/bin."
  msg_info "Abre una terminal nueva, o ejecuta aquí mismo:  export PATH=\"\$HOME/bin:\$PATH\""
fi
