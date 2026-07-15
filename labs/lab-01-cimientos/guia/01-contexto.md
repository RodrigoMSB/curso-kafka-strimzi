# Guía 1 — Contexto: por qué un operador y por qué dos namespaces

## El problema en una página

Banco Meridiano quiere correr Apache Kafka sobre Kubernetes. Kafka es un
sistema con estado: brokers, almacenamiento persistente, configuración de
red, certificados, usuarios, tópicos. Operarlo a mano sobre Kubernetes —pod
por pod, volumen por volumen— es frágil y no escala.

La respuesta de Kubernetes a este tipo de problema es el patrón **operador**:
un componente que corre dentro del clúster y sabe cómo administrar una
aplicación compleja por nosotros. Nosotros le **declaramos** qué queremos (por
ejemplo, "un clúster Kafka de 3 brokers con TLS"), y el operador se encarga de
crear, configurar y mantener todas las piezas para que la realidad coincida
con esa declaración.

El operador de Strimzi se llama **Cluster Operator**. Es el administrador
experto de Kafka que vamos a contratar hoy. Una vez instalado, queda
escuchando: cuando aparezca un recurso de tipo `Kafka` (u otros que veremos),
él lo materializará. Mientras no aparezca ninguno, simplemente vigila y espera.

## Los dos namespaces de Meridiano

En este lab creamos dos namespaces, cada uno con un rol claro:

- **`meridiano-sistema`** — la "oficina del administrador". Aquí vive el
  Cluster Operator: su pod, su ServiceAccount, su configuración. Es
  infraestructura de plataforma.
- **`meridiano-pagos`** — el "edificio que administra". Aquí vivirá, en el
  Lab 02, el clúster Kafka de pagos. Por ahora estará vacío.

## Por qué separar operador y carga

Mantener el operador en un namespace y la carga (el clúster Kafka) en otro es
una práctica de **gobernanza**. Define con claridad quién puede declarar
clústeres y dónde: el equipo de plataforma administra `meridiano-sistema`,
mientras que `meridiano-pagos` es el espacio acotado donde se permite crear
recursos de Kafka. A un banco le importa precisamente eso: poder responder con
precisión a "quién tiene permiso para levantar un clúster, y en qué namespace".

Esta separación también prepara el terreno para el RBAC que revisaremos en la
Guía 4: el operador vive en un sitio pero necesita permisos sobre otro, y eso
no es casualidad, es diseño.

## Antes de continuar: verifica tu entorno

Ejecuta el verificador de entorno y confirma que todo aparezca en verde:

```bash
bash bin/00-verificar-entorno.sh
```

```text
Salida esperada (puede variar levemente)
[INFO] Verificación del entorno para el Lab 01 (no se instala nada).

[OK] Docker está accesible y corriendo.
[OK] kind presente: kind v0.32.0 go1.26.3 darwin/arm64
[OK] Versión de kind suficiente (detectada 0.32.0, mínimo v0.32.0).
[OK] kubectl presente: Client Version: v1.3x.x
[OK] helm presente: v4.x.x
[OK] Resolución DNS de strimzi.io correcta.

[OK] Entorno en verde. Puedes continuar con bin/01-crear-cluster.sh.
```

La versión exacta de `kubectl`, `kind` y `helm` puede variar según tu equipo;
lo importante es que cada línea aparezca en verde.

Si tu `kubectl` es dos o más *minors* más nuevo que la versión del clúster (por
ejemplo, un kubectl 1.36 con los nodos fijados en 1.34), verás además un aviso
`[INFO]` de *skew*. Es informativo, no un error: la política de skew de
Kubernetes recomienda no pasar de ±1 minor entre kubectl y el API server, pero
el lab está probado y funciona igual. kubectl no te avisa solo de este desfase;
por eso lo hace el verificador.

Si algún ítem aparece como `[ERROR]`, no continúes: revisa
`docs/troubleshooting.md` y resuélvelo primero.
