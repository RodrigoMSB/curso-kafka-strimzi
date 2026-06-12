# Lab 02 — El clúster de pagos

El operador que contratamos en el Lab 01 recibe su primer encargo: levantar el
clúster Kafka de pagos de Banco Meridiano. Lo haremos en dos bloques. En la
parte 1 desplegamos el clúster y mandamos el primer mensaje. En la parte 2
descubrimos —a las malas— por qué el almacenamiento importa, lo hacemos
persistente y repartimos las réplicas entre tres zonas.

## Objetivos del lab

- Declarar un clúster Kafka KRaft con un `Kafka` y dos `KafkaNodePool` (controllers y brokers).
- Producir y consumir el primer mensaje de pagos desde un pod cliente.
- Vivir la diferencia entre storage efímero y persistente, y entender por qué el storage se decide el día cero.
- Habilitar rack awareness y verificar que las réplicas se reparten entre zonas.

## Prerrequisitos

- **Lab 01 completado** (operador instalado y vigilando `meridiano-pagos`). Si no, recupéralo con `labs/lab-01-cimientos/bin/95-recuperar-lab.sh`.
- El clúster del curso con su topología de **4 nodos** (1 control-plane + 3 workers).
- Verifica todo con: `bash bin/00-verificar-prerrequisitos.sh`.

## Tiempo estimado

Dos bloques de 40 minutos (parte 1 = guías 1–3; parte 2 = guías 4–5).

## Mapa del lab

| Guía | Archivo | Qué logras |
|------|---------|------------|
| 1 | `guia/01-dos-crs-un-cluster.md` | Entiendes `Kafka` + `KafkaNodePool` y la topología (1 controller / 3 brokers). |
| 2 | `guia/02-desplegar-el-cluster.md` | Completas las plantillas, aplicas y observas la convergencia. |
| 3 | `guia/03-primer-mensaje.md` | Creas el tópico a la antigua y produces/consumes el primer pago. |
| 4 | `guia/04-el-problema-del-estado.md` | Pierdes datos con storage efímero, los recuperas con persistente. |
| 5 | `guia/05-zonas-y-rack-awareness.md` | Etiquetas zonas, habilitas rack y verificas la distribución. |

## Verifica tu trabajo

`bin/90-test-lab.sh` comprueba el estado final del lab (clúster persistente con
rack y round-trip de humo). Córrelo al terminar o al inicio de la siguiente
sesión:

```bash
bash bin/90-test-lab.sh
```

## Para el instructor

- `bin/91-test-e2e.sh` certifica el lab completo de cero a fin (Lab 01 → Lab 02 → test → limpieza) en un ambiente nuevo; úsalo en la VM antes del curso.
- `bin/95-recuperar-lab.sh` reconstruye el estado final del Lab 02 (incluye recuperar el Lab 01 primero) para poner al día a un alumno rezagado.

## Convención del curso

Los comandos que ejecuta el alumno van en bloques de código; las salidas
esperadas, en bloques aparte marcados como "Salida esperada (puede variar
levemente)".
