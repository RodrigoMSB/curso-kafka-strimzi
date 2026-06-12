#!/usr/bin/env bash
# Plomería: extrae a archivos locales (./credenciales/, ignorado por git) lo que
# un cliente externo necesita:
#   - ca.crt              : la CA del clúster (para confiar en los brokers, TLS).
#   - app-pagos.password  : la contraseña SCRAM de app-pagos.
#   - motor-fraude.crt/.key: el certificado y llave de cliente de motor-fraude (mTLS).
#
# Decodifica base64 con openssl (portable macOS/WSL2). LAB01_CLUSTER opcional.
set -euo pipefail
DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"

NOMBRE_CLUSTER="${LAB01_CLUSTER:-meridiano}"
CONTEXTO="kind-${NOMBRE_CLUSTER}"
NS="meridiano-pagos"
DIR_CRED="$DIR_SCRIPT/../credenciales"

b64d() { openssl base64 -d -A; }

for s in pagos-cluster-ca-cert app-pagos motor-fraude; do
  if ! kubectl get secret "$s" -n "$NS" --context "$CONTEXTO" >/dev/null 2>&1; then
    msg_error "No existe el Secret '$s'. ¿Está el Lab 03 aplicado y Ready?"
    exit 1
  fi
done

mkdir -p "$DIR_CRED"

kubectl get secret pagos-cluster-ca-cert -n "$NS" --context "$CONTEXTO" \
  -o jsonpath='{.data.ca\.crt}' | b64d > "$DIR_CRED/ca.crt"
kubectl get secret app-pagos -n "$NS" --context "$CONTEXTO" \
  -o jsonpath='{.data.password}' | b64d > "$DIR_CRED/app-pagos.password"
kubectl get secret motor-fraude -n "$NS" --context "$CONTEXTO" \
  -o jsonpath='{.data.user\.crt}' | b64d > "$DIR_CRED/motor-fraude.crt"
kubectl get secret motor-fraude -n "$NS" --context "$CONTEXTO" \
  -o jsonpath='{.data.user\.key}' | b64d > "$DIR_CRED/motor-fraude.key"

chmod 600 "$DIR_CRED"/* 2>/dev/null || true
msg_ok "Credenciales extraídas en: ${DIR_CRED}"
msg_info "Archivos: ca.crt, app-pagos.password, motor-fraude.crt, motor-fraude.key"
msg_info "Este directorio está ignorado por git: nunca se versiona."
