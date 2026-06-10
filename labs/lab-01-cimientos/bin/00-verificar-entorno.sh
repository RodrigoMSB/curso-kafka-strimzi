#!/usr/bin/env bash
# Verifica que el entorno local tenga todo lo necesario para el Lab 01.
# No instala nada: solo comprueba y reporta.
set -euo pipefail

DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"

msg_info "Verificación del entorno para el Lab 01 (no se instala nada)."
echo

errores=0

# 1. Docker accesible y corriendo.
if docker info >/dev/null 2>&1; then
  msg_ok "Docker está accesible y corriendo."
else
  msg_error "Docker no responde. Inicia Docker Desktop y vuelve a intentar."
  errores=$((errores + 1))
fi

# 2. Herramientas presentes, imprimiendo su versión.
if verificar_comando kind; then
  msg_ok "kind presente: $(kind version 2>/dev/null)"
else
  msg_error "Falta el comando: kind"
  errores=$((errores + 1))
fi

if verificar_comando kubectl; then
  msg_ok "kubectl presente: $(kubectl version --client 2>/dev/null | head -1)"
else
  msg_error "Falta el comando: kubectl"
  errores=$((errores + 1))
fi

if verificar_comando helm; then
  msg_ok "helm presente: $(helm version --short 2>/dev/null)"
else
  msg_error "Falta el comando: helm"
  errores=$((errores + 1))
fi

# 3. Conectividad básica: resolución de strimzi.io.
if verificar_comando nslookup && nslookup strimzi.io >/dev/null 2>&1; then
  msg_ok "Resolución DNS de strimzi.io correcta."
elif verificar_comando host && host strimzi.io >/dev/null 2>&1; then
  msg_ok "Resolución DNS de strimzi.io correcta."
elif ping -c 1 strimzi.io >/dev/null 2>&1; then
  msg_ok "strimzi.io responde."
else
  msg_error "No se pudo contactar strimzi.io. Revisa tu conexión a Internet o la VPN."
  errores=$((errores + 1))
fi

echo
if [ "$errores" -eq 0 ]; then
  msg_ok "Entorno en verde. Puedes continuar con bin/01-crear-cluster.sh."
else
  msg_error "Se encontraron $errores problema(s). Resuélvelos antes de continuar (ver docs/troubleshooting.md)."
  exit 1
fi
