# Guía 2 — El clúster Kubernetes local con kind

## Qué es kind

**kind** (Kubernetes IN Docker) levanta clústeres de Kubernetes usando
contenedores Docker como si fueran nodos. Cada nodo del clúster es, en
realidad, un contenedor. Esto lo hace ideal para laboratorio: un clúster
completo nace y muere en minutos, es reproducible en cualquier máquina con
Docker y no deja nada instalado en el sistema operativo del alumno.

## El archivo `infra/kind-config.yaml`

Nuestro clúster se define en un archivo corto. La brevedad es parte del
mensaje: para construir cimientos no hace falta complejidad.

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: meridiano
nodes:
  - role: control-plane
    image: kindest/node:v1.34.8@sha256:02722c2dedddcfc00febf5d27fbeb9b7b2c14294c82109ff4a85d89ac9ba3256
```

Campo por campo:

- **`kind: Cluster`** — el tipo de objeto que describe este archivo (un clúster kind).
- **`apiVersion: kind.x-k8s.io/v1alpha4`** — la versión del formato de configuración de kind.
- **`name: meridiano`** — el nombre del clúster. kind lo prefija como contexto `kind-meridiano`.
- **`nodes`** — la lista de nodos. Aquí, uno solo.
  - **`role: control-plane`** — ese único nodo es el plano de control. Para este lab no necesitamos workers.
  - **`image`** — la imagen del nodo, **fijada con su digest** a Kubernetes v1.34.8.

## Por qué se fija la versión del nodo

La matriz de soporte oficial de Strimzi 0.51 prueba **Kubernetes 1.30 a 1.35**.
Un kind recién instalado puede traer una versión más nueva que esa matriz (la
rama actual de kind ya apunta a 1.36), todavía no probada con esta versión de
Strimzi. Por eso fijamos explícitamente la imagen del nodo a una versión dentro
del rango soportado.

Fijar versiones es **disciplina de plataforma, no desconfianza**: garantiza que
todos en la sala —y el entorno productivo del banco— trabajen sobre una versión
probada, no sobre "la que viniera por defecto ese día".

## Crear el clúster

```bash
bash bin/01-crear-cluster.sh
```

La primera vez, kind descargará la imagen del nodo; puede tardar unos minutos.

## Verificar a mano

Confirma que el plano de control responde:

```bash
kubectl cluster-info --context kind-meridiano
```

```text
Salida esperada (puede variar levemente)
Kubernetes control plane is running at https://127.0.0.1:PUERTO
CoreDNS is running at https://127.0.0.1:PUERTO/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
```

Ahora mira los nodos y, sobre todo, la columna **VERSION**:

```bash
kubectl get nodes -o wide
```

```text
Salida esperada (puede variar levemente)
NAME                      STATUS   ROLES           AGE   VERSION   ...
meridiano-control-plane   Ready    control-plane   90s   v1.34.8   ...
```

Durante los primeros segundos el nodo puede aparecer `NotReady` mientras termina
de arrancar la red interna; es normal. Espera un momento y vuelve a consultar.

Confirma que la columna VERSION muestre una versión dentro del rango soportado
por Strimzi 0.51 (**1.30 a 1.35**). En nuestro caso, `v1.34.8`.

## Crear los namespaces

```bash
bash bin/02-crear-namespaces.sh
```

Verifica que existan los dos:

```bash
kubectl get namespaces | grep meridiano
```

```text
Salida esperada (puede variar levemente)
meridiano-pagos     Active   10s
meridiano-sistema   Active   10s
```

Con el clúster arriba y los namespaces creados, los cimientos están puestos.
En la siguiente guía contratamos al administrador.
