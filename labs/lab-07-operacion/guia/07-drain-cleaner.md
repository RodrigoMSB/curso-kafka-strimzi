# Guía 7 — Drain Cleaner (sobrevivir al mantenimiento de la infraestructura)

> **Esta guía es conceptual + de referencia, no una demo en vivo.** El porqué es
> honesto y está al final: en kind no se puede demostrar dignamente. En EKS sí.

## El problema

Kubernetes **drena** nodos por mantenimiento: upgrades del propio Kubernetes,
parches del sistema operativo, reemplazo de máquinas. Drenar un nodo significa
**evictar** (echar) todos sus pods para apagarlo.

Un drain **ingenuo** evicta los brokers sin criterio Kafka: los echa de golpe,
sin mover el liderazgo de las particiones ni esperar a que las réplicas estén en
sincronía. Resultado: particiones sin líder por un rato, posibles errores en los
clientes, riesgo de pérdida si coincide con otra falla.

## Qué hace Drain Cleaner

**Strimzi Drain Cleaner** se interpone. Es un *webhook* que **intercepta** las
peticiones de eviction de los brokers (y de ZooKeeper, si lo hubiera) y, en vez
de dejar que Kubernetes los eche a la fuerza, le pasa la pelota al **operador de
Strimzi**: el operador hace un **rolling controlado** (mueve el liderazgo, espera
ISR) y recién entonces el pod se va.

```
   kubectl drain nodo
        │  intenta evictar pagos-brokers-1
        ▼
   Drain Cleaner (webhook)  ──intercepta──▶  operador de Strimzi
                                                 │  rolling con criterio (ISR primero)
                                                 ▼
                                            broker reubicado con seguridad
```

El resultado: el mantenimiento de la infraestructura ocurre **sin** sacrificar la
seguridad de Kafka. El nodo se drena, pero los brokers se mueven con cabeza.

## Instalación (referencia)

Drain Cleaner se instala con sus manifiestos oficiales o con Helm:

```bash
# Con Helm (autogenera los certificados del webhook):
helm install strimzi-drain-cleaner strimzi/strimzi-drain-cleaner \
  -n strimzi-drain-cleaner --create-namespace
```

(El manifiesto de referencia está en `infra/drain-cleaner-referencia.yaml`.)

## Por qué NO lo demostramos en vivo aquí (honestidad de laboratorio)

Lo probamos de verdad antes de escribir esta guía. **Dos cosas lo impiden en kind:**

1. **Volúmenes locales.** Los PVC de `pagos` usan el StorageClass local de kind:
   cada disco vive **atado a su nodo**. Al drenar un worker con un broker encima,
   el pod **no puede seguir a su disco** a otro nodo: queda caído hasta que se
   "des-acordona" (uncordon) el nodo. Lo verificamos: el broker drenado **no se
   recuperó**. La demo de "mover el broker a otro nodo" es, sencillamente,
   imposible con discos locales.
2. **El webhook necesita certificados** que en kind, sin cert-manager, son
   frágiles de provisionar.

**En EKS es distinto y natural:** los discos **EBS siguen al pod** dentro de la
misma zona de disponibilidad, así que el broker SÍ se reubica en otro nodo; y con
cert-manager el webhook se instala limpio. Allí Drain Cleaner brilla: drenas un
nodo para mantenerlo, y tus brokers se mudan solos, con criterio Kafka, sin que
un solo pago se pierda.

> La lección no es menos valiosa por ser conceptual: **el mantenimiento de la
> infraestructura no debe atropellar a Kafka**, y Drain Cleaner es la pieza que lo
> garantiza en un Kubernetes de verdad.

## Desafío extra (parte 2)

Fuerza la **renovación de los certificados** de la cluster CA y observa que es...
otro rolling. Todo en esta plataforma es un rolling bien hecho. La resolución
está en `soluciones/desafio-renovar-certs.md`.

## Cierre del Capítulo 5 (y del curso)

La plataforma de Banco Meridiano ya es **adulta**: crece y encoge sin perder
datos, cambia y se actualiza sin downtime, y está preparada para el mantenimiento
de la infraestructura. Empezó como un operador vacío en el Lab 01; hoy es un
sistema que un auditor firma y un equipo de operaciones duerme tranquilo
operando.
