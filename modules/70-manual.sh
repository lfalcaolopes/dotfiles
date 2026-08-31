#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly REPO_ROOT
# shellcheck source=lib/common.sh
source "$REPO_ROOT/lib/common.sh"

parse_module_args "$@"

# Este módulo nunca escreve nada: ele sonda o que o bootstrap não tem como
# automatizar (logins, chaves pessoais, instaladores interativos) e registra no
# resumo o que ainda falta. Como as sondagens são de leitura pura, o --dry-run e
# a execução real produzem exatamente a mesma lista.
#
# Um item só entra na lista quando a sondagem diz que falta. A exceção está
# marcada no próprio texto: o login do VS Code fica no keyring do sistema e não
# é legível daqui, então é lembrado sempre.
readonly NOTES_REMOTE=git@github.com:lfalcaolopes/notes.git
readonly NOTES_DIR="$HOME/notes"

pending=0

manual() {
  pending=$((pending + 1))
  summary_manual "$1" "${2:-}"
}

package_installed() {
  command_exists pacman || return 1
  pacman -Qq "$1" >/dev/null 2>&1
}

ssh_key_exists() {
  local key
  shopt -s nullglob
  local -a keys=("$HOME/.ssh"/*.pub)
  shopt -u nullglob
  for key in ${keys[@]+"${keys[@]}"}; do
    [[ -s $key ]] && return 0
  done
  return 1
}

# O cliente grava o loginusers.vdf depois do primeiro login bem-sucedido. Os
# dois caminhos existem porque a Steam migrou o diretório e mantém o antigo
# como link em instalações mais velhas.
steam_logged_in() {
  [[ -f "$HOME/.steam/steam/config/loginusers.vdf" ]] ||
    [[ -f "$HOME/.local/share/Steam/config/loginusers.vdf" ]]
}

# O gh grava hosts.yml no primeiro `gh auth login`; o arquivo tem token e por
# isso fica fora dos dotfiles. O protocolo escolhido no login também mora ali, e
# é ele que decide se `git clone`, `push` e `gh repo clone` falam SSH ou HTTPS.
readonly GH_HOSTS="${XDG_CONFIG_HOME:-$HOME/.config}/gh/hosts.yml"

gh_authenticated() {
  [[ -f "$GH_HOSTS" ]]
}

gh_uses_ssh() {
  grep -q '^[[:space:]]*git_protocol:[[:space:]]*ssh[[:space:]]*$' "$GH_HOSTS" 2>/dev/null
}

# A chave vem antes do login: com ela no lugar, o próprio `gh auth login` se
# oferece para registrá-la na conta do GitHub.
if ! ssh_key_exists; then
  manual 'gerar a chave SSH; o gh auth login registra a pública na conta' \
    'ssh-keygen -t ed25519 -C "$(hostname)"'
fi

if ! gh_authenticated; then
  manual 'autenticar o GitHub por SSH' \
    'gh auth login --git-protocol ssh --hostname github.com'
elif ! gh_uses_ssh; then
  manual 'passar o GitHub para SSH; o login atual continua valendo' \
    'gh config set -h github.com git_protocol ssh'
fi

manual 'entrar no GitHub pelo VS Code, pelo ícone de conta; fica no keyring e não é verificável daqui'

if ! steam_logged_in; then
  manual 'entrar na Steam; o login não é versionado' steam
fi

if [[ ! -d "$NOTES_DIR/.git" ]]; then
  manual 'clonar o vault do Obsidian' "git clone $NOTES_REMOTE $NOTES_DIR"
fi

if ! command_exists voxtype && ! package_installed voxtype; then
  manual 'instalar o ditado' omarchy-voxtype-install
fi

if ! package_installed 1password; then
  manual 'instalar o 1Password e a extensão do Chromium' \
    omarchy-install-service-1password
fi

log_info "$pending passo(s) manual(is) pendente(s); detalhe no fim do resumo"
