# Guion de Slides — Capítulo 2: Despliegue e infraestructura base

**Curso:** Administración de Apache Kafka sobre Kubernetes con Strimzi
**Sesiones cubiertas:** 3, 4 y 5 (3 × 60 min: ~20 min teoría + ~40 min laboratorio por sesión)
**Narrativa:** Banco Meridiano — Plataforma de Eventos de Pagos
**Labs asociados:** Lab 01 (sesión 3) y Lab 02 (sesiones 4–5)
**Estado:** Guion de contenido. Pendiente vertido a template Netec.

**Convenciones:** mismas del guion Cap 1. La numeración de slides continúa desde S30.

**Nota de ritmo:** a diferencia del Cap 1 (teoría pura), desde aquí cada sesión es 20/40. Las slides cubren solo el bloque teórico; la última slide de cada sesión lanza el laboratorio. Menos slides, más densas en intención.

---

## SESIÓN 3 — Instalación del Cluster Operator e introducción de los CRDs

**Objetivo de la sesión:** que el alumno instale el Cluster Operator con Helm (aprendiendo Helm en el camino), entienda qué quedó instalado (CRDs, RBAC, scope de namespaces) y sepa leer el loop de reconciliación en los logs.

### Bloque teórico (20 min, S31–S37)

**S31 — Mapa maestro: dónde estamos**
- Contenido: El mapa maestro del curso (S13) con la primera pieza por iluminar: "Cimientos — Cluster Operator". Todo lo demás en gris.
- Nota: Ritual de apertura de cada capítulo: 1 minuto, ubicar al grupo en el viaje. "Hoy ponemos la primera piedra de la plataforma Meridiano."

**S32 — Helm en 5 minutos: lo justo y necesario**
- Contenido: Cuatro conceptos, cuatro líneas: **Chart** (paquete de manifiestos parametrizado), **Repositorio** (donde viven los charts), **Release** (una instalación con nombre), **Values** (los parámetros que personalizan). Los cuatro comandos del día: `helm repo add`, `helm install`, `helm list`, `helm upgrade`.
- Nota: AQUÍ se cierra el hueco detectado: los 20 alumnos no traen Helm. No teorizar de más — Helm se aprende usándolo en el lab. Analogía: chart = receta, values = los ajustes de sal y picante, release = el plato servido con nombre propio.

**S33 — Las tres vías de instalación de Strimzi**
- Contenido: (1) **Helm** — la del curso y la más común en EKS/GKE/AKS. (2) **Manifiestos directos** — máximo control, mínimo confort; útil en entornos con egress restringido. (3) **OLM** — el camino natural en OpenShift. La elección depende de la plataforma y las políticas del banco.
- Nota: Conectar con su realidad: "ustedes están en EKS, así que Helm es su vía natural; OLM lo dejamos nombrado por si algún día conviven con OpenShift". No profundizar en OLM.

**S34 — Qué deja instalado el chart**
- Contenido: Anatomía de la instalación: el **Deployment del Cluster Operator** (un pod vigilante), los **CRDs** (Kafka, KafkaNodePool, KafkaTopic... el catálogo de S26–S27 ahora instalado de verdad), y el **RBAC** (ServiceAccount, ClusterRoles, bindings) que le da permiso al operador para crear y operar recursos.
- Nota: Insistir en la separación conceptual: instalar el operador NO crea ningún clúster Kafka. Es contratar al administrador experto; el clúster se le encarga después (sesión 4).
- Diagrama: Tres cajas apiladas: "Pod del operador" / "CRDs (el vocabulario nuevo)" / "RBAC (los permisos)".

**S35 — Scope: ¿qué namespaces vigila el operador?**
- Contenido: Tres modos: un solo namespace (el default del chart), lista de namespaces, o todos (`watchAnyNamespace`). Implicancia directa en RBAC: vigilar más namespaces exige ClusterRoles más amplios. En el curso: operador en `meridiano-sistema`, clúster Kafka en `meridiano-pagos`.
- Nota: Para un banco esto es gobernanza, no detalle técnico: quién puede declarar clústeres y dónde. Anticipar que en EKS multi-equipo este scope es una decisión de plataforma, no del equipo Kafka.

**S36 — Leer al operador: logs y reconciliación**
- Contenido: El operador escribe su razonamiento en logs: qué CR observó, qué difiere, qué va a hacer. `kubectl logs deployment/strimzi-cluster-operator` es la primera herramienta de diagnóstico del curso. Reconciliación periódica además de reactiva (timer + eventos).
- Nota: Cambio de hábito para admins Kafka: antes miraban server.log del broker; ahora la primera pregunta es "¿qué dice el operador?". Mostrar un fragmento real de log de reconciliación en la slide.

**S37 — Lanzamiento Lab 01: "Los cimientos de Meridiano"**
- Contenido: Objetivos del lab en 4 bullets: (1) kind arriba y verificado, (2) repo de Strimzi agregado a Helm, (3) Cluster Operator instalado en `meridiano-sistema` vigilando `meridiano-pagos`, (4) CRDs inspeccionados y logs del operador leídos. Tiempo: 40 min. Entregable: operador esperando órdenes.
- Nota: Recordar la estructura del material (README, guía numerada, plantillas, soluciones, troubleshooting). Primera vez que tocan el repo del curso: dar 3 minutos para clonar y orientarse.

---

## SESIÓN 4 — Despliegue de un clúster Kafka KRaft con KafkaNodePool

**Objetivo de la sesión:** que el alumno declare y despliegue el clúster de pagos de Meridiano con Kafka + KafkaNodePool, entendiendo la topología por pools, los roles KRaft y los recursos por pod.

### Bloque teórico (20 min, S38–S44)

**S38 — Mapa maestro: dónde estamos**
- Contenido: Mapa con "Cimientos" iluminado y "Clúster de pagos" por iluminar.
- Nota: "El administrador experto ya está contratado. Hoy le encargamos el clúster."

**S39 — Dos CRs, un clúster**
- Contenido: La pareja inseparable: **Kafka** declara el clúster como totalidad (versión, listeners, configuración global, Entity Operator) y **KafkaNodePool** declara los nodos (cuántos, qué rol, qué recursos, qué storage). Un clúster = un CR Kafka + uno o más pools.
- Nota: Error conceptual a desactivar de entrada: buscar `replicas` en el CR Kafka. Ese campo murió con ZooKeeper — los nodos viven en los pools. Quien venga de tutoriales viejos va a tropezar justo ahí.
- Diagrama: CR Kafka como marco grande conteniendo dos cajas KafkaNodePool: "controllers" y "brokers".

**S40 — Topología por pools: roles KRaft**
- Contenido: Tres roles posibles por pool: `controller` (quorum de metadata), `broker` (datos y clientes), o ambos (nodos duales). Producción: pools separados (aislar el quorum del tráfico de datos). Laboratorio/dev: nodos duales para ahorrar recursos.
- Nota: Decisión explícita del curso: en kind usamos topología económica (pools mínimos) pero los manifiestos de referencia para su EKS muestran la separación productiva. Decir el porqué en voz alta — esa honestidad evita que se lleven el lab como receta de producción.

**S41 — El quorum de controllers: estático, y por qué**
- Contenido: KRaft soporta quorums estáticos (número fijo de controllers, escalar exige downtime) y dinámicos (entran y salen sin downtime). Kafka aún no soporta migrar de estático a dinámico → Strimzi usa quorum estático en TODOS los despliegues, incluso nuevos, por compatibilidad. Regla práctica de PRODUCCIÓN: 3 controllers (tolera la caída de uno) y no se tocan.
- Nota: Afirmación validada contra docs oficiales (no improvisar más allá). Honestidad de alcance: en el laboratorio usamos UN solo controller (un nodo dual o un pool de 1) porque una máquina de 16 GB no es un datacenter — y se dice de frente. La regla de los 3 es para su EKS, no para el kind del alumno. Si preguntan "¿y cuándo dinámico?": cuando Kafka soporte la migración, Strimzi evaluará adoptarlo — respuesta oficial del proyecto.

**S42 — Dimensionar los pods: recursos y JVM**
- Contenido: Por pool se declaran `resources` (requests/limits de CPU y memoria) y opciones de JVM (`-Xms`/`-Xmx`). Regla de oro heredada de Kafka clásico: el heap NO se come toda la memoria del pod — el page cache es el motor de rendimiento de Kafka y vive fuera del heap.
- Nota: Puente directo con lo que ya saben: "esto es el mismo tuning de siempre, ahora declarado en YAML". En kind: valores mínimos viables; en la referencia EKS: valores realistas comentados.

**S43 — Lo que el operador hace con la declaración**
- Contenido: Secuencia al aplicar los CRs: el operador valida → genera StrimziPodSets → crea pods con identidad estable → emite certificados internos → levanta services → arranca Entity Operator → reporta estado en `.status` del CR. `kubectl get kafka` muestra el estado de convergencia.
- Nota: Momento "magia revelada": la demo de S29 ahora explicada por dentro. El campo `.status` y las conditions del CR son el segundo punto de diagnóstico (tras los logs del operador).

**S44 — Lanzamiento Lab 02 (parte 1): "El clúster de pagos"**
- Contenido: Objetivos: (1) declarar pools de controllers y brokers para Meridiano (1 controller + 3 brokers: topología económica de laboratorio), (2) aplicar Kafka + KafkaNodePool en `meridiano-pagos`, (3) observar la convergencia (pods, status, logs), (4) producir y consumir el primer mensaje en `pagos.meridiano.transacciones` con los scripts nativos de Kafka desde un pod cliente efímero. Tiempo: 40 min.
- Nota: El primer mensaje fluyendo por el clúster es el hito emocional del curso — dejar que lo celebren. En este lab se produce/consume DESDE DENTRO del clúster (pod cliente) porque aún no hay acceso externo; kcat desde el host llega en el Lab 04, cuando se abre el listener externo. La parte 2 del lab (storage y rack) continúa la próxima sesión sobre este mismo clúster.

---

## SESIÓN 5 — Storage persistente, rack awareness y configuración multi-zona

**Objetivo de la sesión:** que el alumno configure almacenamiento persistente correcto para Kafka, entienda qué tipo de storage aplica en cada escenario y habilite rack awareness para sobrevivir caídas de zona.

### Bloque teórico (20 min, S45–S51)

**S45 — Mapa maestro: dónde estamos**
- Contenido: Mapa con "Clúster de pagos" iluminado; hoy se le pone el subtítulo "que sobrevive reinicios y zonas caídas".
- Nota: "Un clúster que pierde datos al reiniciar un pod no es una plataforma de pagos: es una demo. Hoy lo hacemos durable."

**S46 — Los tres tipos de storage de Strimzi**
- Contenido: **EphemeralStorage** (vive y muere con el pod — solo dev/pruebas), **PersistentClaimStorage** (PVC por nodo — el estándar productivo), **JbodStorage** (varios volúmenes por broker — separar datos, escalar disco, rendimiento). Tabla de cuándo aplica cada uno.
- Nota: Conectar con S6 (el problema del estado): esta es la respuesta concreta. Pregunta a la sala antes de mostrar la tabla: "¿alguien se atreve a poner ephemeral en producción? ¿por qué no?" — la respuesta correcta tiene matices (réplicas + ephemeral es debatible) y abre buena discusión de 2 minutos.

**S47 — El contrato del PVC: el disco sigue al broker**
- Contenido: Cada nodo del pool recibe su PVC con identidad fija: el broker 0 renace siempre con SU disco. El PVC sobrevive al pod (y opcionalmente al clúster: `deleteClaim: false`). El StorageClass define quién y cómo provee el volumen.
- Nota: Cerrar formalmente el problema 1 de la sesión 1. Advertencia operacional para el banco: `deleteClaim` es la diferencia entre "borré el CR" y "borré los datos del banco" — contarlo como historia de terror preventiva.

**S48 — StorageClass para Kafka: kind vs EKS**
- Contenido: En kind: StorageClass `standard` (local, suficiente para aprender). En su EKS: EBS CSI con `gp3` como línea base (IOPS y throughput configurables), `volumeBindingMode: WaitForFirstConsumer` para que el volumen nazca en la zona del pod. Kafka quiere discos por nodo, no storage compartido (NFS: no).
- Nota: Slide con doble columna lab/producción — el puente kind→EKS más explícito del capítulo. El manifiesto de referencia EKS va comentado en el repo del lab. "NFS: no" merece énfasis: aparece más de lo que debería en el mundo real.

**S49 — Rack awareness: réplicas que no comparten destino**
- Contenido: Kafka distribuye réplicas entre "racks"; en la nube, rack = zona de disponibilidad. Strimzi lo habilita leyendo la etiqueta `topology.kubernetes.io/zone` del nodo K8s. Resultado: las 3 réplicas de una partición de `pagos.meridiano.transacciones` viven en 3 zonas distintas — una zona caída no detiene los pagos.
- Nota: Argumento de negocio puro para un banco. En kind se simula etiquetando nodos del clúster local con zonas ficticias — decirlo de frente: "simulamos lo que en su EKS es automático".
- Diagrama: Tres zonas (A/B/C) con un broker cada una y las réplicas de una partición repartidas; una zona tachada y el clúster sigue.

**S50 — Nodos dedicados: taints y tolerations**
- Contenido: Patrón productivo: nodos K8s dedicados a Kafka (taint en el nodo, toleration + affinity en el pool). Evita que cargas vecinas compitan por disco y red con los brokers. En EKS: node group dedicado para Kafka.
- Nota: Marcar como "patrón de referencia, sin lab": en kind de un alumno no hay nodos que dedicar. Es contenido para sus decisiones de plataforma, no para sus manos hoy. Honestidad de alcance, como siempre.

**S51 — Lanzamiento Lab 02 (parte 2): "Durabilidad y zonas"**
- Contenido: Objetivos: (1) migrar el clúster a PersistentClaimStorage y verificar que los mensajes sobreviven el reinicio de pods, (2) etiquetar nodos kind con zonas simuladas y habilitar rack awareness, (3) verificar la distribución de réplicas por zona, (4) desafío extra: tumbar una "zona" y observar la continuidad. Tiempo: 40 min.
- Nota: El desafío extra de tumbar la zona es la primera simulación de fallo del curso — los SRE de la sala lo van a disfrutar. Cierre del capítulo: el mapa maestro queda con cimientos + clúster durable iluminados; próxima sesión empieza el Cap 3 (tópicos y usuarios como código).

---

## Resumen ejecutivo del guion

| Sesión | Slides | Lab | Diagramas clave |
|---|---|---|---|
| 3 | S31–S37 (7) | Lab 01 — Cimientos de Meridiano | Anatomía de la instalación (S34) |
| 4 | S38–S44 (7) | Lab 02 p1 — El clúster de pagos | Kafka + pools (S39) |
| 5 | S45–S51 (7) | Lab 02 p2 — Durabilidad y zonas | Rack awareness multi-zona (S49) |

**Total Cap 2: 21 slides.** Acumulado curso: 51 (S1–S51). En línea con la estimación de 80–100 totales.

**Pendientes que este guion deja registrados:**
1. Vertido a template Netec (igual que Cap 1).
2. Fragmento real de log de reconciliación para S36 — se captura cuando el instructor corra el Lab 01 como alumno cero.
3. Manifiestos de referencia EKS (StorageClass gp3, node group dedicado) — se escriben junto con el Lab 02, marcados como "referencia, no ejecutable en kind".
4. Decisión de topología económica exacta para kind (cuántos nodos por pool) — se cierra en la spec del Lab 02 según lo que aguante una máquina de 16 GB.
