#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly REPO_ROOT
# shellcheck source=lib/common.sh
source "$REPO_ROOT/lib/common.sh"

parse_module_args "$@"
if ! require_provisioned_command mise "o Omarchy"; then
  log_info "dry-run: os comandos abaixo dependem do mise instalado"
fi

if command_exists mise && command_exists jq; then
  # mise ls apenas lê a configuração global e o que está instalado. A consulta
  # roda nos dois modos: `mise use` é chamado sempre, então só a comparação
  # anterior diz se algum pino mudou de fato.
  global_state=$(mise ls --global --json 2>/dev/null || printf '{}')
  pending=0

  for pin in node@24 pnpm@12 dotnet@10; do
    tool=${pin%@*}
    desired=${pin#*@}
    requested=$(jq -r --arg tool "$tool" \
      '.[$tool][0].requested_version // empty' <<< "$global_state" 2>/dev/null || true)

    if [[ $requested != "$desired" ]]; then
      if [[ $DRY_RUN == true ]]; then
        log_info "dry-run: $tool fixado em '${requested:-nenhum}', esperado '$desired'"
      else
        log_info "$tool fixado em '${requested:-nenhum}', será fixado em '$desired'"
      fi
      pending=$((pending + 1))
    fi
  done

  if (( pending > 0 )); then
    if [[ $DRY_RUN == true ]]; then
      summary_change "$pending" "$pending runtime(s) a fixar"
    else
      summary_change "$pending" "$pending runtime(s) fixado(s)"
    fi
  fi
fi

run_mutating "fixar Node 24 global" mise use -g node@24
run_mutating "fixar pnpm 12 global" mise use -g pnpm@12
run_mutating "fixar .NET SDK 10 global" mise use -g dotnet@10

log_info "runtimes globais do mise convergidos"
