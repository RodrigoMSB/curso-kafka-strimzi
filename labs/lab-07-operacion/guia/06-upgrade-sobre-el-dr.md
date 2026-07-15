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

## La otra versión que también se migra: la API del CR (rumbo a 1.0.0)

Acabas de mover la versión de **Kafka** (los datos). Hay una segunda versión en
juego que suena igual pero no lo es: la **versión de API del Custom Resource**
(`kafka.strimzi.io/v1beta2` → `v1`). Y con ella, una distinción que conviene
hacer propia:

- **Servir** una versión: la API la acepta y la devuelve.
- **Almacenar** una versión: en cuál quedan escritos los objetos en etcd.

Un CRD puede **servir varias** versiones a la vez, pero **almacena en una sola**.
Compruébalo en tu propio clúster:

```bash
kubectl get crd kafkas.kafka.strimzi.io \
  -o jsonpath='{range .spec.versions[*]}{.name}{" served="}{.served}{" storage="}{.storage}{"\n"}{end}'
kubectl get crd kafkas.kafka.strimzi.io -o jsonpath='storedVersions={.status.storedVersions}{"\n"}'
```

```text
Salida esperada (Strimzi 0.51)
v1 served=true storage=false
v1beta2 served=true storage=true
storedVersions=["v1beta2"]
```

Strimzi 0.51 ya **sirve** `v1` —por eso, al leer un CR, el server te responde
`apiVersion: kafka.strimzi.io/v1`, convertido al vuelo por un webhook—, pero
todavía **almacena** en `v1beta2`. Lo viste desde el Lab 01, cuando el CRD
listaba `v1beta2 v1`.

¿Por qué importa esto? **Strimzi 1.0.0 elimina `v1beta2`** y deja solo `v1`. Pero
tus objetos siguen guardados como `v1beta2`: si esa versión desaparece sin más,
el API server ya no sabría leerlos. Por eso, **antes** del salto a 1.0.0 hay que
hacer una **migración de storage version**: reescribir cada CR para que quede
almacenado como `v1` y actualizar `storedVersions` a `["v1"]`. Servir `v1` fue
gratis y transparente; **cambiar la versión almacenada es la migración de
verdad**, y es la razón concreta por la que subir a 1.0.0 no es "solo actualizar
el operador".

> En este lab no ejecutamos esa migración (llega con la 1.0.0). Pero ahora sabes
> que existe, por qué existe, y cómo ver su rastro en el CRD: servido en `v1`,
> almacenado en `v1beta2`, esperando el día del salto.
