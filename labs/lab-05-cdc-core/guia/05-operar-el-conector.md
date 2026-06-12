# Guía 5 — Operar el conector

Un conector de CDC en un banco no es "fire and forget": se pausa para
mantenimiento, sobrevive a caídas del core y se reincorpora sin perder eventos.
Veámoslo.

## Pausar y reanudar (declarativo)

El estado del conector se controla con el campo `spec.state` del `KafkaConnector`
(valores: `running`, `paused`, `stopped`). Para pausarlo, edita tu copia:

```yaml
spec:
  state: paused
  class: io.debezium.connector.postgresql.PostgresConnector
  ...
```

```bash
kubectl apply -n meridiano-pagos -f mi-connector.yaml
kubectl get kafkaconnector core-clientes -n meridiano-pagos \
  -o jsonpath='{.status.connectorStatus.connector.state}{"\n"}'
```

```text
Salida esperada (puede variar levemente)
PAUSED
```

Pausado, Debezium deja de emitir, pero **recuerda dónde quedó** (su posición en
el WAL, guardada en el tópico de offsets). Para reanudar, vuelve a `running` (o
quita el campo) y aplica. No se pierde nada en el intervalo.

## Simulacro: "se cayó el core"

Tira el core a cero réplicas y observa qué hace el conector:

```bash
kubectl scale deployment/core-postgres -n meridiano-core --replicas=0
```

Mira el estado del conector y su tarea: la tarea pasará a `FAILED` o reintentará
(no puede hablar con una base que no está):

```bash
kubectl get kafkaconnector core-clientes -n meridiano-pagos \
  -o jsonpath='{.status.connectorStatus.tasks[*].state}{"\n"}'
```

Mientras tanto, **produce un cambio que el conector aún no vio** no es posible
(la base está caída). Levanta el core de nuevo:

```bash
kubectl scale deployment/core-postgres -n meridiano-core --replicas=1
kubectl rollout status deployment/core-postgres -n meridiano-core
```

> **Nota:** el core de este lab usa almacenamiento efímero, así que al recrearse
> el pod la tabla vuelve al estado semilla (el init corre de nuevo). Lo que nos
> interesa observar aquí es la **recuperación del conector**: su tarea vuelve a
> `RUNNING` sola, retomando desde su última posición guardada. En un core real
> con disco persistente, los cambios hechos antes de la caída también estarían.

Verifica que el conector se recuperó:

```bash
kubectl get kafkaconnector core-clientes -n meridiano-pagos \
  -o jsonpath='{.status.connectorStatus.tasks[*].state}{"\n"}'
```

```text
Salida esperada (puede variar levemente)
RUNNING
```

El conector guarda su progreso en Kafka (el tópico de offsets), no en su memoria:
por eso una caída no le hace perder el hilo. Esa es la resiliencia que un banco
necesita.

## Verificación final del lab

```bash
bash bin/90-test-lab.sh
```

## Desafío extra (post-sesión)

Añade una segunda tabla (`cuentas`) al `table.include.list` y verifica que su
tópico de CDC nace solo. La resolución está en `soluciones/desafio-segunda-tabla.md`.

## Cierre del Capítulo 4 (parte 1)

El core legado ya habla el idioma de la plataforma: cada cambio en su base es un
evento Kafka, con su antes y su después, sin haber tocado el código del core. El
puente entre el banco viejo y el nuevo está tendido.
