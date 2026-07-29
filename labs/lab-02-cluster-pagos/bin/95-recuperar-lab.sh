#!/usr/bin/env bash
# Recuperación del Lab 02: reconstruye el ESTADO FINAL del lab (clúster Kafka de
# pagos persistente, con rack y el tópico creado) sin interacción.
#
# Encadena el 95 del Lab 01 (clúster + operador) y luego despliega el ESTADO
# FINAL del Lab 02: los nodepools persistentes de soluciones/parte-2-persistente/
# más el Kafka con rack de soluciones/parte-3-rack/. Se declara exitoso solo si
# el test 90 del Lab 02 pasa: hereda su exit code.
#
# LAB01_CLUSTER permite usar otro nombre de clúster (consistente con el molde).
set -euo pipefail

DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"

export LAB01_CLUSTER="${LAB01_CLUSTER:-meridiano}"
NOMBRE_CLUSTER="$LAB01_CLUSTER"
CONTEXTO="kind-${NOMBRE_CLUSTER}"
NS="meridiano-pagos"
CLUSTER="pagos"
BOOTSTRAP="pagos-kafka-bootstrap:9092"
TOPICO="pagos.meridiano.transacciones"
LAB01_95="$DIR_SCRIPT/../../lab-01-cimientos/bin/95-recuperar-lab.sh"
# Estado final = nodepools persistentes (parte 2) + Kafka con rack (parte 3).
# Los nodepools NO cambian entre la parte 2 y la 3: rack es un cambio solo en el
# Kafka CR, aplicable en caliente (ver guía 05).
SOL_PERSISTENTE="$DIR_SCRIPT/../soluciones/parte-2-persistente"
SOL_RACK="$DIR_SCRIPT/../soluciones/parte-3-rack"
TIMEOUT_KAFKA="600s"
TIMEOUT_BORRADO="300s"

msg_info "Este script reconstruye el resultado del Lab 02 sin pasar por las guías."
msg_info "Úsalo solo para ponerte al día; el aprendizaje está en las guías."
echo

# 1. Estado final del Lab 01 (clúster + operador). Su 95 termina ejecutando su
#    propio test 90; si falla, no seguimos.
msg_info "Reconstruyendo primero el estado del Lab 01..."
if ! bash "$LAB01_95" >/tmp/lab02-lab01-95.out 2>&1; then
  msg_error "La recuperación del Lab 01 falló. Detalle:"
  tail -n 15 /tmp/lab02-lab01-95.out | sed 's/^/    /'
  exit 1
fi
msg_ok "Estado del Lab 01 reconstruido."

# 2. Etiquetar zonas ANTES de aplicar el clúster con rack.
bash "$DIR_SCRIPT/01-etiquetar-zonas.sh"

# 3. Detección: ¿el clúster ya existe con un storage que NO se puede migrar en
#    caliente? Es la trampa que enseña el propio Lab 02: si el clúster está en
#    efímero (estado de la parte 1) el operador IGNORA el cambio de storage
#    ("all storage changes will be ignored") y el clúster queda Ready pero sin
#    PVCs. Aplicar encima no arregla nada: hay que destruir y recrear.
#
#    Se recrea si se cumple cualquiera de estas condiciones:
#      a) el pool de brokers declara storage efímero, o
#      b) existe el Kafka, el pool declara persistent-claim y NO hay ni un PVC
#         de brokers (el operador ignoró el cambio en una corrida anterior), o
#      c) NO existe el Kafka pero sí quedan PVCs de brokers: son discos
#         huérfanos de un clúster borrado a mano y traen un cluster.id que el
#         clúster nuevo rechazaría (ver la nota de los PVC más abajo).
#    NO se recrea si no hay nada (construcción desde cero, camino normal) ni si
#    el clúster está sano con sus PVCs (el estado ya es correcto).
necesita_recrear=0
motivo=""

# Tipo de storage declarado por el pool de brokers. Con jbod el tipo real está
# en el primer volumen; con storage plano (no jbod) está en .spec.storage.type.
# Vacío si el pool no existe.
tipo_storage=$(kubectl get kafkanodepool brokers -n "$NS" --context "$CONTEXTO" \
  -o jsonpath='{.spec.storage.volumes[0].type}' 2>/dev/null || true)
if [ -z "$tipo_storage" ]; then
  tipo_storage=$(kubectl get kafkanodepool brokers -n "$NS" --context "$CONTEXTO" \
    -o jsonpath='{.spec.storage.type}' 2>/dev/null || true)
fi

# PVCs de los brokers. Se cuentan por el nombre (data-<vol>-pagos-brokers-<id>)
# y no por etiqueta: el nombre es estable entre versiones del operador y es el
# mismo criterio que usa el test 90.
pvcs_brokers=$(kubectl get pvc -n "$NS" --context "$CONTEXTO" \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null \
  | grep -c "${CLUSTER}-brokers-" || true)

kafka_existe=$(kubectl get kafka "$CLUSTER" -n "$NS" --context "$CONTEXTO" \
  -o name 2>/dev/null || true)

if [ "$tipo_storage" = "ephemeral" ]; then
  necesita_recrear=1
  motivo="el pool de brokers está en storage efímero"
elif [ -n "$kafka_existe" ] && [ "$tipo_storage" = "persistent-claim" ] \
     && [ "$pvcs_brokers" -eq 0 ]; then
  necesita_recrear=1
  motivo="el pool de brokers declara discos persistentes pero no existe ninguno"
elif [ -z "$kafka_existe" ] && [ "$pvcs_brokers" -gt 0 ]; then
  necesita_recrear=1
  motivo="quedaron discos huérfanos de un clúster anterior ya borrado"
fi

# Destruye el clúster de pagos por completo y deja el namespace listo para
# reconstruirlo desde cero. Se usa en la detección previa y también como
# reparación si el clúster no llega a Ready por un cluster.id incompatible.
recrear_cluster() {
  kubectl delete kafka "$CLUSTER" -n "$NS" --context "$CONTEXTO" \
    --ignore-not-found --timeout="$TIMEOUT_BORRADO" || true
  kubectl delete kafkanodepool brokers controllers -n "$NS" --context "$CONTEXTO" \
    --ignore-not-found --timeout="$TIMEOUT_BORRADO" || true

  # Paso obligatorio: si el apply llega mientras los pods viejos agonizan, el
  # operador vuelve a ignorar el cambio de storage y se cae en el mismo pozo.
  msg_info "Esperando a que los pods del clúster desaparezcan (máximo ${TIMEOUT_BORRADO})..."
  kubectl wait --for=delete pod -l strimzi.io/cluster="$CLUSTER" -n "$NS" \
    --context "$CONTEXTO" --timeout="$TIMEOUT_BORRADO" >/dev/null 2>&1 || true

  # Confirmación activa: 'wait --for=delete' devuelve de inmediato si el
  # selector no encontró nada, así que se comprueba a mano que no quede ninguno.
  restantes=1
  intento=0
  while [ "$intento" -lt 60 ]; do
    restantes=$(kubectl get pods -n "$NS" --context "$CONTEXTO" \
      -l "strimzi.io/cluster=${CLUSTER}" -o name 2>/dev/null | grep -c . || true)
    [ "$restantes" -eq 0 ] && break
    intento=$((intento + 1))
    sleep 5
  done
  if [ "$restantes" -ne 0 ]; then
    msg_error "Quedan ${restantes} pods del clúster anterior tras esperar el borrado."
    msg_error "Revisa 'kubectl get pods -n ${NS}' y vuelve a ejecutar este script."
    exit 1
  fi

  # Los discos del clúster anterior SOBREVIVEN al borrado: los manifiestos usan
  # deleteClaim: false (deliberado, es la "historia de terror" de la guía 04).
  # Pero el clúster que se reconstruye nace con un cluster.id de KRaft NUEVO, y
  # un PVC viejo trae el anterior en su meta.properties. Si se reutilizan, los
  # brokers arrancan y mueren en bucle con:
  #   Invalid cluster.id in: /var/lib/kafka/data-0/kafka-log0/meta.properties
  # Por eso hay que retirarlos: se recrea sobre discos limpios. Solo se tocan
  # los del clúster 'pagos' (selector por etiqueta), nunca los de otros
  # componentes del namespace. Se borran DESPUÉS de que los pods se fueron: un
  # PVC en uso queda bloqueado por su finalizador y el borrado se colgaría.
  msg_info "Retirando los discos del clúster anterior (traen otro cluster.id de KRaft)..."
  kubectl delete pvc -n "$NS" --context "$CONTEXTO" \
    -l "strimzi.io/cluster=${CLUSTER}" --ignore-not-found --timeout="$TIMEOUT_BORRADO" || true

  pvcs_restantes=1
  intento=0
  while [ "$intento" -lt 36 ]; do
    pvcs_restantes=$(kubectl get pvc -n "$NS" --context "$CONTEXTO" \
      -l "strimzi.io/cluster=${CLUSTER}" -o name 2>/dev/null | grep -c . || true)
    [ "$pvcs_restantes" -eq 0 ] && break
    intento=$((intento + 1))
    sleep 5
  done
  if [ "$pvcs_restantes" -ne 0 ]; then
    msg_error "Quedan ${pvcs_restantes} PVCs del clúster anterior sin borrar."
    msg_error "Revisa 'kubectl get pvc -n ${NS}' y vuelve a ejecutar este script."
    exit 1
  fi

  msg_ok "Clúster anterior eliminado; se reconstruye desde cero."
  echo
}

if [ "$necesita_recrear" -eq 1 ]; then
  echo
  msg_info "El clúster existe con storage efímero (o sin discos creados): ${motivo}."
  msg_info "El storage de Kafka NO se puede cambiar en caliente: hay que recrear."
  msg_info "Destruyendo y reconstruyendo el clúster (los datos de prueba se pierden)..."
  recrear_cluster
fi

# Espera a que el clúster refleje DE VERDAD el último cambio aplicado.
#
# Un 'kubectl wait --for=condition=Ready' a secas no sirve justo después de un
# apply: el CR conserva el Ready de la reconciliación anterior, así que el wait
# vuelve de inmediato, antes de que el operador haya empezado siquiera el
# rolling. Por eso se exige además que observedGeneration haya alcanzado a
# metadata.generation: es lo que el operador actualiza cuando TERMINA de
# reconciliar el spec actual. Al final se rematan los pods, que es lo que mira
# el test 90.
#
# El argumento es el número de vueltas de 5s (120 -> 600s).
esperar_kafka_listo() {
  vueltas_max="$1"
  vuelta=0
  while [ "$vuelta" -lt "$vueltas_max" ]; do
    gen=$(kubectl get kafka "$CLUSTER" -n "$NS" --context "$CONTEXTO" \
      -o jsonpath='{.metadata.generation}' 2>/dev/null || true)
    obs=$(kubectl get kafka "$CLUSTER" -n "$NS" --context "$CONTEXTO" \
      -o jsonpath='{.status.observedGeneration}' 2>/dev/null || true)
    ready=$(kubectl get kafka "$CLUSTER" -n "$NS" --context "$CONTEXTO" \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    if [ -n "$gen" ] && [ "$gen" = "$obs" ] && [ "$ready" = "True" ]; then
      kubectl wait --for=condition=Ready pod -l "strimzi.io/cluster=${CLUSTER}" \
        -n "$NS" --context "$CONTEXTO" --timeout=300s >/dev/null 2>&1 || true
      return 0
    fi
    vuelta=$((vuelta + 1))
    sleep 5
  done
  return 1
}

# Paso 1 del estado final: nodepools persistentes + Kafka de la parte 2 (todavía
# SIN rack). Devuelve 1 si el clúster no queda Ready dentro del timeout.
aplicar_persistente() {
  msg_info "Aplicando el clúster de pagos (storage persistente, aún sin rack)..."
  kubectl apply -n "$NS" --context "$CONTEXTO" -f "$SOL_PERSISTENTE"
  msg_info "Esperando a que el clúster Kafka esté Ready (máximo ${TIMEOUT_KAFKA}, la primera vez baja la imagen)..."
  esperar_kafka_listo 120
}

# Paso 2 del estado final: el rack, en un apply APARTE y sobre un clúster ya
# levantado. Activar rack es un cambio en caliente y el operador lo resuelve con
# un rolling update ordenado (guía 05); separarlo del apply anterior evita que
# el rack viaje mezclado con la creación del clúster.
aplicar_rack() {
  msg_info "Aplicando el rack awareness sobre el clúster ya en marcha..."
  kubectl apply -n "$NS" --context "$CONTEXTO" -f "$SOL_RACK"
  msg_info "Esperando a que el clúster vuelva a Ready tras el rolling del rack..."
  esperar_kafka_listo 120
}

# ¿Los brokers están muriendo porque su disco trae el cluster.id de otro
# clúster? Es el síntoma de unos PVCs heredados de un clúster ya borrado; el
# mensaje del broker es inequívoco, así que no hay falsos positivos.
#
# Nada de 'algo | while ... | grep -q': con 'pipefail' activo, el grep -q corta
# al primer acierto y el productor muere con SIGPIPE, así que la función
# devolvería "no" de forma intermitente. Se recorre en el shell actual y se
# compara con 'case', sin tuberías en la decisión.
hay_cluster_id_incompatible() {
  pods_kafka=$(kubectl get pods -n "$NS" --context "$CONTEXTO" \
    -l "strimzi.io/cluster=${CLUSTER}" -o name 2>/dev/null || true)
  [ -z "$pods_kafka" ] && return 1
  hallazgos=0
  while IFS= read -r pod; do
    [ -z "$pod" ] && continue
    registro=$(kubectl logs "$pod" -n "$NS" --context "$CONTEXTO" --tail=200 2>/dev/null || true)
    case "$registro" in
      *"Invalid cluster.id"*) hallazgos=$((hallazgos + 1)) ;;
    esac
  done <<EOF
$pods_kafka
EOF
  [ "$hallazgos" -gt 0 ]
}

# 4. Levantar el clúster persistente (parte 2), todavía sin rack. El recuperador
#    no separa los estados como las guías porque no enseña, pero sí separa el
#    storage del rack: son cambios de naturaleza distinta (uno obliga a recrear,
#    el otro es en caliente) y mezclarlos en un mismo apply enturbia la espera.
if aplicar_persistente; then
  msg_ok "Clúster Kafka Ready (persistente)."
else
  # Última red de seguridad: el clúster puede no arrancar porque unos PVCs
  # heredados traen el cluster.id de un clúster anterior (pasa si el alumno
  # borró el Kafka a mano y volvió a aplicarlo: deleteClaim es false y los
  # discos sobreviven). Se detecta por el mensaje del broker, se limpia y se
  # reconstruye UNA vez.
  if hay_cluster_id_incompatible; then
    echo
    msg_info "Los brokers no arrancan: sus discos traen el cluster.id de otro clúster."
    msg_info "Son discos heredados de un clúster ya borrado y no se pueden reutilizar."
    msg_info "Destruyendo y reconstruyendo sobre discos limpios (los datos de prueba se pierden)..."
    recrear_cluster
    if aplicar_persistente; then
      msg_ok "Clúster Kafka Ready (persistente)."
    else
      msg_error "El clúster Kafka no quedó Ready en ${TIMEOUT_KAFKA}."
      msg_error "Revisa 'kubectl get pods -n ${NS}' y docs/troubleshooting.md."
      exit 1
    fi
  else
    msg_error "El clúster Kafka no quedó Ready en ${TIMEOUT_KAFKA}."
    msg_error "Revisa 'kubectl get pods -n ${NS}' y docs/troubleshooting.md."
    exit 1
  fi
fi

# 5. El rack, en un apply aparte y con el clúster ya levantado.
if aplicar_rack; then
  msg_ok "Rack awareness aplicado; clúster Kafka Ready."
else
  msg_error "El clúster no volvió a Ready tras aplicar el rack en ${TIMEOUT_KAFKA}."
  msg_error "Revisa 'kubectl get pods -n ${NS}' y docs/troubleshooting.md."
  exit 1
fi

# 6. Crear el tópico de pagos (idempotente). Imagen tomada de un broker real.
#    Si se recreó el clúster, el tópico se perdió con él y hay que rehacerlo: el
#    test 90 lo verifica con RF=3. Se reintenta porque un clúster recién Ready
#    puede tardar unos segundos en aceptar peticiones de administración.
IMG=$(kubectl get pods -n "$NS" --context "$CONTEXTO" \
  -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.containers[0].image}{"\n"}{end}' 2>/dev/null \
  | grep '^pagos-brokers-' | head -1 | cut -d' ' -f2)
[ -z "$IMG" ] && IMG="quay.io/strimzi/kafka:0.51.0-kafka-4.2.0"
msg_info "Asegurando el tópico ${TOPICO}..."
intento=1
while [ "$intento" -le 3 ]; do
  kubectl run "cli-topic-$$-${intento}" --rm -i --restart=Never -n "$NS" --context "$CONTEXTO" \
    --image="$IMG" --command -- bin/kafka-topics.sh \
    --bootstrap-server "$BOOTSTRAP" --create --if-not-exists \
    --topic "$TOPICO" --partitions 3 --replication-factor 3 \
    --config min.insync.replicas=2 >/dev/null 2>&1 || true
  existe=$(kubectl run "cli-lista-$$-${intento}" --rm -i --restart=Never -n "$NS" --context "$CONTEXTO" \
    --image="$IMG" --command -- bin/kafka-topics.sh \
    --bootstrap-server "$BOOTSTRAP" --list 2>/dev/null | grep -c "^${TOPICO}$" || true)
  [ "$existe" -ge 1 ] && break
  intento=$((intento + 1))
  sleep 10
done
if [ "${existe:-0}" -ge 1 ]; then
  msg_ok "Tópico ${TOPICO} disponible."
else
  msg_info "No se pudo confirmar el tópico ${TOPICO}; el test 90 lo dirá."
fi

# 7. Verificación final: hereda el exit code del test 90 del Lab 02.
echo
msg_info "Ejecutando el test de estado del Lab 02 (bin/90-test-lab.sh)..."
echo
exec bash "$DIR_SCRIPT/90-test-lab.sh"
