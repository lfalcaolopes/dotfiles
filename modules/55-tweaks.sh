#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly REPO_ROOT
# shellcheck source=lib/common.sh
source "$REPO_ROOT/lib/common.sh"

parse_module_args "$@"

config_home=${XDG_CONFIG_HOME:-$HOME/.config}
alacritty="$config_home/alacritty/alacritty.toml"
foot="$config_home/foot/foot.ini"
ghostty="$config_home/ghostty/config"
kitty="$config_home/kitty/kitty.conf"
shell_json="$config_home/omarchy/shell.json"

require_command awk

jq_available=true
if ! require_provisioned_command jq "o Omarchy"; then
  jq_available=false
fi

# Nenhum terminal está nas listas de pacotes: os quatro configs vêm do próprio
# Omarchy, e o do ghostty também do 17-terminal quando a máquina ainda não o
# tinha. Numa máquina recém-instalada eles podem faltar, então em dry-run
# apenas os anotamos com quem os cria.
present_specifications=()
for specification in \
  "alacritty:$alacritty" \
  "foot:$foot" \
  "ghostty:$ghostty" \
  "kitty:$kitty"; do
  kind=${specification%%:*}
  file=${specification#*:}
  case $kind in
    ghostty) provider="o Omarchy ou o módulo 17-terminal" ;;
    *) provider="o Omarchy" ;;
  esac
  if require_provisioned_file "$file" "$provider"; then
    present_specifications+=("$specification")
  fi
done

shell_json_available=true
if ! require_provisioned_file "$shell_json" "o Omarchy"; then
  shell_json_available=false
fi

render_terminal() {
  local kind=$1 file=$2
  case $kind in
    alacritty)
      awk '
        /^\[[^]]+\][[:space:]]*$/ { in_font = ($0 == "[font]") }
        in_font && /^[[:space:]]*size[[:space:]]*=[[:space:]]*[0-9]+([.][0-9]+)?[[:space:]]*$/ {
          sub(/size[[:space:]]*=[[:space:]]*[0-9]+([.][0-9]+)?/, "size = 11")
          count++
        }
        { print }
        END { if (count != 1) exit 42 }
      ' "$file"
      ;;
    foot)
      awk '
        /^font=.*:size=[0-9]+([.][0-9]+)?[[:space:]]*$/ {
          sub(/:size=[0-9]+([.][0-9]+)?[[:space:]]*$/, ":size=11")
          count++
        }
        { print }
        END { if (count != 1) exit 42 }
      ' "$file"
      ;;
    ghostty)
      awk '
        /^[[:space:]]*font-size[[:space:]]*=[[:space:]]*[0-9]+([.][0-9]+)?[[:space:]]*$/ {
          sub(/font-size[[:space:]]*=[[:space:]]*[0-9]+([.][0-9]+)?/, "font-size = 11")
          count++
        }
        { print }
        END { if (count != 1) exit 42 }
      ' "$file"
      ;;
    kitty)
      awk '
        /^[[:space:]]*font_size[[:space:]]+[0-9]+([.][0-9]+)?[[:space:]]*$/ {
          sub(/font_size[[:space:]]+[0-9]+([.][0-9]+)?/, "font_size 11.0")
          count++
        }
        { print }
        END { if (count != 1) exit 42 }
      ' "$file"
      ;;
    *) die "tipo de terminal desconhecido: $kind" ;;
  esac
}

for specification in ${present_specifications[@]+"${present_specifications[@]}"}; do
  kind=${specification%%:*}
  file=${specification#*:}
  render_terminal "$kind" "$file" >/dev/null || die \
    "formato esperado de fonte não encontrado uma única vez em $file"
done

if [[ $jq_available == true && $shell_json_available == true ]]; then
  jq -e '
    (.idle | type == "object") and
    (.idle.lock | type == "number") and
    (.idle.screensaver | type == "number")
  ' "$shell_json" >/dev/null || die \
    "formato esperado de idle não encontrado em $shell_json"
fi

# O render já é somente leitura: comparar a saída com o arquivo atual diz quais
# arquivos a execução real muda. Vale nos dois modos, já que a execução real
# reescreve os cinco arquivos sem olhar o conteúdo anterior.
divergent=()
for specification in ${present_specifications[@]+"${present_specifications[@]}"}; do
  kind=${specification%%:*}
  file=${specification#*:}
  if ! render_terminal "$kind" "$file" | cmp -s - "$file"; then
    divergent+=("$file")
  fi
done

if [[ $jq_available == true && $shell_json_available == true ]]; then
  if ! jq '.idle.lock = 3600 | .idle.screensaver = 86400' "$shell_json" | \
    cmp -s - "$shell_json"; then
    divergent+=("$shell_json")
  fi
fi

if [[ $DRY_RUN == true ]]; then
  log_info "dry-run: ajustar fontes dos quatro terminais para 11"
  log_info "dry-run: ajustar idle.lock=3600 e idle.screensaver=86400 em $shell_json"

  for file in ${divergent[@]+"${divergent[@]}"}; do
    log_info "dry-run: conteúdo divergente em $file"
  done

  (( ${#divergent[@]} == 0 )) || summary_change "${#divergent[@]}" \
    "${#divergent[@]} arquivo(s) a reescrever"
  exit 0
fi

declare -a temporary_files=()
cleanup() {
  ((${#temporary_files[@]} == 0)) || rm -f -- "${temporary_files[@]}"
}
trap cleanup EXIT

for specification in \
  "alacritty:$alacritty" \
  "foot:$foot" \
  "ghostty:$ghostty" \
  "kitty:$kitty"; do
  kind=${specification%%:*}
  file=${specification#*:}
  temporary=$(mktemp "$(dirname -- "$file")/.dotfiles-tweak.XXXXXX")
  temporary_files+=("$temporary")
  render_terminal "$kind" "$file" > "$temporary"
  chmod --reference="$file" "$temporary"
done

temporary=$(mktemp "$(dirname -- "$shell_json")/.dotfiles-tweak.XXXXXX")
temporary_files+=("$temporary")
jq '.idle.lock = 3600 | .idle.screensaver = 86400' "$shell_json" > "$temporary"
chmod --reference="$shell_json" "$temporary"

index=0
for file in "$alacritty" "$foot" "$ghostty" "$kitty" "$shell_json"; do
  mv -f -- "${temporary_files[$index]}" "$file"
  index=$((index + 1))
done
temporary_files=()
trap - EXIT

(( ${#divergent[@]} == 0 )) || summary_change "${#divergent[@]}" \
  "${#divergent[@]} arquivo(s) reescrito(s)"

log_info "fontes de terminal e idle convergidos"
