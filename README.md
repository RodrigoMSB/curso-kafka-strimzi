# Administración de Apache Kafka sobre Kubernetes con Strimzi

Curso de 14 horas sobre Strimzi 0.51, Kafka en modo KRaft (versión según matriz de soporte de Strimzi 0.51) y Kubernetes.

## Prerrequisitos de hardware (prerequisito duro — léelo antes de la sala)

Todo el curso corre en local sobre Docker + kind. El clúster es único y **crece
lab a lab**; el pico está en el **Lab 06**, donde conviven **dos** clústeres Kafka
(`pagos` + `dr`) más MirrorMaker 2, Kafka Connect, PostgreSQL, Prometheus y
Grafana. Medido en el pico: **≈ 6,25 GiB** de memoria real de contenedores.

- **Mínimo: 16 GB de RAM** en la máquina **y Docker Desktop configurado con
  ≥ 8 GB** de memoria (recomendado 10 GB). En Docker Desktop se ajusta en
  *Settings → Resources → Memory*.
- **8 GB de RAM no alcanza:** el Lab 06 no levanta (pods `Pending`/`OOMKilled`).
- Cierra aplicaciones pesadas del host (navegadores con muchas pestañas, otros
  IDEs) durante los labs pesados: la RAM que se lleve el host se la quita a Docker.

> Si tu laptop tiene 16 GB pero Docker Desktop está en su asignación por defecto
> (a menudo menos de 8 GB), **súbela antes de empezar**. El verificador del Lab 01
> (`bin/00-verificar-entorno.sh`) te avisa si Docker tiene menos de 8 GB.

## Estructura de carpetas

- `docs/guiones-slides/` — Guiones de las diapositivas y material de apoyo de las sesiones.
- `ppt/` — Presentaciones del curso.
- `labs/lab-01-cimientos/` — Laboratorio 1: cimientos del entorno.
- `labs/lab-02-cluster-pagos/` — Laboratorio 2: clúster de pagos.
- `labs/lab-03-topicos-identidad/` — Laboratorio 3: tópicos e identidad (KafkaTopic, KafkaUser, ACLs).
- `labs/lab-04-puerta-segura/` — Laboratorio 4: puerta segura.
- `labs/lab-05-cdc-core/` — Laboratorio 5: CDC sobre el core.
- `labs/lab-06-contingencia-ojos/` — Laboratorio 6: contingencia y observabilidad.
- `labs/lab-07-operacion/` — Laboratorio 7: operación.
- `labs/capstone-migracion/` — Proyecto capstone: migración.
- `formacion/` — Material de formación.

## Mapa del curso: sesiones, capítulos y laboratorios

| Sesión | Capítulo | Tema | Laboratorio |
|---|---|---|---|
| 1 | Cap 1 | De Kafka on-premises a Kafka en Kubernetes | Solo teoría |
| 2 | Cap 1 | El patrón Operator y la anatomía de Strimzi 0.51 | Solo teoría |
| 3 | Cap 2 | Instalación del Cluster Operator y CRDs | Lab 01 — Cimientos |
| 4 | Cap 2 | Clúster Kafka KRaft con KafkaNodePool | Lab 02 (parte 1) — Clúster de pagos |
| 5 | Cap 2 | Storage persistente, rack awareness y multi-zona | Lab 02 (parte 2) — Durabilidad y zonas |
| 6 | Cap 3 | Tópicos como código con KafkaTopic | Lab 03 (parte 1) — Tópicos como código |
| 7 | Cap 3 | Usuarios, ACLs y cuotas con KafkaUser | Lab 03 (parte 2) — Identidad y mínimo privilegio |
| 8 | Cap 3 | Listeners, TLS/mTLS y exposición segura | Lab 04 — La puerta segura |
| 9 | Cap 4 | Kafka Connect declarativo y CDC con Debezium | Lab 05 — CDC del core |
| 10 | Cap 4 | MirrorMaker 2: replicación multi-clúster | Lab 06 (parte 1) — Contingencia |
| 11 | Cap 4 | Observabilidad: Prometheus, Grafana y tracing | Lab 06 (parte 2) — Ojos sobre la plataforma |
| 12 | Cap 5 | Cruise Control: rebalanceo automatizado | Lab 07 (parte 1) — Operación |
| 13 | Cap 5 | Rolling updates, upgrades y Drain Cleaner | Lab 07 (parte 2) — Operación |
| 14 | Cap 5 | Estrategias de unificación y migración | Capstone — Migración |

Las sesiones 1 y 2 construyen la base conceptual; desde la sesión 3 cada sesión
combina ~20 min de teoría con ~40 min de laboratorio. Los laboratorios construyen
un único clúster que evoluciona durante todo el curso.
