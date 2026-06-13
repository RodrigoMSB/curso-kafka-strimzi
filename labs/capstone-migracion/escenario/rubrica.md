# Rúbrica del Capstone "La migración"

El **estado final verificable** lo mide `bin/90-test-lab.sh` (el `90` ES parte
del evaluador). El **runbook** lo evalúa el instructor. Pesos:

| Criterio | Peso |
|---|---|
| Paridad sin pérdida | 40% |
| Seguridad correcta en el destino | 20% |
| Cutover limpio | 20% |
| Runbook | 20% |

---

## 1. Paridad sin pérdida — 40%

Mide que toda la historia y el tráfico vivo del legado llegaron al destino sin
perder ni un mensaje. (Checks 2 y 3 del `90`.)

| Nivel | Descriptor |
|---|---|
| **Excelente (40)** | `legado.transferencias` existe en pagos como KafkaTopic **Ready con RF=3**; el conteo en destino ≥ N semilla + vivos; la serie de IDs es **continua** (sin huecos), arrancando en 1. |
| **Aceptable (24)** | Los mensajes llegan, pero el tópico no heredó RF=3 (quedó con la durabilidad del legado), o el conteo solo cuadra para la historia y no para el tráfico vivo. |
| **Insuficiente (0–12)** | Hay huecos en la serie (pérdida), MM2 no replica (típico: ACLs del target), o el tópico no existe en el destino. |

## 2. Seguridad correcta en el destino — 20%

Mide que el destino endurecido se respetó: identidades correctas con los
privilegios adecuados. (El destino es SCRAM/`authorization: simple`.)

| Nivel | Descriptor |
|---|---|
| **Excelente (20)** | MM2 autentica en el target con una identidad de ACLs **suficientes y justificadas** (crear/escribir el tópico replicado y los internos de Connect); el productor nuevo usa una identidad **de mínimo privilegio** (Write/Describe solo sobre el tópico), no `app-pagos` ni la de MM2. |
| **Aceptable (12)** | Funciona, pero reutiliza una identidad existente o concede ACLs de más sin justificarlo (p. ej. la misma cuenta amplia para todo). |
| **Insuficiente (0–6)** | El destino quedó accesible sin auth, o se debilitaron sus listeners/authorization para "que funcionara". |

## 3. Cutover limpio — 20%

Mide la continuidad del negocio en el corte. (Check 4 del `90`.)

| Nivel | Descriptor |
|---|---|
| **Excelente (20)** | El productor nuevo escribe en la plataforma con la identidad elegida; **primer ID nuevo == último ID del legado + 1**; sin hueco ni duplicado en la frontera. |
| **Aceptable (12)** | El cutover ocurre pero con un pequeño solape (duplicado) o un hueco de 1–2 mensajes recuperable. |
| **Insuficiente (0–6)** | Se detuvo el negocio para migrar, o hay pérdida/duplicación grande en la frontera. |

## 4. Runbook — 20%

Mide el criterio operativo escrito (media página, plantilla provista).

| Nivel | Descriptor |
|---|---|
| **Excelente (20)** | Orden de pasos correcto; **punto de no retorno** identificado; **plan de rollback antes del cutover**; validaciones concretas de cero pérdida; qué verificar antes del decomiso. |
| **Aceptable (12)** | Cubre los pasos pero el rollback o el punto de no retorno son vagos. |
| **Insuficiente (0–6)** | Lista de comandos sin razonamiento de riesgo, o sin plan de rollback. |

---

### Veredicto del `90`

`MIGRACIÓN COMPLETADA: cero pérdida verificada` cuando los 5 checks pasan:
plataforma intacta (Lab 07), tópico RF=3, paridad continua, cutover en frontera
limpia, y legado decomisado con el espejo ya inactivo.
