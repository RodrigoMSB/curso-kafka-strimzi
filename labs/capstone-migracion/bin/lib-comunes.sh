#!/usr/bin/env bash
# Funciones comunes del Capstone "La migración" de Banco Meridiano.
msg_ok()    { printf '[OK] %s\n' "$*"; }
msg_info()  { printf '[INFO] %s\n' "$*"; }
msg_error() { printf '[ERROR] %s\n' "$*" >&2; }
verificar_comando() { if command -v "$1" >/dev/null 2>&1; then return 0; else return 1; fi; }

# Nombre del contenedor del Kafka legado y su imagen (la del curso).
LEGADO_NOMBRE="${LEGADO_NOMBRE:-kafka-legado}"
LEGADO_IMG="${LEGADO_IMG:-quay.io/strimzi/kafka:0.51.0-kafka-4.2.0}"
LEGADO_TOPICO="legado.transferencias"

# ¿El contenedor del legado está corriendo? (0 = sí).
legado_corriendo() { [ -n "$(docker ps -q -f name="^${LEGADO_NOMBRE}$" 2>/dev/null)" ]; }

# Memoria del Docker VM en uso por contenedores (suma de MemUsage), en MiB.
# Devuelve "?" si no se puede calcular.
memoria_docker_mib() {
  docker stats --no-stream --format '{{.MemUsage}}' 2>/dev/null \
    | awk '{u=$1; if (u ~ /GiB/){sub(/GiB/,"",u); s+=u*1024} else if (u ~ /MiB/){sub(/MiB/,"",u); s+=u} } END{ if (NR>0) printf "%d", s; else printf "?" }'
}

# Decodifica base64 de una sola línea de forma portable (macOS y WSL2).
b64d() { openssl base64 -d -A; }

# Lee la contraseña SCRAM de un Secret de KafkaUser.
# Uso: pw_de_usuario <usuario> <ns> <ctx>
pw_de_usuario() {
  kubectl get secret "$1" -n "$2" --context "$3" -o jsonpath='{.data.password}' 2>/dev/null | b64d
}

# Imagen de Kafka tomada de un broker real de pagos (o el default del curso).
# Uso: imagen_kafka <ns> <ctx>
imagen_kafka() {
  img=$(kubectl get pods -n "$1" --context "$2" \
    -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.containers[0].image}{"\n"}{end}' 2>/dev/null \
    | grep '^pagos-brokers-' | head -1 | cut -d' ' -f2)
  [ -z "$img" ] && img="$LEGADO_IMG"
  printf '%s' "$img"
}

# Cuenta los mensajes del tópico destino sumando los offsets finales de todas las
# particiones (kafka-get-offsets.sh con auth). Fiable incluso con tráfico vivo,
# a diferencia de un consumidor con timeout. Imprime un entero.
# Uso: contar_destino <ctx> <ns> <img> <usuario> <password> <topico> <tag>
contar_destino() {
  ct_ctx=$1; ct_ns=$2; ct_img=$3; ct_user=$4; ct_pw=$5; ct_topic=$6; ct_tag=${7:-x}
  kubectl run "contador-mig-${ct_tag}" --rm -i --restart=Never -n "$ct_ns" --context "$ct_ctx" \
    --image="$ct_img" --command -- bash -c "
      printf 'security.protocol=SASL_PLAINTEXT\nsasl.mechanism=SCRAM-SHA-512\nsasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username=\"${ct_user}\" password=\"${ct_pw}\";\n' > /tmp/c.properties
      exec /opt/kafka/bin/kafka-get-offsets.sh --bootstrap-server pagos-kafka-bootstrap:9094 --command-config /tmp/c.properties --topic ${ct_topic} --time -1
    " 2>/dev/null | awk -F: '{s+=$3} END{printf "%d", s+0}'
}

# Vuelca un SNAPSHOT FIEL de TODO el tópico destino, robusto frente a tráfico
# vivo: captura los offsets finales por partición y lee CADA partición hasta su
# offset (con --partition + --max-messages), en vez de leer N mensajes globales
# (que con un productor vivo puede detenerse antes de drenar la cola de alguna
# partición — lectura no determinista). Autentica con SCRAM. Pod efímero.
# Uso: volcar_destino <ctx> <ns> <img> <usuario> <password> <topico> <tag>
volcar_destino() {
  vd_ctx=$1; vd_ns=$2; vd_img=$3; vd_user=$4; vd_pw=$5; vd_topic=$6; vd_tag=${7:-x}
  kubectl run "volcado-mig-${vd_tag}" --rm -i --restart=Never -n "$vd_ns" --context "$vd_ctx" \
    --image="$vd_img" --command -- bash -c "
      printf 'security.protocol=SASL_PLAINTEXT\nsasl.mechanism=SCRAM-SHA-512\nsasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username=\"${vd_user}\" password=\"${vd_pw}\";\n' > /tmp/c.properties
      OFFS=\$(/opt/kafka/bin/kafka-get-offsets.sh --bootstrap-server pagos-kafka-bootstrap:9094 --command-config /tmp/c.properties --topic ${vd_topic} --time -1)
      echo \"\$OFFS\" | while IFS=: read t p o; do
        [ \"\$o\" -gt 0 ] && /opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server pagos-kafka-bootstrap:9094 --consumer.config /tmp/c.properties --topic ${vd_topic} --partition \"\$p\" --offset earliest --max-messages \"\$o\" --timeout-ms 60000 2>/dev/null
      done
    " 2>/dev/null
}

# A partir de un volcado de mensajes JSON {"id":N,...} en stdin, imprime una línea:
#   <min> <max> <distintos> <esperados>
# donde esperados = max-min+1. La serie es continua (sin huecos) si distintos==esperados.
analizar_ids() {
  grep -o '"id":[0-9]\{1,\}' | sed 's/[^0-9]//g' | sort -n | uniq | awk '
    NR==1{min=$1} {max=$1; c++} END{ if(c==0){print "0 0 0 0"} else {print min, max, c, (max-min+1)} }'
}

# Ejecuta la SOLUCIÓN DE REFERENCIA de la migración de punta a punta (la usan el
# 95 y el 91). Asume la plataforma del Lab 07 ya en pie. Imprime los números.
# Uso: ejecutar_migracion <ctx> <nsp> <sol_dir> <bin_dir>
ejecutar_migracion() {
  em_ctx=$1; em_nsp=$2; em_sol=$3; em_bin=$4
  em_img=$(imagen_kafka "$em_nsp" "$em_ctx")

  msg_info "[migración] 1/6 Desplegando el Kafka legado (historia + tráfico vivo)..."
  bash "$em_bin/01-desplegar-legado.sh"

  msg_info "[migración] 2/6 Declarando tópico destino (RF=3), identidades y el espejo MM2..."
  kubectl apply --context "$em_ctx" -f "$em_sol/topicos/10-kafkatopic-legado-transferencias.yaml" >/dev/null
  kubectl apply --context "$em_ctx" -f "$em_sol/usuarios/10-kafkauser-mm2-migracion.yaml" >/dev/null
  kubectl apply --context "$em_ctx" -f "$em_sol/usuarios/20-kafkauser-transferencias.yaml" >/dev/null
  kubectl wait --for=condition=Ready kafkauser/mm2-migracion -n "$em_nsp" --context "$em_ctx" --timeout=180s || true
  kubectl wait --for=condition=Ready kafkauser/transferencias -n "$em_nsp" --context "$em_ctx" --timeout=180s || true
  kubectl apply --context "$em_ctx" -f "$em_sol/mm2/30-mirrormaker2-migracion.yaml" >/dev/null
  kubectl wait --for=condition=Ready kafkamirrormaker2/migracion-legado-a-pagos -n "$em_nsp" --context "$em_ctx" --timeout=600s || true

  em_pw=$(pw_de_usuario mm2-migracion "$em_nsp" "$em_ctx")
  em_semilla=$(kubectl get configmap migracion-estado -n "$em_nsp" --context "$em_ctx" -o jsonpath='{.data.semilla}' 2>/dev/null || echo 0)
  printf '%s' "$em_semilla" | grep -q '^[0-9]\{1,\}$' || em_semilla=0

  msg_info "[migración] 3/6 Esperando paridad de la historia (destino >= ${em_semilla})..."
  em_total=0
  for i in $(seq 1 40); do
    em_total=$(contar_destino "$em_ctx" "$em_nsp" "$em_img" mm2-migracion "$em_pw" "$LEGADO_TOPICO" "wp${i}")
    printf '%s' "$em_total" | grep -q '^[0-9]\{1,\}$' || em_total=0
    [ "$em_total" -ge "$em_semilla" ] && [ "$em_semilla" -gt 0 ] && break
    sleep 10
  done
  msg_ok "[migración] Paridad de historia alcanzada: ${em_total} mensajes en el destino (semilla=${em_semilla})."

  msg_info "[migración] 4/6 Cutover: cortar el legado y arrancar el productor nuevo en la plataforma..."
  bash "$em_bin/02-cutover-productor.sh"
  em_ultimo=$(kubectl get configmap migracion-estado -n "$em_nsp" --context "$em_ctx" -o jsonpath='{.data.ultimo-id-legado}' 2>/dev/null || echo 0)

  msg_info "[migración] 5/6 Esperando que MM2 drene toda la historia del legado (hasta ID ${em_ultimo})..."
  for i in $(seq 1 30); do
    em_dump=$(volcar_destino "$em_ctx" "$em_nsp" "$em_img" mm2-migracion "$em_pw" "$LEGADO_TOPICO" "dd${i}")
    set -- $(printf '%s\n' "$em_dump" | grep '"origen":"legado"' | analizar_ids); em_lmax=$2
    set -- $(printf '%s\n' "$em_dump" | grep '"origen":"plataforma"' | analizar_ids); em_pmin=$1
    if [ "${em_lmax:-0}" -ge "${em_ultimo:-1}" ] 2>/dev/null && [ "${em_pmin:-0}" -gt 0 ] 2>/dev/null; then
      msg_ok "[migración] Drenaje completo: legado hasta ${em_lmax}, plataforma desde ${em_pmin} (frontera limpia)."
      break
    fi
    sleep 8
  done

  msg_info "[migración] 6/6 Decomiso: apagar el espejo de migración y el Kafka legado..."
  bash "$em_bin/03-decomisar-legado.sh" --si
  msg_ok "[migración] Secuencia de migración completada."
}
