# Desafío extra — capturar una segunda tabla

> Objetivo: añadir la tabla `cuentas` al CDC y ver nacer su tópico, sin recrear
> nada.

## 1. Crea la tabla en el core

Conéctate a PostgreSQL desde su propio pod y crea la tabla:

```bash
POD=$(kubectl get pod -n meridiano-core -l app=core-postgres -o name)
kubectl exec -n meridiano-core "$POD" -- psql -U postgres -d meridiano -c \
  "CREATE TABLE cuentas (id SERIAL PRIMARY KEY, cliente_id INT, tipo TEXT, saldo NUMERIC(14,2));
   ALTER TABLE cuentas REPLICA IDENTITY FULL;"
```

La publicación del conector es `FOR ALL TABLES`, así que `cuentas` ya está
incluida; no hay que tocarla.

## 2. Añade la tabla al conector

En tu copia del `KafkaConnector`, amplía `table.include.list`:

```yaml
    table.include.list: public.clientes,public.cuentas
```

Aplícalo:

```bash
kubectl apply -n meridiano-pagos -f mi-connector.yaml
```

El operador reconfigura el conector; Debezium hace un snapshot de la nueva tabla.

## 3. Genera un evento y verifica el tópico nuevo

```bash
kubectl exec -n meridiano-core "$POD" -- psql -U postgres -d meridiano -c \
  "INSERT INTO cuentas (cliente_id, tipo, saldo) VALUES (1, 'corriente', 999.99);"
```

El tópico `core.public.cuentas` nace solo y recibe el evento. Conéctate como
`motor-fraude` (o un consumidor del clúster) a `core.public.cuentas` y míralo.

```bash
kubectl get kafkatopics -n meridiano-pagos | grep core.public
```

Verás `core.public.clientes` y ahora también `core.public.cuentas`. Un conector,
muchas tablas: el core entero puede entrar al río de eventos declarativamente.
