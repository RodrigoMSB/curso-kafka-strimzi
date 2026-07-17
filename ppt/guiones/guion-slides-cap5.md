# Guion de Slides — Capítulo 5: Operación avanzada y migración

**Curso:** Administración de Apache Kafka sobre Kubernetes con Strimzi
**Sesiones cubiertas:** 12, 13 y 14 (3 × 60 min)
**Narrativa:** Banco Meridiano — Plataforma de Eventos de Pagos
**Labs asociados:** Lab 07 (sesiones 12–13) y Capstone (sesión 14)
**Estado:** Guion de contenido. Pendiente vertido a template Netec.

**Convenciones:** mismas de los guiones anteriores. La numeración continúa desde S93.

**Nota de tono del capítulo:** la plataforma ya existe, está segura, integrada, con contingencia y ojos. Este capítulo es la **vida adulta** de la plataforma: crecer sin downtime, cambiar sin downtime, sobrevivir al mantenimiento de la infraestructura — y finalmente, la pregunta que Bancolombia se hace en la vida real: cómo migrar el Kafka legado hacia esto sin perder un pago. El Cap 5 cierra el arco completo del curso.

**Nota de ritmo del capítulo:** las sesiones 12 y 13 siguen el patrón 20/40 (teoría + Lab 07). La **sesión 14 es distinta**: ~15 min de marco teórico y ~45 min de capstone integrador (el alumno diseña y ejecuta la migración, no sigue una guía). Por eso la sesión 14 tiene menos slides y más densas.

---

## SESIÓN 12 — Cruise Control: rebalanceo automatizado y escalado

**Objetivo de la sesión:** que el alumno habilite Cruise Control, entienda el flujo declarativo de propuesta → aprobación → ejecución del CR KafkaRebalance, y ejecute el ciclo completo de crecer y encoger el clúster sin perder datos.

### Bloque teórico (20 min, S94–S100)

**S94 — Mapa maestro: dónde estamos**
- Contenido: El mapa con todo el Cap 4 iluminado (plataforma segura, integrada, con contingencia y ojos). Por iluminar: "Operar fino — crecer, cambiar, sobrevivir al mantenimiento". Arranca el último capítulo.
- Nota: Ritual de apertura. "Meridiano ya hace todo lo importante. Lo que falta es lo que separa a un clúster que funciona de uno que se OPERA: crecer cuando el negocio crece, actualizar sin cortar pagos, y aguantar que mantengan la infraestructura por debajo. Esa es la vida real de un administrador."

**S95 — El problema del crecimiento: el broker nuevo nace vacío**
- Contenido: El negocio creció, agregamos un broker. Pero un broker nuevo NO recibe particiones existentes automáticamente: nace vacío y se queda vacío. Las particiones viejas siguen apretadas en los brokers originales. Agregar capacidad ≠ usar la capacidad.
- Nota: Contraintuitivo y por eso vale la slide. Pregunta a la sala: "¿cuántos han agregado un broker esperando alivio inmediato y no pasó nada?". Mover particiones a mano (kafka-reassign-partitions) es el dolor histórico que Cruise Control automatiza.
- Diagrama: 3 brokers llenos + 1 broker nuevo vacío, con una flecha "¿y ahora qué?" señalando el vacío.

**S96 — Cruise Control: el cerebro de balanceo**
- Contenido: Cruise Control observa el clúster (carga, distribución, recursos), construye un modelo y genera propuestas de movimiento de particiones según **goals** (objetivos: distribución de réplicas, balance de disco, de CPU, de red...). En Strimzi se habilita con `cruiseControl: {}` en el CR Kafka — otro componente declarativo, otro pod que el operador gestiona.
- Nota: El mensaje clave: Cruise Control no decide solo cuándo actuar — propone, y un humano (o un CR) aprueba. Es un asesor experto, no un piloto automático suelto. Para un banco, esa distinción es gobernanza.

**S97 — KafkaRebalance: la orden de trabajo declarativa**
- Contenido: El rebalanceo se pide con un CR `KafkaRebalance` (modo `full`, `add-brokers` o `remove-brokers`). El flujo: se aplica el CR → Cruise Control genera una **propuesta** (qué moverá, cuántas particiones, cuántos datos) → el CR queda en estado `ProposalReady` → el humano **aprueba** con la annotation `strimzi.io/rebalance=approve` → Cruise Control ejecuta → estado `Ready`.
- Nota: El patrón a grabar: NADA se mueve sin una propuesta legible y una aprobación explícita. Leer la propuesta antes de aprobar es el hábito profesional — saber cuántos datos se van a mover en una plataforma de pagos antes de apretar el botón.
- Diagrama: El ciclo del CR: aplicar → ProposalReady → (leer) → approve → Rebalancing → Ready.

**S98 — Crecer: add-brokers**
- Contenido: Tras escalar el pool de brokers (subir `replicas` en el KafkaNodePool), el broker nuevo está pero vacío. Un `KafkaRebalance` modo `add-brokers` apuntando al broker nuevo genera la propuesta para POBLARLO: mover una porción justa de particiones hacia él. Aprobar → las particiones se redistribuyen → el broker nuevo ahora trabaja.
- Nota: Verdad de terreno (validada en el lab): Cruise Control necesita su **ventana de métricas** antes de poder proponer — no reconoce un broker recién unido al instante. El material reintenta hasta que CC refresca su modelo. En sala: si la primera propuesta dice "brokers don't exist", no es error, es que CC todavía no lo vio — esperar y reintentar. Decirlo evita pánico.

**S99 — Encoger: remove-brokers, con la misma disciplina**
- Contenido: El camino inverso es igual de importante. Para retirar un broker (bajar costos, consolidar): primero un `KafkaRebalance` modo `remove-brokers` VACÍA el broker objetivo (mueve sus particiones a los demás), se aprueba, y SOLO cuando quedó vacío se reduce el pool. Encoger sin perder un byte es tan crítico como crecer.
- Nota: El error a prevenir: bajar `replicas` del pool ANTES de vaciar el broker = perder las particiones que vivían ahí (si no hay réplicas suficientes) o forzar un under-replicated. El orden es sagrado: vaciar primero, encoger después. Estado final canónico del curso tras este ejercicio: 3 brokers.

**S100 — Lanzamiento Lab 07 (parte 1): "Crecer y encoger sin downtime"**
- Contenido: Objetivos: (1) habilitar Cruise Control en `pagos` y verlo arrancar, (2) escalar a 4 brokers y comprobar que el nuevo nace vacío, (3) `KafkaRebalance` add-brokers: leer la propuesta, aprobar, ver poblarse el broker 4, (4) `KafkaRebalance` remove-brokers: vaciar el broker 4 y volver a 3. Desafío extra: leer los goals de una propuesta en el `.status` del CR. Tiempo: 40 min.
- Nota: El momento de aprobar la propuesta y ver moverse las particiones es el clic del capítulo: operación declarativa de algo que históricamente fue un script manual aterrador. Verdad de terreno: el sampling de CC debe configurarse con cuidado (período de muestreo mayor que su timeout de metadata) — el material ya lo trae afinado; mencionar que CC mal configurado entra en CrashLoop es buena anécdota preventiva.

---

## SESIÓN 13 — Rolling updates, upgrades de versión y Drain Cleaner

**Objetivo de la sesión:** que el alumno consolide el modelo de rolling updates, ejecute un upgrade de versión de Kafka declarativo sobre el clúster de contingencia, y entienda el rol de Drain Cleaner en el mantenimiento de la infraestructura.

### Bloque teórico (20 min, S101–S107)

**S101 — Mapa maestro: dónde estamos**
- Contenido: Cruise Control iluminado. Por iluminar: "Cambiar sin downtime". Penúltima pieza antes del capstone.
- Nota: "Ya sabemos crecer. Ahora: cómo cambiar la plataforma —su configuración, sus certificados, su versión de Kafka— sin que un solo pago deje de procesarse. Y cómo sobrevivir cuando alguien mantiene los servidores por debajo de nosotros."

**S102 — Rolling updates: lo que ya viviste cuatro veces**
- Contenido: Consolidación: cada cambio de config, rotación de certificado o cambio de versión dispara un **rolling update** — el operador reinicia los brokers DE A UNO, esperando que cada uno vuelva a estar en sync (ISR completo) antes de tocar el siguiente. Cero downtime porque siempre hay réplicas sirviendo. El alumno ya lo vio en los Labs 02, 03, 04 y 06 sin nombrarlo: hoy se nombra.
- Nota: Revelación retroactiva: "cada vez que aplicaron un cambio y vieron los pods reiniciarse en orden, eso era un rolling update orquestado. No es magia nueva, es algo que ya dominan sin saberlo". Reconocer lo que ya hicieron consolida confianza.

**S103 — El rolling manual: el botón de reinicio civilizado**
- Contenido: A veces el operador no dispara un rolling solo, pero el administrador necesita uno (forzar recarga, recuperar un pod raro). La annotation `strimzi.io/manual-rolling-update` sobre el StrimziPodSet pide al operador que ruede los pods con su lógica segura (ISR primero), en vez de un `kubectl delete pod` brutal que no respeta la salud del clúster.
- Nota: Distinción clave: `kubectl delete pod` también reinicia, pero sin criterio Kafka. El rolling manual de Strimzi es "reiniciar como el operador lo haría" — seguro, de a uno, respetando ISR. Para un banco, esa diferencia es la que evita un incidente.

**S104 — El upgrade de versión: nunca el primario primero**
- Contenido: Regla de oro bancaria: jamás actualizas tu clúster crítico primero. El upgrade de Kafka en Strimzi es declarativo: cambiar `spec.kafka.version` dispara el rolling de upgrade; después se sube `metadataVersion` (el formato de metadata KRaft) en un segundo paso. El orden importa: **primero version, después metadataVersion**.
- Nota: Verdad de terreno (validada): la secuencia es version → rolling → metadataVersion → rolling. Subir metadataVersion antes de tiempo, o saltarse el orden, es el error clásico. El material lo ejecuta en el orden correcto y lo explica paso a paso.
- Diagrama: Línea de tiempo de dos pasos: [cambiar version → rolling] luego [subir metadataVersion → rolling], con el clúster sirviendo pagos durante todo el proceso.

**S104b — La otra migración de la 1.0.0: servir una versión no es almacenarla**
- Contenido: Hay dos "versiones" que se mueven en un upgrade y no son la misma. Una es la **versión de Kafka** (los datos, S104). La otra es la **versión de API del Custom Resource** (`kafka.strimzi.io/v1beta2` → `v1`). Y aquí hay una distinción que el alumno debe hacer suya: **servir** una versión ≠ **almacenarla**. *Servir* significa que la API la acepta y la devuelve; *almacenar* significa en qué versión quedan escritos los objetos en etcd. Un CRD puede servir varias versiones a la vez, pero **almacena en una sola**.
- Nota (evidencia empírica del propio curso, verificada en vivo): en Strimzi 0.51 el CRD `kafkas` **sirve las dos** versiones —`v1beta2 served=true` y `v1 served=true`—, pero **almacena en `v1beta2`** (`storage=true` solo en v1beta2; en v1 `storage=false`). Compruébalo: `kubectl get crd kafkas.kafka.strimzi.io -o jsonpath='{.status.storedVersions}'` devuelve `["v1beta2"]`, y aun así, al leer el CR, el server responde `apiVersion: kafka.strimzi.io/v1` (un webhook lo convierte al vuelo). Servido en v1, guardado en v1beta2. Es exactamente lo que el alumno ya vio en el Lab 01 (guía 04) cuando el CRD listaba `v1beta2 v1`.
- Nota (por qué obliga a una migración al saltar a 1.0.0): Strimzi **1.0.0 elimina `v1beta2`** y deja solo `v1`. El problema: los objetos guardados siguen escritos como `v1beta2` en etcd. Si desaparece esa versión sin más, el API server ya no sabría leerlos. Por eso, **antes** del salto, hay que hacer una **migración de storage version**: reescribir cada CR para que quede almacenado como `v1` y actualizar `storedVersions` del CRD a `["v1"]`. Servir v1 fue gratis y transparente; **cambiar la versión almacenada es la migración de verdad**, y es la razón concreta por la que la 1.0.0 no es "solo actualizar el operador".
- Diagrama: Un CRD con dos etiquetas de "servido" (v1beta2 ✓, v1 ✓) pero una sola de "almacenado" (v1beta2 ✓ → v1 ✗); flecha de migración que mueve el "almacenado" a v1 y apaga v1beta2, habilitando el salto a 1.0.0.

**S105 — El upgrade en la práctica: ensayar en el DR**
- Contenido: El ejercicio aplica la regla: se ensaya el upgrade 4.1.1 → 4.2.0 sobre el clúster de **contingencia** (`dr`), no sobre `pagos`. Y trae la mejor lección de contingencia del curso: **MM2 guarda su estado —configs, offsets, status— en tópicos internos que viven DENTRO del DR**, así que recrear el DR (efímero, un solo nodo) o hacerle rolling lo deja huérfano y la réplica se **detiene** (el `MirrorSourceConnector` pierde su task). El procedimiento honesto: **parar MM2 antes de tocar el DR y recrearlo al final**, cuando el DR ya está en su versión definitiva. Se verifica que la réplica queda **restaurada** tras recrear MM2 — no que "sobrevivió sola".
- Nota: Doble lección: se aprende el upgrade Y se refuerza por qué tener un DR desechable es valioso (es tu campo de pruebas además de tu seguro). El procedimiento para el primario es idéntico — solo cambia la ventana de cambio y la cantidad de café.

**S106 — Drain Cleaner: sobrevivir al mantenimiento de la infraestructura**
- Contenido: Kubernetes drena nodos por mantenimiento (parches del SO, upgrade del propio K8s): evicta los pods del nodo para vaciarlo. Un drain ingenuo evicta brokers sin criterio Kafka — varios a la vez, sin esperar ISR. **Strimzi Drain Cleaner** intercepta esas evictions y deja que el OPERADOR ruede los brokers con seguridad (de a uno, ISR primero), en vez de que Kubernetes los tumbe en masa.
- Nota: HONESTIDAD DE ALCANCE (verdad de terreno del de-risk): esta capacidad NO se demuestra en vivo en kind. Los volúmenes locales de kind atan el disco del broker a su nodo: al drenar el nodo, el pod no puede mudarse y queda Pending. Además Drain Cleaner requiere cert-manager. Por eso esta sesión la trata CONCEPTUALMENTE + cómo se ve en EKS (donde EBS sigue al pod dentro de la zona y cert-manager está disponible). El material es explícito: "en su EKS esto funciona; en kind lo explicamos pero no lo corremos". Esa honestidad es parte de la calidad del curso.
- Diagrama: Kubernetes intentando evictar 2 brokers a la vez (✗) vs Drain Cleaner + operador rodándolos de a uno respetando ISR (✓).

**S107 — Lanzamiento Lab 07 (parte 2): "Cambiar sin downtime"**
- Contenido: Objetivos: (1) ejecutar un rolling manual sobre el clúster `dr` y observarlo, (2) parar MM2, recrear el `dr` en Kafka 4.1.1 y ejecutar el upgrade declarativo a 4.2.0 (version → metadataVersion), (3) recrear MM2 al final y verificar que la réplica quedó **restaurada** (recrear el DR efímero mató su estado; hay que traer MM2 de vuelta), (4) estudiar Drain Cleaner (instalación de referencia + explicación EKS). Desafío extra: forzar la renovación de certificados con `strimzi.io/force-renew` y observar que también es... un rolling. Tiempo: 40 min.
- Nota: El cierre conceptual del capítulo técnico: "TODO en esta plataforma —crecer, cambiar config, renovar certificados, actualizar versión— termina siendo un rolling update bien hecho. Dominar el rolling es dominar la operación de Strimzi". El mapa maestro queda con todo el Cap 5 técnico iluminado; solo falta la coronación: la migración.

---

## SESIÓN 14 — Estrategias de unificación y migración (Capstone)

**Objetivo de la sesión:** que el alumno integre todo lo aprendido para diseñar y ejecutar la migración del Kafka legado de Meridiano hacia la plataforma Strimzi, sin pérdida de datos y sin detener el negocio.

### Bloque teórico (15 min, S108–S112)

**S108 — Mapa maestro: la última pieza**
- Contenido: El mapa COMPLETO iluminado salvo una pieza final: "Migración — del legado a la plataforma". Esta sesión la enciende y cierra el viaje de Meridiano.
- Nota: Momento de cierre narrativo. "Durante 13 sesiones construimos la plataforma nueva: segura, integrada, con contingencia, observable y operable. Pero falta lo más difícil de la vida real: Meridiano todavía tiene un Kafka viejo corriendo fuera de Kubernetes, con transferencias vivas. Hoy lo migramos. Esto no es un lab guiado — es SU prueba como administradores."

**S109 — El escenario: el legado que no se puede apagar**
- Contenido: Banco Meridiano tiene un Kafka legado (fuera de Kubernetes, anterior a la plataforma) con el tópico `legado.transferencias`: historia acumulada Y un productor vivo escribiendo transferencias nuevas en este instante. No se puede "apagar y copiar": el negocio no para. La migración debe ser en caliente, verificable y reversible hasta el último segundo.
- Nota: Plantear el problema como lo vive un banco: nadie te da una ventana de mantenimiento de 8 horas para mover el core de pagos. La migración profesional es sin downtime o no es. El alumno debe sentir el peso: cada mensaje es una transferencia de dinero real.

**S110 — Las cuatro fases de una migración sin pérdida**
- Contenido: (1) **Replicar** — MirrorMaker 2 desde el legado hacia la plataforma (historia + tráfico vivo). (2) **Verificar paridad** — contar y comparar: el destino tiene todo lo del origen, sin huecos. (3) **Cutover** — cortar el productor del legado y arrancarlo contra la plataforma, con identidad y permisos propios. (4) **Decomisar** — apagar MM2 y el legado, pero solo tras verificar que no se perdió nada.
- Nota: Cada fase usa algo que YA aprendieron: MM2 (Cap 4), KafkaTopic y KafkaUser/ACLs (Cap 3), verificación con clientes (todo el curso). El capstone no enseña herramientas nuevas — exige combinar las conocidas con criterio. Eso es lo que se evalúa.
- Diagrama: Las 4 fases en línea, con el punto de no retorno marcado entre cutover y decomiso.

**S111 — Las decisiones que el alumno debe tomar**
- Contenido: La migración tiene decisiones de diseño sin respuesta única en la guía: ¿qué identidad usa el productor nuevo (reutilizar una existente o crear `transferencias` de mínimo privilegio)? ¿el tópico destino hereda la durabilidad de la plataforma (RF=3) o copia la pobreza del legado (RF=1)? ¿IdentityReplicationPolicy o naming con prefijo? ¿cuándo es seguro decomisar? Cada decisión se justifica en el runbook.
- Nota: Aquí se separa al que memorizó del que entendió. La rúbrica premia las decisiones correctas Y su justificación: heredar RF=3 (durabilidad de la plataforma), usuario dedicado de mínimo privilegio (no reutilizar app-pagos), decomisar solo tras verificar paridad. El runbook escrito es tan evaluable como el clúster funcionando.

**S112 — La prueba de cero pérdida: los números no mienten**
- Contenido: La migración se declara exitosa cuando se demuestra MATEMÁTICAMENTE que no se perdió nada: IDs secuenciales en origen, conteo en destino, y la frontera limpia del cutover (el último ID del legado + 1 = primer ID del productor nuevo, sin hueco ni duplicado). En el capstone real: 5000 de historia, frontera en el ID 5069, serie continua hasta el final. Cero pérdida no es una afirmación de fe — es un conteo verificable.
- Nota: El principio profesional que se llevan: "una migración no termina cuando los datos llegaron; termina cuando DEMOSTRASTE que llegaron todos". En banca, esa demostración es auditable y obligatoria. El que migra sin verificar paridad, no migró — apostó.

### Capstone (45 min, hands-on integrador)

**El alumno ejecuta la migración completa de Meridiano:**
- Recibe el escenario (legado vivo + productor activo), diseña la estrategia, ejecuta las cuatro fases y completa su runbook.
- Evaluación: el estado final verificable (cero pérdida, seguridad correcta en el destino, cutover limpio) + el runbook (orden, punto de no retorno, plan de rollback, validaciones).
- Pistas graduadas disponibles para quien las necesite — el alumno elige cuánto destapar.

- Nota de cierre del curso: cuando el último alumno vea "MIGRACIÓN COMPLETADA: cero pérdida verificada", el viaje de Meridiano terminó — y con él, el curso. De un PostgreSQL legado y un Kafka viejo a una plataforma sobre Kubernetes: segura, integrada, con contingencia, observable, operable y migrada. Cerrar agradeciendo y conectando con su realidad: "esto que hicieron con Meridiano es exactamente lo que les espera con su plataforma real. Ya saben hacerlo."

---

## Resumen ejecutivo del guion

| Sesión | Slides | Lab | Diagramas clave |
|---|---|---|---|
| 12 | S94–S100 (7) | Lab 07 p1 — Crecer y encoger | Ciclo del KafkaRebalance (S97) |
| 13 | S101–S107 (7) | Lab 07 p2 — Cambiar sin downtime | Upgrade en dos pasos (S104) |
| 14 | S108–S112 (5) | Capstone — La migración | Las 4 fases de migración (S110) |

**Total Cap 5: 19 slides.** Acumulado curso: **112 (S1–S112).**

**Nota sobre el conteo final del curso:** 112 slides para 14 sesiones está por sobre la estimación inicial de 80–100, pero es coherente con la densidad real: 5 capítulos, narrativa continua y mapa maestro recurrente. La sesión 14 deliberadamente tiene menos slides (5) por ser mayormente capstone. Recomendación: NO podar por podar — el ritmo 20/40 hace que 7 slides por sesión teórica sea holgado (≈3 min por slide en el bloque de 20 min). El conteo se valida en el vertido a template, donde algunas slides-mapa pueden fusionarse si el template lo pide.

**Pendientes que este guion deja registrados:**
1. Vertido a template Netec (igual que Caps 1–4).
2. Captura real de una propuesta de KafkaRebalance (el `.status` con los goals y el conteo de movimientos) para S97/S98 — se obtiene corriendo el Lab 07.
3. Diagrama del semáforo de upgrade en dos pasos (S104) — boceto a diseño final en el vertido.
4. Material de referencia de Drain Cleaner (manifiestos + nota EKS/cert-manager) — ya resuelto en el Lab 07 como referencia conceptual; enlazarlo desde la slide S106.
5. Revisión global del conteo de slides (112) en el vertido a template: decidir si las 5 slides-mapa maestro recurrentes se mantienen como están o se consolidan visualmente.
6. La cifra "frontera en el ID 5069" de S112 proviene de una corrida específica del capstone; al vertir, considerar si se deja el número concreto (más potente) o se generaliza ("el último ID del legado + 1") por si una corrida futura da otra cifra.
