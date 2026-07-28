#!/usr/bin/env bash
# Instalador de kind para el curso.
#
# kind no viene en la imagen base de las VMs del curso, y no está en Chocolatey
# ni en WinGet en la versión que el curso exige. Sin kind no hay clúster, así
# que el Lab 01 muere en su primer paso. Este script lo descarga del release
# oficial a $HOME/bin, sin permisos de administrador, y deja $HOME/bin en el
# PATH del ~/.bashrc.
#
# Funciona en Git Bash (Windows), macOS y Linux.
# Es idempotente: si kind ya está en la versión esperada, no descarga nada.
set -euo pipefail
DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"

# --- Configuración: cambiar de versión es cambiar esta línea. ----------------
KIND_VERSION="v0.32.0"
KIND_BASE_URL="https://github.com/kubernetes-sigs/kind/releases/download"

BASHRC="$HOME/.bashrc"
LINEA_PATH='export PATH="$HOME/bin:$PATH"'

# ¿El ~/.bashrc ya mete $HOME/bin en el PATH? Se aceptan las tres formas
# habituales de escribirlo para no duplicar la línea en corridas sucesivas.
bashrc_ya_tiene_bin() {
  [ -f "$BASHRC" ] || return 1
  grep -Eq "PATH=.*(\\\$HOME/bin|\\\$\\{HOME\\}/bin|${HOME}/bin)" "$BASHRC"
}

# La versión que reporta un kind concreto, normalizada a vX.Y.Z.
version_de() {
  "$1" version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true
}

explicar_fallo() {
  msg_error "kind no está disponible y no se pudo instalar automáticamente."
  msg_error ""
  msg_error "  kind ${KIND_VERSION} es obligatorio: el kind-config.yaml del curso fija la versión"
  msg_error "  del nodo y la topología, y otras versiones no están probadas."
  msg_error ""
  msg_error "  Instalación manual (Git Bash, sin permisos de administrador):"
  msg_error "    mkdir -p ~/bin"
  msg_error "    curl -sL -o ~/bin/kind.exe \\"
  msg_error "      ${KIND_BASE_URL}/${KIND_VERSION}/kind-windows-amd64"
  msg_error "    chmod +x ~/bin/kind.exe"
  msg_error "    export PATH=\"\$HOME/bin:\$PATH\""
  msg_error "    kind version"
  msg_error ""
  msg_error "  Si falla la descarga, revisa el proxy corporativo o avisa al instructor."
}

# --- 1 y 2. ¿kind ya está, y en qué versión? ---------------------------------
if verificar_comando kind; then
  ruta_actual="$(command -v kind)"
  ver_actual="$(version_de kind)"
  if [ "$ver_actual" = "$KIND_VERSION" ]; then
    msg_ok "kind ya está en la versión esperada (${KIND_VERSION}) en ${ruta_actual}."
    exit 0
  fi
  msg_info "kind presente en ${ruta_actual}, pero su versión es '${ver_actual:-desconocida}' y el curso fija ${KIND_VERSION}."
  msg_info "Instalaré ${KIND_VERSION} en \$HOME/bin, que tiene precedencia en el PATH."
else
  msg_info "kind no está instalado. Descargando ${KIND_VERSION}..."
fi

# --- 3. Plataforma y binario correspondiente. --------------------------------
case "$(uname -s 2>/dev/null || true)" in
  MINGW*|MSYS*)
    ARCHIVO="kind-windows-amd64"; DESTINO="$HOME/bin/kind.exe" ;;
  Darwin)
    case "$(uname -m 2>/dev/null || true)" in
      arm64|aarch64) ARCHIVO="kind-darwin-arm64" ;;
      *)             ARCHIVO="kind-darwin-amd64" ;;
    esac
    DESTINO="$HOME/bin/kind" ;;
  Linux)
    ARCHIVO="kind-linux-amd64"; DESTINO="$HOME/bin/kind" ;;
  *)
    msg_error "Sistema no reconocido: $(uname -s 2>/dev/null || echo desconocido)."
    explicar_fallo
    exit 1 ;;
esac
URL="${KIND_BASE_URL}/${KIND_VERSION}/${ARCHIVO}"
msg_info "Plataforma detectada: ${ARCHIVO}."

# --- 4. ¿Se llega a la URL? --------------------------------------------------
if ! verificar_comando curl; then
  msg_error "curl no está disponible: no puedo descargar kind."
  explicar_fallo
  exit 1
fi
codigo="$(curl -sIL -o /dev/null -w '%{http_code}' "$URL" 2>/dev/null || true)"
if [ "$codigo" != "200" ]; then
  msg_error "La descarga de kind no está accesible (HTTP ${codigo:-sin respuesta})."
  msg_error "URL: ${URL}"
  explicar_fallo
  exit 1
fi
msg_ok "Release de kind accesible (HTTP 200)."

# --- 5. Descargar. -----------------------------------------------------------
mkdir -p "$HOME/bin"
if ! curl -sL --fail -o "$DESTINO" "$URL"; then
  msg_error "Falló la descarga de ${URL}."
  rm -f "$DESTINO"
  explicar_fallo
  exit 1
fi
chmod +x "$DESTINO"
msg_ok "kind descargado en ${DESTINO}."

# --- 6. ¿Quedó operativo y en la versión correcta? ---------------------------
# Se invoca por ruta absoluta: el PATH puede no incluir aún $HOME/bin.
ver_nueva="$(version_de "$DESTINO")"
if [ "$ver_nueva" != "$KIND_VERSION" ]; then
  msg_error "El binario descargado no responde la versión esperada."
  msg_error "Esperada: ${KIND_VERSION} | obtenida: '${ver_nueva:-sin respuesta}'"
  msg_error "Se elimina el binario a medias: ${DESTINO}"
  rm -f "$DESTINO"
  explicar_fallo
  exit 1
fi
msg_ok "kind operativo: $("$DESTINO" version 2>&1 | head -1)"

# --- 7. Dejar $HOME/bin en el PATH, ahora y en las próximas terminales. ------
case ":${PATH}:" in
  *":${HOME}/bin:"*) en_path_ahora=1 ;;
  *)                 en_path_ahora=0 ;;
esac

if bashrc_ya_tiene_bin; then
  msg_ok "Tu ~/.bashrc ya deja \$HOME/bin en el PATH: no modifiqué nada."
else
  printf '\n# Añadido por el curso (Lab 01): kind vive en $HOME/bin.\n%s\n' \
    "$LINEA_PATH" >> "$BASHRC"
  msg_ok "Añadí esta línea al final de tu ~/.bashrc:  ${LINEA_PATH}"
fi

if [ "$en_path_ahora" -eq 1 ]; then
  msg_ok "\$HOME/bin ya estaba en el PATH de esta terminal: kind funciona aquí y ahora."
else
  msg_info "Esta terminal se abrió antes del cambio, así que aún no ve \$HOME/bin."
  msg_info "Abre una terminal nueva, o ejecuta aquí mismo:  export PATH=\"\$HOME/bin:\$PATH\""
fi
