#!/usr/bin/env bash
# Test automatizado del Lab 01. SOLO LECTURA: verifica el estado final del lab
# y NO crea, repara, instala ni borra nada.
#
# Ejecuta TODAS las verificaciones (no aborta en la primera falla), acumula
# resultados y reporta al final. Por eso NO se usa 'set -e': cada verificación
# se evalúa con condicionales explícitos.
#
# Permite apuntar a otro clúster (para pruebas) con la variable de entorno
# LAB01_CLUSTER. Por defecto usa 'meridiano'.
set -uo pipefail

DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"

NOMBRE_CLUSTER="${LAB01_CLUSTER:-meridiano}"
CONTEXTO="kind-${NOMBRE_CLUSTER}"
NS_SISTEMA="meridiano-sistema"
NS_PAGOS="meridiano-pagos"

# --- Contadores dinámicos (no se hardcodea el total) ---
total=0
aprobadas=0

# verificar <descripción> <0|1 resultado> <pista accionable si falla>
verificar() {
  total=$((total + 1))
  if [ "$2" -eq 0 ]; then
    aprobadas=$((aprobadas + 1))
    msg_ok "$1"
  else
    msg_error "$1 -> $3"
  fi
}

msg_info "Test del Lab 01 (solo lectura). Clúster objetivo: ${NOMBRE_CLUSTER}"
echo

# 1. Docker accesible.
if docker info >/dev/null 2>&1; then r=0; else r=1; fi
verificar "Docker accesible" "$r" "Inicia Docker Desktop (docs/troubleshooting.md, fila 1)."

# 2. El clúster kind existe.
if kind get clusters 2>/dev/null | grep -q "^${NOMBRE_CLUSTER}$"; then r=0; else r=1; fi
verificar "Clúster kind '${NOMBRE_CLUSTER}' existe" "$r" "Créalo con bin/01-crear-cluster.sh (Guía 2)."

# 3. Nodo control-plane en estado Ready.
estado_ready=$(kubectl get nodes "${NOMBRE_CLUSTER}-control-plane" --context "$CONTEXTO" \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
if [ "$estado_ready" = "True" ]; then r=0; else r=1; fi
verificar "Nodo ${NOMBRE_CLUSTER}-control-plane en estado Ready" "$r" \
  "Si recién creaste el clúster, espera 30-60 s (NotReady transitorio, ver Guía 2 y troubleshooting)."

# 4. Versión de Kubernetes del nodo dentro del rango 1.30-1.35 (comparación numérica).
version_nodo=$(kubectl get nodes "${NOMBRE_CLUSTER}-control-plane" --context "$CONTEXTO" \
  -o jsonpath='{.status.nodeInfo.kubeletVersion}' 2>/dev/null || true)
version_limpia=${version_nodo#v}        # quita la 'v' inicial -> 1.34.8
major=${version_limpia%%.*}             # 1
resto=${version_limpia#*.}              # 34.8
minor=${resto%%.*}                      # 34
r=1
case "${major}-${minor}" in
  *[!0-9-]*|-*|*-) r=1 ;;               # algún campo vacío o no numérico
  *)
    if [ "$major" -eq 1 ] && [ "$minor" -ge 30 ] && [ "$minor" -le 35 ]; then
      r=0
    else
      r=1
    fi
    ;;
esac
verificar "Versión de Kubernetes en rango 1.30-1.35 (detectada: ${version_nodo:-desconocida})" "$r" \
  "Fija la imagen del nodo a una versión soportada en infra/kind-config.yaml (Guía 2)."

# 5. Namespaces presentes.
r=0
for ns in "$NS_SISTEMA" "$NS_PAGOS"; do
  if kubectl get namespace "$ns" --context "$CONTEXTO" >/dev/null 2>&1; then :; else r=1; fi
done
verificar "Namespaces ${NS_SISTEMA} y ${NS_PAGOS} presentes" "$r" \
  "Créalos con bin/02-crear-namespaces.sh (Guía 2)."

# 6. Release de Helm sano (parseo tolerante de 'helm list -o json').
helm_json=$(helm list -n "$NS_SISTEMA" --kube-context "$CONTEXTO" -o json 2>/dev/null | tr -d ' ' || true)
if printf '%s' "$helm_json" | grep -q '"name":"strimzi-operator"' \
   && printf '%s' "$helm_json" | grep -q '"status":"deployed"' \
   && printf '%s' "$helm_json" | grep -q '"chart":"strimzi-kafka-operator-0.51.0"'; then
  r=0
else
  r=1
fi
verificar "Release de Helm strimzi-operator desplegado (chart 0.51.0)" "$r" \
  "Instala el operador con helm install ... --version 0.51.0 (Guía 3, sección instalación)."

# 7. Pod del operador sano: exactamente uno, Running y con todos sus contenedores listos.
listado_pods=$(kubectl get pods -n "$NS_SISTEMA" --context "$CONTEXTO" \
  -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.status.phase}{"|"}{range .status.containerStatuses[*]}{.ready}{","}{end}{"\n"}{end}' \
  2>/dev/null || true)
cuenta_pods=0
fase_pod=""
listos_pod=""
while IFS='|' read -r nombre fase listos; do
  case "$nombre" in
    strimzi-cluster-operator-*)
      cuenta_pods=$((cuenta_pods + 1))
      fase_pod="$fase"
      listos_pod="$listos"
      ;;
  esac
done <<EOF
$listado_pods
EOF
if [ "$cuenta_pods" -eq 0 ]; then
  r=1; pista_pod="No hay pod del operador; revisa la Guía 3 (instalación)."
elif [ "$cuenta_pods" -ge 2 ]; then
  r=1; pista_pod="Hay un despliegue en transición; espera unos segundos y reintenta."
else
  case "$listos_pod" in
    *false*|,|"") listo_ok=1 ;;
    *) listo_ok=0 ;;
  esac
  if [ "$fase_pod" = "Running" ] && [ "$listo_ok" -eq 0 ]; then
    r=0; pista_pod=""
  else
    r=1; pista_pod="El pod existe pero no está Running/listo; revisa la Guía 3 y troubleshooting."
  fi
fi
verificar "Pod del operador único, Running y listo" "$r" "$pista_pod"

# 8. CRDs de Strimzi instalados (al menos los cuatro fundamentales).
lista_crds=$(kubectl get crds --context "$CONTEXTO" \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
r=0
for crd in kafkas.kafka.strimzi.io kafkanodepools.kafka.strimzi.io \
           kafkatopics.kafka.strimzi.io kafkausers.kafka.strimzi.io; do
  if printf '%s\n' "$lista_crds" | grep -qx "$crd"; then :; else r=1; fi
done
verificar "CRDs de Strimzi instalados (kafkas, kafkanodepools, kafkatopics, kafkausers)" "$r" \
  "Reinstala el operador; los CRDs los crea el chart (Guía 3 / Guía 4)."

# 9. El operador vigila meridiano-pagos (línea namespaces='[...]' en los logs).
linea_ns=$(kubectl logs deployment/strimzi-cluster-operator -n "$NS_SISTEMA" --context "$CONTEXTO" 2>/dev/null \
  | grep -m1 "namespaces=" || true)
if printf '%s' "$linea_ns" | grep -q "$NS_PAGOS"; then r=0; else r=1; fi
verificar "El operador vigila ${NS_PAGOS}" "$r" \
  "Tu mi-values.yaml no quedó con watchNamespaces correcto; corrígelo con helm upgrade (Guía 3)."

# 10. API v1 servida por el CRD kafkas.
versiones_api=$(kubectl get crd kafkas.kafka.strimzi.io --context "$CONTEXTO" \
  -o jsonpath='{.spec.versions[*].name}' 2>/dev/null || true)
if printf '%s' "$versiones_api" | tr ' ' '\n' | grep -qx "v1"; then r=0; else r=1; fi
verificar "El CRD kafkas sirve la API v1" "$r" \
  "Verifica la versión del chart instalada; v1 llega con Strimzi 0.51 (Guía 4)."

# --- Resumen ---
echo
if [ "$aprobadas" -eq "$total" ]; then
  msg_ok "${aprobadas}/${total} verificaciones correctas"
  msg_ok "Lab 01 completado correctamente"
  exit 0
else
  msg_error "${aprobadas}/${total} verificaciones correctas"
  msg_error "Lab 01 incompleto: revisa los [ERROR] de arriba"
  exit 1
fi
