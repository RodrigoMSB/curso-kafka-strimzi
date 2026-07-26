# Lab 01 — Los cimientos de Meridiano

Banco Meridiano decidió unificar su plataforma de eventos de pagos sobre
Kubernetes. Hoy no desplegamos todavía ningún clúster Kafka: hoy se construyen
los cimientos. Levantamos un clúster Kubernetes local y contratamos al
administrador que, de aquí en adelante, gestionará Kafka de forma declarativa:
el Strimzi Cluster Operator.

Al terminar este lab tendrás contratado y vigilando al administrador experto.
Todavía no le encargaremos nada: eso es el Lab 02.

## Objetivos del lab

- Tener un clúster Kubernetes local (kind) llamado `meridiano` corriendo y verificado.
- Instalar el Strimzi Cluster Operator 0.51.0 con Helm en el namespace `meridiano-sistema`, configurado para vigilar el namespace `meridiano-pagos`.
- Inspeccionar y comprender los CRDs de Strimzi como el "vocabulario nuevo" que el operador enseña al clúster.
- Revisar el RBAC del operador (ServiceAccount, ClusterRoles y bindings) y entender por qué tiene los permisos que tiene.
- Leer e interpretar los logs del operador: el loop de reconciliación en reposo, esperando recursos.

## Prerrequisitos

- Docker Desktop instalado y **corriendo**.
- `kind` **v0.32.0 o superior**, `kubectl` y `helm` instalados (ver el documento de setup del curso). La versión de kind importa: v0.32.0 es la que publica el digest pineado de `kindest/node:v1.34.8` que usa el curso.
- Conexión a Internet (descarga de la imagen del nodo y del chart del operador).

> **Si trabajas en Windows con Git Bash:** Git Bash (MSYS2) reescribe las rutas tipo
> `/props/...` a rutas de Windows antes de pasarlas al contenedor. **El curso ya lo resuelve**
> envolviendo esos comandos en `bash -c '...'`, así que no tienes que hacer nada.
> ⚠️ **No exportes `MSYS_NO_PATHCONV=1`:** esa variable apaga la conversión de rutas de forma
> global y rompe `kind`, `helm` y `kubectl`, que **sí la necesitan** para leer archivos del
> disco de Windows. Si la tienes en tu terminal o en tu `.bashrc`, quítala.

## Tiempo estimado

40 minutos.

## Mapa del lab

| Guía | Archivo | Qué logras |
|------|---------|------------|
| 1 | `guia/01-contexto.md` | Entiendes el problema y por qué hay dos namespaces. Verificas tu entorno. |
| 2 | `guia/02-cluster-kind.md` | Creas el clúster kind `meridiano` y confirmas su versión de Kubernetes. |
| 3 | `guia/03-instalacion-operador.md` | Instalas el Cluster Operator 0.51.0 con Helm y verificas el pod. |
| 4 | `guia/04-inspeccion-crds-rbac.md` | Inspeccionas los CRDs de Strimzi y el RBAC del operador. |
| 5 | `guia/05-logs-y-reconciliacion.md` | Lees los logs y comprendes la reconciliación. Cierras el lab. |

## Convención del curso

A lo largo de las guías encontrarás dos tipos de bloque:

- **Comandos que tú ejecutas**, en bloques de código:

```bash
kubectl get nodes
```

- **Salidas esperadas**, en bloques separados marcados como tales. Recuerda
  que tu salida puede variar levemente (nombres internos, fechas, edades de
  los recursos):

```text
Salida esperada (puede variar levemente)
NAME                     STATUS   ROLES           AGE   VERSION
meridiano-control-plane   Ready    control-plane   60s   v1.34.8
```

## Verifica tu trabajo

El script `bin/90-test-lab.sh` comprueba automáticamente que el estado final del
lab sea correcto. Es de **solo lectura**: no crea, instala ni borra nada; solo
mira y reporta.

```bash
bash bin/90-test-lab.sh
```

Córrelo **al terminar el lab**, o **al inicio de la siguiente sesión** para
confirmar que tu entorno sigue en pie antes del Lab 02. Cada línea muestra
`[OK]` o `[ERROR]`; cada error incluye una pista que apunta a la guía o al
documento de troubleshooting que lo resuelve. Al final verás un resumen del
tipo `N/N verificaciones correctas`: si todas pasan, el lab está completo; si
no, revisa los `[ERROR]` de arriba.

## Para el instructor

- `bin/91-test-e2e.sh` certifica el lab completo (de cero a fin, con limpieza) en un ambiente nuevo; úsalo en la VM antes del curso.
- `bin/95-recuperar-lab.sh` reconstruye el estado final del lab para poner al día a un alumno rezagado.
