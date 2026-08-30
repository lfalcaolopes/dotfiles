#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly REPO_ROOT
# shellcheck source=lib/common.sh
source "$REPO_ROOT/lib/common.sh"

parse_module_args "$@"

oh_my_zsh="$HOME/.oh-my-zsh"
zsh_custom=${ZSH_CUSTOM:-$oh_my_zsh/custom}

checkout() {
  local name=$1 url=$2 destination=$3

  if [[ ! -e $destination ]]; then
    ensure_dir "$(dirname -- "$destination")"
    run_mutating "clonar $name" git clone --quiet "$url" "$destination"
    return
  fi

  [[ -d $destination/.git ]] || die \
    "$name existe, mas não é um checkout Git: $destination"

  if [[ $DRY_RUN == true ]]; then
    log_info "dry-run: atualizar checkout limpo de $name: $(shell_join git -C "$destination" pull --ff-only --quiet)"
    return
  fi

  if [[ -n $(git -C "$destination" status --porcelain --untracked-files=normal) ]]; then
    die "$name possui alterações locais; atualização recusada: $destination"
  fi

  git -C "$destination" pull --ff-only --quiet
  log_info "$name atualizado"
}

require_command git
checkout oh-my-zsh https://github.com/ohmyzsh/ohmyzsh "$oh_my_zsh"
checkout zsh-autosuggestions \
  https://github.com/zsh-users/zsh-autosuggestions \
  "$zsh_custom/plugins/zsh-autosuggestions"
checkout zsh-syntax-highlighting \
  https://github.com/zsh-users/zsh-syntax-highlighting.git \
  "$zsh_custom/plugins/zsh-syntax-highlighting"

run_mutating "configurar nome global do Git" \
  git config --global user.name "Lucas Falcao Lopes"
run_mutating "configurar email global do Git" \
  git config --global user.email "lfalcaolopes@gmail.com"

require_command zsh
zsh_path=$(command -v zsh)
current_shell=${DOTFILES_CURRENT_SHELL:-${SHELL:-}}
if [[ $current_shell != "$zsh_path" ]]; then
  require_command chsh
  run_mutating "alterar shell padrão para $zsh_path" chsh -s "$zsh_path"
else
  log_info "shell padrão já é $zsh_path"
fi

claude_profile="$HOME/.claude-dio"
if [[ $DRY_RUN == true ]]; then
  log_info "dry-run: criar perfil Claude secundário em $claude_profile"
else
  ensure_dir "$claude_profile"
  ln -sfn -- "$HOME/.claude/CLAUDE.md" "$claude_profile/CLAUDE.md"
  tmp_settings=$(mktemp "$claude_profile/.settings.json.XXXXXX")
  trap 'rm -f -- "${tmp_settings:-}"' EXIT
  printf '%s\n' '{' '  "theme": "dark",' '  "model": "opus"' '}' > "$tmp_settings"
  chmod 0600 "$tmp_settings"
  mv -f -- "$tmp_settings" "$claude_profile/settings.json"
  trap - EXIT
fi

log_info "shell, Git e perfil Claude secundário convergidos"
