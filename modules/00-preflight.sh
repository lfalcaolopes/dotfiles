#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly REPO_ROOT
# shellcheck source=lib/common.sh
source "$REPO_ROOT/lib/common.sh"

parse_module_args "$@"

os_release=${DOTFILES_OS_RELEASE:-/etc/os-release}
require_file "$os_release"

read_os_value() {
  local key=$1 line value
  line=$(/usr/bin/grep -m1 "^${key}=" "$os_release" || true)
  value=${line#*=}
  value=${value#\"}
  value=${value%\"}
  printf '%s' "$value"
}

os_id=$(read_os_value ID)
os_like=$(read_os_value ID_LIKE)
os_name=$(read_os_value NAME)

if [[ $os_id != omarchy && $os_name != *Omarchy* ]]; then
  die "ambiente incompatível: Omarchy não identificado em $os_release"
fi
if [[ $os_id != arch && " $os_like " != *' arch '* ]]; then
  die "ambiente incompatível: base Arch não identificada em $os_release"
fi

require_command curl
curl --fail --silent --show-error --head https://archlinux.org/ >/dev/null
log_info "rede disponível e ambiente Omarchy/Arch validado"

missing=()
for dependency in git stow; do
  command_exists "$dependency" || missing+=("$dependency")
done

if [[ $DRY_RUN == true ]]; then
  if (( ${#missing[@]} > 0 )); then
    log_info "dry-run: seriam instalados: ${missing[*]}"
    log_info "dry-run: $(shell_join sudo pacman -S --needed --noconfirm "${missing[@]}")"
  else
    log_info "Git e Stow já estão disponíveis"
  fi
  log_info "dry-run: sudo -v seria executado"
  exit 0
fi

require_command sudo
sudo -v

if (( ${#missing[@]} > 0 )); then
  require_command pacman
  sudo pacman -S --needed --noconfirm "${missing[@]}"
fi

require_command git
require_command stow
log_info "preflight concluído"
