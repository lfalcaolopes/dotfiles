#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly REPO_ROOT
# shellcheck source=lib/common.sh
source "$REPO_ROOT/lib/common.sh"

parse_module_args "$@"

# O instalador do Omarchy grava o layout escolhido durante a instalação e nada
# mais o revisita: numa máquina instalada com `us` puro as teclas mortas de
# acento não existem. O input.lua do Omarchy lê XKBLAYOUT/XKBVARIANT de
# /etc/vconsole.conf, então convergir o estado do systemd resolve o Hyprland, o
# Xorg e o TTY de uma vez.
readonly TARGET_LAYOUT=us
readonly TARGET_MODEL=pc105
readonly TARGET_VARIANT=intl
readonly TARGET_KEYMAP=us-acentos

vconsole=${DOTFILES_VCONSOLE:-/etc/vconsole.conf}
x11_keymap=${DOTFILES_X11_KEYMAP:-/etc/X11/xorg.conf.d/00-keyboard.conf}

require_command localectl

# Leitura direta dos arquivos que o systemd-localed escreve: consultar o estado
# não exige privilégio e mantém o dry-run sem nenhuma chamada externa.
read_vconsole_value() {
  local key=$1 line value=''

  [[ -f $vconsole ]] || return 0
  # A condição extra processa uma última linha sem quebra no fim do arquivo.
  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line == "$key="* ]] || continue
    value=${line#*=}
    value=${value#\"}
    value=${value%\"}
  done < "$vconsole"

  printf '%s' "$value"
}

# Extrai o segundo token entre aspas de `Option "XkbLayout" "us"`.
read_x11_option() {
  local line=$1 rest
  rest=${line#*\"}
  rest=${rest#*\"}
  rest=${rest#*\"}
  printf '%s' "${rest%%\"*}"
}

x11_is_converged() {
  local line layout='' model='' variant=''

  [[ -f $x11_keymap ]] || return 1
  while IFS= read -r line || [[ -n $line ]]; do
    case $line in
      *'"XkbLayout"'*) layout=$(read_x11_option "$line") ;;
      *'"XkbModel"'*) model=$(read_x11_option "$line") ;;
      *'"XkbVariant"'*) variant=$(read_x11_option "$line") ;;
    esac
  done < "$x11_keymap"

  [[ $layout == "$TARGET_LAYOUT" && \
    $model == "$TARGET_MODEL" && \
    $variant == "$TARGET_VARIANT" ]]
}

# `localectl set-x11-keymap` escreve XKBLAYOUT/XKBMODEL/XKBVARIANT no
# vconsole.conf e o InputClass do Xorg; os dois precisam bater para o estado
# contar como convergido.
x11_keymap_diverges() {
  if [[ $(read_vconsole_value XKBLAYOUT) != "$TARGET_LAYOUT" || \
    $(read_vconsole_value XKBMODEL) != "$TARGET_MODEL" || \
    $(read_vconsole_value XKBVARIANT) != "$TARGET_VARIANT" ]]; then
    return 0
  fi

  if x11_is_converged; then
    return 1
  fi
  return 0
}

vc_keymap_diverges() {
  [[ $(read_vconsole_value KEYMAP) != "$TARGET_KEYMAP" ]]
}

x11_command=(localectl set-x11-keymap "$TARGET_LAYOUT" "$TARGET_MODEL" "$TARGET_VARIANT")
vc_command=(localectl set-keymap "$TARGET_KEYMAP")

if [[ $DRY_RUN == true ]]; then
  pending=0

  if x11_keymap_diverges; then
    log_info "dry-run: layout X11 divergente em $vconsole e $x11_keymap"
    log_info "dry-run: $(shell_join sudo "${x11_command[@]}")"
    pending=$((pending + 1))
  else
    log_info "layout X11 já é $TARGET_LAYOUT $TARGET_MODEL $TARGET_VARIANT"
  fi

  if vc_keymap_diverges; then
    log_info "dry-run: keymap do console divergente em $vconsole"
    log_info "dry-run: $(shell_join sudo "${vc_command[@]}")"
    pending=$((pending + 1))
  else
    log_info "keymap do console já é $TARGET_KEYMAP"
  fi

  if (( pending > 0 )); then
    summary_change "$pending" "$pending ajuste(s) de teclado a aplicar"
    summary_attention "$pending" \
      "teclado passa a $TARGET_LAYOUT($TARGET_VARIANT); a sessão aberta só muda com hyprctl reload"
  fi
  exit 0
fi

require_command sudo

changed=false
if x11_keymap_diverges; then
  sudo "${x11_command[@]}"
  changed=true
fi

if vc_keymap_diverges; then
  sudo "${vc_command[@]}"
  changed=true
fi

if x11_keymap_diverges || vc_keymap_diverges; then
  die "layout de teclado não convergiu após localectl; confira $vconsole e $x11_keymap"
fi

if [[ $changed == true ]]; then
  log_info "teclado convergido: $TARGET_LAYOUT($TARGET_VARIANT), console $TARGET_KEYMAP"
  log_info "a sessão já aberta assume o layout depois de hyprctl reload"
else
  log_info "teclado já estava convergido: $TARGET_LAYOUT($TARGET_VARIANT), console $TARGET_KEYMAP"
fi
