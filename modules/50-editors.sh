#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly REPO_ROOT
# shellcheck source=lib/common.sh
source "$REPO_ROOT/lib/common.sh"

parse_module_args "$@"

settings_source="$REPO_ROOT/config/vscode/settings.json"
extensions_file="$REPO_ROOT/packages/vscode-extensions.txt"
settings_destination=${DOTFILES_VSCODE_SETTINGS:-$HOME/.config/Code/User/settings.json}
settings_parent=$(dirname -- "$settings_destination")

require_file "$settings_source"
require_file "$extensions_file"
require_command jq
require_command python3
require_command code

[[ ! -L $settings_destination ]] || die \
  "settings do VS Code é symlink; merge recusado: $settings_destination"

repo_resolved=$(readlink -f -- "$REPO_ROOT")
parent_resolved=$(readlink -m -- "$settings_parent")
if [[ $parent_resolved == "$repo_resolved" || $parent_resolved == "$repo_resolved/"* ]]; then
  die "destino do VS Code resolve para dentro do repositório; merge recusado: $settings_destination"
fi

jq -e 'type == "object"' "$settings_source" >/dev/null || \
  die "fonte gerenciada do VS Code deve ser um objeto JSON: $settings_source"

if [[ -e $settings_destination ]]; then
  python3 "$REPO_ROOT/lib/jsonc_to_json.py" < "$settings_destination" | \
    jq -e 'type == "object"' >/dev/null || \
    die "settings local do VS Code não é um objeto JSON/JSONC válido: $settings_destination"
fi

if [[ $DRY_RUN == true ]]; then
  log_info "dry-run: mesclar preferências em $settings_destination"
  while IFS= read -r extension || [[ -n $extension ]]; do
    [[ -z $extension || $extension == \#* ]] && continue
    log_info "dry-run: instalar extensão VS Code se ausente: $extension"
  done < "$extensions_file"
  exit 0
fi

ensure_dir "$settings_parent"
local_json=$(mktemp)
merged_json=$(mktemp "$settings_parent/.settings.json.XXXXXX")
trap 'rm -f -- "${local_json:-}" "${merged_json:-}"' EXIT

if [[ -e $settings_destination ]]; then
  python3 "$REPO_ROOT/lib/jsonc_to_json.py" < "$settings_destination" > "$local_json"
else
  printf '{}\n' > "$local_json"
fi

jq -S -s '.[0] * .[1]' "$local_json" "$settings_source" > "$merged_json"
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
rm -f -- "$local_json"
log_info "VS Code convergido"
