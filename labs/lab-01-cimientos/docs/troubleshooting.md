# Troubleshooting — Lab 01

Problemas frecuentes durante el lab, su causa típica y cómo resolverlos.

| # | Problema | Causa típica | Solución |
|---|----------|--------------|----------|
| 1 | `docker info` falla o el verificador marca Docker en rojo. | Docker Desktop no está corriendo. | Inicia Docker Desktop y espera a que el ícono indique que está listo. Vuelve a ejecutar `bin/00-verificar-entorno.sh`. |
| 2 | La creación del clúster se queda en "Starting control-plane" o falla. | Docker tiene pocos recursos asignados. | En Docker Desktop, Settings → Resources, sube la RAM y CPU asignadas (recomendado: 4+ CPU, 6+ GB RAM). Reintenta `bin/01-crear-cluster.sh`. |
| 3 | Descarga lenta o timeout de la imagen `kindest/node` o de la imagen del operador. | Red corporativa o VPN lenta/restrictiva. | Reintenta; las descargas se reanudan. Si tu entorno lo previó, usa la pre-descarga de imágenes indicada en el documento de setup del curso. |
| 4 | `helm install` falla porque la release ya existe. | Ya instalaste antes el operador con ese nombre. | Desinstala y reinstala: `helm uninstall strimzi-operator -n meridiano-sistema` y repite el `helm install`. Alternativa idempotente: usa `helm upgrade --install` en lugar de `helm install`. |
| 5 | El pod del operador queda en `ImagePullBackOff`. | No se pudo descargar la imagen (red o rate limit del registry). | Inspecciona el motivo real: `kubectl describe pod <nombre-del-pod> -n meridiano-sistema` y lee la sección Events. Suele ser red o límite de descargas del registry; reintenta más tarde o usa la pre-descarga del setup. |
| 6 | Instalaste el operador en el namespace equivocado. | Olvidaste `--namespace meridiano-sistema` en `helm install`. | Una release no se "mueve" de namespace: desinstala y reinstala. `helm uninstall strimzi-operator -n <namespace-equivocado>` y vuelve a instalar con `--namespace meridiano-sistema`. El namespace es parte de la identidad de la release. |
| 7 | En Windows con WSL2, los comandos no encuentran Docker o kind. | Estás ejecutando en PowerShell en lugar de la terminal WSL2. | Docker Desktop expone el motor a WSL2; ejecuta **todos** los comandos del lab dentro de la terminal WSL2 (tu distribución Linux), no en PowerShell ni en CMD. Verifica con `docker info` desde WSL2. |
