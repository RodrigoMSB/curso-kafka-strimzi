# Guía 4 — Encoger con la misma disciplina

Crecer es fácil de aceptar; encoger da más respeto (¿y si pierdo datos?). Con
Cruise Control, encoger es tan seguro como crecer: primero **vacías** el broker,
luego lo quitas.

## 1. Vaciar el broker 4: KafkaRebalance remove-brokers

Antes de quitar el broker 4, hay que mover sus réplicas a los demás. Copia tu
`KafkaRebalance` a un archivo nuevo (`mi-remove.yaml`) y cámbiale **el nombre y
el modo**: es un rebalanceo distinto, con su **propio nombre** (`vaciar-broker-4`).

**ANTES** (tu copia de add-brokers):

```yaml
metadata:
  name: agregar-broker-4
spec:
  mode: add-brokers
  brokers: [4]
```

**DESPUÉS** (nombre nuevo y modo inverso):

```yaml
metadata:
  name: vaciar-broker-4
spec:
  mode: remove-brokers
  brokers: [4]
```

> **No reutilices el nombre `agregar-broker-4`.** Los comandos de abajo y el
> `90-test` buscan `vaciar-broker-4`; si dejas el nombre viejo, `kubectl` no lo
> encuentra y el test no ve el segundo rebalanceo.

```bash
kubectl apply -n meridiano-pagos -f mi-remove.yaml
```

Misma mecánica: espera `ProposalReady`, lee la propuesta, aprueba:

```bash
kubectl get kafkarebalance vaciar-broker-4 -n meridiano-pagos
kubectl annotate kafkarebalance vaciar-broker-4 -n meridiano-pagos strimzi.io/rebalance=approve
```

Cuando llegue a `Ready`, el broker 4 está **vacío**. Verifícalo: en el `--describe`
del tópico, el broker 4 ya **no** aparece en ningún `Replicas:`.

## 2. Encoger: escalar de vuelta a 3

Ahora sí, quita el broker. Edita el pool a 3 réplicas:

```yaml
spec:
  replicas: 3
```

```bash
kubectl apply -n meridiano-pagos -f mi-brokers.yaml
kubectl wait --for=condition=Ready kafka/pagos -n meridiano-pagos --timeout=600s
```

```bash
kubectl get pods -n meridiano-pagos | grep pagos-brokers
```

Quedan los brokers 0, 1, 2. **No se perdió un solo byte:** vaciamos antes de
quitar. Encoger sin perder datos es tan importante como crecer sin downtime — un
banco escala en las dos direcciones según la demanda (y el costo).

> **Estado canónico:** el clúster vuelve a **3 brokers**. Los labs siguientes y
> el capstone asumen 3. Si quitas un broker sin vaciarlo antes, Strimzi te
> protege (no deja perder réplicas), pero el camino correcto es siempre
> vaciar → quitar.

## Desafío extra (parte 1)

Explora `kubectl get kafkarebalance agregar-broker-4 -n meridiano-pagos -o yaml`:
lee los **goals** de la propuesta y entiende 2–3 de ellos. La resolución está en
`soluciones/desafio-goals.md`.
