# Guía 2 — El core del banco

Desplegamos el PostgreSQL del core. Vive en **su propio namespace**,
`meridiano-core`, separado de la plataforma de pagos: quien administra el core no
es quien administra Kafka. Es gobernanza, no capricho.

> PostgreSQL no es contenido de este curso: lee los manifiestos, no los
> escribas. Lo importante es **qué hay que preparar para CDC**.

## Despliega el core

```bash
bash bin/02-desplegar-core.sh
```

Esto aplica `infra/core/` (namespace, Secret, init y el Deployment+Service) y
espera a que PostgreSQL esté listo con la tabla semilla.

```bash
kubectl get pods -n meridiano-core
kubectl exec -n meridiano-core deploy/core-postgres -- \
  psql -U postgres -d meridiano -c "SELECT id, nombre, saldo FROM clientes"
```

```text
Salida esperada (puede variar levemente)
 id |   nombre   | saldo
----+------------+--------
  1 | Ana Perez  | 1500.00
  2 | Beto Soto  | 3200.50
  3 | Carla Diaz |  780.25
```

## Lo que CDC exige de PostgreSQL (y por qué)

Tres preparativos, que verás en `infra/core/`:

1. **`wal_level=logical`** (argumento del contenedor PostgreSQL). Sin esto,
   PostgreSQL no escribe en el WAL la información suficiente para la
   **decodificación lógica** que Debezium necesita. Es el interruptor maestro de
   CDC.
2. **`REPLICA IDENTITY FULL`** en la tabla. Define cuánta información del estado
   **anterior** de una fila se registra en el WAL. Con `DEFAULT`, en un UPDATE o
   DELETE solo se captura la clave primaria; con `FULL`, se captura la fila
   entera. Para una auditoría bancaria, queremos el `before` completo.
3. **Un usuario de replicación** (`debezium`, con `REPLICATION LOGIN`) y una
   **publicación** (`dbz_publication FOR ALL TABLES`). La publicación la crea el
   superusuario en el init, así el usuario `debezium` —que **no** es superusuario—
   solo necesita leer, no crear nada. Mínimo privilegio también en la base.

> El plugin de decodificación es **`pgoutput`**, nativo de PostgreSQL: no hay que
> instalar extensiones en la base.

Con el core listo y preparado para CDC, en la siguiente guía construimos el
equipo de Connect que lo va a leer.
