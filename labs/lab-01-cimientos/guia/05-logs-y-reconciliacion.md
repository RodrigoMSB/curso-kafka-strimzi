# Guía 5 — Los logs y el loop de reconciliación

El operador ya está contratado y vigilando. ¿Cómo sabemos qué está haciendo?
Lo escuchamos. Sus logs son la primera herramienta de diagnóstico del curso.

## Leer los logs del operador

```bash
kubectl logs deployment/strimzi-cluster-operator -n meridiano-sistema
```

```text
Salida esperada (puede variar levemente)
INFO  AbstractOperator:... - Starting Cluster Operator
INFO  ClusterOperator:... - Creating Cluster Operator for namespace meridiano-pagos
INFO  ClusterOperator:... - Cluster Operator started
INFO  ClusterOperator:... - Starting to watch resources in namespace meridiano-pagos
INFO  Util:... - Reconciliation #1 ... reconciled
```

Léelo con calma y busca dos cosas:

1. **Qué namespaces vigila.** Verás mencionado `meridiano-pagos`: el operador
   confirma en voz alta el scope que le dimos por values.
2. **El arranque del loop de reconciliación.** El operador anuncia que empieza
   a observar recursos y queda a la espera.

## El concepto: reconciliación

Un operador trabaja en un **loop de reconciliación**: compara el estado deseado
(lo que declaramos en los Custom Resources) con el estado real del clúster, y
actúa para cerrar la diferencia. Ese loop se dispara de dos maneras:

- **Reactiva (por eventos):** cuando algo cambia —se crea, modifica o borra un
  recurso que el operador vigila—, reacciona de inmediato.
- **Periódica (por timer):** cada cierto intervalo, el operador revisa todo de
  nuevo aunque no haya pasado nada, por si se perdió algún evento o algo derivó.

El operador "razona en voz alta" en sus logs. Si vienes de Kafka clásico, este
es el equivalente cultural al `server.log` del broker: el primer lugar al que
mirar cuando algo no cuadra.

Ahora mismo, como no hemos declarado ningún clúster Kafka, el loop está **en
reposo**: vigila `meridiano-pagos`, no encuentra recursos que materializar y
espera. Eso es exactamente lo que debe pasar al terminar el Lab 01.

## Verificación final del lab

Marca los cinco ítems antes de cerrar:

- [ ] El clúster kind `meridiano` está arriba (`kubectl get nodes` muestra el nodo `Ready`).
- [ ] Los namespaces `meridiano-sistema` y `meridiano-pagos` existen.
- [ ] La release de Helm `strimzi-operator` aparece como `deployed` (`helm list -n meridiano-sistema`).
- [ ] El pod del operador está en estado `Running` (`kubectl get pods -n meridiano-sistema`).
- [ ] Los logs muestran que el operador vigila `meridiano-pagos`.

## Desafío extra (opcional, post-sesión)

1. Localiza en los logs el **intervalo de reconciliación periódica**. Pista: el
   valor por defecto del chart son 2 minutos (120000 ms); observa cada cuánto
   se repiten las reconciliaciones cuando no hay cambios.
2. Reduce ese intervalo mediante `helm upgrade` usando el value correspondiente
   del chart, y vuelve a leer los logs para observar el cambio de frecuencia.

La resolución completa —la clave exacta del chart y el comando `helm upgrade`—
está en `soluciones/values-operador-solucion.yaml`.

## Cierre

El administrador experto ya está contratado y vigila la oficina de pagos. En el
**Lab 02** le encargamos el clúster.
