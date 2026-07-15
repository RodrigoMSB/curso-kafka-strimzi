# Guía 4 — El problema del estado

> Parte 2, sesión 5. Aquí el clúster se gana (o se pierde) la confianza de un
> banco: ¿sobreviven los pagos a un reinicio?

## 1. Vive el problema antes de que te lo expliquen

Tienes mensajes en `pagos.meridiano.transacciones` desde la guía 3. Vamos a
reiniciar los brokers y ver qué pasa.

Primero, un matiz importante. Si reinicias **un solo** broker, no pierdes nada:
el tópico tiene replication factor 3, así que las otras dos réplicas conservan
los datos. **Eso es bueno** y es justo para lo que sirve replicar. Pruébalo si
quieres: borra un pod de broker, espera a que vuelva, consume — los mensajes
siguen ahí.

El riesgo del storage efímero aparece cuando se reinician **todos** los brokers
a la vez: un reinicio general del clúster, el recreado de un pool, un evento de
mantenimiento. Simulémoslo borrando los tres brokers de golpe:

```bash
kubectl delete pod -l strimzi.io/pool-name=brokers -n meridiano-pagos
```

El operador los recrea en segundos. Espera a que los tres vuelvan a `Running`:

```bash
kubectl get pods -n meridiano-pagos -w
```

Ahora consume de nuevo:

```bash
kubectl run cli-consumidor --rm -i --restart=Never \
  -n meridiano-pagos \
  --image=quay.io/strimzi/kafka:0.51.0-kafka-4.2.0 --command -- \
  bin/kafka-console-consumer.sh \
  --bootstrap-server pagos-kafka-bootstrap:9092 \
  --topic pagos.meridiano.transacciones \
  --from-beginning --timeout-ms 15000
```

**No aparece ningún mensaje.** El tópico sigue existiendo (sus metadatos viven
en el controller), pero los datos de los brokers se esfumaron: el storage
`ephemeral` es un `emptyDir` que muere con el pod. Al reiniciarse los tres a la
vez, las tres réplicas nacieron vacías. Acabas de perder los pagos.

En un banco, esto es inadmisible. Vamos a arreglarlo.

## 2. El intento ingenuo: cambiar el storage en caliente

Lo natural sería editar el pool de brokers y cambiar `ephemeral` por
`persistent-claim`. Inténtalo sobre tu copia:

```yaml
# mis-brokers.yaml — storage del pool de brokers
  storage:
    type: jbod
    volumes:
      - id: 0
        type: persistent-claim   # antes: ephemeral
        size: 2Gi
        kraftMetadata: shared
```

```bash
kubectl apply -n meridiano-pagos -f mis-brokers.yaml
```

**El operador no aplica el cambio.** El tipo de storage de un pool **no es
modificable en caliente**: se decide cuando el pool nace. Compruébalo leyendo el
estado del pool y los logs del operador:

```bash
kubectl get kafkanodepool brokers -n meridiano-pagos -o yaml | grep -A20 "status:"
kubectl logs deployment/strimzi-cluster-operator -n meridiano-sistema | grep -i storage | tail -5
```

En el `status` del pool (y del `Kafka`) aparece una condición de tipo `Warning`
con el mensaje real del operador:

```text
type: Warning   reason: KafkaStorage
message: The desired Kafka storage configuration in the KafkaNodePool resource
meridiano-pagos/brokers contains changes which are not allowed. As a result, all
storage changes will be ignored.
```

El clúster sigue `Ready`: el operador **no** rompe nada, simplemente **ignora**
el cambio de storage y te avisa. Tu disco sigue siendo el de antes.

Esta es una lección de plataforma, no un castigo: **el storage se planifica el
día cero**. Por eso en producción decides el disco antes de desplegar, no
después de un susto.

## 3. La vía limpia: recrear con storage persistente

Como el storage se decide al nacer, para cambiarlo se **recrea** el clúster de
forma declarativa. En este laboratorio aún no hay datos que valga la pena
conservar (acabamos de perderlos), así que es el momento perfecto.

Borra los tres recursos y **espera a que el operador termine de desmontarlos**
antes de volver a aplicarlos en su versión persistente. Las soluciones de la
parte 2 ya traen `persistent-claim` (y todavía **sin** rack: el rack llega en la
guía 05):

```bash
kubectl delete kafka pagos -n meridiano-pagos
kubectl delete kafkanodepool brokers controllers -n meridiano-pagos

# Espera a que los pods del clúster desaparezcan del todo antes de recrear.
kubectl wait --for=delete pod -l strimzi.io/cluster=pagos -n meridiano-pagos --timeout=300s

kubectl apply -n meridiano-pagos -f soluciones/parte-2-persistente/
```

> **¿Por qué ese `kubectl wait --for=delete`?** No es un adorno. Sin él, el
> `apply` llega mientras el operador todavía está desmontando los pods viejos. En
> ese instante el operador no ve un clúster nuevo: ve el **mismo** clúster con un
> cambio de storage de `ephemeral` a `persistent-claim` — exactamente el cambio
> que en el §2 acabas de comprobar que **no se permite en caliente**. Lo ignora,
> te avisa con el mismo `Warning KafkaStorage`, y el clúster se queda en
> `ephemeral` sin que se note. La espera garantiza que los pools nacen de cero,
> de verdad persistentes. Es el mismo pozo del §2, con una línea que te salva.

Espera a que el clúster vuelva a estar Ready:

```bash
kubectl wait --for=condition=Ready kafka/pagos -n meridiano-pagos --timeout=600s
```

### Comprueba que la persistencia quedó de verdad

El modo de fallo de este paso es **silencioso**: el clúster puede reportar
`Ready` y verse perfecto aun estando todavía sobre `emptyDir`. No te fíes de
`Ready`; exige la prueba física, los PVC:

```bash
kubectl get pvc -n meridiano-pagos
```

```text
Salida esperada (puede variar levemente)
NAME                         STATUS   VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS
data-0-pagos-brokers-0       Bound    pvc-...  2Gi        RWO            standard
data-0-pagos-brokers-1       Bound    pvc-...  2Gi        RWO            standard
data-0-pagos-brokers-2       Bound    pvc-...  2Gi        RWO            standard
data-0-pagos-controllers-3   Bound    pvc-...  1Gi        RWO            standard
```

Cuatro PVC en estado **Bound** (uno por broker y uno por el controller): esa es
la prueba de que el almacenamiento sobrevivirá al reinicio de los pods. Si en
cambio ves *"No resources found"*, el cambio de storage se ignoró: repite el
borrado y esta vez deja que el `wait --for=delete` termine antes de re-aplicar.

Vuelve a crear el tópico (guía 3) y produce un mensaje nuevo.

## 4. Ahora sí: los pagos sobreviven

Con storage persistente, repite el reinicio general de brokers:

```bash
kubectl delete pod -l strimzi.io/pool-name=brokers -n meridiano-pagos
# espera a que los tres vuelvan a Running, y consume:
```

Esta vez **los mensajes siguen ahí**. Los tres brokers se reiniciaron, pero cada
uno volvió a montar su PVC con los datos intactos. La diferencia entre perder un
pago y conservarlo fue una línea de YAML.

### El PVC es el mismo objeto, antes y después

La identidad del almacenamiento es estable: el PVC del broker no se recrea con el
pod, se reusa. Compruébalo (el PVC del broker con id 0):

```bash
kubectl get pvc -n meridiano-pagos -o wide | grep brokers
```

Anota el nombre y el `VOLUME` (el PV) de uno de ellos, reinicia ese broker, y
vuelve a mirar: mismo PVC, mismo PV. El pod es desechable; su disco, no.

## El storage no se borra solo (la historia de terror)

En las soluciones, el storage lleva `deleteClaim: false` (el valor por defecto):
si borras el clúster, **los PVC sobreviven**. Es deliberado —no quieres que un
`kubectl delete` se lleve por delante los datos del banco— pero tiene contracara:
los PVC huérfanos se acumulan y hay que limpiarlos a mano. En producción, esa
decisión (`true` o `false`) se toma con los ojos abiertos.

En la siguiente guía repartimos las réplicas entre zonas.
