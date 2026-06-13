# Guía 6 — El upgrade (sobre el DR, como en producción)

> La regla de banco: **nunca actualizas el clúster primario primero.** Se ensaya
> en el DR (o en pre-producción), se mira que todo siga vivo, y solo entonces se
> toca el primario — con ventana de cambio y mucho café.

Recreamos el `dr` fijado en **Kafka 4.1.1** y lo subimos a **4.2.0**.

## 1. Recrear el DR en 4.1.1

El DR es efímero y RF=1: recrearlo es barato, y **MM2 lo repuebla solo** (eso
también es lección de contingencia). Borra y recrea fijado en 4.1.1:

```bash
kubectl delete kafka dr -n meridiano-dr
kubectl delete kafkanodepool dr-nodes -n meridiano-dr
kubectl apply -f soluciones/dr-upgrade/10-dr-4.1.1.yaml
kubectl wait --for=condition=Ready kafka/dr -n meridiano-dr --timeout=600s
```

Verifica la versión:

```bash
kubectl get kafka dr -n meridiano-dr -o jsonpath='{.spec.kafka.version}{"\n"}'
```

```text
Salida esperada
4.1.1
```

(MM2 vuelve a replicar hacia el DR recreado en cuanto está listo.)

## 2. El upgrade declarativo: primero la versión, después la metadata

El procedimiento oficial tiene un **orden** que importa:

1. **Sube `spec.kafka.version`** a 4.2.0 → el operador hace un **rolling de
   upgrade** (cada broker arranca con el binario nuevo, manteniendo el formato de
   metadata viejo por compatibilidad).
2. **Después, sube `metadataVersion`** a `4.2-IV1` → otro paso, ahora que todos
   los brokers ya corren 4.2.0.

> Nunca al revés: si subes `metadataVersion` antes de que los brokers entiendan el
> formato nuevo, rompes la compatibilidad. Y ojo: bajar `metadataVersion` después
> puede no ser posible — por eso es el último paso, con red.

Aplica el CR con la versión nueva (la solución lo trae con ambos cambios; en la
práctica el operador aplica primero el rolling de versión y luego la metadata):

```bash
kubectl apply -f soluciones/dr-upgrade/20-dr-4.2.0.yaml
kubectl wait --for=condition=Ready kafka/dr -n meridiano-dr --timeout=600s

kubectl get kafka dr -n meridiano-dr -o jsonpath='version={.spec.kafka.version} metadata={.spec.kafka.metadataVersion}{"\n"}'
```

```text
Salida esperada
version=4.2.0 metadata=4.2-IV1
```

## 3. Verificar que la réplica sobrevivió al upgrade

Produce en `pagos` y comprueba que el evento llega al `dr` (ya en 4.2.0):

```bash
kubectl exec -i cliente-kafka -n meridiano-pagos -- bash -c \
  'echo "post-upgrade" | bin/kafka-console-producer.sh --bootstrap-server pagos-kafka-bootstrap:9094 \
   --producer.config /props/app-pagos.properties --topic pagos.meridiano.transacciones'

kubectl run dr-cons --rm -i --restart=Never -n meridiano-dr \
  --image=quay.io/strimzi/kafka:0.51.0-kafka-4.2.0 --command -- \
  bin/kafka-console-consumer.sh --bootstrap-server dr-kafka-bootstrap.meridiano-dr.svc:9092 \
  --topic pagos.meridiano.transacciones --from-beginning --timeout-ms 20000 | grep post-upgrade
```

La réplica siguió funcionando tras el upgrade.

## El mapa para el primario

El procedimiento para `pagos` es **el mismo** (subir version → rolling → subir
metadataVersion), pero:

- con **ventana de cambio** acordada (los rollings de un clúster grande tardan);
- vigilando las **métricas** (guía del Lab 06) durante todo el proceso;
- con un **plan de rollback** del binario (la metadata no se baja, por eso se sube
  al final, cuando ya hay confianza).

Mismo procedimiento, más cuidado y más café. Eso es operar un banco.
