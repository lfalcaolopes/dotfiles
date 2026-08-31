#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly REPO_ROOT
# shellcheck source=lib/common.sh
source "$REPO_ROOT/lib/common.sh"

parse_module_args "$@"

packages_dir=${DOTFILES_PACKAGES_DIR:-$REPO_ROOT/packages}
core_list="$packages_dir/core.txt"
host_list="$packages_dir/host-$HOST.txt"
require_file "$core_list"

packages=()
read_package_list() {
  local list=$1 line
  [[ -f $list ]] || return 0

  while IFS= read -r line || [[ -n $line ]]; do
    [[ -z $line || $line == \#* ]] && continue
    [[ $line != *[[:space:]]* ]] || die "entrada de pacote inválida em $list: $line"
    packages+=("$line")
  done < "$list"
}

read_package_list "$core_list"
if [[ -f $host_list ]]; then
  read_package_list "$host_list"
else
  log_info "lista opcional ausente, continuando: $host_list"
fi

official=()
aur=()
declare -A seen=()
for package in "${packages[@]}"; do
  [[ -z ${seen[$package]+present} ]] || continue
  seen[$package]=1

  case $package in
    postman-bin|kanata-bin) aur+=("$package") ;;
    *) official+=("$package") ;;
  esac
done

if (( ${#official[@]} > 0 )); then
  require_command sudo
  require_command pacman
fi
if (( ${#aur[@]} > 0 )); then
  require_command yay
fi

# pacman -Qq só consulta o banco local: diz o que falta sem tocar em nada. A
# consulta roda nos dois modos, para o resumo contar o que o comando instalou
# de fato; com --needed a chamada é a mesma tenha ou não pacote ausente.
missing=()
missing_known=false
if command_exists pacman; then
  missing_known=true
  for package in "${official[@]}" "${aur[@]}"; do
    pacman -Qq "$package" >/dev/null 2>&1 || missing+=("$package")
  done
fi

if [[ $DRY_RUN == true ]]; then
  (( ${#official[@]} == 0 )) || run_mutating \
    "instalar pacotes oficiais" sudo pacman -S --needed --noconfirm "${official[@]}"
  (( ${#aur[@]} == 0 )) || run_mutating \
    "instalar pacotes AUR" yay -S --needed --noconfirm "${aur[@]}"

  if [[ $missing_known == false ]]; then
    summary_hold pacman
  elif (( ${#missing[@]} > 0 )); then
    log_info "dry-run: ausentes nesta máquina: ${missing[*]}"
    summary_change "${#missing[@]}" "${#missing[@]} pacote(s) a instalar"
  else
    log_info "todos os pacotes já estão instalados"
  fi
  exit 0
fi

if (( ${#official[@]} > 0 )); then
  sudo pacman -S --needed --noconfirm "${official[@]}"
fi

if (( ${#aur[@]} > 0 )); then
  yay -S --needed --noconfirm "${aur[@]}"
fi

if (( ${#missing[@]} > 0 )); then
  summary_change "${#missing[@]}" "${#missing[@]} pacote(s) instalado(s)"
else
  log_info "todos os pacotes já estavam instalados"
fi

log_info "pacotes convergidos para o host $HOST"
