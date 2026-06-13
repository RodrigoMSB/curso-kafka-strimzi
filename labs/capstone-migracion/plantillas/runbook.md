# Runbook de migración — `legado.transferencias` → plataforma Meridiano

> Plantilla (no se edita). Trabaja sobre una **copia** tuya (p. ej.
> `mi-runbook.md`). Media página. El `90` no evalúa este documento; el instructor
> sí (rúbrica).

**Autor:** _______________  **Fecha:** _______________

## 1. Orden de pasos (de principio a fin)

<!-- Lista numerada: qué se ejecuta y en qué orden. Incluye despliegue del
     espejo, verificación de paridad, cutover y decomiso. -->

1.
2.
3.
4.
5.

## 2. Punto de no retorno

<!-- ¿Cuál es el paso exacto tras el cual ya no se puede volver atrás sin
     consecuencias? ¿Por qué? -->

## 3. Plan de rollback (ANTES del cutover)

<!-- Si algo falla durante la replicación o justo en el cutover, ¿cómo se
     vuelve al estado seguro (el legado como fuente de verdad)? -->

## 4. Validaciones (cómo se prueba "cero pérdida")

<!-- ¿Qué se mide y cómo? Conteos de origen y destino, continuidad de IDs,
     frontera del cutover. -->

## 5. Decomiso (qué verificar ANTES de apagar)

<!-- ¿Qué tiene que ser cierto para apagar el legado con seguridad? -->
