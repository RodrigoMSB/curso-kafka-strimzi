# Guía 4 — Encoger con la misma disciplina

Crecer es fácil de aceptar; encoger da más respeto (¿y si pierdo datos?). Con
Cruise Control, encoger es tan seguro como crecer: primero **vacías** el broker,
luego lo quitas.

## 1. Vaciar el broker 4: KafkaRebalance remove-brokers

Antes de quitar el broker 4, hay que mover sus réplicas a los demás. Sobre tu
copia del `KafkaRebalance`:

**DESPUÉS** (modo inverso):

```yaml
spec:
  mode: remove-brokers
  brokers: [4]
```

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
