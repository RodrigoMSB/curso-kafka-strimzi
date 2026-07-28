#!/usr/bin/env bash
# Verifica que el entorno local tenga todo lo necesario para el Lab 01.
# Comprueba y reporta. La única excepción es kind: si falta o es anterior al
# mínimo del curso, se instala solo en $HOME/bin (bin/00c-instalar-kind.sh),
# porque no viene en la imagen base de las VMs y sin él no hay clúster.
set -euo pipefail

DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"

. "$DIR_SCRIPT/lib-comunes.sh"

msg_info "Verificación del entorno para el Lab 01 (solo kind se instala si falta)."
echo

errores=0

# 1. Docker accesible y corriendo.
if docker info >/dev/null 2>&1; then
  msg_ok "Docker está accesible y corriendo."
else
  msg_error "Docker no responde. Inicia Docker Desktop y vuelve a intentar."
  errores=$((errores + 1))
fi

# 1b. Memoria asignada a Docker. El pico del curso es el Lab 07 durante el
# rebalanceo (dos clústeres Kafka con un 4º broker temporal + Cruise Control + MM2
# + Connect + puente HTTP + PostgreSQL + Prometheus + Grafana, ~7.5 GiB; el Lab 06
# pesa ~6.25 GiB). Se recomiendan >= 10 GiB con holgura. Es un aviso [INFO], no un
# [ERROR]: no suma al contador ni bloquea — mismo criterio que el aviso de skew.
mem_bytes=$(docker info --format '{{.MemTotal}}' 2>/dev/null || true)
case "$mem_bytes" in
  ''|*[!0-9]*) : ;;   # no disponible o no numérico: no avisamos
  *)
    umbral=$((10 * 1024 * 1024 * 1024))         # 10 GiB en bytes (recomendado)
    mem_gib=$((mem_bytes / 1024 / 1024 / 1024))
    if [ "$mem_bytes" -lt "$umbral" ]; then
      msg_info "Docker tiene ~${mem_gib} GiB asignados; el pico del curso (Lab 07, rebalanceo con 4 brokers + Cruise Control) es ~7.5 GiB y se recomiendan >= 10 GiB."
      msg_info "Súbelo en Docker Desktop → Settings → Resources → Memory. 8 GiB es el suelo (labs 01-06); con menos de 10 el Lab 07 puede dejar pods en Pending/OOMKilled."
    else
      msg_ok "Memoria de Docker suficiente (~${mem_gib} GiB, recomendado >= 10 GiB)."
    fi
    ;;
esac

# 2. Herramientas presentes, imprimiendo su versión.
# kind debe ser v0.32.0 o superior: es la release que publica el digest pineado
# de kindest/node:v1.34.8 y el containerd compatible.
#
# kind no viene en la imagen base de las VMs del curso ni está en Chocolatey o
# WinGet en la versión requerida, así que si falta (o es anterior al mínimo) se
# instala solo con bin/00c-instalar-kind.sh. El alumno no tiene que saber que
# el instalador existe: corre el verificador y funciona.
instalado_kind=0
kind_hay=0; verificar_comando kind && kind_hay=1
if [ "$kind_hay" -eq 1 ]; then
  kv_previa=$(kind version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  case "${kv_previa}" in
    v0.3[2-9].*|v0.[4-9][0-9].*|v[1-9]*) ;;   # >= v0.32.0: nada que hacer
    *) kind_hay=0 ;;                          # anterior al mínimo: reinstalar
  esac
fi
if [ "$kind_hay" -eq 0 ]; then
  msg_info "kind falta o es anterior al mínimo del curso. Instalándolo automáticamente..."
  if bash "$DIR_SCRIPT/00c-instalar-kind.sh"; then
    # El instalador deja el binario en $HOME/bin; añadirlo al PATH de ESTA
    # ejecución basta para que el resto del verificador lo encuentre.
    PATH="$HOME/bin:$PATH"
    instalado_kind=1
  fi
fi
if [ "$instalado_kind" -eq 1 ]; then
  msg_info "kind se instaló automáticamente en \$HOME/bin (y \$HOME/bin quedó en tu ~/.bashrc)."
fi

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
  # El instalador ya explicó arriba qué falló y cuál es la vía manual.
  msg_error "Falta el comando: kind (la instalación automática no prosperó; revisa el detalle de arriba)."
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

# 2c. Git Bash (MSYS2) y la conversión de rutas. MSYS reescribe los argumentos que
# parecen rutas Unix ('/props/...') a rutas de Windows antes de entregárselos al
# comando. Las guías ya lo resuelven envolviendo esos comandos en bash -c '...',
# donde la ruta viaja dentro de una cadena que MSYS no inspecciona.
# Lo que NO hay que hacer es apagar la conversión globalmente: kind, helm y kubectl
# son binarios nativos de Windows y SÍ la necesitan para leer archivos del disco.
# Por eso esto es un [ERROR] que suma al contador: rompe el Lab 01 en su primer
# comando, antes de que exista el clúster.
if [ -n "${MSYS_NO_PATHCONV:-}" ]; then
  msg_error "MSYS_NO_PATHCONV está definida en tu terminal."
  msg_info "Esa variable apaga la conversión de rutas de forma global y rompe kind, helm y kubectl: no encuentran los archivos del disco y fallan con 'The system cannot find the path specified'."
  msg_info "Quítala con: unset MSYS_NO_PATHCONV"
  msg_info "Y si está en tu ~/.bashrc, elimina la línea y abre una terminal nueva."
  errores=$((errores + 1))
else
  case "$(uname -s 2>/dev/null || true)" in
    MINGW*|MSYS*)
      msg_ok "Git Bash detectado sin MSYS_NO_PATHCONV: es la configuración correcta."
      msg_info "Si un comando de las guías falla con 'NoSuchFileException: C:/Program Files/Git/props/...', NO exportes esa variable: usa el comando envuelto en bash -c '...' tal como aparece en la guía."
      ;;
  esac
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
