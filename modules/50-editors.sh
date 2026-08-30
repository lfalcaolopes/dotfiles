#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly REPO_ROOT
# shellcheck source=lib/common.sh
source "$REPO_ROOT/lib/common.sh"

parse_module_args "$@"

settings_source=${DOTFILES_VSCODE_MANAGED:-$REPO_ROOT/config/vscode/settings.json}
extensions_file="$REPO_ROOT/packages/vscode-extensions.txt"
settings_destination=${DOTFILES_VSCODE_SETTINGS:-$HOME/.config/Code/User/settings.json}
settings_parent=$(dirname -- "$settings_destination")

require_file "$settings_source"
require_file "$extensions_file"
require_command jq
require_command python3
if ! require_provisioned_command code "o módulo 10-packages"; then
  log_info "dry-run: as extensões só podem ser conferidas com o code instalado"
fi

[[ ! -L $settings_destination ]] || die \
  "settings do VS Code é symlink; merge recusado: $settings_destination"

repo_resolved=$(readlink -f -- "$REPO_ROOT")
parent_resolved=$(readlink -m -- "$settings_parent")
if [[ $parent_resolved == "$repo_resolved" || $parent_resolved == "$repo_resolved/"* ]]; then
  die "destino do VS Code resolve para dentro do repositório; merge recusado: $settings_destination"
fi

python3 "$REPO_ROOT/lib/jsonc_to_json.py" < "$settings_source" | \
  jq -e 'type == "object"' >/dev/null || \
  die "fonte gerenciada do VS Code deve ser um objeto JSON/JSONC: $settings_source"

if [[ -e $settings_destination ]]; then
  python3 "$REPO_ROOT/lib/jsonc_to_json.py" < "$settings_destination" | \
    jq -e 'type == "object"' >/dev/null || \
    die "settings local do VS Code não é um objeto JSON/JSONC válido: $settings_destination"
fi

if [[ $DRY_RUN == true ]]; then
  log_info "dry-run: aplicar bloco gerenciado e preservar bloco local em $settings_destination"

  # O merge é montado num temporário fora do HOME só para comparar com o
  # arquivo atual; o destino não é tocado.
  preview=$(mktemp)
  # Caminho absoluto para o temporário interno não passar pelos shims de teste.
  trap '/usr/bin/rm -f -- "${preview:-}"' EXIT
  divergences=$(python3 "$REPO_ROOT/lib/vscode_settings_merge.py" \
    --managed "$settings_source" \
    --destination "$settings_destination" \
    --output "$preview") || die \
    "falha ao montar as preferências do VS Code: $settings_destination"

  if [[ -n $divergences ]]; then
    while IFS= read -r divergence; do
      log_info "$divergence"
    done <<< "$divergences"
  fi

  if cmp -s -- "$preview" "$settings_destination"; then
    log_info "settings.json do VS Code já está convergido"
  else
    summary_change 1 "reescrever o settings.json do VS Code"
  fi
  /usr/bin/rm -f -- "$preview"
  trap - EXIT

  pending_extensions=0
  if command_exists code; then
    declare -A installed=()
    while IFS= read -r extension || [[ -n $extension ]]; do
      [[ -n $extension ]] && installed["${extension,,}"]=1
    done < <(code --list-extensions)
  fi

  while IFS= read -r extension || [[ -n $extension ]]; do
    [[ -z $extension || $extension == \#* ]] && continue
    log_info "dry-run: instalar extensão VS Code se ausente: $extension"
    if command_exists code && [[ -z ${installed[${extension,,}]+present} ]]; then
      pending_extensions=$((pending_extensions + 1))
    fi
  done < "$extensions_file"

  (( pending_extensions == 0 )) || summary_change "$pending_extensions" \
    "$pending_extensions extensão(ões) do VS Code a instalar"
  exit 0
fi

ensure_dir "$settings_parent"
merged_json=$(mktemp "$settings_parent/.settings.json.XXXXXX")
trap 'rm -f -- "${merged_json:-}"' EXIT

divergences=$(python3 "$REPO_ROOT/lib/vscode_settings_merge.py" \
  --managed "$settings_source" \
  --destination "$settings_destination" \
  --output "$merged_json") || die \
  "falha ao montar as preferências do VS Code: $settings_destination"

if [[ -n $divergences ]]; then
  while IFS= read -r divergence; do
    log_info "$divergence"
  done <<< "$divergences"
fi

if [[ -e $settings_destination ]]; then
  chmod --reference="$settings_destination" "$merged_json"
else
  chmod 0644 "$merged_json"
fi
mv -f -- "$merged_json" "$settings_destination"

declare -A installed=()
installed_output=$(code --list-extensions)
while IFS= read -r extension || [[ -n $extension ]]; do
  [[ -n $extension ]] && installed["${extension,,}"]=1
done <<< "$installed_output"

while IFS= read -r extension || [[ -n $extension ]]; do
  [[ -z $extension || $extension == \#* ]] && continue
  [[ $extension != *[[:space:]]* ]] || die \
    "identificador de extensão inválido em $extensions_file: $extension"
  if [[ -z ${installed[${extension,,}]+present} ]]; then
    code --install-extension "$extension"
  fi
done < "$extensions_file"

trap - EXIT
log_info "VS Code convergido"
