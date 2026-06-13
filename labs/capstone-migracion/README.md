# Capstone — La migración

> **Módulo insignia del curso (Cap 5, sesión 14).** Esto **no es un lab más**: no
> hay guía paso a paso. Hay un **escenario**, un **objetivo medible**, **pistas
> graduadas** y una **rúbrica**. Tú diseñas y ejecutas; las herramientas ya las
> aprendiste (MM2, KafkaUser/ACLs, KafkaTopic, observabilidad, rolling).

## El escenario

Banco Meridiano tiene un **Kafka legado** corriendo **fuera de Kubernetes** — el
clúster histórico de transferencias, anterior a la plataforma. Contiene el tópico
`legado.transferencias` con **historia acumulada** (miles de mensajes semilla) y
un **productor todavía vivo** escribiendo transferencias nuevas, 1/s, sin parar.

Tu misión, como en la vida real de un banco: **migrar ese flujo a la plataforma
Strimzi sin perder un solo mensaje y sin detener el negocio.**

El legado es PLAINTEXT, sin TLS ni auth ("así vivíamos"). La plataforma `pagos`
está endurecida (SCRAM, `authorization: simple`). Esa **inversión** — origen
abierto, destino seguro — es el corazón del reto.

## El objetivo medible

Al terminar, `bin/90-test-lab.sh` declara **"MIGRACIÓN COMPLETADA: cero pérdida
verificada"**. Para ello, el estado final debe cumplir:

1. La plataforma del Lab 07 sigue **sana** (migrar no es romper lo demás).
2. `legado.transferencias` existe en `pagos` como **KafkaTopic Ready con RF=3**.
3. **Paridad sin pérdida:** el destino tiene ≥ N semilla + tráfico vivo, y la
   serie de IDs es **continua** (sin huecos).
4. **Cutover limpio:** hay mensajes de la identidad **nueva** después del último
   ID del legado, y la frontera calza (último del legado + 1 = primero del nuevo).
5. El legado está **decomisado** y el espejo de migración ya **no está activo**.

## Las fases (lo que se espera que hagas)

1. **Replicar** historia + tráfico vivo con un MirrorMaker 2 legado→pagos.
2. **Verificar paridad** (conteos y continuidad de IDs).
3. **Cutover:** cortar el productor del legado y arrancar el productor nuevo
   hacia la plataforma.
4. **Verificar cero pérdida** en la frontera.
5. **Decomisar** el legado.

## Qué está provisto vs. qué diseñas tú

| Provisto (plomería) | Lo diseñas tú (lo evaluado) |
|---|---|
| `bin/01-desplegar-legado.sh` — levanta el legado, siembra N, deja el productor vivo | El **espejo** `KafkaMirrorMaker2` legado→pagos (Identity policy) |
| `bin/02-cutover-productor.sh` — corta el legado y arranca el productor nuevo (identidad por parámetro) | El **tópico destino como código** (KafkaTopic, RF=3) |
| `bin/03-decomisar-legado.sh` — apaga espejo + legado | La **identidad del target** de MM2 (ACLs correctas) |
| `bin/90-test-lab.sh` — el evaluador | La **identidad nueva** del negocio (mínimo privilegio) |
| El contenedor Kafka legado (red de kind) | El **runbook** (orden, no-retorno, rollback) |

## Pistas y rúbrica

- `escenario/pistas.md` — tres niveles graduados (qué piezas → campos clave →
  casi-solución). Destapa solo lo que necesites.
- `escenario/rubrica.md` — paridad 40%, seguridad 20%, cutover 20%, runbook 20%.
- `plantillas/` — `runbook.md` (a completar a mano) y un MM2 con TODO mínimos
  (úsalos solo si llegaste al nivel 3 de pistas).
- `soluciones/` — la solución de referencia completa (compara, no copies).

## Prerrequisitos

- **Lab 07 completado** (plataforma completa). Si no, recupéralo con
  `labs/lab-07-operacion/bin/95-recuperar-lab.sh`.
- Verifica con: `bash bin/00-verificar-prerrequisitos.sh`.

> **Recursos:** el legado (un broker single-node) y MM2 (un pod Connect) se
> suman a la plataforma del Lab 07. Sigue cabiendo en 16 GB; mantén cerradas las
> apps pesadas.

## Tiempo estimado

~20 min de teoría (en sala) + ~40 min de capstone.

## Cómo se evalúa

```bash
bash bin/90-test-lab.sh          # el estado final (el '90' ES el evaluador)
```
Más el **runbook** escrito a mano, que evalúa el instructor con la rúbrica.

## Para el instructor

- `bin/91-test-e2e.sh` — la **corrida total del curso**: cadena Lab 01→07 (vía el
  95 del Lab 07) + la migración de referencia de cero a fin. Reporta duración,
  pico de memoria y los números de paridad. Limpia clúster + legado + registry.
  Override de nombre con `CAPSTONE_E2E_CLUSTER`; `--conservar` para inspección.
- `bin/95-recuperar-lab.sh` — reconstruye el estado final (migración completada)
  para un alumno rezagado; encadena el 95 del Lab 07.
- `docs/troubleshooting.md` — los fallos más probables (auth del target, legado
  inalcanzable, conteos que no calzan, hueco/duplicado en el cutover).
