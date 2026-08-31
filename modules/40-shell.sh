#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly REPO_ROOT
# shellcheck source=lib/common.sh
source "$REPO_ROOT/lib/common.sh"

parse_module_args "$@"

oh_my_zsh="$HOME/.oh-my-zsh"
zsh_custom=${ZSH_CUSTOM:-$oh_my_zsh/custom}
oh_my_zsh_repository=${DOTFILES_OH_MY_ZSH_REPOSITORY:-https://github.com/ohmyzsh/ohmyzsh}
autosuggestions_repository=${DOTFILES_AUTOSUGGESTIONS_REPOSITORY:-https://github.com/zsh-users/zsh-autosuggestions}
syntax_highlighting_repository=${DOTFILES_SYNTAX_HIGHLIGHTING_REPOSITORY:-https://github.com/zsh-users/zsh-syntax-highlighting.git}

checkout() {
  local name=$1 url=$2 destination=$3

  if [[ ! -e $destination ]]; then
    ensure_dir "$(dirname -- "$destination")"
    run_mutating "clonar $name" git clone --quiet "$url" "$destination"
    summary_change 1 "clonar $name"
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

  # rev-parse antes e depois do pull: só conta como mudança o checkout que
  # realmente avançou de commit.
  local revision_before revision_after
  revision_before=$(git -C "$destination" rev-parse HEAD 2>/dev/null || true)
  git -C "$destination" pull --ff-only --quiet
  revision_after=$(git -C "$destination" rev-parse HEAD 2>/dev/null || true)
  if [[ $revision_before != "$revision_after" ]]; then
    summary_change 1 "atualizar $name"
  fi
  log_info "$name atualizado"
}

if ! require_provisioned_command git "o módulo 00-preflight"; then
  log_info "dry-run: os clones e o git config dependem do Git instalado"
fi
checkout oh-my-zsh "$oh_my_zsh_repository" "$oh_my_zsh"
checkout zsh-autosuggestions \
  "$autosuggestions_repository" \
  "$zsh_custom/plugins/zsh-autosuggestions"
checkout zsh-syntax-highlighting \
  "$syntax_highlighting_repository" \
  "$zsh_custom/plugins/zsh-syntax-highlighting"

git_identity() {
  local key=$1 desired=$2 current

  # --get só lê a configuração; nada é escrito.
  current=$(git config --global --get "$key" 2>/dev/null || true)
  [[ $current != "$desired" ]] || return 1
  summary_change 1 "git config $key"
  return 0
}

if [[ $DRY_RUN == true ]] && ! command_exists git; then
  summary_hold git
else
  git_identity user.name "Lucas Falcao Lopes" || true
  git_identity user.email "lfalcaolopes@gmail.com" || true
fi

run_mutating "configurar nome global do Git" \
  git config --global user.name "Lucas Falcao Lopes"
run_mutating "configurar email global do Git" \
  git config --global user.email "lfalcaolopes@gmail.com"

if require_provisioned_command zsh "o módulo 10-packages"; then
  zsh_path=$(command -v zsh)
  if [[ -n ${DOTFILES_CURRENT_SHELL:-} ]]; then
    current_shell=$DOTFILES_CURRENT_SHELL
  else
    require_command getent
    require_command id
    passwd_entry=$(getent passwd "$(id -un)") || die \
      "não foi possível consultar o shell padrão do usuário atual"
    current_shell=${passwd_entry##*:}
  fi
  if [[ $current_shell != "$zsh_path" ]]; then
    require_command chsh
    summary_change 1 "trocar shell padrão para $zsh_path"
    if [[ $DRY_RUN == false ]]; then
      summary_attention 1 "shell padrão passou a $zsh_path; vale a partir do próximo login"
    fi
    run_mutating "alterar shell padrão para $zsh_path" chsh -s "$zsh_path"
  else
    log_info "shell padrão já é $zsh_path"
  fi
else
  log_info "dry-run: shell padrão passaria a ser o zsh instalado pelo módulo 10-packages"
fi

claude_profile="$HOME/.claude-dio"

# Comparação somente leitura do perfil secundário, usada nos dois modos: no
# plano diz o que mudaria, na execução real é medida antes da escrita para o
# resumo contar o que mudou.
claude_divergences() {
  local pending=0

  [[ -d $claude_profile ]] || pending=$((pending + 1))
  [[ -L $claude_profile/CLAUDE.md && \
    $(readlink -- "$claude_profile/CLAUDE.md" 2>/dev/null || true) == "$HOME/.claude/CLAUDE.md" ]] || \
    pending=$((pending + 1))
  printf '%s\n' '{' '  "theme": "dark",' '  "model": "opus"' '}' | \
    cmp -s - "$claude_profile/settings.json" 2>/dev/null || \
    pending=$((pending + 1))

  printf '%s' "$pending"
}

claude_pending=$(claude_divergences)
(( claude_pending == 0 )) || summary_change "$claude_pending" \
  "$claude_pending ajuste(s) no perfil Claude secundário"

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
