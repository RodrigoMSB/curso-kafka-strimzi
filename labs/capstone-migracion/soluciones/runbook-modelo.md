# Runbook de migración (MODELO RESUELTO) — `legado.transferencias` → plataforma

> Versión de referencia. El runbook del alumno se evalúa por la rúbrica (20%),
> no por el `90`. Esto es lo que un buen runbook bancario contiene.

**Autor:** Equipo de Plataforma  **Fecha:** día de la ventana de migración

## 1. Orden de pasos

1. **Preparar el destino como código.** Declarar `legado.transferencias` como
   `KafkaTopic` en `pagos` con **RF=3** (hereda la durabilidad de la plataforma).
2. **Crear identidades.** `mm2-migracion` (la identidad del espejo en el destino,
   con ACLs de escritura/admin) y `transferencias` (la identidad del productor
   nuevo, mínimo privilegio: `Write`/`Describe` solo sobre el tópico).
3. **Levantar el espejo.** `KafkaMirrorMaker2` legado→pagos con
   `IdentityReplicationPolicy`. Esperar a `Ready`.
4. **Verificar paridad de la historia.** Contar en origen y destino; confirmar
   que la serie de IDs es continua (sin huecos). El tráfico vivo del legado se
   replica de forma continua: la paridad se mantiene mientras MM2 corre.
5. **Cutover.** Cortar el productor del legado, **registrar el último ID emitido**,
   y arrancar el productor nuevo en la plataforma escribiendo desde último+1.
6. **Verificar cero pérdida.** Confirmar en el destino: `legado` hasta último ID,
   `plataforma` desde último+1, **sin hueco ni duplicado** en la frontera.
7. **Decomiso.** Detener/eliminar el espejo de migración y apagar el legado.

## 2. Punto de no retorno

El **cutover (paso 5)**. Una vez que el productor nuevo escribe en la plataforma
con IDs ≥ último+1, volver al legado obligaría a reconciliar dos fuentes de
verdad. Antes del cutover el rollback es trivial; después, no.

## 3. Plan de rollback (antes del cutover)

Mientras el legado siga siendo la fuente de verdad y MM2 solo **lee** de él:
- Si el espejo falla o la paridad no cuadra, **no se hace cutover**. Se corrige
  MM2 (lo más probable: ACLs del target) y se reintenta. El negocio nunca dejó
  de escribir en el legado, así que no hay nada que deshacer.
- Si el cutover se ejecuta y algo sale mal **en el primer minuto**, se puede
  reactivar el productor del legado (el contenedor sigue vivo: el decomiso es un
  paso posterior y deliberado) y detener el productor nuevo. Por eso el legado
  **no se apaga en el cutover**: se apaga solo tras verificar cero pérdida.

## 4. Validaciones ("cero pérdida")

- **Conteo:** mensajes en destino ≥ semilla (N) + producidos en vivo.
- **Continuidad:** IDs `1..max` sin huecos (distintos == max-min+1).
- **Frontera:** `max(origen=legado) == último-ID-legado` y
  `min(origen=plataforma) == último-ID-legado + 1`.

## 5. Decomiso (verificar antes de apagar)

Antes de apagar el legado, confirmar que **toda** su historia (IDs `1..último`)
ya está en el destino. Si se apaga el legado mientras MM2 aún drena, se pierden
los últimos mensajes. El `03-decomisar-legado.sh` se niega a apagar si no consta
el cutover; aun así, la verificación de drenaje es responsabilidad del operador.

## Decisión de identidad (justificación)

Se usa una identidad **dedicada** `transferencias` (no se reutiliza `app-pagos`
ni la amplia de MM2) con **mínimo privilegio**. Un flujo de pagos migrado merece
su propia credencial acotada: si se filtra, el daño se limita a un tópico.
