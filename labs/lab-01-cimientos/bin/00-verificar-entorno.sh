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
# kind debe ser v0.32.0 o superior: es la release que publica el digest pineado
# de kindest/node:v1.34.8 y el containerd compatible.
if verificar_comando kind; then
  kind_ver_raw=$(kind version 2>/dev/null)
  msg_ok "kind presente: ${kind_ver_raw}"
  kv=$(printf '%s\n' "$kind_ver_raw" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  kv=${kv#v}
  if [ -z "$kv" ]; then
    msg_info "No se pudo determinar la versión de kind; se requiere v0.32.0 o superior."
  else
    kmaj=${kv%%.*}; krest=${kv#*.}; kmin=${krest%%.*}; kpatch=${krest#*.}
    ver_ok=1
    case "${kmaj}-${kmin}-${kpatch}" in
      *[!0-9-]*) ver_ok=1 ;;   # no parseable: no bloquear por el parseo
      *)
        if [ "$kmaj" -gt 0 ]; then ver_ok=0
        elif [ "$kmaj" -eq 0 ] && [ "$kmin" -gt 32 ]; then ver_ok=0
        elif [ "$kmaj" -eq 0 ] && [ "$kmin" -eq 32 ] && [ "$kpatch" -ge 0 ]; then ver_ok=0
        else ver_ok=1; fi
        ;;
    esac
    if [ "$ver_ok" -eq 0 ]; then
      msg_ok "Versión de kind suficiente (detectada ${kv}, mínimo v0.32.0)."
    else
      msg_error "kind ${kv} es anterior al mínimo requerido v0.32.0."
      msg_error "v0.32.0 publica el digest pineado de kindest/node:v1.34.8 y el containerd compatible."
      msg_error "Actualiza: 'brew upgrade kind' (macOS); en WSL2, reinstala el binario desde https://kind.sigs.k8s.io/docs/user/quick-start/#installation"
      errores=$((errores + 1))
    fi
  fi
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
