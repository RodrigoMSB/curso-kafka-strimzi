# Guía 5 — Rolling updates como rutina

> Parte 2, sesión 13. Cambiar sin downtime. Ya viste rollings cuatro veces
> (endurecer, listeners externos, métricas, Cruise Control). Consolidemos qué son
> y cómo dispararlos a mano cuando hace falta.

## Qué dispara un rolling

El operador reinicia los brokers **de a uno** —esperando a que cada uno vuelva
sano (con sus réplicas en ISR) antes de tocar el siguiente— cuando cambias:

- la **configuración** del clúster (un listener, una opción de broker, recursos);
- los **certificados** (renovación de la CA o de los certs de servidor);
- la **versión** de Kafka (un upgrade — guía 6).

Es la misma orquestación cuidadosa cada vez: nunca pierde quórum, nunca corta el
servicio. Por eso "todo en esta plataforma es un rolling bien hecho".

## El rolling manual: el botón de reinicio civilizado

A veces quieres reiniciar los brokers **sin** cambiar nada (p. ej. para forzar
que tomen una config externa nueva, o por higiene). En vez de borrar pods a mano
—que sería un reinicio brusco—, le pides al operador que haga el rolling con su
criterio (ISR primero), anotando el **StrimziPodSet**:

```bash
# Identifica el StrimziPodSet del DR
kubectl get strimzipodset -n meridiano-dr

# Dispara el rolling manual (el operador lo orquesta con seguridad)
kubectl annotate strimzipodset dr-dr-nodes -n meridiano-dr \
  strimzi.io/manual-rolling-update="true"
```

Observa el rolling:

```bash
kubectl get pods -n meridiano-dr -w
```

El pod del DR se reinicia de forma controlada (en un clúster de varios brokers,
sería de a uno). El operador retira la annotation cuando termina. Es el "botón de
reinicio civilizado": el operador hace el trabajo sucio con criterio Kafka, no un
`kubectl delete pod` a ciegas.

> Lo probamos sobre el **DR** (es barato y aislado). Sobre `pagos` el efecto es el
> mismo, pero con varios brokers el rolling tarda más (uno por uno, esperando ISR).

En la siguiente guía hacemos el rolling más delicado de todos: un **upgrade de
versión** — y, como manda el banco, lo ensayamos sobre el DR.
