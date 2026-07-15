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

# 2b. Aviso de skew de versiones (kubectl vs API server, o el pin del kind-config).
# La política de skew de Kubernetes soporta como máximo ±1 minor entre kubectl y
# el API server. Con un desfase mayor algunas operaciones pueden comportarse de
# forma inesperada. Lo importante: kubectl NO avisa solo de este desfase (probado
# en la práctica), así que lo señalamos nosotros. Es un aviso [INFO], no un
# [ERROR]: no suma al contador ni bloquea el lab, que funciona incluso con 2
# minors de diferencia.
cli_raw=""; srv_raw=""; origen=""
cli_raw=$(kubectl version --client 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
srv_raw=$(kubectl version --request-timeout=5s 2>/dev/null | grep -i server | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
if [ -n "$srv_raw" ]; then
  origen="el API server"
else
  # Sin clúster todavía: comparamos contra la versión pineada de los nodos.
  archivo_cfg="$DIR_SCRIPT/../infra/kind-config.yaml"
  srv_raw=$(grep -oE 'kindest/node:v[0-9]+\.[0-9]+\.[0-9]+' "$archivo_cfg" 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
  origen="el pin del kind-config (aún no hay clúster)"
fi
if [ -n "$cli_raw" ] && [ -n "$srv_raw" ]; then
  c=${cli_raw#v}; s=${srv_raw#v}
  c_major=${c%%.*}; c_min=${c#*.}; c_min=${c_min%%.*}
  s_major=${s%%.*}; s_min=${s#*.}; s_min=${s_min%%.*}
  if [ "$c_major" = "$s_major" ]; then
    gap=$((c_min - s_min))
    if [ "$gap" -lt 0 ]; then gap=$((0 - gap)); fi
    if [ "$gap" -gt 1 ]; then
      msg_info "Aviso de skew: kubectl ${cli_raw} frente a ${origen} ${srv_raw} → ${gap} minors de diferencia."
      msg_info "La política de skew de Kubernetes soporta ±1 minor entre kubectl y el API server, y kubectl no te avisará solo de este desfase."
      msg_info "No es un error: el lab está probado y funciona con este gap. Si quieres alinearlo, usa un kubectl más cercano a ${srv_raw}."
    fi
  fi
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
