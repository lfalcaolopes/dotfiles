#!/usr/bin/env bash
set -Eeuo pipefail

log_info() {
  printf '[INFO] %s\n' "$*"
}

log_warn() {
  printf '[WARN] %s\n' "$*" >&2
}

log_error() {
  printf '[ERROR] %s\n' "$*" >&2
}

die() {
  log_error "$*"
  return 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

require_command() {
  command_exists "$1" || die "comando obrigatório não encontrado: $1"
}

require_file() {
  [[ -f "$1" ]] || die "arquivo obrigatório não encontrado: $1"
}

shell_join() {
  local arg quoted
  local -a output=()

  for arg in "$@"; do
    printf -v quoted '%q' "$arg"
    output+=("$quoted")
  done

  local IFS=' '
  printf '%s' "${output[*]}"
}

run_mutating() {
  local description=$1
  shift

  if [[ ${DRY_RUN:-false} == true ]]; then
    log_info "dry-run: $description: $(shell_join "$@")"
    return 0
  fi

  "$@"
}

ensure_dir() {
  local directory=$1

  if [[ -d "$directory" ]]; then
    return 0
  fi

  run_mutating "criar diretório $directory" mkdir -p -- "$directory"
}

confirm() {
  local prompt=${1:-Continuar?}
  local reply

  if [[ ${DRY_RUN:-false} == true ]]; then
    log_info "dry-run: confirmação seria solicitada: $prompt"
    return 0
  fi

  read -r -p "$prompt [y/N] " reply
  [[ $reply == [yY] || $reply == [yY][eE][sS] ]]
}

parse_module_args() {
  if (( $# < 1 || $# > 2 )); then
    die "uso: $(basename "$0") <notebook|desktop> [--dry-run]"
    return 1
  fi

  HOST=$1
  DRY_RUN=false

  if (( $# == 2 )); then
    [[ $2 == --dry-run ]] || {
      die "opção desconhecida para o módulo: $2"
      return 1
    }
    DRY_RUN=true
  fi

  local host_package="${DOTFILES_STOW_DIR:-$REPO_ROOT/stow}/host-$HOST"
  [[ -d $host_package ]] || {
    die "host inválido para o módulo: $HOST"
    return 1
  }

  export HOST DRY_RUN
}
