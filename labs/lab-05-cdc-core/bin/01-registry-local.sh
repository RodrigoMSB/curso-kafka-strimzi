#!/usr/bin/env bash
# Plomería del registry local para el Connect Build. Patrón oficial de kind:
# un contenedor 'registry:2' en la red de kind, con cada nodo configurado para
# resolverlo por HTTP. Idempotente.
#
# En EKS este registry es ECR; el registry local es el equivalente de juguete.
# Con imágenes de kind v0.27.0+ NO hace falta containerdConfigPatches.
set -euo pipefail
DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"

NOMBRE_CLUSTER="${LAB01_CLUSTER:-meridiano}"
CONTEXTO="kind-${NOMBRE_CLUSTER}"
REG_NAME="kind-registry"
REG_HOST_PORT="5001"

# 1. Contenedor del registry (idempotente).
if [ -n "$(docker ps -q -f name="^${REG_NAME}$")" ]; then
  msg_info "El registry '${REG_NAME}' ya está corriendo."
else
  docker rm -f "$REG_NAME" >/dev/null 2>&1 || true
  docker run -d --restart=always -p "127.0.0.1:${REG_HOST_PORT}:5000" --name "$REG_NAME" registry:2 >/dev/null
  msg_ok "Registry '${REG_NAME}' creado (host 127.0.0.1:${REG_HOST_PORT})."
fi

# 2. Conectar el registry a la red de kind (idempotente).
docker network connect kind "$REG_NAME" >/dev/null 2>&1 || true

# 3. Configurar cada nodo para resolver kind-registry:5000 por HTTP (pull).
for node in $(kind get nodes --name "$NOMBRE_CLUSTER"); do
  # MSYS_NO_PATHCONV en línea: las rutas son del contenedor, no del host (Git Bash).
  MSYS_NO_PATHCONV=1 docker exec "$node" mkdir -p "/etc/containerd/certs.d/${REG_NAME}:5000"
  echo "[host.\"http://${REG_NAME}:5000\"]" \
    | MSYS_NO_PATHCONV=1 docker exec -i "$node" cp /dev/stdin "/etc/containerd/certs.d/${REG_NAME}:5000/hosts.toml"
done

# 4. ConfigMap informativo (patrón oficial de kind).
kubectl apply --context "$CONTEXTO" -f - >/dev/null <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "localhost:${REG_HOST_PORT}"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF

msg_ok "Registry local listo. Imágenes: kind-registry:5000/... (push del build con --insecure)."
