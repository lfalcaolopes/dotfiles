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

if [[ $DRY_RUN == true ]]; then
  (( ${#official[@]} == 0 )) || run_mutating \
    "instalar pacotes oficiais" sudo pacman -S --needed --noconfirm "${official[@]}"
  (( ${#aur[@]} == 0 )) || run_mutating \
    "instalar pacotes AUR" yay -S --needed --noconfirm "${aur[@]}"
  exit 0
fi

if (( ${#official[@]} > 0 )); then
  sudo pacman -S --needed --noconfirm "${official[@]}"
fi

if (( ${#aur[@]} > 0 )); then
  yay -S --needed --noconfirm "${aur[@]}"
fi

log_info "pacotes convergidos para o host $HOST"
