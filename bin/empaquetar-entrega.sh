#!/usr/bin/env bash
# Empaqueta los laboratorios del curso para entregar al alumno de forma SEGURA.
#
# Por qué git archive y no "comprimir con Finder": git archive empaqueta el
# árbol tal como lo ve git, respetando el índice y el .gitignore por diseño. Todo
# lo ignorado —en particular credenciales/ con las llaves privadas del Lab 04—
# nunca entra al paquete. Comprimir la carpeta a mano SÍ arrastra esos archivos.
#
# Además, no confiamos a ciegas: tras construir el zip lo INSPECCIONAMOS y, si
# aparece cualquier credencial, fallamos ruidosamente y borramos el paquete. En
# un curso que le enseña mTLS y mínimo privilegio a un banco, una llave privada
# viajando dentro del material sería justo lo contrario de lo que enseñamos.
#
# Uso:
#   bash bin/empaquetar-entrega.sh
#
# Empaqueta el estado COMPROMETIDO (HEAD) del subárbol labs/. Los cambios sin
# commitear no entran: git archive parte de HEAD, no del working tree.
set -euo pipefail

# --- Mensajería en español neutro (mismo molde que los lib-comunes.sh) ---
msg_ok()    { printf '[OK] %s\n' "$*"; }
msg_info()  { printf '[INFO] %s\n' "$*"; }
msg_error() { printf '[ERROR] %s\n' "$*" >&2; }

# --- Ubicación: raíz del repo, salga desde donde salga la invocación ---
RAIZ="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$RAIZ" ]; then
  msg_error "Este script debe ejecutarse dentro del repositorio git del curso."
  exit 1
fi
cd "$RAIZ"

SUBARBOL="labs"
DIR_ENTREGA="ENTREGA"
ZIP="${DIR_ENTREGA}/Laboratorios-Kafka-Strimzi.zip"
REF="HEAD"

# Patrones de credenciales que JAMÁS deben viajar en la entrega.
PATRONES_SECRETOS='\.key$|\.password$|\.pem$|\.p12$|(^|/)credenciales/'

# --- Prevuelo ---
if ! git cat-file -e "${REF}:${SUBARBOL}" 2>/dev/null; then
  msg_error "No existe el subárbol '${SUBARBOL}' en ${REF}. ¿Estás en la rama correcta?"
  exit 1
fi

# Aviso (no bloqueante): git archive parte de HEAD; los cambios sin commitear
# no se incluyen. Es correcto para una entrega reproducible, pero conviene saberlo.
if ! git diff --quiet -- "$SUBARBOL" || ! git diff --cached --quiet -- "$SUBARBOL"; then
  msg_info "Hay cambios sin commitear en '${SUBARBOL}/'. El paquete usa ${REF} (lo comprometido)."
fi

mkdir -p "$DIR_ENTREGA"

# --- Construcción con git archive (respeta el índice → lo ignorado no entra) ---
msg_info "Empaquetando '${SUBARBOL}/' desde ${REF} con git archive..."
git archive --format=zip -o "$ZIP" "$REF" "$SUBARBOL"

# --- Verificación post-build: el zip NO debe contener credenciales ---
# zipinfo -1 lista una ruta por línea; unzip -l es el respaldo portable.
if command -v zipinfo >/dev/null 2>&1; then
  contenido="$(zipinfo -1 "$ZIP")"
else
  contenido="$(unzip -l "$ZIP" | awk 'NR>3 {print $4}')"
fi

encontrados="$(printf '%s\n' "$contenido" | grep -Ei "$PATRONES_SECRETOS" || true)"
if [ -n "$encontrados" ]; then
  msg_error "ABORTADO: el paquete contiene archivos que parecen credenciales:"
  printf '%s\n' "$encontrados" | sed 's/^/    /' >&2
  rm -f "$ZIP"
  msg_error "Se borró '${ZIP}'. Revisa el .gitignore y que credenciales/ no esté versionado."
  exit 1
fi

# --- Reporte ---
n_archivos="$(printf '%s\n' "$contenido" | grep -c . || true)"
tam="$(du -h "$ZIP" | cut -f1)"
msg_ok "Paquete generado sin credenciales: ${ZIP} (${tam}, ${n_archivos} archivos)."
msg_info "Verifica el contenido con: unzip -l ${ZIP}"
