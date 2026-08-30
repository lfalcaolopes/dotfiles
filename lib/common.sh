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

# Dependências que outro módulo (ou o próprio preflight) instala antes deste.
# Em --dry-run numa máquina recém-instalada a ausência é esperada: o plano é
# registrado e a execução segue, em vez de abortar. Retorna 1 quando a
# dependência está ausente sob dry-run, para o chamador pular o que dependeria
# dela; sempre use em um condicional, já que os módulos rodam com set -e.
require_provisioned_command() {
  local command_name=$1
  local provider=${2:-um módulo anterior}

  command_exists "$command_name" && return 0

  if [[ ${DRY_RUN:-false} == true ]]; then
    log_info "dry-run: $command_name ainda não existe; $provider o instala antes deste módulo"
    summary_hold "$command_name"
    return 1
  fi

  # Fora do dry-run a ausência é fatal. Módulos rodam como processos próprios,
  # então encerramos aqui em vez de depender do set -e do chamador.
  log_error "comando obrigatório não encontrado: $command_name"
  exit 1
}

require_provisioned_file() {
  local file=$1
  local provider=${2:-um módulo anterior}

  [[ -f "$file" ]] && return 0

  if [[ ${DRY_RUN:-false} == true ]]; then
    log_info "dry-run: $file ainda não existe; $provider o cria antes deste módulo"
    summary_hold "${file##*/}"
    return 1
  fi

  log_error "arquivo obrigatório não encontrado: $file"
  exit 1
}

# O bootstrap agrega estes registros no resumo final do dry-run. Cada linha é
# módulo, tipo, contagem e mensagem, separados por tabulação. O resumo mostra
# atenções e pendências linha a linha e usa as mudanças apenas na contagem
# total; a mensagem de uma mudança fica no arquivo para diagnóstico. Sem
# DOTFILES_SUMMARY_FILE (módulo executado direto, fora do bootstrap) a função é
# um no-op.
summary_record() {
  local kind=$1 count=$2 message=$3
  local file=${DOTFILES_SUMMARY_FILE:-}

  [[ -n $file ]] || return 0
  printf '%s\t%s\t%s\t%s\n' \
    "${DOTFILES_SUMMARY_MODULE:-desconhecido}" "$kind" "$count" "$message" >> "$file"
}

# Mudanças que a execução real faria de fato; o módulo já confirmou que o
# estado atual diverge do desejado.
summary_change() {
  summary_record change "$1" "$2"
}

# Algo que a pessoa precisa conferir antes de aplicar.
summary_attention() {
  summary_record attention "$1" "$2"
}

# Validação que só é possível depois que outro módulo rodar.
summary_hold() {
  summary_record hold 1 "$1"
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
  local character index simulation line
  local pending_links=0
  local -a conflicts=()
  local -a stow_args=(--no-folding --restow --dir "$stow_dir" --target "$target")

  if ! require_provisioned_command stow "o módulo 00-preflight"; then
    log_info "dry-run: planejamento do pacote $package segue sem consultar o Stow"
  fi
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
    else
      pending_links=$((pending_links + 1))
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

    (( pending_links == 0 )) || summary_change "$pending_links" \
      "$pending_links link(s) a criar"
    if (( ${#conflicts[@]} > 0 )); then
      summary_change "${#conflicts[@]}" "${#conflicts[@]} arquivo(s) a substituir por link"
      summary_attention "${#conflicts[@]}" \
        "${#conflicts[@]} conflito(s) seriam movidos para backup"
    fi

    if ! command_exists stow; then
      return 0
    fi
    if (( ${#conflicts[@]} > 0 )); then
      log_info "dry-run: simulação do Stow pulada; a execução real protegeria os conflitos antes"
      return 0
    fi

    # -n não toca no disco: valida os argumentos e o plano de links de verdade.
    simulation=$(stow -n -v "${stow_args[@]}" "$package" 2>&1) || die \
      "simulação do Stow falhou para $package: $simulation"
    if [[ -n $simulation ]]; then
      while IFS= read -r line; do
        log_info "dry-run: stow: $line"
      done <<< "$simulation"
    fi
    return 0
  fi

  stow "${stow_args[@]}" "$package"
  log_info "pacote Stow aplicado: $package"
}
