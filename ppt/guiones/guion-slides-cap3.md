# Guion de Slides — Capítulo 3: Gestión declarativa y seguridad

**Curso:** Administración de Apache Kafka sobre Kubernetes con Strimzi
**Sesiones cubiertas:** 6, 7 y 8 (3 × 60 min: ~20 min teoría + ~40 min laboratorio por sesión)
**Narrativa:** Banco Meridiano — Plataforma de Eventos de Pagos
**Labs asociados:** Lab 03 (sesiones 6–7) y Lab 04 (sesión 8)
**Estado:** Guion de contenido. Pendiente vertido a template Netec.

**Convenciones:** mismas de los guiones anteriores. La numeración continúa desde S51.

**Nota de tono del capítulo:** este es el capítulo donde el curso se vuelve "bancario" en serio: credenciales, permisos mínimos, certificados, auditoría. El hilo narrativo es que la plataforma de pagos deja de ser un clúster abierto y pasa a ser un sistema que un auditor aprobaría.

---

## SESIÓN 6 — Tópicos como código con KafkaTopic y el Topic Operator

**Objetivo de la sesión:** que el alumno gestione el ciclo de vida completo de tópicos vía KafkaTopic, entienda al Topic Operator como fuente única de verdad y sepa cuándo NO conviene usarlo.

### Bloque teórico (20 min, S52–S58)

**S52 — Mapa maestro: dónde estamos**
- Contenido: Cimientos y clúster durable iluminados. Por iluminar: "Tópicos y credenciales como código".
- Nota: "El clúster de Meridiano existe y sobrevive fallos. Pero hoy cualquiera con acceso crea lo que quiere y nadie sabe quién cambió qué. Este capítulo arregla eso."

**S53 — El problema del tópico fantasma**
- Contenido: Escenario real: alguien crea un tópico por CLI a las 3 AM durante un incidente, con 1 réplica y retención infinita. Nadie lo documenta. Seis meses después: ¿quién lo creó, por qué, quién depende de él? La gestión imperativa de tópicos no deja rastro ni control.
- Nota: Pedir manos levantadas: "¿quién ha heredado un clúster con 400 tópicos sin dueño?". Los admins de la sala tienen esta cicatriz. El dolor compartido abre la solución.

**S54 — KafkaTopic: el tópico como recurso**
- Contenido: YAML mínimo en pantalla: nombre, particiones, réplicas, config (retención, compresión, cleanup.policy). Se aplica con kubectl, vive en Git, tiene historia, autor y revisión por PR. El tópico `pagos.meridiano.transacciones` declarado como código.
- Nota: Mostrar el YAML completo — es corto y eso es parte del mensaje. Énfasis en la consecuencia organizacional: crear un tópico pasa de "comando de madrugada" a "pull request revisado".

**S55 — El Topic Operator: fuente única de verdad**
- Contenido: El Topic Operator reconcilia KafkaTopic ↔ tópico real. Cambios en el CR se aplican al clúster. Cambio manual por CLI sobre un tópico gestionado → el operador lo detecta y lo revierte a lo declarado. El drift muere por diseño.
- Nota: Demo conceptual potente para el lab: cambiar retención por CLI y ver al operador devolverla. Advertencia operacional: esto también significa que "arreglar a mano" un tópico gestionado no funciona — el arreglo se hace en el YAML o no se hace.
- Diagrama: Triángulo Git (deseado) → Topic Operator → clúster (real), con la flecha de reversión del drift marcada en rojo.

**S56 — Cuándo NO usar el Topic Operator**
- Contenido: Escenarios donde no conviene: tópicos creados dinámicamente por aplicaciones (Kafka Streams y sus tópicos internos, frameworks con auto-create), entornos con miles de tópicos efímeros, equipos sin flujo Git maduro. Convivencia: el operador gestiona SOLO lo que está declarado; lo externo no se toca.
- Nota: La ley pide este matiz explícitamente y es señal de madurez del curso: la herramienta no es religión. Regla práctica para Meridiano: tópicos de negocio (pagos, fraude) declarados; tópicos internos de frameworks, libres.

**S57 — GitOps: la consecuencia natural**
- Contenido: Si los tópicos son YAML en Git, el paso siguiente es que NADIE haga kubectl apply a mano: un agente (Argo CD / Flux) sincroniza Git → clúster. Mención anticipada: se profundiza en la sesión 14 como parte del runbook de Meridiano.
- Nota: Solo sembrar la semilla (1 minuto). El capstone la cosecha. Para los auditores del banco: Git se convierte en el registro de auditoría de la configuración del clúster.

**S58 — Lanzamiento Lab 03 (parte 1): "Tópicos como código"**
- Contenido: Objetivos: (1) declarar los tópicos de la plataforma de pagos (`pagos.meridiano.transacciones`, `pagos.meridiano.confirmaciones`) vía KafkaTopic, (2) modificar configuración por YAML y observar la reconciliación, (3) provocar drift por CLI y ver la reversión, (4) inspeccionar cómo convive un tópico no gestionado. Tiempo: 40 min.
- Nota: El momento "el operador me revirtió el cambio" es el clic conceptual del capítulo — dejar que lo experimenten antes de explicarlo dos veces.

---

## SESIÓN 7 — Usuarios, ACLs y cuotas con KafkaUser

**Objetivo de la sesión:** que el alumno cree usuarios con SCRAM-SHA-512 y mTLS, defina ACLs de mínimo privilegio y cuotas, y entienda la gestión y rotación de credenciales del User Operator.

### Bloque teórico (20 min, S59–S65)

**S59 — Mapa maestro: dónde estamos**
- Contenido: Tópicos como código iluminado a medias; hoy se completa con "credenciales y permisos".
- Nota: "Los tópicos ya tienen dueño y rastro. Ahora le ponemos nombre y apellido a quien produce y consume — y le quitamos todo permiso que no necesite."

**S60 — El clúster anónimo es un riesgo inaceptable**
- Contenido: Estado actual del lab: cualquier cliente con acceso de red produce y consume lo que quiera. En una plataforma de pagos eso es: lectura de transacciones sin control, inyección de eventos falsos, cero trazabilidad por actor. Identidad + autorización no son opcionales en banca.
- Nota: Tono serio sin terrorismo: enumerar los tres riesgos y dejar que el contexto bancario de la sala haga el resto. Transición: "Strimzi resuelve identidad, permisos y límites con UN recurso".

**S61 — KafkaUser: identidad como recurso**
- Contenido: YAML de KafkaUser: autenticación (`scram-sha-512` o `tls`), autorización (ACLs), cuotas. El User Operator reconcilia: crea el usuario en Kafka y materializa las credenciales como **Secret de Kubernetes** en el namespace.
- Nota: La elegancia a destacar: el ciclo completo (usuario + password/certificado + permisos) nace de un solo apply. Nadie copia passwords por chat — la aplicación monta el Secret y listo.

**S62 — SCRAM-SHA-512 vs mTLS: cuándo cada uno**
- Contenido: **SCRAM-SHA-512**: usuario y contraseña con challenge-response (la contraseña nunca viaja); simple de consumir desde cualquier cliente. **mTLS**: el certificado ES la identidad; máxima garantía, requiere gestión de certificados en el cliente. Meridiano usa ambos: SCRAM para aplicaciones (`app-pagos`), mTLS para servicios críticos (`motor-fraude`).
- Nota: Delta explícito contra cursos básicos: aquí no hay SASL/PLAIN — un banco no manda contraseñas en texto plano ni para aprender. Los dos mecanismos se practican en el lab, no se elige uno. Nota de honestidad para alumnos avanzados: el listener SCRAM interno del lab va sin TLS por simplicidad; en producción bancaria SCRAM viaja siempre sobre TLS — exactamente como se hace en el Lab 04 con el listener externo (SASL_SSL). El trade-off se declara, no se esconde.

**S63 — ACLs declarativas: mínimo privilegio**
- Contenido: ACLs por recurso (tópico, grupo, clúster), operación (Read, Write, Describe...) y patrón (literal o prefijo). Ejemplo Meridiano en pantalla: `app-pagos` solo escribe en `pagos.meridiano.transacciones`; `motor-fraude` solo lee ese tópico con su consumer group. Nada más.
- Nota: Leer las ACLs del ejemplo en voz alta como frases: "app-pagos puede escribir transacciones y nada más". Si las ACLs no se pueden leer así de simple, están mal diseñadas. El patrón por prefijo (`pagos.meridiano.*`) como herramienta de escala.
- Diagrama: Matriz usuarios × tópicos con celdas marcadas solo donde hay permiso — visualmente casi vacía: eso ES mínimo privilegio.

**S64 — Cuotas y rotación: operación civilizada**
- Contenido: Cuotas por usuario (bytes/s de producción y consumo, % de CPU de request): un cliente desbocado no tumba la plataforma de pagos. Rotación de credenciales: el User Operator regenera el Secret y el clúster acepta transición sin downtime — los clientes recargan el Secret y siguen.
- Nota: Las cuotas como "fusibles por inquilino" — para SREs es música. La rotación sin downtime conecta con políticas bancarias de vencimiento de credenciales: lo que hoy es proyecto de un trimestre, acá es reconciliación.

**S65 — Lanzamiento Lab 03 (parte 2): "Identidad y mínimo privilegio"**
- Contenido: Objetivos: (1) crear `app-pagos` (SCRAM) y `motor-fraude` (mTLS) con sus ACLs de mínimo privilegio, (2) producir y consumir con credenciales reales desde kcat, (3) verificar que lo no permitido efectivamente falla (la prueba negativa), (4) aplicar cuotas y observarlas actuar. Desafío extra: rotar credenciales de `app-pagos` sin cortar el flujo. Tiempo: 40 min.
- Nota: Insistir en la prueba negativa como hábito profesional: seguridad no verificada en su rechazo no está verificada. Nota de continuidad: al cerrar esta sesión el clúster ya exige identidad — el listener abierto se cierra en la sesión 8, donde el cerco se completa.

---

## SESIÓN 8 — Listeners, TLS/mTLS y exposición segura del clúster

**Objetivo de la sesión:** que el alumno configure listeners internos y externos con TLS end-to-end, entienda el ciclo de vida de los certificados de Strimzi y sepa elegir el tipo de listener correcto por escenario — incluido su EKS.

### Bloque teórico (20 min, S66–S72)

**S66 — Mapa maestro: dónde estamos**
- Contenido: Tópicos y credenciales iluminados. Por iluminar: "Acceso seguro desde fuera". Con esta pieza, el Cap 3 completo queda encendido.
- Nota: "Tenemos identidad y permisos, pero todo ocurre dentro del clúster K8s. Las aplicaciones del banco viven fuera. Hoy abrimos la puerta — sin abrir un hoyo."

**S67 — Listeners en Strimzi: las puertas declaradas**
- Contenido: Cada listener se declara en el CR Kafka: nombre, puerto, tipo, TLS y autenticación. Tipos: `internal` (dentro del clúster K8s), `nodeport`, `loadbalancer`, `route` (OpenShift). Cada listener puede exigir su propio mecanismo de autenticación.
- Nota: Recordar el dolor de advertised.listeners de la sesión 1 (S7): Strimzi genera la dirección anunciada correcta por cada tipo de listener automáticamente — uno de los problemas más sufridos de Kafka, resuelto por declaración. Regla que importa para el lab: cada listener admite UN SOLO mecanismo de autenticación. Por eso, para exponer SCRAM (aplicaciones) y mTLS (servicios críticos) hacia afuera, hacen falta DOS listeners externos separados — no se pueden mezclar en uno. Es el patrón real de banca: una puerta por tipo de credencial.

**S68 — Elegir el tipo: el mapa de decisión (y el caso EKS)**
- Contenido: `internal` para todo lo que vive en el mismo clúster K8s (lo más común y lo más barato). Fuera del clúster: `nodeport` (simple, sin costo de infraestructura, puertos altos), `loadbalancer` (la vía natural en nubes — en EKS provisiona un NLB de AWS por las annotations correspondientes), `route` (solo OpenShift). Tabla de decisión en pantalla.
- Nota: Hablarle directo a su realidad: "en su EKS, el listener externo es `loadbalancer` con NLB". En el lab usamos `nodeport` porque kind no tiene loadbalancers — y el manifiesto de referencia EKS va en el repo, comentado annotation por annotation. El puente kind→EKS más importante del curso.

**S69 — El listener `ingress`: deprecado, y la lección**
- Contenido: Existía un tipo `ingress` (TLS passthrough sobre NGINX Ingress Controller). Quedó **deprecado en Strimzi 0.51** tras el archivado del proyecto NGINX Ingress Controller (marzo 2026). El código permanece pero sin desarrollo futuro. Lección: las plataformas declarativas también dependen de ecosistemas vivos.
- Nota: Dato validado contra release notes oficiales — citarlo con fecha da autoridad. Si alguien del banco usa ingress hoy para otras cargas: el archivado de NGINX Ingress les afecta más allá de Kafka; vale el desvío de 1 minuto.

**S70 — TLS end-to-end: las CAs de Strimzi**
- Contenido: Strimzi opera dos CAs propias: **cluster CA** (certificados de brokers, tráfico interno SIEMPRE cifrado) y **clients CA** (certificados de usuarios mTLS). Renovación automática con ventanas configurables. Los clientes externos confían en la cluster CA vía el Secret `<cluster>-cluster-ca-cert`.
- Nota: Subrayar lo que ya recibieron gratis: desde el Lab 02, TODO el tráfico interno (réplica, controllers) viaja cifrado sin que nadie configurara nada. Lo que se agrega hoy es extender esa confianza hacia afuera.
- Diagrama: Dos árboles de confianza (cluster CA / clients CA) con sus certificados hijos, y el cliente externo validando contra la cluster CA.

**S71 — CA propia del banco y ciclo de vida**
- Contenido: Escenario corporativo: el banco ya tiene PKI y políticas (la CA de Strimzi no está en su cadena de confianza). Strimzi soporta operar con CA propia del cliente (certificados emitidos por la PKI corporativa). Trade-off: la renovación pasa a ser responsabilidad del banco. Ventanas de renovación y rotación de certificados de broker sin downtime (rolling).
- Nota: Pregunta casi garantizada del equipo de seguridad de un banco — por eso tiene slide propia. Posición recomendada: CA de Strimzi para empezar (automatización completa), CA corporativa cuando seguridad lo exija, sabiendo el costo operacional que se asume.

**S72 — Lanzamiento Lab 04: "La puerta segura"**
- Contenido: Objetivos: (1) declarar DOS listeners externos `nodeport` con TLS — uno con autenticación SCRAM-SHA-512 (para aplicaciones) y otro con mTLS (para servicios críticos), porque un listener admite un solo mecanismo de autenticación, (2) extraer la cluster CA y conectarse desde fuera del clúster con kcat como `app-pagos` por el listener SCRAM, (3) verificar mTLS con `motor-fraude` por el listener mTLS, (4) revisar el manifiesto de referencia `loadbalancer`/NLB para EKS, (5) cerrar la puerta vieja: eliminar el listener plano y verificar que ahora falla por conexión, no por autorización. Desafío extra: inspeccionar el certificado del broker con openssl y leer su cadena. Tiempo: 40 min.
- Nota: Cierre del capítulo con el mapa maestro: la plataforma de pagos ahora exige identidad, otorga mínimo privilegio y cifra de extremo a extremo — "esto ya se parece a un sistema que un auditor firma". Anticipo Cap 4: el core legado del banco entra al río de eventos vía CDC.

---

## Resumen ejecutivo del guion

| Sesión | Slides | Lab | Diagramas clave |
|---|---|---|---|
| 6 | S52–S58 (7) | Lab 03 p1 — Tópicos como código | Triángulo Git/Operator/clúster (S55) |
| 7 | S59–S65 (7) | Lab 03 p2 — Identidad y mínimo privilegio | Matriz de ACLs (S63) |
| 8 | S66–S72 (7) | Lab 04 — La puerta segura | Árboles de confianza de las CAs (S70) |

**Total Cap 3: 21 slides.** Acumulado curso: 72 (S1–S72). Proyección final ~95–100: dentro del rango estimado.

**Pendientes que este guion deja registrados:**
1. Vertido a template Netec (igual que Caps 1–2).
2. Manifiesto de referencia `loadbalancer` + annotations NLB para EKS — se escribe con la spec del Lab 04, comentado annotation por annotation.
3. Decisión fina para la spec del Lab 04: si el listener sin autenticación de los Labs 01–03 se elimina o se conserva para contraste didáctico. Propuesta del arquitecto: eliminarlo como acto final del lab ("cerrar la puerta vieja") — refuerza la narrativa de endurecimiento progresivo.
4. Verificar en el alumno cero los tiempos de la parte mTLS del Lab 03 p2 (extracción de Secrets y configuración de kcat con certificados suele comerse minutos) — si no calza en 40 min, el desafío de rotación pasa a material post-sesión.
