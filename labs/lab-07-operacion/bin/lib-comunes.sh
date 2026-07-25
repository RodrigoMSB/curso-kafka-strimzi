#!/usr/bin/env bash
# Funciones comunes para los scripts del Lab 07 de Banco Meridiano.

# Git Bash (MSYS2) reescribe los argumentos que parecen rutas Unix a rutas Windows
# antes de pasarlos al comando. Eso rompe cualquier '--command-config /props/...' que
# viaje como argumento directo de 'kubectl exec'. Desactivarlo es inocuo en macOS y
# Linux (la variable simplemente no se usa).
export MSYS_NO_PATHCONV=1

msg_ok()    { printf '[OK] %s\n' "$*"; }
msg_info()  { printf '[INFO] %s\n' "$*"; }
msg_error() { printf '[ERROR] %s\n' "$*" >&2; }
verificar_comando() { if command -v "$1" >/dev/null 2>&1; then return 0; else return 1; fi; }

# Memoria del Docker VM en uso por contenedores (suma de MemUsage), en MiB.
# Devuelve "?" si no se puede calcular.
memoria_docker_mib() {
  docker stats --no-stream --format '{{.MemUsage}}' 2>/dev/null \
    | awk '{u=$1; if (u ~ /GiB/){sub(/GiB/,"",u); s+=u*1024} else if (u ~ /MiB/){sub(/MiB/,"",u); s+=u} } END{ if (NR>0) printf "%d", s; else printf "?" }'
}

# Espera a que un KafkaRebalance alcance un estado (PendingProposal, ProposalReady,
# Rebalancing, Ready). El estado vive en status.conditions[*].type.
# Uso: esperar_rebalance <name> <ctx> <ns> <estado_objetivo> <timeout_s>
# Devuelve 0 si lo alcanza, 2 si queda NotReady, 1 si expira.
esperar_rebalance() {
  name=$1; ctx=$2; ns=$3; obj=$4; tmax=${5:-400}; t=0; st=""
  while [ "$t" -lt "$tmax" ]; do
    st=$(kubectl get kafkarebalance "$name" -n "$ns" --context "$ctx" -o jsonpath='{.status.conditions[*].type}' 2>/dev/null || true)
    case " $st " in *" $obj "*) return 0 ;; esac
    case " $st " in *" NotReady "*) return 2 ;; esac
    sleep 10; t=$((t + 10))
  done
  return 1
}

# Aplica un KafkaRebalance de forma robusta: reintenta si Cruise Control aún no
# reconoce los brokers nuevos (NotReady, por refresco de su modelo), espera
# ProposalReady, aprueba y espera Ready.
# Uso: rebalance_completo <name> <manifiesto> <ctx> <ns>
rebalance_completo() {
  rc_name=$1; rc_mani=$2; rc_ctx=$3; rc_ns=$4; rc_try=1; rc_st=1
  while [ "$rc_try" -le 6 ]; do
    kubectl apply -n "$rc_ns" --context "$rc_ctx" -f "$rc_mani" >/dev/null 2>&1
    esperar_rebalance "$rc_name" "$rc_ctx" "$rc_ns" ProposalReady 600
    rc_st=$?
    [ "$rc_st" -eq 0 ] && break
    if [ "$rc_st" -eq 2 ]; then
      msg_info "[rebalance] ${rc_name}: Cruise Control aún no reconoce los brokers; reintento (${rc_try})..."
      kubectl delete kafkarebalance "$rc_name" -n "$rc_ns" --context "$rc_ctx" >/dev/null 2>&1
      sleep 30; rc_try=$((rc_try + 1)); continue
    fi
    return 1
  done
  [ "$rc_st" -ne 0 ] && return 1
  kubectl annotate kafkarebalance "$rc_name" -n "$rc_ns" --context "$rc_ctx" strimzi.io/rebalance=approve --overwrite >/dev/null 2>&1
  esperar_rebalance "$rc_name" "$rc_ctx" "$rc_ns" Ready 600
}
