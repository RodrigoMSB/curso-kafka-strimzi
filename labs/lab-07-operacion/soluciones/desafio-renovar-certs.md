# Desafío extra (parte 2) — renovar certificados (otro rolling)

> Objetivo: forzar la renovación de la cluster CA y observar que el resultado es,
> otra vez, un rolling controlado.

## Forzar la renovación de la cluster CA

Strimzi gestiona dos CA por clúster: la **cluster CA** (certifica a los brokers
entre sí y a sus clientes internos) y la **clients CA** (certifica a los usuarios
mTLS). Para forzar la renovación de la cluster CA, se anota su Secret:

```bash
kubectl annotate secret pagos-cluster-ca -n meridiano-pagos \
  strimzi.io/force-renew="true"
```

> El Secret de la CA es `<cluster>-cluster-ca` (la clave privada). El certificado
> público está en `<cluster>-cluster-ca-cert`.

## Observa qué pasa

El operador, en su siguiente reconciliación:

1. **Genera una CA nueva** (nuevo certificado, manteniendo la cadena de confianza).
2. **Renueva los certificados de los brokers** firmados por esa CA.
3. Hace un **rolling update** de los brokers para que tomen los certs nuevos —
   de a uno, esperando ISR, como siempre.

```bash
kubectl get pods -n meridiano-pagos -w   # observa el rolling
```

Verifica que la CA se renovó (la fecha de generación cambia):

```bash
kubectl get secret pagos-cluster-ca-cert -n meridiano-pagos \
  -o jsonpath='{.metadata.annotations.strimzi\.io/ca-cert-generation}{"\n"}'
```

## La moraleja del curso

Renovar certificados —una de las operaciones más temidas en sistemas seguros— es,
en esta plataforma, **otro rolling bien hecho**. Igual que endurecer, que cambiar
listeners, que habilitar métricas, que actualizar la versión. Todo converge al
mismo patrón seguro: el operador cambia el estado del clúster sin downtime, de a
un broker, esperando que cada uno esté sano antes de tocar el siguiente.

**Eso** es lo que hace que un equipo duerma tranquilo operando un banco sobre
Kafka.
