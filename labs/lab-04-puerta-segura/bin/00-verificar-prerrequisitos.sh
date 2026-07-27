#!/usr/bin/env bash
# Verifica los prerrequisitos del Lab 04:
#   1) Estado final del Lab 03 (su test 90 en verde).
#   2) kcat instalado en esta máquina.
#   3) Puertos 32000-32007 mapeados del nodo control-plane al host (acceso externo).
#
# LAB01_CLUSTER permite apuntar a otro clúster.
set -uo pipefail
DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"

NOMBRE_CLUSTER="${LAB01_CLUSTER:-meridiano}"
LAB03_90="$DIR_SCRIPT/../../lab-03-topicos-identidad/bin/90-test-lab.sh"
errores=0

msg_info "Verificando prerrequisitos del Lab 04..."
echo

# 1. Estado del Lab 03.
if [ -f "$LAB03_90" ] && bash "$LAB03_90" >/tmp/lab04-lab03-90.out 2>&1; then
  msg_ok "Estado final del Lab 03 presente (su test 90 en verde)."
else
  msg_error "El Lab 03 no está completo. Recupéralo con: labs/lab-03-topicos-identidad/bin/95-recuperar-lab.sh"
  errores=$((errores + 1))
fi

# 2. kcat instalado. En Git Bash no existe binario nativo, así que si falta se
# intenta crear el puente a WSL2 (bin/00b-puente-kcat.sh) sin que el alumno
# tenga que saber que existe. En macOS y Linux el comportamiento no cambia.
puente=0
if ! verificar_comando kcat; then
  case "$(uname -s 2>/dev/null || true)" in
    MINGW*|MSYS*)
      msg_info "kcat no responde. Intentando crear el puente a WSL2..."
      if bash "$DIR_SCRIPT/00b-puente-kcat.sh"; then
        # El puente vive en $HOME/bin; añadirlo al PATH de ESTA ejecución basta
        # para que el resto del verificador y el test 90 lo encuentren.
        PATH="$HOME/bin:$PATH"
        puente=1
      fi
      ;;
  esac
fi
if verificar_comando kcat; then
  if [ "$puente" -eq 1 ]; then
    msg_ok "kcat operativo vía el puente a WSL2: $(kcat -V 2>&1 | head -1)"
    msg_info "El puente quedó en \$HOME/bin/kcat y \$HOME/bin ya está en tu ~/.bashrc."
  else
    msg_ok "kcat presente: $(kcat -V 2>&1 | head -1)"
  fi
else
  case "$(uname -s 2>/dev/null || true)" in
    MINGW*|MSYS*)
      # El puente ya explicó arriba qué falta y cómo resolverlo.
      msg_error "kcat sigue sin estar disponible (revisa el detalle del puente, más arriba)."
      ;;
    *)
      msg_error "kcat no está instalado. Instálalo:"
      msg_error "  macOS:        brew install kcat"
      msg_error "  Debian/Ubuntu (WSL2): sudo apt-get install -y kcat"
      ;;
  esac
  errores=$((errores + 1))
fi

# 3. Puertos externos mapeados al host.
faltan_puertos=""
mapeos=$(docker port "${NOMBRE_CLUSTER}-control-plane" 2>/dev/null || true)
for p in 32000 32001 32002 32003 32004 32005 32006 32007; do
  if ! printf '%s\n' "$mapeos" | grep -q "${p}/tcp"; then
    faltan_puertos="${faltan_puertos} ${p}"
  fi
done
if [ -z "$faltan_puertos" ]; then
  msg_ok "Puertos externos 32000-32007 mapeados al host."
else
  msg_error "Faltan mapeos de puertos:${faltan_puertos}."
  msg_error "Tu clúster es anterior al mapeo de puertos del curso. Recréalo:"
  msg_error "  labs/lab-01-cimientos/bin/99-destruir-lab.sh  (destruye)"
  msg_error "  labs/lab-03-topicos-identidad/bin/95-recuperar-lab.sh  (reconstruye hasta el Lab 03)"
  errores=$((errores + 1))
fi

echo
if [ "$errores" -eq 0 ]; then
  msg_ok "Prerrequisitos satisfechos. Puedes empezar el Lab 04."
else
  msg_error "Prerrequisitos NO satisfechos (${errores}). Resuélvelos antes de continuar."
  exit 1
fi
