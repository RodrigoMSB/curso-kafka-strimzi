# Guía 6 — La puerta HTTP (Kafka Bridge)

> Anexo del Lab 04. Hasta aquí abrimos y cerramos puertas del **protocolo Kafka**.
> Pero en Meridiano hay un inquilino que no habla ese idioma.

## Por qué existe esta puerta

En el banco hay un sistema viejo —un motor de reglas, un ERP, un webhook de un
tercero— que **solo sabe hablar HTTP**. No entiende el protocolo binario de Kafka,
no sabe hacer el handshake de SCRAM ni presentar un certificado de cliente. Con
lo que construimos hasta la guía 05, ese sistema **se queda afuera**: todas
nuestras puertas exigen hablar Kafka.

La tentación fácil sería abrirle un listener plano sin autenticación —un agujero
en el muro— para que entre "como pueda". Eso es exactamente lo que el Lab 04
enseña a **no** hacer.

El **Kafka Bridge** es la respuesta correcta: un **traductor**. Habla **HTTP hacia
afuera** (lo que el sistema viejo entiende) y **Kafka autenticado hacia adentro**
(SCRAM contra el listener interno seguro, con su propia identidad y sus ACLs de
mínimo privilegio). El cliente HTTP nunca ve una credencial de Kafka; el clúster
nunca ve un cliente sin autenticar. El puente no es un agujero: es una puerta con
su propio guardia.

## 1. Despliega el puente (tu manifiesto)

> **La plantilla es el camino; `soluciones/` es para comparar.** Trabaja sobre tu
> copia.

```bash
cp plantillas/30-bridge.yaml mi-bridge.yaml
```

Completa los dos TODO de `mi-bridge.yaml`:

- **TODO A** — las operaciones de la ACL del `KafkaUser bridge-http`. Mínimo
  privilegio para un puente que **produce y consume** su tópico: `Describe`,
  `Read`, `Write`.
- **TODO B** — el `bootstrapServers` del `KafkaBridge`: el listener **interno
  seguro** (SCRAM), no el plano. Es `pagos-kafka-bootstrap:9094`.

Fíjate en lo que ya viene resuelto: el puente tiene su **propio tópico**
(`pagos.meridiano.http`) y su ACL **no toca** `pagos.meridiano.transacciones`. El
sistema HTTP entra a su propia sala, no al core de pagos.

Aplica **lo tuyo** y espera:

```bash
kubectl apply -n meridiano-pagos -f mi-bridge.yaml
kubectl wait --for=condition=Ready kafkabridge/puente-http -n meridiano-pagos --timeout=300s
```

```text
Salida esperada (puede variar levemente)
kafkabridge.kafka.strimzi.io/puente-http condition met
```

Strimzi levanta un pod `puente-http-bridge-*` y un servicio
`puente-http-bridge-service` en el puerto 8080. Si tu `KafkaUser` quedó
`NotReady`, compáralo con `soluciones/30-bridge.yaml`.

## 2. Produce por HTTP, míralo salir por Kafka

Como en el Lab 06 con Prometheus/Grafana, no exponemos el puente a Internet:
llegamos por un túnel. En **una terminal**, abre el port-forward:

```bash
kubectl port-forward -n meridiano-pagos svc/puente-http-bridge-service 8080:8080
```

En **otra terminal**, produce un mensaje **con un simple `curl`** —sin cliente
Kafka, sin credenciales de Kafka, solo HTTP:

```bash
curl -X POST http://localhost:8080/topics/pagos.meridiano.http \
  -H 'Content-Type: application/vnd.kafka.json.v2+json' \
  -d '{"records":[{"value":{"origen":"sistema-http","monto":15000}}]}'
```

```text
Salida esperada (puede variar levemente)
{"offsets":[{"partition":2,"offset":0}]}
```

El puente responde con la **partición y el offset** donde aterrizó el mensaje.
Entró por HTTP; ya es un mensaje Kafka de pleno derecho. **Compruébalo con un
consumidor Kafka normal** (autenticado como el propio puente, por SCRAM):

```bash
PW=$(kubectl get secret bridge-http -n meridiano-pagos -o jsonpath='{.data.password}' | openssl base64 -d -A)
kubectl run ver-kafka --rm -i --restart=Never -n meridiano-pagos \
  --image=quay.io/strimzi/kafka:0.51.0-kafka-4.2.0 --command -- bash -c "
  printf 'security.protocol=SASL_PLAINTEXT\nsasl.mechanism=SCRAM-SHA-512\nsasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username=\"bridge-http\" password=\"$PW\";\n' > /tmp/c.properties
  bin/kafka-console-consumer.sh --bootstrap-server pagos-kafka-bootstrap:9094 \
    --consumer.config /tmp/c.properties --topic pagos.meridiano.http \
    --from-beginning --timeout-ms 15000"
```

```text
Salida esperada (puede variar levemente)
{"origen":"sistema-http","monto":15000}
```

**Entró por HTTP, salió por Kafka.** Esa es la traducción: el sistema viejo habló
su idioma y el mensaje llegó al río de eventos, autenticado y con permisos
mínimos.

## 3. Consume por HTTP

El puente también traduce en el otro sentido. La API HTTP de consumo son tres
pasos: crear un consumidor, suscribirlo a un tópico y hacer *poll*. Usa el mismo
port-forward:

```bash
# 1) Crear el consumidor (en el grupo 'puente-http-grupo')
curl -X POST http://localhost:8080/consumers/puente-http-grupo \
  -H 'Content-Type: application/vnd.kafka.v2+json' \
  -d '{"name":"mi-lector","format":"json","auto.offset.reset":"earliest"}'

# 2) Suscribirlo al tópico
curl -X POST http://localhost:8080/consumers/puente-http-grupo/instances/mi-lector/subscription \
  -H 'Content-Type: application/vnd.kafka.v2+json' \
  -d '{"topics":["pagos.meridiano.http"]}'

# 3) Hacer poll (el PRIMER poll suele venir vacío: la suscripción tarda un
#    instante en asignar particiones; repite el comando una o dos veces)
curl http://localhost:8080/consumers/puente-http-grupo/instances/mi-lector/records \
  -H 'Accept: application/vnd.kafka.json.v2+json'
```

```text
Salida esperada (puede variar levemente)
[{"topic":"pagos.meridiano.http","key":null,"value":{"origen":"sistema-http","monto":15000},"partition":2,"offset":0}]
```

Cuando termines, borra el consumidor (buena higiene: libera su sesión en el
grupo):

```bash
curl -X DELETE http://localhost:8080/consumers/puente-http-grupo/instances/mi-lector
```

## Verificación

```bash
bash bin/90-test-lab.sh
```

Debe quedar todo en verde, incluidos los dos checks nuevos del puente: el
`KafkaBridge` en `Ready` y el round-trip real **HTTP → Kafka**.

## Cierre

El Lab 04 abrió puertas seguras del protocolo Kafka (guías 02–04), cerró la vieja
puerta plana (guía 05) y, con esta guía, le dio entrada al que **no puede hablar
Kafka** —sin abrir un agujero—. Tres formas de exponer la plataforma, y ninguna
sin credenciales: esa es la puerta segura completa.
