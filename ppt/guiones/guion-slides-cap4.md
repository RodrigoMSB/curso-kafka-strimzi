# Guion de Slides — Capítulo 4: Ecosistema extendido y observabilidad

**Curso:** Administración de Apache Kafka sobre Kubernetes con Strimzi
**Sesiones cubiertas:** 9, 10 y 11 (3 × 60 min: ~20 min teoría + ~40 min laboratorio por sesión)
**Narrativa:** Banco Meridiano — Plataforma de Eventos de Pagos
**Labs asociados:** Lab 05 (sesión 9) y Lab 06 (sesiones 10–11)
**Estado:** Guion de contenido. Pendiente vertido a template Netec.

**Convenciones:** mismas de los guiones anteriores. La numeración continúa desde S72.

**Nota de tono del capítulo:** la plataforma segura ya existe; este capítulo la conecta con el mundo. El core legado entra al río de eventos (CDC), el negocio gana contingencia (DR con MM2) y la operación gana ojos (observabilidad). Es el capítulo donde Meridiano deja de ser un clúster y pasa a ser una plataforma.

---

## SESIÓN 9 — Kafka Connect declarativo y Connect Build

**Objetivo de la sesión:** que el alumno despliegue Kafka Connect con Connect Build, configure un conector vía KafkaConnector y ejecute un caso real de CDC con Debezium sobre PostgreSQL.

### Bloque teórico (20 min, S73–S79)

**S73 — Mapa maestro: dónde estamos**
- Contenido: Cap 3 completo iluminado. Por iluminar: "El core legado entra al río de eventos".
- Nota: "La plataforma está segura pero vacía de negocio real. El core bancario de Meridiano sigue escribiendo en PostgreSQL, como hace 20 años. Hoy esos datos empiezan a fluir como eventos — sin tocar una línea del core."

**S74 — El problema: el core no se toca**
- Contenido: Realidad bancaria: el core es intocable (riesgo, regulación, costo). Pero el negocio nuevo (motor de fraude, confirmaciones en línea, analítica) necesita los datos del core EN TIEMPO REAL. Opciones malas: polling por batch (lento, carga la BD), doble escritura desde el core (tocar lo intocable). Opción buena: capturar el log de cambios de la BD.
- Nota: CDC explicado por el dolor antes que por la sigla. El log de transacciones de PostgreSQL (WAL) ya registra cada cambio — la idea genial es leerlo como fuente de eventos. El core ni se entera.

**S75 — Kafka Connect: el puerto de carga del clúster**
- Contenido: Connect = runtime de integración del ecosistema Kafka: conectores source (mundo → Kafka) y sink (Kafka → mundo), corriendo sobre workers escalables con offsets gestionados. En Strimzi: el CR **KafkaConnect** declara el runtime (réplicas, recursos, config) y el operador lo gestiona como todo lo demás.
- Nota: Para quienes operaron Connect clásico: el delta es que workers, config y ciclo de vida ahora son declarativos. Para quienes no: basta la metáfora del puerto de carga — los conectores son las grúas, cada una sabe cargar/descargar un sistema específico.

**S76 — Connect Build: imágenes sin Dockerfiles**
- Contenido: El problema clásico: agregar un plugin a Connect = mantener un Dockerfile, pipeline de build, registry, versionado. Connect Build lo vuelve declarativo: en el CR se listan los plugins (artefactos Maven/zip con checksum) y Strimzi **construye y publica la imagen** automáticamente hacia un registry destino.
- Nota: Detalle de infraestructura honesto: "construye y publica" implica un registry al que pushear — en el lab usamos un registry local junto a kind (ya preparado en el material); en su EKS sería ECR. Es el costo oculto de la magia y conviene decirlo antes de que lo descubran.
- Diagrama: CR KafkaConnect con lista de plugins → Strimzi construye → imagen en registry → pods de Connect corriendo la imagen.

**S77 — KafkaConnector: el conector como recurso**
- Contenido: El CR **KafkaConnector** declara cada conector: clase, configuración, tareas, estado (running/paused/stopped). Reemplaza la API REST imperativa de Connect clásico. Reinicios, pausas y cambios de config: por YAML, con historia en Git.
- Nota: Cerrar el paralelo del capítulo 3: KafkaTopic es a los tópicos lo que KafkaConnector es a los conectores — el mismo patrón mental, tercera vez. A esta altura los alumnos deberían poder predecir cómo funciona antes de verlo: hacérselos notar refuerza que YA piensan declarativo.

**S78 — Debezium: el oído en el log de PostgreSQL**
- Contenido: Debezium = familia de conectores source CDC. El conector PostgreSQL lee el WAL vía replicación lógica (plugin `pgoutput`, nativo de PostgreSQL): cada INSERT/UPDATE/DELETE en las tablas del core se vuelve un evento estructurado (antes/después, operación, timestamp, transacción) en un tópico Kafka. El tópico destino lleva el prefijo del conector: la tabla `public.clientes` del core llega a `core.public.clientes`. Snapshot inicial + streaming continuo.
- Nota: Mostrar UN evento Debezium real en pantalla (JSON recortado a lo esencial: op, before, after). Conectarlo al negocio: "este evento es un cliente de Meridiano actualizando sus datos — y el motor de fraude lo sabe medio segundo después, sin que el core haya hecho nada".

**S79 — Lanzamiento Lab 05: "El core entra al río"**
- Contenido: Objetivos: (1) desplegar PostgreSQL como core simulado de Meridiano (en su propio namespace `meridiano-core`) con la tabla de clientes, (2) desplegar KafkaConnect con Connect Build incorporando el plugin Debezium, (3) declarar el KafkaConnector CDC apuntando al core, (4) verificar el snapshot inicial y el streaming: insertar/actualizar filas y ver los eventos llegar a `core.public.clientes`. Desafío extra: agregar una segunda tabla al conector y ver nacer su tópico. Tiempo: 40 min.
- Nota: Sesión técnica más densa del curso en infraestructura (BD + build + registry + conector). El material trae el PostgreSQL y el registry pre-resueltos para que los 40 min se gasten en lo que importa: Connect Build y el conector. Si el build de la imagen demora en máquinas lentas, ese tiempo se usa para explicar qué está construyendo — el tiempo muerto se vuelve teoría aplicada.

---

## SESIÓN 10 — MirrorMaker 2 para replicación multi-clúster

**Objetivo de la sesión:** que el alumno despliegue un segundo clúster de contingencia, replique tópicos con KafkaMirrorMaker2 en topología activo-pasivo y ejecute un failover con continuidad de offsets de consumer groups.

### Bloque teórico (20 min, S80–S86)

**S80 — Mapa maestro: dónde estamos**
- Contenido: CDC iluminado. Por iluminar: "Contingencia — el segundo clúster".
- Nota: "El río de eventos ya mueve el negocio de Meridiano. Pregunta de directorio: ¿y si la región se cae? Para un banco, esa pregunta tiene regulador. Hoy construimos la respuesta."

**S81 — Por qué la replicación interna no basta**
- Contenido: Rack awareness (sesión 5) protege contra la caída de UNA zona. No protege contra: caída regional completa, desastre del clúster K8s, error humano catastrófico (borrar el namespace equivocado). La respuesta: un segundo clúster Kafka independiente, en otra región/infraestructura, con los datos replicados.
- Nota: Encadenar explícitamente las capas de resiliencia construidas: réplicas (partición) → rack awareness (zona) → MM2 (región/clúster). Cada capa contra un tamaño de desastre distinto. Para el regulador bancario, esta capa es la que se llama plan de continuidad.

**S82 — MirrorMaker 2: replicación entre clústeres**
- Contenido: MM2 replica tópicos, configuraciones y offsets de consumer groups entre clústeres Kafka. Corre sobre el runtime de Connect (por eso viene después de la sesión 9). En Strimzi: el CR **KafkaMirrorMaker2** declara origen, destino y qué se replica (patrones de tópicos y grupos).
- Nota: Aclarar la convención de nombres que verán en el lab. Por defecto MM2 prefija los tópicos replicados con el alias del clúster origen (ej. `pagos.pagos.meridiano.transacciones`) — útil en topologías complejas para evitar ciclos. Pero en Meridiano usamos **IdentityReplicationPolicy**: los tópicos se replican con nombre IDÉNTICO en el destino (sin prefijo), lo natural para un activo-pasivo donde el DR debe ser un espejo exacto del primario. El trade-off es disciplina: nunca replicar de vuelta (origen→destino solamente). Decirlo explícito porque es una decisión de diseño, no un default.

**S83 — Activo-pasivo: la topología de Meridiano**
- Contenido: **Activo-pasivo**: producción en el clúster principal; el pasivo recibe réplica y espera. Simple de razonar, failover claro. **Activo-activo**: ambos producen y se replican mutuamente — más capacidad y cercanía geográfica, pero complejidad real (ciclos, resolución de conflictos, naming). Decisión Meridiano: activo-pasivo; activo-activo se analiza, no se construye.
- Nota: La ley pide exactamente este balance: activo-pasivo en las manos, activo-activo en la cabeza. Regla honesta para la sala: "si no pueden explicar en una pizarra cómo evitan el ciclo de replicación, no están listos para activo-activo".
- Diagrama: Dos clústeres (`pagos` / `dr`) con flecha MM2 unidireccional y los consumidores apuntando al principal con línea punteada hacia el pasivo ("en caso de failover").

**S84 — El detalle que separa juniors de seniors: los offsets**
- Contenido: Replicar mensajes no basta en un failover real: un consumer group que migra al clúster pasivo necesita saber DÓNDE iba. MM2 puede traducir y replicar offsets de consumer groups (checkpoints) para que el consumidor retome en el destino sin reprocesar todo ni perder posición.
- Nota: Hacer tangible el desastre que esto evita: motor de fraude con 50 millones de eventos procesados; sin traducción de offsets, tras el failover reprocesa TODO (50M de falsas alarmas) o parte del final (fraudes sin revisar). Honestidad de alcance: en el lab demostramos la réplica de datos completa (consumir del `dr` y ver toda la historia); la traducción de offsets se explica como concepto y queda como lectura — montar un failover de consumidores con checkpoints en kind excede los 40 min. En su EKS con dos clústeres reales, es el siguiente paso natural.

**S85 — Anatomía de un failover**
- Contenido: Secuencia: (1) decisión de failover (criterios definidos ANTES del desastre), (2) detener productores hacia el principal, (3) redirigir productores al pasivo, (4) consumidores migran usando los offsets traducidos, (5) el pasivo es el nuevo principal. La vuelta atrás (failback) es otro proyecto — planificarlo también.
- Nota: Subrayar el paso 1: la decisión es lo que nunca se ensaya y por eso los failovers reales demoran horas en empezar. El runbook del capstone (sesión 14) incluye estos criterios — sembrar esa conexión aquí.

**S86 — Lanzamiento Lab 06 (parte 1): "El clúster de contingencia"**
- Contenido: Objetivos: (1) ampliar el scope del operador para que vigile el namespace `meridiano-dr` (helm upgrade — gobernanza en vivo) y desplegar el clúster `dr` (un nodo dual-role, topología mínima — la máquina del alumno corre dos clústeres desde ahora), (2) crear la identidad `mm2` con sus ACLs y declarar KafkaMirrorMaker2 replicando `pagos.meridiano.*` con IdentityReplicationPolicy, (3) producir en `pagos` y verificar la réplica fluyendo hacia `dr` con nombre idéntico, (4) simular el desastre: consumir directamente desde `dr` y comprobar que la historia de pagos está completa hasta el último offset replicado. Tiempo: 40 min.
- Nota: ADVERTENCIA DE RECURSOS en voz alta antes de partir: dos clústeres + Connect + MM2 es lo más pesado que corre el curso en una máquina de 16 GB — el material trae topologías recortadas a propósito (el pico medido es ~52% de 16 GB) y conviene cerrar aplicaciones pesadas. La observabilidad de la próxima sesión se monta SOBRE este mismo clúster: no destruir nada al terminar.

---

## SESIÓN 11 — Observabilidad: Prometheus, Grafana y tracing distribuido

**Objetivo de la sesión:** que el alumno exponga métricas de ambos clústeres vía JMX Exporter, monte los dashboards oficiales de Strimzi en Grafana, configure alertas sobre métricas críticas y comprenda el rol del tracing distribuido con OpenTelemetry.

### Bloque teórico (20 min, S87–S93)

**S87 — Mapa maestro: dónde estamos**
- Contenido: Contingencia iluminada. Por iluminar: "Los ojos de la plataforma". Con esta pieza, el Cap 4 completo queda encendido.
- Nota: "Meridiano ya tiene plataforma segura, integrada y con contingencia. Pero operamos a ciegas: si una partición queda sub-replicada a las 2 AM, nadie lo sabe hasta que duele. Hoy le ponemos ojos."

**S88 — Las tres preguntas de la observabilidad**
- Contenido: Métricas responden "¿cómo está el sistema?" (números en el tiempo). Logs responden "¿qué pasó exactamente?" (eventos discretos). Trazas responden "¿por dónde pasó esta operación?" (el viaje de un request). Hoy: métricas a fondo (el día a día del administrador), logs ya los usamos (operador), trazas al final de la sesión.
- Nota: Encuadre clásico pero útil para ordenar la sesión. Los SRE de la sala lo conocen — pedirles que lo digan ellos: "¿qué les falta hoy para operar su Kafka tranquilos?" suele responder la agenda sola.

**S89 — JMX Exporter: las métricas ya estaban ahí**
- Contenido: Kafka expone cientos de métricas por JMX desde siempre. Strimzi integra el JMX Exporter como agente: un ConfigMap con reglas + una referencia en el CR Kafka = endpoint Prometheus en cada pod. Sin sidecars, sin agentes externos, sin tocar imágenes.
- Nota: Para los que vienen del mundo VM: esto reemplaza la instalación manual del javaagent en cada broker. La configuración de reglas que usaremos es la oficial del proyecto Strimzi — no reinventamos el mapeo de métricas.

**S90 — Los dashboards oficiales de Strimzi**
- Contenido: El proyecto mantiene dashboards Grafana listos: Kafka (brokers, particiones, tráfico), operadores, Connect, MirrorMaker 2, Cruise Control. Se importan y funcionan contra las reglas oficiales del exporter. En el lab: UN Prometheus y UN Grafana observando AMBOS clústeres de Meridiano.
- Nota: Mensaje anti-síndrome-de-dashboard-propio: empezar con los oficiales y personalizar después con criterio. Detalle técnico heredado de cursos anteriores: el datasource de Grafana debe llamarse exactamente como esperan los dashboards (uid `prometheus`) — el material ya lo trae resuelto, pero mencionarlo evita una hora de frustración a quien lo monte en su banco.

**S91 — Las métricas que despiertan a alguien**
- Contenido: Las cuatro alertas mínimas de una plataforma Kafka de pagos: **particiones under-replicated** (> 0 sostenido = durabilidad comprometida), **lag de consumidores** (el motor de fraude atrasado = fraude sin revisar), **disco** (% usado y proyección — Kafka sin disco no degrada: muere), **brokers/controllers caídos**. Para cada una: umbral sugerido y POR QUÉ ese umbral.
- Nota: Énfasis de criterio sobre herramienta: la pregunta no es "qué puedo graficar" sino "qué me despierta a las 3 AM y por qué". Conectar lag con la narrativa: el lag del `motor-fraude` no es un número técnico — es riesgo de negocio acumulándose.
- Diagrama: Semáforo de las 4 métricas con sus umbrales (verde/amarillo/rojo) — candidata a slide de referencia que los alumnos se llevan impresa en la memoria.

**S92 — Tracing distribuido con OpenTelemetry (demo del instructor)**
- Contenido: Las métricas dicen que el sistema sufre; las trazas dicen DÓNDE: el viaje de un evento de pago (productor → tópico → Connect → consumidor) con tiempos por salto. Kafka y sus clientes se instrumentan con OpenTelemetry; las trazas se visualizan en un backend compatible (Jaeger en la demo). Strimzi soporta instrumentación OTel en Connect, MM2 y Bridge.
- Nota: DEMO DEL INSTRUCTOR, no lab (decisión de alcance: montar el backend de tracing en 20 kinds no paga sus minutos en un curso de 14 horas). La demo muestra una traza real de extremo a extremo y se entrega como material reproducible para quien quiera montarla después. Decirlo con esa honestidad.

**S93 — Lanzamiento Lab 06 (parte 2): "Los ojos de Meridiano"**
- Contenido: Objetivos: (1) habilitar JMX Exporter en ambos clústeres vía ConfigMap + CR, (2) desplegar Prometheus y Grafana con los dashboards oficiales, (3) generar carga sobre `pagos.meridiano.transacciones` y verla en los dashboards (incluido el tráfico de MM2), (4) configurar la alerta de under-replicated y dispararla matando un broker. Desafío extra: alerta de lag sobre el consumer group del motor de fraude. Tiempo: 40 min. Cierra con demo OTel del instructor (~5 min).
- Nota: Disparar la alerta matando un broker es el clímax operacional del capítulo: ven el dashboard reaccionar, la alerta encenderse y al operador (Strimzi) reparar — el ciclo completo de detección y recuperación en vivo. Cierre del capítulo con el mapa maestro casi completo: queda el Cap 5 — operar fino (rebalanceo, upgrades) y el plan de migración.

---

## Resumen ejecutivo del guion

| Sesión | Slides | Lab | Diagramas clave |
|---|---|---|---|
| 9 | S73–S79 (7) | Lab 05 — El core entra al río | Flujo Connect Build (S76) |
| 10 | S80–S86 (7) | Lab 06 p1 — El clúster de contingencia | Topología activo-pasivo (S83) |
| 11 | S87–S93 (7) | Lab 06 p2 — Los ojos de Meridiano | Semáforo de alertas (S91) |

**Total Cap 4: 21 slides.** Acumulado curso: 93 (S1–S93). Queda Cap 5 (~20–25 slides): proyección final ~115. Sobre la estimación inicial de 80–100 — aceptable para 14 sesiones, pero se revisa el conteo final al cerrar Cap 5 por si conviene podar.

**Pendientes que este guion deja registrados:**
1. Vertido a template Netec (igual que Caps 1–3).
2. Registry local para Connect Build junto a kind — pieza de infraestructura del Lab 05 que debe quedar pre-resuelta en el material (y agregarse al doc de setup de Operaciones, hallazgo #4 de la revisión).
3. Demo OTel de S92: requiere montaje propio del instructor (Jaeger + app instrumentada) — entra al plan de formación como hito posterior al Lab 06; plan B: grabación de pantalla.
4. Topologías recortadas exactas para correr dos clústeres + Connect + MM2 + Prometheus/Grafana en 16 GB — la decisión de dimensionamiento más delicada del curso, se cierra en la spec del Lab 06 y se valida con el alumno cero ANTES de darla por viable.
5. Evento Debezium de ejemplo para S78 — se captura real durante la construcción del Lab 05.
