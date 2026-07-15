# Guion de Slides — Capítulo 1: Fundamentos de Strimzi y el patrón Operator

**Curso:** Administración de Apache Kafka sobre Kubernetes con Strimzi
**Sesiones cubiertas:** 1 y 2 (120 min de teoría)
**Narrativa:** Banco Meridiano — Plataforma de Eventos de Pagos
**Estado:** Guion de contenido. Pendiente vertido a template Netec.

**Convenciones de este guion:**
- `S#` = número de slide propuesto.
- **Contenido** = bullets que van en la slide (español neutro, alumno).
- **Nota** = nota del orador (qué decir, énfasis, anécdotas).
- **Diagrama** = boceto sugerido si la slide es visual.
- Tiempos por bloque indicados para calzar los 60 min de cada sesión.

---

## SESIÓN 1 — De Kafka on-premises a Kafka en Kubernetes: el problema a resolver

**Objetivo de la sesión:** que el alumno entienda por qué correr Kafka sobre Kubernetes NO es trivial, qué enfoques fallaron y por qué el patrón Operator es la respuesta del ecosistema.

### Bloque 1 — Apertura y narrativa (10 min, S1–S4)

**S1 — Portada del curso**
- Contenido: Título del curso, nombre del instructor, logo Netec (según template).
- Nota: Presentación personal breve. Mencionar certificación CCAAK y experiencia dictando Kafka. Encuadre: "este curso asume que ustedes ya operan Kafka — vamos a hablar de cómo llevarlo a Kubernetes bien hecho".

**S2 — Agenda general del curso**
- Contenido: Los 5 capítulos en una línea cada uno. Proporción 30/70 teoría-práctica. Mención de los 7 laboratorios + capstone.
- Nota: Vender el arco completo: "al final del curso van a tener un clúster securizado, observado, rebalanceado, y un plan de migración real". Aclarar que sesiones 1 y 2 son las únicas de teoría pura.

**S3 — Banco Meridiano: el caso que nos acompaña**
- Contenido: Banco Meridiano opera una plataforma de pagos sobre Kafka legado (VMs). Decisión estratégica: unificar la operación sobre Kubernetes. El curso construye su Plataforma de Eventos de Pagos paso a paso.
- Nota: Conectar sin nombrar al cliente: "esto les va a sonar familiar". Anticipar los nombres técnicos que verán todo el curso: `meridiano-kafka`, `pagos.meridiano.transacciones`.
- Diagrama: Caja "Core bancario (legado)" → flecha → "Plataforma de Eventos de Pagos (Kafka sobre K8s)" → consumidores (motor de fraude, confirmaciones, analítica).

**S4 — Punto de partida: lo que ya sabemos**
- Contenido: Repaso relámpago de Kafka (brokers, particiones, replicación, ISR, consumer groups) en UNA slide. Repaso relámpago de Kubernetes (pods, deployments, services, PV/PVC, namespaces) en la misma slide, dos columnas.
- Nota: NO detenerse a explicar. Es un contrato: "esto lo asumimos; si algo de esta slide les hace ruido, me avisan en el primer descanso". Sirve de termómetro del grupo.

### Bloque 2 — Por qué Kafka y Kubernetes se llevan mal por defecto (20 min, S5–S9)

**S5 — Kubernetes nació para ganado, Kafka es mascota**
- Contenido: Filosofía K8s: pods efímeros, desechables, intercambiables ("ganado"). Kafka: nodos con identidad, estado y datos que NO son intercambiables ("mascotas"). El choque conceptual de origen.
- Nota: Analogía central de la sesión. Un pod de un microservicio stateless muere y a nadie le importa; un broker que muere se lleva particiones, liderazgos y clientes conectados.

**S6 — Problema 1: el estado persistente**
- Contenido: Los datos de Kafka viven en disco local del broker. En K8s el disco del pod muere con el pod. PersistentVolumes y PVCs existen, pero alguien debe orquestar QUÉ volumen le toca a QUÉ broker, siempre.
- Nota: Pregunta retórica a la sala: "¿qué pasa si el broker 2 renace con el disco del broker 0?". Respuesta: corrupción de la identidad del clúster. Esto justifica por qué no basta un Deployment.

**S7 — Problema 2: identidad de red estable**
- Contenido: Cada broker tiene un `node.id` y los clientes (y los demás brokers) lo encuentran por una dirección concreta (advertised listeners). Los pods cambian de IP y de nombre al reprogramarse. Kafka necesita que el broker 0 sea SIEMPRE alcanzable como broker 0.
- Nota: Conectar con el conocimiento que traen: recordar el dolor de configurar advertised.listeners en VMs. En K8s el problema se multiplica porque la plataforma mueve pods sin preguntar.

**S8 — Problema 3: el ciclo de vida operacional**
- Contenido: Operar Kafka no es solo mantener procesos vivos: rolling restarts en orden seguro, expansión sin perder réplicas, upgrades coordinados broker por broker, rotación de certificados, rebalanceo de particiones. Kubernetes por sí solo no sabe NADA de esto.
- Nota: Punto clave: K8s sabe reiniciar pods, no sabe que reiniciar dos brokers a la vez puede dejar particiones offline. El conocimiento operacional de Kafka no está en la plataforma.

**S9 — La pregunta de la sesión**
- Contenido: Una sola frase grande: "¿Cómo le enseñamos a Kubernetes a operar Kafka como lo haría un administrador experto?"
- Nota: Pausa dramática. Las próximas slides son los intentos fallidos de responderla.

### Bloque 3 — Los patrones que fallaron (15 min, S10–S12)

**S10 — Intento fallido 1: StatefulSets puros**
- Contenido: StatefulSet da identidad estable (pod-0, pod-1) y PVCs por pod. Resuelve los problemas 1 y 2... a medias. No resuelve NADA del problema 3: no entiende rolling seguro, ni configuración de Kafka, ni certificados, ni listeners.
- Nota: Reconocer que es el primer instinto de todo equipo K8s. Anticipar dato de credibilidad que se profundiza en sesión 2: Strimzi ni siquiera usa StatefulSets — construyó su propio controlador (StrimziPodSet).

**S11 — Intento fallido 2: Helm charts artesanales**
- Contenido: Un chart genera los manifiestos, pero Helm es una herramienta de INSTALACIÓN, no de OPERACIÓN. Después del `helm install`, nadie reconcilia: el día 2 (upgrades, fallos, escalado) queda en manos humanas.
- Nota: Frase para pizarra: "Helm te deja el auto estacionado; nadie lo maneja". Distinguir instalar de operar es el corazón conceptual del curso.

**S12 — Lo que de verdad se necesita**
- Contenido: Un componente que (1) sepa de Kafka lo que sabe un administrador experto, (2) viva DENTRO del clúster vigilando 24/7, (3) compare estado deseado vs estado real y actúe solo. Eso tiene nombre: patrón Operator.
- Nota: Esta slide es el puente a la sesión 2. Dejar la definición en suspenso: "la próxima hora abrimos el capó".

### Bloque 4 — Cierre y anticipo (15 min, S13–S14 + discusión)

**S13 — El mapa del territorio**
- Contenido: Diagrama del estado final del curso: clúster Meridiano sobre Strimzi con seguridad (candado), observabilidad (gráficos), CDC desde el core legado (flecha entrante), DR con MM2 (flecha a segundo clúster), Cruise Control (balanza).
- Nota: Recorrer el diagrama nombrando en qué sesión se construye cada pieza. Este mismo diagrama reaparece al inicio de cada capítulo con las piezas ya construidas iluminadas.
- Diagrama: El "mapa maestro" del curso — pieza clave, vale la pena dibujarlo bien.

**S14 — Preguntas y discusión dirigida**
- Contenido: Tres preguntas para la sala: ¿Qué operan hoy sobre K8s? ¿Qué los asusta de poner Kafka ahí? ¿Quién ha sufrido un rolling restart mal hecho?
- Nota: Reservar 10 min reales. Las respuestas calibran el tono del resto del curso y dan material para conectar en sesiones siguientes.

---

## SESIÓN 2 — El patrón Operator y la anatomía de Strimzi 0.51

**Objetivo de la sesión:** que el alumno entienda el mecanismo de reconciliación, conozca cada componente de Strimzi por nombre y función, y reconozca los Custom Resources que va a usar el resto del curso.

### Bloque 1 — El patrón Operator (20 min, S15–S19)

**S15 — Recapitulación en una slide**
- Contenido: La pregunta de la sesión 1 + los tres problemas (estado, identidad, ciclo de vida operacional). "Hoy: la respuesta."
- Nota: 2 minutos máximo. Sirve para los que llegan tarde a la sesión.

**S16 — Extender Kubernetes: CRDs**
- Contenido: Kubernetes trae recursos nativos (Pod, Service, Deployment). Los CustomResourceDefinitions permiten enseñarle recursos nuevos: `kind: Kafka` pasa a ser tan ciudadano de K8s como `kind: Pod`. kubectl, RBAC y la API los tratan igual.
- Nota: Demo en vivo opcional (si hay clúster a mano): `kubectl api-resources | grep kafka` antes y después de instalar CRDs. Si no, screenshot preparado.

**S17 — El loop de reconciliación**
- Contenido: El operador observa los CRs (estado DESEADO), inspecciona el clúster (estado REAL), calcula la diferencia y actúa para converger. En bucle, para siempre. Sin humanos en el camino.
- Nota: Analogía: termostato — uno declara 21°C, el termostato mide, decide y actúa; nadie prende la calefacción a mano. Frase clave: "ustedes declaran, el operador opera".
- Diagrama: Círculo de 4 pasos: Observar → Comparar → Actuar → (volver a) Observar. Con el CR a un lado y el clúster al otro.

**S18 — Declarativo vs imperativo: el cambio cultural**
- Contenido: Antes: `kafka-topics.sh --create ...` (orden imperativa, se ejecuta y se olvida). Ahora: `kubectl apply -f topic.yaml` (declaración persistente, vigilada y corregida). El YAML en Git ES el clúster.
- Nota: Conectar con lo que viene en Cap 3: si alguien cambia un tópico a mano, el operador lo devuelve a lo declarado. Esto es lo que habilita GitOps (sesión 14).

**S19 — Por qué Strimzi y no otra cosa**
- Contenido: Operador de Kafka del ecosistema CNCF, código abierto, mantenido activamente, estándar de facto. Alternativas existen (operadores comerciales), pero Strimzi es la referencia neutral en la que se basan distribuciones comerciales (ej. Red Hat Streams).
- Nota: Dato honesto para la sala: Strimzi 0.51 (la versión del curso) salió en marzo de 2026 y la 1.0.0 salió en abril. Trabajamos sobre 0.51 por estabilidad de material, y la sesión 13 cubre exactamente cómo se hace ese upgrade — incluida la migración de API que la 1.0.0 exige. Esto convierte una posible objeción en argumento de venta del Cap 5.

### Bloque 2 — Anatomía de Strimzi (20 min, S20–S25)

**S20 — Vista de helicóptero**
- Contenido: Diagrama maestro de la anatomía: Cluster Operator al centro, Entity Operator (con Topic + User Operator adentro), el clúster Kafka (pods controller y broker), Drain Cleaner al costado.
- Nota: Presentar el elenco completo antes de entrar personaje por personaje. Este diagrama se redibuja en pizarra durante el resto del bloque.
- Diagrama: La pieza visual central de la sesión. Cluster Operator con flechas hacia todo lo que crea y vigila.

**S21 — Cluster Operator: el orquestador**
- Contenido: Es EL operador: vigila los CRs Kafka, KafkaNodePool, KafkaConnect, etc. Crea y opera los pods del clúster, los services, los secretos, los certificados. Un Cluster Operator puede gestionar múltiples clústeres Kafka en uno o varios namespaces.
- Nota: Aclarar jerarquía desde ya: el Cluster Operator se instala UNA vez (Lab 01); los clústeres Kafka se declaran después, los que se necesiten (Lab 02).

**S22 — Topic Operator y User Operator: la gestión declarativa**
- Contenido: Topic Operator: reconcilia recursos KafkaTopic contra tópicos reales. User Operator: reconcilia KafkaUser, genera credenciales (SCRAM/mTLS) como Secrets de K8s y gestiona ACLs y cuotas. Ambos viven juntos en el pod Entity Operator.
- Nota: "Trinidad" mnemotécnica: Cluster Operator es el jefe; Entity Operator es el pod que el jefe despliega; adentro van Topic y User Operator. Caps 3 los explota a fondo — aquí solo presentación.

**S23 — Drain Cleaner: el guardaespaldas de los drenajes**
- Contenido: Cuando K8s drena un nodo (mantención, upgrade del clúster), puede desalojar brokers sin criterio Kafka. Drain Cleaner intercepta el desalojo y se lo entrega al Cluster Operator para hacerlo en orden seguro, sin particiones sub-replicadas.
- Nota: Para un banco esto es continuidad operacional pura: "el equipo de plataforma parcha nodos sin coordinar con el equipo Kafka, y nadie pierde una réplica". Lab 07 lo demuestra en vivo.

**S24 — StrimziPodSet: el dato de credibilidad**
- Contenido: Strimzi NO usa StatefulSets. Construyó su propio controlador (StrimziPodSet) para control fino: rolling updates en orden consciente de Kafka, identidad de nodo exacta, operaciones por pod individual.
- Nota: Cerrar el arco abierto en S10: "les dije que StatefulSets no alcanzaban — ni al propio Strimzi le alcanzaron". Anécdota técnica que distingue al instructor.

**S25 — KRaft en Strimzi 0.51: sin ZooKeeper, con pools**
- Contenido: Strimzi 0.51 es KRaft-only: ZooKeeper no existe. Los nodos se declaran con KafkaNodePool y roles explícitos: controller, broker o ambos. Quorum de controllers estático (decisión de compatibilidad de Strimzi — Kafka aún no soporta migrar quorums estáticos a dinámicos).
- Nota: Los alumnos vienen de Kafka intermedio: algunos quizá operan aún con ZooKeeper. Mensaje: "ese mundo se terminó; acá los controllers son pods de un pool". El detalle del quorum se profundiza en sesión 4 con el clúster en la mano.

### Bloque 3 — El catálogo de Custom Resources (15 min, S26–S28)

**S26 — Los CRs del día a día**
- Contenido: Tabla de 4: `Kafka` (el clúster: versión, listeners, config), `KafkaNodePool` (los nodos: roles, réplicas, storage), `KafkaTopic` (tópicos como código), `KafkaUser` (usuarios, ACLs, cuotas).
- Nota: Estos 4 son el 80% del trabajo diario de un administrador. Mostrar un YAML mínimo de `Kafka` en pantalla — no para leerlo línea a línea, sino para que pierdan el miedo: "es un YAML como cualquier otro".

**S27 — Los CRs del ecosistema extendido**
- Contenido: Tabla de 4: `KafkaConnect` + `KafkaConnector` (integración y CDC — Cap 4), `KafkaMirrorMaker2` (replicación entre clústeres — Cap 4), `KafkaBridge` (acceso HTTP al clúster para clientes que no hablan protocolo Kafka), `KafkaRebalance` (rebalanceo con Cruise Control — Cap 5).
- Nota: KafkaBridge se menciona aquí como pieza del ecosistema pero no tiene laboratorio: dejarlo dicho explícitamente para administrar expectativas. Cada uno de los otros tiene su sesión.

**S28 — El mapa CR → curso**
- Contenido: El diagrama maestro de S13 anotado: cada pieza del clúster Meridiano con el CR que la declara y la sesión donde se construye.
- Nota: Refuerza la promesa del curso: "todo lo que vieron en este catálogo lo van a escribir con sus manos". Transición natural al cierre.

### Bloque 4 — Demo del instructor y cierre (5 min + demo, S29–S30)

**S29 — Demo: un clúster Kafka en un YAML**
- Contenido: Slide de apoyo para demo en vivo: `kubectl apply` de un Kafka + KafkaNodePool mínimo en kind, y ver los pods aparecer. Comandos visibles en la slide como respaldo si la demo falla.
- Nota: PREPARAR Y ENSAYAR antes de la sesión (esta demo es además parte del Día 1-2 de formación del instructor). Plan B: grabación de pantalla de la misma secuencia. El efecto buscado: "declaré 15 líneas y apareció un clúster completo".

**S30 — Cierre del capítulo: lo que viene**
- Contenido: Resumen en 3 frases: (1) Kafka en K8s necesita un operador, (2) Strimzi es ese operador y conocemos su anatomía, (3) desde la próxima sesión, manos al clúster: instalación del Cluster Operator con Helm. Recordatorio de prerrequisitos de laboratorio (kind funcionando, recursos de máquina).
- Nota: Anunciar que la sesión 3 arranca el Lab 01 y que incluye una introducción guiada a Helm desde cero. Pedir que validen su entorno local antes de la próxima sesión (checklist del doc de Operaciones).

---

## Resumen ejecutivo del guion

| Sesión | Slides | Bloques | Diagramas clave |
|---|---|---|---|
| 1 | S1–S14 (14) | Narrativa → Problemas → Patrones fallidos → Mapa del curso | Mapa maestro del curso (S13) |
| 2 | S15–S30 (16) | Patrón Operator → Anatomía Strimzi → Catálogo CRs → Demo | Loop de reconciliación (S17), Anatomía Strimzi (S20) |

**Total Cap 1: 30 slides** (calza con estimación de 80–100 para el curso completo, siendo este el capítulo más teórico).

**Pendientes que este guion deja registrados:**
1. Vertido a template Netec cuando Lucy envíe las plantillas.
2. Diagramas S13, S17 y S20 — decidir si van como imagen renderizada (estilo workbooks del CCAAK) o dibujo en pizarra.
3. Demo de S29 depende de la formación del instructor (Día 1–2 con kind) — ensayar antes de cerrar la sesión 2.
