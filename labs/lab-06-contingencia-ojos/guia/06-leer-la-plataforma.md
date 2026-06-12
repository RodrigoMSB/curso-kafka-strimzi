# Guía 6 — Leer la plataforma

Con el port-forward de Grafana abierto (`http://localhost:3000`), abre el
dashboard **Strimzi Kafka** (carpeta *Strimzi*). Vamos a leer la plataforma.

## Las 4 métricas que un administrador mira primero

1. **Mensajes por segundo (throughput).** ¿Cuánto está moviendo el clúster? Una
   caída brusca a cero suele significar que algo dejó de producir o consumir.
2. **Particiones sub-replicadas (under-replicated partitions).** Debe ser **0**.
   Si sube, hay réplicas que no están al día: un broker en problemas, riesgo de
   pérdida de datos. Es la métrica de alarma número uno.
3. **Uso de disco.** Los brokers que se quedan sin disco **se caen**. Se vigila
   la tendencia para reaccionar antes del 100%.
4. **Lag de consumidores.** ¿Los consumidores van al día o se quedan atrás? Un
   lag que crece sin parar significa que el consumo no da abasto.

## Genera carga y mira el dashboard moverse

Produce un lote como `app-pagos` y observa el panel de mensajes/s subir:

```bash
kubectl exec -i cliente-kafka -n meridiano-pagos -- bash -c \
  'for i in $(seq 1 5000); do echo "carga-$i"; done | bin/kafka-console-producer.sh \
   --bootstrap-server pagos-kafka-bootstrap:9094 \
   --producer.config /props/app-pagos.properties \
   --topic pagos.meridiano.transacciones'
```

En Grafana (o en Prometheus, **Graph**), consulta una métrica viva, por ejemplo
las particiones por broker:

```text
kafka_server_replicamanager_partitioncount
```

Verás series con datos: la plataforma ya no es una caja negra.

## Mención honesta: el tracing

El temario nombra el **tracing distribuido**. Las métricas responden "¿cuánto y
cómo de sano?"; el tracing responde **"¿por dónde pasó ESTE mensaje y cuánto tardó
en cada salto?"**: sigue una transacción a través de productores, brokers y
consumidores, midiendo la latencia de cada tramo. Strimzi lo soporta
(OpenTelemetry), pero su despliegue completo —un colector y un backend como
Jaeger— excede este lab. Quédate con la idea: **métricas para el estado del
sistema, tracing para el viaje de un mensaje.**

## Verificación final del lab

```bash
bash bin/90-test-lab.sh
```

## Desafío extra (parte 2)

Encuentra en Prometheus la métrica de **lag de MM2** (los espejos también se
observan) y explica qué pasaría con el RPO si ese lag crece. Resolución en
`soluciones/desafio-lag-mm2.md`.

## Cierre del Capítulo 4

La plataforma de Meridiano ya tiene **contingencia** (un DR que recibe el río de
eventos) y **ojos** (métricas y dashboards para operarla). Un banco no opera a
ciegas ni sin red: ahora la plataforma tampoco.
