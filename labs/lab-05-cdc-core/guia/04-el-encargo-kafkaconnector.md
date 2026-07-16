# Guía 4 — El encargo (KafkaConnector) y el CDC en vivo

El equipo de Connect está listo. Hora del encargo: capturar la tabla
`public.clientes` del core.

## Completa el KafkaConnector

Sobre una copia de `plantillas/40-kafkaconnector.yaml`, completa los TODO:

**ANTES**:

```yaml
    database.password: # TODO A
    topic.prefix: # TODO B
    table.include.list: # TODO C
```

**DESPUÉS**:

```yaml
    # La contraseña se lee del archivo montado, NO va en texto plano.
    database.password: ${directory:/mnt/core-db:password}
    topic.prefix: core
    table.include.list: public.clientes
```

> Fíjate en `database.password`: es una **referencia** al config provider
> `directory`, que lee el archivo `password` del Secret montado. La contraseña
> nunca aparece en el CR ni en Git.

Aplica:

```bash
kubectl apply -n meridiano-pagos -f mi-connector.yaml
kubectl wait --for=condition=Ready kafkaconnector/core-clientes -n meridiano-pagos --timeout=300s
```

Verifica el estado del conector y su tarea:

```bash
kubectl get kafkaconnector core-clientes -n meridiano-pagos \
  -o jsonpath='{.status.connectorStatus.connector.state}{"\n"}{.status.connectorStatus.tasks[*].state}{"\n"}'
```

```text
Salida esperada (puede variar levemente)
RUNNING
RUNNING
```

Debezium hace primero un **snapshot** (lee las filas existentes) y luego sigue el
WAL en streaming.

## El momento estrella: CDC en vivo

Abre **dos terminales**.

**Terminal A — un consumidor** sobre el tópico de CDC, autenticado como
`cdc-reader`. Primero extrae su contraseña y monta un consumidor:

```bash
PW=$(kubectl get secret cdc-reader -n meridiano-pagos -o jsonpath='{.data.password}' | openssl base64 -d -A)
kubectl run cdc-watch --rm -i --restart=Never -n meridiano-pagos \
  --image=quay.io/strimzi/kafka:0.51.0-kafka-4.2.0 --command -- bash -c "
  printf 'security.protocol=SASL_PLAINTEXT\nsasl.mechanism=SCRAM-SHA-512\nsasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username=\"cdc-reader\" password=\"$PW\";\n' > /tmp/c.properties
  bin/kafka-console-consumer.sh --bootstrap-server pagos-kafka-bootstrap:9094 \
    --command-config /tmp/c.properties --topic core.public.clientes --from-beginning"
```

Verás los 3 clientes semilla (el snapshot). Déjala corriendo.

**Terminal B — cambios en el core**:

```bash
kubectl exec -n meridiano-core deploy/core-postgres -- psql -U postgres -d meridiano -c \
  "INSERT INTO clientes (nombre, email, saldo) VALUES ('Dani Luna','dani@meridiano.cl', 500.00)"

kubectl exec -n meridiano-core deploy/core-postgres -- psql -U postgres -d meridiano -c \
  "UPDATE clientes SET saldo = 999.00 WHERE nombre = 'Dani Luna'"

kubectl exec -n meridiano-core deploy/core-postgres -- psql -U postgres -d meridiano -c \
  "DELETE FROM clientes WHERE nombre = 'Dani Luna'"
```

En la Terminal A aparecen **tres eventos en vivo**, uno por cada cambio.

## El sobre de Debezium

Cada evento es un "sobre" con esta forma (JSON):

```json
{ "before": { ... }, "after": { ... }, "op": "c", "source": { ... }, "ts_ms": ... }
```

- **`op`** — la operación: `c` (create/insert), `u` (update), `d` (delete), `r` (read, del snapshot).
- **`after`** — el estado **nuevo** de la fila (en INSERT y UPDATE).
- **`before`** — el estado **anterior** (en UPDATE y DELETE; completo gracias a `REPLICA IDENTITY FULL`).

| Cambio en el core | `op` | `before` | `after` |
|---|---|---|---|
| INSERT Dani | `c` | null | la fila nueva |
| UPDATE saldo | `u` | la fila vieja (saldo 500) | la fila nueva (saldo 999) |
| DELETE Dani | `d` | la fila borrada | null |

Para un banco, esto es **auditoría perfecta del core**: cada cambio, con su antes
y su después, en un tópico inmutable. El core ya habla el idioma de la plataforma.
