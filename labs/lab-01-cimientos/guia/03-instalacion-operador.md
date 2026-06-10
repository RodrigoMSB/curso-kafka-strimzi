# Guía 3 — Instalación del Cluster Operator con Helm

Esta parte se hace **a mano**, comando por comando, porque instalar el operador
es justamente el contenido central de esta sesión. No hay script que lo haga
por ti: queremos que veas cada paso.

## Helm en 4 conceptos

Es probable que sea tu primer contacto con Helm. Cuatro ideas bastan para hoy:

- **Chart** — el paquete. Una plantilla parametrizable que describe un conjunto
  de recursos de Kubernetes (en nuestro caso, todo lo necesario para el Cluster
  Operator: deployment, RBAC, CRDs, etc.).
- **Repositorio** — el catálogo desde donde se descargan charts. Strimzi publica
  el suyo en `https://strimzi.io/charts/`.
- **Release** — una instalación concreta de un chart en tu clúster, con un
  nombre. Aquí la llamaremos `strimzi-operator`.
- **Values** — los parámetros con los que personalizas el chart al instalarlo
  (por ejemplo, qué namespace debe vigilar el operador).

## Pasos del alumno

### 1. Agregar el repositorio de Strimzi

```bash
helm repo add strimzi https://strimzi.io/charts/
```

### 2. Actualizar el índice local de charts

```bash
helm repo update
```

### 3. Preparar tu archivo de values

Abre la plantilla `plantillas/values-operador-plantilla.yaml` y completa los dos
TODO que contiene:

- **TODO 1:** el namespace que el operador debe **vigilar** (pista: no es donde
  se instala el operador, sino donde vivirá el clúster Kafka de pagos).
- **TODO 2:** la versión del chart a instalar (recordatorio; se usa en el
  comando del paso 4).

Guarda el resultado como tu values de trabajo, por ejemplo `mi-values.yaml`. Si
te atascas, en `soluciones/values-operador-solucion.yaml` está la versión
resuelta.

### 4. Instalar el operador

```bash
helm install strimzi-operator strimzi/strimzi-kafka-operator \
  --version 0.51.0 \
  --namespace meridiano-sistema \
  --values mi-values.yaml
```

### 5. Verificar la instalación

```bash
helm list -n meridiano-sistema
```

```text
Salida esperada (puede variar levemente)
NAME              NAMESPACE          REVISION  STATUS    CHART                          APP VERSION
strimzi-operator  meridiano-sistema  1         deployed  strimzi-kafka-operator-0.51.0  0.51.0
```

```bash
kubectl get pods -n meridiano-sistema
```

```text
Salida esperada (puede variar levemente)
NAME                                        READY   STATUS    RESTARTS   AGE
strimzi-cluster-operator-xxxxxxxxxx-xxxxx   1/1     Running   0          60s
```

Espera a que el pod `strimzi-cluster-operator-*` quede en estado **Running**.
La primera vez, la imagen del operador puede tardar en descargarse; mientras
tanto verás estados como `ContainerCreating`. Es normal.

## Cierre conceptual

Instalar el operador **no crea ningún clúster Kafka**. Acabamos de contratar al
administrador; todavía no le encargamos nada. Compruébalo:

```bash
kubectl get pods -n meridiano-pagos
```

```text
Salida esperada (puede variar levemente)
No resources found in meridiano-pagos namespace.
```

El namespace de pagos está vacío, y así debe estar al terminar este lab. En la
Guía 4 abrimos el "vocabulario" que el operador acaba de enseñarle al clúster.
