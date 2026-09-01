#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly REPO_ROOT
# shellcheck source=lib/common.sh
source "$REPO_ROOT/lib/common.sh"

parse_module_args "$@"

# O instalador do Omarchy pergunta o navegador uma única vez e grava a escolha
# em ~/.config/mimeapps.list; numa instalação limpa que aceitou o padrão o
# resultado é o Chromium. O .zshrc do repositório já exporta
# BROWSER=zen-browser, então
# convergir aqui evita a variável apontar para um binário inexistente.
#
# Os dois comandos abaixo são do próprio Omarchy: o instalador também configura
# as políticas do Firefox e habilita o backend Wayland, coisas que um
# `yay -S zen-browser-bin` cru deixaria de fora.
readonly TARGET_BROWSER=zen
readonly TARGET_PACKAGE=zen-browser-bin

require_command omarchy-install-browser
require_command omarchy-default-browser
require_command pacman

# Sem argumento o comando apenas traduz o mimeapps.list para o nome curto; é
# leitura pura, sem privilégio nem escrita.
current_browser=$(omarchy-default-browser)

browser_is_installed() {
  pacman -Qq "$TARGET_PACKAGE" >/dev/null 2>&1
}

# Só chamamos o instalador quando o pacote falta. Além de evitar trabalho
# desnecessário, isso mantém instalação e seleção do padrão como convergências
# independentes.
install_diverges() {
  ! browser_is_installed
}

default_diverges() {
  [[ $current_browser != "$TARGET_BROWSER" ]]
}

if [[ $DRY_RUN == true ]]; then
  pending=0

  if install_diverges; then
    log_info "dry-run: $TARGET_PACKAGE ausente"
    log_info "dry-run: $(shell_join omarchy-install-browser "$TARGET_BROWSER")"
    pending=$((pending + 1))
  else
    log_info "$TARGET_PACKAGE já está instalado"
  fi

  if default_diverges; then
    log_info "dry-run: navegador padrão é '$current_browser', esperado '$TARGET_BROWSER'"
    log_info "dry-run: $(shell_join omarchy-default-browser "$TARGET_BROWSER")"
    pending=$((pending + 1))
  else
    log_info "navegador padrão já é $TARGET_BROWSER"
  fi

  if (( pending > 0 )); then
    summary_change "$pending" "$pending ajuste(s) de navegador a aplicar"
    summary_attention "$pending" \
      "navegação normal passa ao $TARGET_BROWSER; webapps do Omarchy continuam no Chromium"
  fi
  exit 0
fi

applied=0
if install_diverges; then
  omarchy-install-browser "$TARGET_BROWSER"
  browser_is_installed || die \
    "$TARGET_PACKAGE não foi instalado; confira a saída do omarchy-install-browser"
  applied=$((applied + 1))
fi

if default_diverges; then
  omarchy-default-browser "$TARGET_BROWSER"
  applied=$((applied + 1))
fi

current_browser=$(omarchy-default-browser)
if install_diverges || default_diverges; then
  die "navegador não convergiu; padrão atual: $current_browser"
fi

if (( applied > 0 )); then
  summary_change "$applied" "$applied ajuste(s) de navegador aplicado(s)"
  summary_attention "$applied" \
    "navegação normal passou ao $TARGET_BROWSER; webapps do Omarchy continuam no Chromium"
  log_info "navegador convergido: $TARGET_BROWSER"
  log_info "webapps do Omarchy continuam abrindo no Chromium"
else
  log_info "navegador já estava convergido: $TARGET_BROWSER"
fi
