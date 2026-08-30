#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly REPO_ROOT
# shellcheck source=lib/common.sh
source "$REPO_ROOT/lib/common.sh"

STOW_DIR=${DOTFILES_STOW_DIR:-$REPO_ROOT/stow}
MODULES_DIR=${DOTFILES_MODULES_DIR:-$REPO_ROOT/modules}

discover_hosts() {
  local path
  HOSTS=()

  shopt -s nullglob
  for path in "$STOW_DIR"/host-*; do
    [[ -d $path ]] && HOSTS+=("${path##*/host-}")
  done
  shopt -u nullglob
}

discover_modules() {
  local path name
  MODULE_PATHS=()
  MODULE_NAMES=()

  shopt -s nullglob
  for path in "$MODULES_DIR"/[0-9][0-9]-*.sh; do
    [[ -f $path ]] || continue
    MODULE_PATHS+=("$path")
    name=${path##*/}
    MODULE_NAMES+=("${name%.sh}")
  done
  shopt -u nullglob
}

join_by_comma() {
  local IFS=', '
  printf '%s' "$*"
}

usage() {
  local hosts=${1:-nenhum}
  printf 'Uso: %s <notebook|desktop> [--only <modulo>] [--dry-run]\n' "$0" >&2
  printf 'Hosts encontrados: %s\n' "$hosts" >&2
}

host_is_known() {
  local candidate=$1 known
  for known in "${HOSTS[@]}"; do
    [[ $candidate == "$known" ]] && return 0
  done
  return 1
}

module_index() {
  local candidate=$1 index
  for index in "${!MODULE_NAMES[@]}"; do
    if [[ $candidate == "${MODULE_NAMES[$index]}" ]]; then
      printf '%s' "$index"
      return 0
    fi
  done
  return 1
}

discover_hosts
hosts_label=$(join_by_comma "${HOSTS[@]}")
[[ -n $hosts_label ]] || hosts_label=nenhum

if (( $# == 0 )); then
  usage "$hosts_label"
  exit 2
fi

HOST=$1
shift
ONLY_MODULE=
DRY_RUN=false

while (( $# > 0 )); do
  case $1 in
    --only)
      [[ -z $ONLY_MODULE ]] || die "--only foi informado mais de uma vez"
      (( $# >= 2 )) || die "--only exige o basename de um módulo"
      ONLY_MODULE=$2
      shift 2
      ;;
    --dry-run)
      [[ $DRY_RUN == false ]] || die "--dry-run foi informado mais de uma vez"
      DRY_RUN=true
      shift
      ;;
    *)
      die "argumento desconhecido: $1"
      ;;
  esac
done

host_is_known "$HOST" || {
  usage "$hosts_label"
  die "host desconhecido: $HOST"
}

discover_modules
(( ${#MODULE_PATHS[@]} > 0 )) || die "nenhum módulo encontrado em $MODULES_DIR"

selected_paths=("${MODULE_PATHS[@]}")
if [[ -n $ONLY_MODULE ]]; then
  index=$(module_index "$ONLY_MODULE") || die "módulo desconhecido: $ONLY_MODULE"
  selected_paths=("${MODULE_PATHS[$index]}")
fi

export REPO_ROOT HOST DRY_RUN

for module_path in "${selected_paths[@]}"; do
  module_name=${module_path##*/}
  module_name=${module_name%.sh}
  log_info "executando módulo: $module_name"

  module_args=("$HOST")
  [[ $DRY_RUN == true ]] && module_args+=(--dry-run)

  if bash "$module_path" "${module_args[@]}"; then
    :
  else
    status=$?
    log_error "módulo falhou: $module_name (status $status)"
    exit "$status"
  fi
done

log_info "bootstrap concluído para $HOST"
