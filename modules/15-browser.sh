#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly REPO_ROOT
# shellcheck source=lib/common.sh
source "$REPO_ROOT/lib/common.sh"

parse_module_args "$@"

# O instalador do Omarchy pergunta o navegador uma única vez e grava a escolha
# em ~/.config/mimeapps.list; numa instalação limpa que aceitou o padrão o
# resultado é o Chromium. O .zshrc do repositório já exporta BROWSER=brave, então
# convergir aqui evita a variável apontar para um binário inexistente.
#
# Os dois comandos abaixo são do próprio Omarchy: o instalador também cria o
# diretório de políticas, copia o chromium-flags.conf e aplica o tema atual,
# coisas que um `yay -S brave-bin` cru deixaria de fora.
readonly TARGET_BROWSER=brave
readonly TARGET_PACKAGE=brave-bin

require_command omarchy-install-browser
require_command omarchy-default-browser
require_command pacman

# Sem argumento o comando apenas traduz o mimeapps.list para o nome curto; é
# leitura pura, sem privilégio nem escrita.
current_browser=$(omarchy-default-browser)

browser_is_installed() {
  pacman -Qq "$TARGET_PACKAGE" >/dev/null 2>&1
}

# O instalador não é idempotente: ele copia o flags file por cima a cada
# execução. Só o chamamos quando o pacote falta, para não descartar ajustes
# locais em ~/.config/brave-flags.conf.
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
      "webapps do Omarchy passam ao perfil do $TARGET_BROWSER e pedem login de novo"
  fi
  exit 0
fi

changed=false
if install_diverges; then
  omarchy-install-browser "$TARGET_BROWSER"
  browser_is_installed || die \
    "$TARGET_PACKAGE não foi instalado; confira a saída do omarchy-install-browser"
  changed=true
fi

if default_diverges; then
  omarchy-default-browser "$TARGET_BROWSER"
  changed=true
fi

current_browser=$(omarchy-default-browser)
if install_diverges || default_diverges; then
  die "navegador não convergiu; padrão atual: $current_browser"
fi

if [[ $changed == true ]]; then
  log_info "navegador convergido: $TARGET_BROWSER"
  log_info "os webapps do Omarchy agora abrem no perfil do $TARGET_BROWSER"
else
  log_info "navegador já estava convergido: $TARGET_BROWSER"
fi
