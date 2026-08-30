#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly REPO_ROOT
# shellcheck source=lib/common.sh
source "$REPO_ROOT/lib/common.sh"

parse_module_args "$@"

if [[ $HOST == desktop ]]; then
  log_info "Kanata não se aplica ao host desktop"
  exit 0
fi

stow_dir=${DOTFILES_STOW_DIR:-$REPO_ROOT/stow}
source_config="$stow_dir/host-notebook/.config/kanata/config.kbd"
installed_config="$HOME/.config/kanata/config.kbd"
unit_source="$REPO_ROOT/config/systemd/kanata.service"
unit_dir="$HOME/.config/systemd/user"
unit_destination="$unit_dir/kanata.service"

kanata_available=true
if ! require_provisioned_command kanata "o módulo 10-packages"; then
  kanata_available=false
  log_info "dry-run: o serviço Kanata só sobe depois que o binário existir"
fi
require_command systemctl
require_command cmp
require_command install
require_command rm
require_file "$source_config"
require_file "$unit_source"

if [[ $DRY_RUN == false ]]; then
  require_file "$installed_config"
fi

# --check só valida a sintaxe e sai; não abre dispositivo nem exige privilégio.
if [[ $kanata_available == true ]]; then
  if kanata_output=$(kanata --cfg "$source_config" --check 2>&1); then
    log_info "config do Kanata validada: $source_config"
  else
    log_error "$kanata_output"
    die "config do Kanata é inválida: $source_config"
  fi
fi

unit_changed=true
if [[ ! -L $unit_destination && -f $unit_destination ]] && \
  cmp -s -- "$unit_source" "$unit_destination"; then
  unit_changed=false
fi

if [[ $DRY_RUN == true ]]; then
  if [[ $unit_changed == true ]]; then
    log_info "dry-run: copiar unit Kanata para $unit_destination"
    log_info "dry-run: $(shell_join systemctl --user daemon-reload)"
  else
    log_info "unit Kanata já está atualizada"
  fi
  log_info "dry-run: garantir kanata.service habilitada e ativa"
  exit 0
fi

if [[ $unit_changed == true ]]; then
  ensure_dir "$unit_dir"
  if [[ -L $unit_destination ]]; then
    rm -- "$unit_destination"
  fi
  install -m 0644 -- "$unit_source" "$unit_destination"
  systemctl --user daemon-reload
fi

if ! systemctl --user is-enabled --quiet kanata.service; then
  systemctl --user enable kanata.service
fi

if systemctl --user is-active --quiet kanata.service; then
  [[ $unit_changed == false ]] || systemctl --user restart kanata.service
else
  systemctl --user start kanata.service
fi

log_info "Kanata habilitado e ativo"
