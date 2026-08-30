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

stow_apply_package() {
  local package=$1
  local stow_dir=${DOTFILES_STOW_DIR:-$REPO_ROOT/stow}
  local package_dir="$stow_dir/$package"
  local target=${DOTFILES_STOW_TARGET:-$HOME}
  local state_home=${XDG_STATE_HOME:-$HOME/.local/state}
  local backup_root="$state_home/dotfiles/backups"
  local timestamp backup_dir=
  local source relative destination resolved_source resolved_destination escaped_relative
  local resolved_backup_root resolved_stow_dir
  local character index
  local -a conflicts=()
  local -a stow_args=(--no-folding --restow --dir "$stow_dir" --target "$target")

  require_command stow
  [[ -d $package_dir ]] || die "pacote Stow não encontrado: $package_dir"
  [[ -d $target ]] || die "destino Stow não encontrado: $target"

  while IFS= read -r -d '' source; do
    relative=${source#"$package_dir"/}
    [[ $relative == .stow-local-ignore ]] && continue
    destination="$target/$relative"

    if [[ -e $destination || -L $destination ]]; then
      resolved_source=$(readlink -f -- "$source")
      resolved_destination=$(readlink -f -- "$destination" 2>/dev/null || true)
      if [[ -n $resolved_destination && $resolved_destination == "$resolved_source" ]]; then
        if [[ -L $destination && $(readlink -- "$destination") == /* ]]; then
          escaped_relative=
          for (( index = 0; index < ${#relative}; index++ )); do
            character=${relative:index:1}
            case $character in
              \\|'['|']'|'.'|'^'|'$'|'*'|'+'|'?'|'('|')'|'{'|'}'|'|')
                escaped_relative+="\\$character"
                ;;
              *) escaped_relative+="$character" ;;
            esac
          done
          stow_args+=("--ignore=^${escaped_relative}$")
        fi
        continue
      fi
      if [[ -n $resolved_destination && \
        ( $resolved_destination == "$package_dir" || $resolved_destination == "$package_dir/"* ) ]]; then
        die "destino resolve para dentro do pacote Stow; remoção recusada: $destination"
      fi
      [[ ! -d $destination ]] || die \
        "conflito é diretório; conteúdo não gerenciado foi preservado: $destination"
      conflicts+=("$relative")
    fi
  done < <(find "$package_dir" \( -type f -o -type l \) -print0)

  if (( ${#conflicts[@]} > 0 )); then
    timestamp=$(date -u +'%Y%m%dT%H%M%S-%N')
    backup_dir="$backup_root/$timestamp"

    if [[ ${DRY_RUN:-false} == true ]]; then
      for relative in "${conflicts[@]}"; do
        log_info "dry-run: proteger conflito $target/$relative em $backup_dir/$relative"
      done
    else
      resolved_backup_root=$(readlink -m -- "$backup_root")
      resolved_stow_dir=$(readlink -f -- "$stow_dir")
      if [[ $resolved_backup_root == "$resolved_stow_dir" || \
        $resolved_backup_root == "$resolved_stow_dir/"* ]]; then
        die "diretório de backup resolve para dentro da fonte Stow: $backup_root"
      fi
      ensure_dir "$backup_root"
      mkdir -- "$backup_dir"

      for relative in "${conflicts[@]}"; do
        destination="$target/$relative"
        ensure_dir "$(dirname -- "$backup_dir/$relative")"
        cp -a -- "$destination" "$backup_dir/$relative"
        [[ -e $backup_dir/$relative || -L $backup_dir/$relative ]] || die \
          "backup não pôde ser verificado: $backup_dir/$relative"
        rm -- "$destination"
      done

      log_info "conflitos protegidos em $backup_dir"
    fi
  fi

  if [[ ${DRY_RUN:-false} == true ]]; then
    log_info "dry-run: aplicar Stow: $(shell_join stow "${stow_args[@]}" "$package")"
    return 0
  fi

  stow "${stow_args[@]}" "$package"
  log_info "pacote Stow aplicado: $package"
}
