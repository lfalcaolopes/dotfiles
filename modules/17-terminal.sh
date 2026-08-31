#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly REPO_ROOT
# shellcheck source=lib/common.sh
source "$REPO_ROOT/lib/common.sh"

parse_module_args "$@"

# O Omarchy escolhe o terminal na instalação e nunca mais revisita: numa máquina
# que aceitou o padrão o resultado é o foot. Quem decide qual terminal abre no
# SUPER + RETURN, no xdg-terminal-exec e nos TUIs do Omarchy é o primeiro
# desktop entry de ~/.config/xdg-terminals.list, e é esse arquivo que os dois
# comandos abaixo escrevem.
#
# O instalador do Omarchy também copia o config padrão do terminal quando
# ~/.config/ghostty falta, coisa que um `pacman -S ghostty` cru deixaria de
# fora. Numa máquina já provisionada o diretório existe e nada é sobrescrito.
readonly TARGET_TERMINAL=ghostty
readonly TARGET_PACKAGE=ghostty

require_command omarchy-install-terminal
require_command omarchy-default-terminal
require_command pacman

# Sem argumento o comando apenas traduz o xdg-terminals.list para o nome curto;
# é leitura pura, sem privilégio nem escrita.
current_terminal=$(omarchy-default-terminal)

terminal_is_installed() {
  pacman -Qq "$TARGET_PACKAGE" >/dev/null 2>&1
}

# O instalador já grava o xdg-terminals.list, então quando ele roda o passo do
# padrão fica redundante. Só o chamamos quando o pacote falta, para não repetir
# a cópia do config numa máquina onde ~/.config/ghostty já foi ajustado.
install_diverges() {
  ! terminal_is_installed
}

default_diverges() {
  [[ $current_terminal != "$TARGET_TERMINAL" ]]
}

if [[ $DRY_RUN == true ]]; then
  pending=0

  if install_diverges; then
    log_info "dry-run: $TARGET_PACKAGE ausente"
    log_info "dry-run: $(shell_join omarchy-install-terminal "$TARGET_TERMINAL")"
    pending=$((pending + 1))
  else
    log_info "$TARGET_PACKAGE já está instalado"
  fi

  if default_diverges; then
    log_info "dry-run: terminal padrão é '$current_terminal', esperado '$TARGET_TERMINAL'"
    log_info "dry-run: $(shell_join omarchy-default-terminal "$TARGET_TERMINAL")"
    pending=$((pending + 1))
  else
    log_info "terminal padrão já é $TARGET_TERMINAL"
  fi

  if (( pending > 0 )); then
    summary_change "$pending" "$pending ajuste(s) de terminal a aplicar"
    summary_attention "$pending" \
      "SUPER + RETURN e os TUIs do Omarchy passam ao $TARGET_TERMINAL; o terminal antigo continua instalado"
  fi
  exit 0
fi

applied=0
if install_diverges; then
  omarchy-install-terminal "$TARGET_TERMINAL"
  terminal_is_installed || die \
    "$TARGET_PACKAGE não foi instalado; confira a saída do omarchy-install-terminal"
  applied=$((applied + 1))
  # O instalador escreve o xdg-terminals.list; reler evita um segundo write.
  current_terminal=$(omarchy-default-terminal)
fi

if default_diverges; then
  omarchy-default-terminal "$TARGET_TERMINAL"
  applied=$((applied + 1))
fi

current_terminal=$(omarchy-default-terminal)
if install_diverges || default_diverges; then
  die "terminal não convergiu; padrão atual: $current_terminal"
fi

if (( applied > 0 )); then
  summary_change "$applied" "$applied ajuste(s) de terminal aplicado(s)"
  summary_attention "$applied" \
    "SUPER + RETURN e os TUIs do Omarchy passaram ao $TARGET_TERMINAL; o terminal antigo continua instalado"
  log_info "terminal convergido: $TARGET_TERMINAL"
  log_info "SUPER + RETURN e o xdg-terminal-exec agora abrem o $TARGET_TERMINAL"
else
  log_info "terminal já estava convergido: $TARGET_TERMINAL"
fi
