# Convenciones de los laboratorios

Este documento define el **molde** común a todos los laboratorios del curso
(labs 01–07 y el capstone). El Lab 01 es la referencia: cualquier lab nuevo o
mantenido debe respetar lo aquí descrito. Audiencia: quien construya o mantenga
laboratorios.

## Estructura obligatoria de cada lab

Cada lab vive bajo `labs/<lab>/` y contiene:

- `README.md` — narrativa, objetivos, prerrequisitos, mapa de guías y la sección "Verifica tu trabajo".
- `guia/` — guías numeradas (`01-...md`, `02-...md`, …) con el contenido pedagógico.
- `bin/` — scripts del lab (ver numeración más abajo) y `lib-comunes.sh`.
- `infra/` — manifiestos y configuración de infraestructura del lab.
- `plantillas/` — archivos con TODOs didácticos para que el alumno los complete.
- `soluciones/` — la versión resuelta de las plantillas.
- `docs/troubleshooting.md` — tabla problema → causa → solución.

## Numeración de scripts en `bin/`

| Rango | Rol |
|---|---|
| `00`–`09` | Plomería de arranque: verificación de entorno y creación de la infraestructura del lab (clúster, namespaces, …). |
| `90` | Test **pasivo** de estado: solo lectura, no modifica nada, una línea `[OK]`/`[ERROR]` por verificación, resumen con contadores y exit `0`/`1`. |
| `91` | Test **end-to-end** del instructor: de cero a fin (entorno → ejecución → verificación) más limpieza. Certifica que el lab funciona en un ambiente nuevo. |
| `95` | **Recuperación** del estado final del lab desde `soluciones/`, sin interacción. Se declara exitoso solo si el `90` pasa. |
| `99` | **Destrucción** del clúster. Interactivo por defecto; flag `--si` para uso no interactivo (lo usa el `91`). |

## Reglas de los scripts

- Bash portable para macOS y WSL2: sin GNU-ismos (nada de `sed -i` sin sufijo, `readarray`, etc.).
- **Prohibido Python.**
- Cada lab tiene su `lib-comunes.sh` con la mensajería `[OK]` / `[INFO]` / `[ERROR]`.
- Idempotencia o falla con mensaje claro: un script se puede repetir sin dañar el estado, o se detiene explicando por qué.
- Mensajes para el alumno y el instructor en **español neutro**.
- Override de nombre de clúster vía `LAB01_CLUSTER` (y su equivalente por lab) para permitir pruebas aisladas; sin la variable, el nombre por defecto es el del lab.

## Plantillas vs soluciones

- `plantillas/` **nunca se edita** y contiene los TODOs didácticos. El alumno
  trabaja siempre sobre **copias** (por ejemplo `mi-values.yaml`), que están
  ignoradas por git.
- `soluciones/` contiene la versión resuelta y es la **fuente de verdad** de los
  scripts `95` (recuperación) y `91` (e2e): ambos instalan a partir de la solución.

## Encadenamiento entre labs

- El estado **final** del lab N es el estado **inicial** del lab N+1: hay un
  único clúster que evoluciona a lo largo del curso.
- El `91` del lab N obtiene su punto de partida ejecutando los `95` de los
  labs `1..N-1` en orden, y luego ejecuta el lab N de cero a fin.
- El `99` de cualquier lab destruye el clúster completo (es el mismo clúster).

## Lo que se hace a mano vs por script

- Los comandos que constituyen el **contenido pedagógico** de la sesión van en
  la guía y los ejecuta el **alumno** a mano (por ejemplo, `helm install` del
  operador en el Lab 01): ahí está el aprendizaje.
- Los scripts solo automatizan **plomería, verificación y recuperación**: crear
  el clúster, los namespaces, comprobar el estado y reconstruirlo. No sustituyen
  a las guías.
