#!/usr/bin/env bash
set -Eeuo pipefail

TEST_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly TEST_ROOT
BOOTSTRAP="$TEST_ROOT/bootstrap.sh"

SANDBOX=$(mktemp -d)
readonly SANDBOX
trap 'rm -rf -- "$SANDBOX"' EXIT

TEST_HOME="$SANDBOX/home"
SHIMS="$SANDBOX/shims"
STOW_FIXTURE="$SANDBOX/stow"
OS_RELEASE="$SANDBOX/os-release"
SHIM_LOG="$SANDBOX/shim.log"
mkdir -p \
  "$TEST_HOME" \
  "$TEST_HOME/.config/alacritty" \
  "$TEST_HOME/.config/foot" \
  "$TEST_HOME/.config/ghostty" \
  "$TEST_HOME/.config/kitty" \
  "$TEST_HOME/.config/omarchy" \
  "$SHIMS" \
  "$STOW_FIXTURE/common" \
  "$STOW_FIXTURE/omarchy" \
  "$STOW_FIXTURE/host-notebook/.config/kanata" \
  "$STOW_FIXTURE/host-desktop"
: > "$SHIM_LOG"

printf '[font]\nsize = 12\n' > "$TEST_HOME/.config/alacritty/alacritty.toml"
printf '[main]\nfont=JetBrainsMono Nerd Font:size=12\n' > "$TEST_HOME/.config/foot/foot.ini"
printf 'font-size = 12\n' > "$TEST_HOME/.config/ghostty/config"
printf 'font_size 12.0\n' > "$TEST_HOME/.config/kitty/kitty.conf"
printf '{"idle":{"lock":300,"screensaver":600},"local":true}\n' > \
  "$TEST_HOME/.config/omarchy/shell.json"
printf '(defcfg process-unmapped-keys yes)\n' > \
  "$STOW_FIXTURE/host-notebook/.config/kanata/config.kbd"

# O 47-voxtype lê o modelo declarado no config versionado, e não no instalado,
# então a fixture usa o arquivo real do repositório em vez de um recorte.
mkdir -p "$STOW_FIXTURE/common/.config/voxtype"
cp -- "$TEST_ROOT/stow/common/.config/voxtype/config.toml" \
  "$STOW_FIXTURE/common/.config/voxtype/config.toml"

# O layout de teclado vem do estado do systemd, não do HOME. As fixtures abaixo
# ficam convergidas e são exportadas para todas as execuções do bootstrap, para
# o resultado dos testes não depender do teclado da máquina que os roda.
VCONSOLE_FIXTURE="$SANDBOX/vconsole.conf"
X11_KEYMAP_FIXTURE="$SANDBOX/00-keyboard.conf"
printf '%s\n' \
  'KEYMAP=us-acentos' \
  'XKBLAYOUT=us' \
  'XKBMODEL=pc105' \
  'XKBVARIANT=intl' > "$VCONSOLE_FIXTURE"
printf '%s\n' \
  'Section "InputClass"' \
  '        Identifier "system-keyboard"' \
  '        MatchIsKeyboard "on"' \
  '        Option "XkbLayout" "us"' \
  '        Option "XkbModel" "pc105"' \
  '        Option "XkbVariant" "intl"' \
  'EndSection' > "$X11_KEYMAP_FIXTURE"
DOTFILES_VCONSOLE="$VCONSOLE_FIXTURE"
DOTFILES_X11_KEYMAP="$X11_KEYMAP_FIXTURE"
export DOTFILES_VCONSOLE DOTFILES_X11_KEYMAP

printf '%s\n' \
  'NAME="Omarchy"' \
  'ID=omarchy' \
  'ID_LIKE=arch' \
  'BUILD_ID=4.0.1' > "$OS_RELEASE"

make_shim() {
  local name=$1 mode=${2:-mutable}
  local path="$SHIMS/$name"

  {
    printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail'
    if [[ $mode == mutable ]]; then
      # The generated shim expands these variables when it runs.
      # shellcheck disable=SC2016
      printf '%s\n' 'printf '\''%s %s\n'\'' "${0##*/}" "$*" >> "$SHIM_LOG"'
    fi
    printf '%s\n' 'exit 0'
  } > "$path"
  chmod +x "$path"
}

for command in sudo pacman yay git stow chsh systemctl code mise mkdir cp mv rm ln install kanata zsh localectl; do
  make_shim "$command"
done
make_shim curl readonly

# stow -n e kanata --check não escrevem no disco: os shims não os registram como
# mutação, e as variáveis abaixo permitem simular uma validação que reprova.
# The generated shim expands these variables when it runs.
# shellcheck disable=SC2016
{
  printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail'
  printf '%s\n' 'for argument in "$@"; do'
  printf '%s\n' '  case $argument in'
  printf '%s\n' '    -n|--simulate|--no) exit "${STOW_SIMULATION_STATUS:-0}" ;;'
  printf '%s\n' '  esac'
  printf '%s\n' 'done'
  # The generated shim expands these variables when it runs.
  # shellcheck disable=SC2016
  printf '%s\n' 'printf '\''%s %s\n'\'' "${0##*/}" "$*" >> "$SHIM_LOG"'
  printf '%s\n' 'exit 0'
} > "$SHIMS/stow"

# The generated shim expands these variables when it runs.
# shellcheck disable=SC2016
{
  printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail'
  printf '%s\n' 'for argument in "$@"; do'
  printf '%s\n' '  [[ $argument == --check ]] && exit "${KANATA_CHECK_STATUS:-0}"'
  printf '%s\n' 'done'
  # The generated shim expands these variables when it runs.
  # shellcheck disable=SC2016
  printf '%s\n' 'printf '\''%s %s\n'\'' "${0##*/}" "$*" >> "$SHIM_LOG"'
  printf '%s\n' 'exit 0'
} > "$SHIMS/kanata"

# Sondagens somente leitura do dry-run: consultam estado e não são mutação.
# As variáveis permitem simular uma máquina onde nada está convergido.
# The generated shim expands these variables when it runs.
# shellcheck disable=SC2016
{
  printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail'
  printf '%s\n' 'if [[ ${1:-} == config && ${2:-} == --global && ${3:-} == --get ]]; then'
  printf '%s\n' '  case ${4:-} in'
  printf '%s\n' '    user.name) printf '\''%s\n'\'' "${GIT_NAME_FIXTURE:-}" ;;'
  printf '%s\n' '    user.email) printf '\''%s\n'\'' "${GIT_EMAIL_FIXTURE:-}" ;;'
  printf '%s\n' '    url.git@github.com:.pushInsteadOf) printf '\''%s\n'\'' "${GIT_PUSH_REWRITE_FIXTURE:-}" ;;'
  printf '%s\n' '  esac'
  printf '%s\n' '  exit 0'
  printf '%s\n' 'fi'
  printf '%s\n' 'printf '\''%s %s\n'\'' "${0##*/}" "$*" >> "$SHIM_LOG"'
  printf '%s\n' 'exit 0'
} > "$SHIMS/git"

# The generated shim expands these variables when it runs.
# shellcheck disable=SC2016
{
  printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail'
  printf '%s\n' 'case ${1:-} in'
  printf '%s\n' '  -Q*) exit "${PACMAN_QUERY_STATUS:-0}" ;;'
  printf '%s\n' 'esac'
  printf '%s\n' 'printf '\''%s %s\n'\'' "${0##*/}" "$*" >> "$SHIM_LOG"'
  printf '%s\n' 'exit 0'
} > "$SHIMS/pacman"

# The generated shim expands these variables when it runs.
# shellcheck disable=SC2016
{
  printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail'
  printf '%s\n' 'for argument in "$@"; do'
  printf '%s\n' '  case $argument in'
  printf '%s\n' '    is-enabled|is-active) exit "${SYSTEMCTL_STATE_STATUS:-0}" ;;'
  printf '%s\n' '    show) printf '\''%s\n'\'' "${SYSTEMCTL_TIMESTAMP_FIXTURE:-}"; exit 0 ;;'
  printf '%s\n' '  esac'
  printf '%s\n' 'done'
  printf '%s\n' 'printf '\''%s %s\n'\'' "${0##*/}" "$*" >> "$SHIM_LOG"'
  printf '%s\n' 'exit 0'
} > "$SHIMS/systemctl"

# The generated shim expands these variables when it runs.
# shellcheck disable=SC2016
{
  printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail'
  printf '%s\n' 'case ${1:-} in'
  printf '%s\n' '  --list-extensions) cat "${VSCODE_INSTALLED_FIXTURE:-/dev/null}"; exit 0 ;;'
  printf '%s\n' 'esac'
  printf '%s\n' 'printf '\''%s %s\n'\'' "${0##*/}" "$*" >> "$SHIM_LOG"'
  printf '%s\n' 'exit 0'
} > "$SHIMS/code"

# The generated shim expands these variables when it runs.
# shellcheck disable=SC2016
{
  printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail'
  printf '%s\n' 'case ${1:-} in'
  printf '%s\n' '  ls) printf '\''%s\n'\'' "${MISE_STATE_FIXTURE:-null}"; exit 0 ;;'
  printf '%s\n' 'esac'
  printf '%s\n' 'printf '\''%s %s\n'\'' "${0##*/}" "$*" >> "$SHIM_LOG"'
  printf '%s\n' 'exit 0'
} > "$SHIMS/mise"

# Sem argumento o comando do Omarchy só traduz o mimeapps.list para o nome
# curto: leitura pura, que o dry-run pode chamar sem contar como mutação. Com
# argumento ele grava o padrão e por isso é registrado.
# The generated shim expands these variables when it runs.
# shellcheck disable=SC2016
{
  printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail'
  printf '%s\n' 'if (($# == 0)); then'
  printf '%s\n' '  printf '\''%s\n'\'' "${OMARCHY_BROWSER_FIXTURE:-brave}"'
  printf '%s\n' '  exit 0'
  printf '%s\n' 'fi'
  printf '%s\n' 'printf '\''%s %s\n'\'' "${0##*/}" "$*" >> "$SHIM_LOG"'
  printf '%s\n' 'exit 0'
} > "$SHIMS/omarchy-default-browser"

make_shim omarchy-install-browser

# O terminal padrão vem do xdg-terminals.list; sem argumento o comando do
# Omarchy só o traduz para o nome curto, então o dry-run pode chamá-lo.
# The generated shim expands these variables when it runs.
# shellcheck disable=SC2016
{
  printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail'
  printf '%s\n' 'if (($# == 0)); then'
  printf '%s\n' '  printf '\''%s\n'\'' "${OMARCHY_TERMINAL_FIXTURE:-ghostty}"'
  printf '%s\n' '  exit 0'
  printf '%s\n' 'fi'
  printf '%s\n' 'printf '\''%s %s\n'\'' "${0##*/}" "$*" >> "$SHIM_LOG"'
  printf '%s\n' 'exit 0'
} > "$SHIMS/omarchy-default-terminal"

make_shim omarchy-install-terminal

# `voxtype setup gpu` sem flag e `omarchy-hw-vulkan` apenas consultam estado: o
# primeiro imprime o backend ativo, o segundo procura um ICD em /usr/share. Ligar
# a GPU é `setup gpu --enable`, com sudo, e esse cai no registro de mutação.
# The generated shim expands these variables when it runs.
# shellcheck disable=SC2016
{
  printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail'
  printf '%s\n' 'if [[ ${1:-} == setup && ${2:-} == gpu && $# -eq 2 ]]; then'
  printf '%s\n' '  printf '\''Active backend: %s\n'\'' "${VOXTYPE_BACKEND_FIXTURE:-GPU (Vulkan)}"'
  printf '%s\n' '  exit 0'
  printf '%s\n' 'fi'
  printf '%s\n' 'printf '\''%s %s\n'\'' "${0##*/}" "$*" >> "$SHIM_LOG"'
  printf '%s\n' 'if [[ ${1:-} == setup && ${2:-} == --download ]]; then'
  printf '%s\n' '  /usr/bin/mkdir -p "$HOME/.local/share/voxtype/models"'
  printf '%s\n' '  : > "$HOME/.local/share/voxtype/models/ggml-${4:-}.bin"'
  printf '%s\n' 'fi'
  printf '%s\n' 'if [[ ${1:-} == setup && ${2:-} == systemd ]]; then'
  printf '%s\n' '  /usr/bin/mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"'
  printf '%s\n' '  : > "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/voxtype.service"'
  printf '%s\n' 'fi'
  printf '%s\n' 'exit 0'
} > "$SHIMS/voxtype"

{
  printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail'
  # The generated shim expands this variable when it runs.
  # shellcheck disable=SC2016
  printf '%s\n' 'exit "${OMARCHY_VULKAN_STATUS:-0}"'
} > "$SHIMS/omarchy-hw-vulkan"

chmod +x "$SHIMS/stow" "$SHIMS/kanata" "$SHIMS/pacman" "$SHIMS/systemctl" \
  "$SHIMS/code" "$SHIMS/mise" "$SHIMS/git" "$SHIMS/omarchy-default-browser" \
  "$SHIMS/omarchy-default-terminal" "$SHIMS/voxtype" "$SHIMS/omarchy-hw-vulkan"

export SHIM_LOG
TEST_PATH="$SHIMS:/usr/bin:/bin"
OUTPUT=
STATUS=0
TESTS_RUN=0

run_bootstrap() {
  set +e
  OUTPUT=$(env \
    HOME="$TEST_HOME" \
    XDG_CONFIG_HOME="$TEST_HOME/.config" \
    XDG_DATA_HOME="$TEST_HOME/.local/share" \
    PATH="$TEST_PATH" \
    DOTFILES_STOW_DIR="$STOW_FIXTURE" \
    DOTFILES_OS_RELEASE="$OS_RELEASE" \
    "$BOOTSTRAP" "$@" 2>&1)
  STATUS=$?
  set -e
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  printf '%s\n' "$OUTPUT" >&2
  exit 1
}

pass() {
  TESTS_RUN=$((TESTS_RUN + 1))
  printf 'ok %d - %s\n' "$TESTS_RUN" "$1"
}

assert_success() {
  (( STATUS == 0 )) || fail "$1 (status $STATUS)"
}

assert_failure() {
  (( STATUS != 0 )) || fail "$1 (sucesso inesperado)"
}

assert_contains() {
  /usr/bin/grep -Fq -- "$2" <<< "$1" || fail "$3 (texto ausente: $2)"
}

assert_not_contains() {
  if /usr/bin/grep -Fq -- "$2" <<< "$1"; then
    fail "$3 (texto inesperado: $2)"
  fi
}

assert_no_mutation() {
  [[ ! -s $SHIM_LOG ]] || fail "$1 (comando mutável chamado: $(<"$SHIM_LOG"))"
}

reset_log() {
  : > "$SHIM_LOG"
}

reset_log
run_bootstrap
assert_failure "host obrigatório"
assert_contains "$OUTPUT" 'Hosts encontrados: desktop,notebook' "host obrigatório"
assert_no_mutation "host obrigatório"
pass "sem host falha e lista os hosts antes de mutar"

reset_log
run_bootstrap servidor --dry-run
assert_failure "host inválido"
assert_contains "$OUTPUT" 'host desconhecido: servidor' "host inválido"
assert_no_mutation "host inválido"
pass "host inválido falha antes de mutar"

for invalid_module in 10-packages.sh inexistente; do
  reset_log
  run_bootstrap notebook --only "$invalid_module" --dry-run
  assert_failure "módulo inválido $invalid_module"
  assert_contains "$OUTPUT" "módulo desconhecido: $invalid_module" "módulo inválido $invalid_module"
  assert_no_mutation "módulo inválido $invalid_module"
done
pass "--only rejeita extensão .sh e módulo inexistente"

all_modules=(
  00-preflight
  05-locale
  10-packages
  15-browser
  17-terminal
  20-stow-common
  30-stow-omarchy
  35-stow-host
  40-shell
  45-kanata
  50-editors
  55-tweaks
  60-mise
  70-manual
)
for selected_module in "${all_modules[@]}"; do
  reset_log
  run_bootstrap notebook --only "$selected_module" --dry-run
  assert_success "seleção --only $selected_module"
  assert_contains "$OUTPUT" "executando módulo: $selected_module" "seleção --only $selected_module"
  for other_module in "${all_modules[@]}"; do
    [[ $other_module == "$selected_module" ]] && continue
    assert_not_contains "$OUTPUT" "executando módulo: $other_module" "seleção --only $selected_module"
  done
  assert_no_mutation "seleção --only $selected_module"
done
pass "cada valor aceito por --only executa isoladamente"

reset_log
home_before=$(find "$TEST_HOME" -mindepth 1 -print | sort)
run_bootstrap notebook --dry-run
home_after=$(find "$TEST_HOME" -mindepth 1 -print | sort)
assert_success "dry-run completo"
[[ $OUTPUT == \
  *'executando módulo: 00-preflight'*\
'executando módulo: 05-locale'*\
'executando módulo: 10-packages'*\
'executando módulo: 15-browser'*\
'executando módulo: 17-terminal'*\
'executando módulo: 20-stow-common'*\
'executando módulo: 30-stow-omarchy'*\
'executando módulo: 35-stow-host'*\
'executando módulo: 40-shell'*\
'executando módulo: 45-kanata'*\
'executando módulo: 50-editors'*\
'executando módulo: 55-tweaks'*\
'executando módulo: 60-mise'*\
'executando módulo: 70-manual'* ]] || \
  fail "ordem do dry-run"
[[ $home_before == "$home_after" ]] || fail "dry-run alterou HOME temporário"
assert_no_mutation "dry-run completo"
pass "dry-run percorre os módulos em ordem sem escrita nem comando mutável"

reset_log
set +e
OUTPUT=$(cd /tmp && env \
  HOME="$TEST_HOME" \
  XDG_CONFIG_HOME="$TEST_HOME/.config" \
  XDG_DATA_HOME="$TEST_HOME/.local/share" \
  PATH="$TEST_PATH" \
  DOTFILES_STOW_DIR="$STOW_FIXTURE" \
  DOTFILES_OS_RELEASE="$OS_RELEASE" \
  "$BOOTSTRAP" desktop --dry-run 2>&1)
STATUS=$?
set -e
assert_success "execução fora da raiz"
assert_contains "$OUTPUT" 'lista opcional ausente' "lista desktop ausente"
assert_no_mutation "execução fora da raiz"
pass "execução independe do diretório atual e aceita lista desktop ausente"

reset_log
run_bootstrap desktop --only 10-packages
assert_success "separação de pacotes"
shim_calls=$(<"$SHIM_LOG")
assert_contains "$shim_calls" 'sudo pacman -S --needed --noconfirm visual-studio-code-bin dbeaver steam zsh python-pipx' \
  "pacotes oficiais"
assert_contains "$shim_calls" 'yay -S --needed --noconfirm postman-bin' \
  "pacotes AUR"
run_bootstrap desktop --only 10-packages
assert_success "reexecução de pacotes"
assert_contains "$OUTPUT" 'pacotes convergidos para o host desktop' "reexecução de pacotes"

reset_log
run_bootstrap notebook --only 10-packages
assert_success "separação de pacotes do notebook"
shim_calls=$(<"$SHIM_LOG")
assert_contains "$shim_calls" 'yay -S --needed --noconfirm postman-bin kanata-bin' \
  "kanata-bin é AUR"
[[ $(/usr/bin/grep -c '^sudo pacman -S .*kanata-bin' "$SHIM_LOG") -eq 0 ]] || \
  fail "kanata-bin foi roteado para o pacman"
pass "pacotes oficiais e AUR usam comandos separados e convergem na reexecução"

CONTROLLED_MODULES="$SANDBOX/modules"
TRACE="$SANDBOX/module.trace"
mkdir -p "$CONTROLLED_MODULES"
for specification in '00-first:0' '10-failure:7' '20-late:0'; do
  module_name=${specification%%:*}
  module_status=${specification##*:}
  {
    printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail'
    # The generated module expands this variable when it runs.
    # shellcheck disable=SC2016
    printf 'printf '\''%%s\\n'\'' %q >> "$MODULE_TRACE"\n' "$module_name"
    printf 'exit %s\n' "$module_status"
  } > "$CONTROLLED_MODULES/$module_name.sh"
  chmod +x "$CONTROLLED_MODULES/$module_name.sh"
done

export MODULE_TRACE="$TRACE"
set +e
OUTPUT=$(env \
  HOME="$TEST_HOME" \
  PATH="$TEST_PATH" \
  DOTFILES_STOW_DIR="$STOW_FIXTURE" \
  DOTFILES_MODULES_DIR="$CONTROLLED_MODULES" \
  "$BOOTSTRAP" notebook 2>&1)
STATUS=$?
set -e
(( STATUS == 7 )) || fail "propagação de status (esperado 7, recebido $STATUS)"
assert_contains "$OUTPUT" 'módulo falhou: 10-failure (status 7)' "identificação de falha"
[[ $(<"$TRACE") == $'00-first\n10-failure' ]] || fail "interrupção após falha de módulo"
pass "falhas preservam status, identificam o módulo e interrompem a ordem"

set +e
OUTPUT=$(env \
  HOME="$TEST_HOME" \
  PATH="$TEST_PATH" \
  DOTFILES_STOW_DIR="$STOW_FIXTURE" \
  DOTFILES_PACKAGES_DIR="$TEST_ROOT/packages" \
  "$TEST_ROOT/modules/10-packages.sh" servidor --dry-run 2>&1)
STATUS=$?
set -e
assert_failure "validação isolada do módulo"
assert_contains "$OUTPUT" 'host inválido para o módulo: servidor' "validação isolada do módulo"
pass "módulo executado isoladamente valida seus argumentos"

REAL_STOW_HOME="$SANDBOX/real-stow-home"
REAL_STOW_STATE="$SANDBOX/real-stow-state"
mkdir -p "$REAL_STOW_HOME"

run_real_stow_module() {
  local module=$1 host=$2
  shift 2
  set +e
  OUTPUT=$(env \
    HOME="$REAL_STOW_HOME" \
    XDG_STATE_HOME="$REAL_STOW_STATE" \
    PATH="/usr/bin:/bin" \
    DOTFILES_STOW_DIR="$TEST_ROOT/stow" \
    DOTFILES_STOW_TARGET="$REAL_STOW_HOME" \
    "$TEST_ROOT/modules/$module.sh" "$host" "$@" 2>&1)
  STATUS=$?
  set -e
}

run_real_stow_module 20-stow-common notebook
assert_success "Stow common em HOME limpo"
run_real_stow_module 30-stow-omarchy notebook
assert_success "Stow omarchy em HOME limpo"
run_real_stow_module 35-stow-host notebook
assert_success "Stow host em HOME limpo"
[[ -L $REAL_STOW_HOME/.zshrc ]] || fail "common não criou link esperado"
[[ -L $REAL_STOW_HOME/.config/hypr/host.lua ]] || fail "host não criou link esperado"
[[ $(readlink -f "$REAL_STOW_HOME/.config/hypr/host.lua") == \
  "$TEST_ROOT/stow/host-notebook/.config/hypr/host.lua" ]] || fail "host incorreto aplicado"
[[ ! -d $REAL_STOW_STATE/dotfiles/backups ]] || fail "HOME limpo criou backup"
run_real_stow_module 20-stow-common notebook
assert_success "reexecução Stow common"
run_real_stow_module 30-stow-omarchy notebook
assert_success "reexecução Stow omarchy"
run_real_stow_module 35-stow-host notebook
assert_success "reexecução Stow host"
[[ ! -d $REAL_STOW_STATE/dotfiles/backups ]] || fail "reexecução criou backup"
pass "Stow aplica common, omarchy e exatamente o host notebook em HOME limpo"

CONFLICT_HOME="$SANDBOX/conflict-home"
CONFLICT_STATE="$SANDBOX/conflict-state"
mkdir -p "$CONFLICT_HOME/.config/git" "$CONFLICT_HOME/.config/Code/User"
printf 'local zsh\n' > "$CONFLICT_HOME/.zshrc"
ln -s "$SANDBOX/wrong-ignore" "$CONFLICT_HOME/.config/git/ignore"
ln -s "$TEST_ROOT/stow/common/.config/Code/User/keybindings.json" \
  "$CONFLICT_HOME/.config/Code/User/keybindings.json"

set +e
OUTPUT=$(env \
  HOME="$CONFLICT_HOME" \
  XDG_STATE_HOME="$CONFLICT_STATE" \
  PATH="/usr/bin:/bin" \
  DOTFILES_STOW_DIR="$TEST_ROOT/stow" \
  DOTFILES_STOW_TARGET="$CONFLICT_HOME" \
  "$TEST_ROOT/modules/20-stow-common.sh" notebook 2>&1)
STATUS=$?
set -e
assert_success "migração de conflitos"
backup_dir=$(find "$CONFLICT_STATE/dotfiles/backups" -mindepth 1 -maxdepth 1 -type d)
[[ -f $backup_dir/.zshrc ]] || fail "arquivo regular não foi protegido"
[[ -L $backup_dir/.config/git/ignore ]] || fail "symlink incorreto não foi protegido"
[[ ! -e $backup_dir/.config/Code/User/keybindings.json ]] || fail "link correto foi tratado como conflito"
[[ -L $CONFLICT_HOME/.zshrc && -L $CONFLICT_HOME/.config/git/ignore ]] || \
  fail "conflitos não foram substituídos pelos links gerenciados"
pass "Stow protege arquivo regular e symlink incorreto, preservando link correto"

BLOCKED_HOME="$SANDBOX/blocked-home"
mkdir -p "$BLOCKED_HOME/.local/bin/hypr-close-window"
printf 'unmanaged\n' > "$BLOCKED_HOME/.local/bin/hypr-close-window/keep"
set +e
OUTPUT=$(env \
  HOME="$BLOCKED_HOME" \
  PATH="/usr/bin:/bin" \
  DOTFILES_STOW_DIR="$TEST_ROOT/stow" \
  DOTFILES_STOW_TARGET="$BLOCKED_HOME" \
  "$TEST_ROOT/modules/20-stow-common.sh" desktop 2>&1)
STATUS=$?
set -e
assert_failure "diretório não gerenciado"
assert_contains "$OUTPUT" 'conteúdo não gerenciado foi preservado' "diretório não gerenciado"
[[ -f $BLOCKED_HOME/.local/bin/hypr-close-window/keep ]] || fail "conteúdo não gerenciado foi removido"
pass "Stow aborta diante de diretório não gerenciado"

FOLDED_HOME="$SANDBOX/folded-home"
mkdir -p "$FOLDED_HOME"
printf 'local zsh\n' > "$FOLDED_HOME/.zshrc"
ln -s "$TEST_ROOT/stow/common/.local" "$FOLDED_HOME/.local"
source_hash_before=$(sha256sum "$TEST_ROOT/stow/common/.local/bin/hypr-close-window")
set +e
OUTPUT=$(env \
  HOME="$FOLDED_HOME" \
  XDG_STATE_HOME="$FOLDED_HOME/.local/state" \
  PATH="/usr/bin:/bin" \
  DOTFILES_STOW_DIR="$TEST_ROOT/stow" \
  DOTFILES_STOW_TARGET="$FOLDED_HOME" \
  "$TEST_ROOT/modules/20-stow-common.sh" notebook 2>&1)
STATUS=$?
set -e
assert_failure "backup dentro da fonte Stow"
assert_contains "$OUTPUT" 'backup resolve para dentro da fonte Stow' "backup dentro da fonte Stow"
[[ $source_hash_before == "$(sha256sum "$TEST_ROOT/stow/common/.local/bin/hypr-close-window")" ]] || \
  fail "fonte Stow foi alterada via symlink de diretório"
pass "Stow recusa backup que resolveria para dentro da fonte versionada"

DRY_STOW_HOME="$SANDBOX/dry-stow-home"
mkdir -p "$DRY_STOW_HOME"
printf 'local zsh\n' > "$DRY_STOW_HOME/.zshrc"
before=$(find "$DRY_STOW_HOME" -printf '%P %y %l\n' | sort)
set +e
OUTPUT=$(env \
  HOME="$DRY_STOW_HOME" \
  PATH="/usr/bin:/bin" \
  DOTFILES_STOW_DIR="$TEST_ROOT/stow" \
  DOTFILES_STOW_TARGET="$DRY_STOW_HOME" \
  "$TEST_ROOT/modules/20-stow-common.sh" notebook --dry-run 2>&1)
STATUS=$?
set -e
assert_success "dry-run Stow"
after=$(find "$DRY_STOW_HOME" -printf '%P %y %l\n' | sort)
[[ $before == "$after" ]] || fail "dry-run Stow alterou o destino"
[[ ! -e $DRY_STOW_HOME/.local/state ]] || fail "dry-run Stow criou estado"
assert_contains "$OUTPUT" 'proteger conflito' "dry-run Stow lista conflito"
assert_contains "$OUTPUT" 'aplicar Stow' "dry-run Stow lista comando"
pass "dry-run Stow relata conflitos e não altera o HOME temporário"

CLEAN_STOW_HOME="$SANDBOX/clean-stow-home"
mkdir -p "$CLEAN_STOW_HOME"
set +e
OUTPUT=$(env \
  HOME="$CLEAN_STOW_HOME" \
  PATH="/usr/bin:/bin" \
  DOTFILES_STOW_DIR="$TEST_ROOT/stow" \
  DOTFILES_STOW_TARGET="$CLEAN_STOW_HOME" \
  "$TEST_ROOT/modules/20-stow-common.sh" notebook --dry-run 2>&1)
STATUS=$?
set -e
assert_success "simulação do Stow em destino limpo"
assert_contains "$OUTPUT" 'dry-run: stow: ' "simulação do Stow em destino limpo"
[[ -z $(find "$CLEAN_STOW_HOME" -mindepth 1 -print) ]] || \
  fail "simulação do Stow escreveu no destino"
pass "dry-run simula o Stow em destino limpo sem escrever nada"

reset_log
STOW_SIMULATION_STATUS=1
export STOW_SIMULATION_STATUS
run_bootstrap notebook --only 20-stow-common --dry-run
unset STOW_SIMULATION_STATUS
assert_failure "simulação do Stow reprovada"
assert_contains "$OUTPUT" 'simulação do Stow falhou para common' "simulação do Stow reprovada"
assert_no_mutation "simulação do Stow reprovada"
pass "dry-run aborta quando a simulação do Stow reprova"

reset_log
KANATA_CHECK_STATUS=1
export KANATA_CHECK_STATUS
run_bootstrap notebook --only 45-kanata --dry-run
unset KANATA_CHECK_STATUS
assert_failure "config Kanata inválida"
assert_contains "$OUTPUT" 'config do Kanata é inválida' "config Kanata inválida"
assert_no_mutation "config Kanata inválida"
pass "dry-run aborta quando a config do Kanata não passa no --check"

SHELL_HOME="$SANDBOX/shell-home"
SHELL_SHIMS="$SANDBOX/shell-shims"
mkdir -p "$SHELL_HOME/.config" "$SHELL_SHIMS"
for command in zsh chsh; do
  make_shim_path="$SHELL_SHIMS/$command"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$make_shim_path"
  chmod +x "$make_shim_path"
done

make_git_source() {
  local directory=$1
  mkdir -p "$directory"
  git -C "$directory" init -q
  printf 'fixture\n' > "$directory/README"
  git -C "$directory" add README
  git -C "$directory" -c user.name=Fixture -c user.email=fixture@example.test \
    commit -qm initial
}

OH_MY_ZSH_SOURCE="$SANDBOX/source-oh-my-zsh"
AUTOSUGGESTIONS_SOURCE="$SANDBOX/source-autosuggestions"
SYNTAX_SOURCE="$SANDBOX/source-syntax"
make_git_source "$OH_MY_ZSH_SOURCE"
make_git_source "$AUTOSUGGESTIONS_SOURCE"
make_git_source "$SYNTAX_SOURCE"
printf 'custom/plugins/zsh-*\n' > "$OH_MY_ZSH_SOURCE/.gitignore"
git -C "$OH_MY_ZSH_SOURCE" add .gitignore
git -C "$OH_MY_ZSH_SOURCE" -c user.name=Fixture -c user.email=fixture@example.test \
  commit -qm 'ignore external plugins'

run_shell_module() {
  set +e
  OUTPUT=$(env \
    HOME="$SHELL_HOME" \
    XDG_CONFIG_HOME="$SHELL_HOME/.config" \
    XDG_DATA_HOME="$SHELL_HOME/.local/share" \
    PATH="$SHELL_SHIMS:/usr/bin:/bin" \
    DOTFILES_STOW_DIR="$TEST_ROOT/stow" \
    DOTFILES_CURRENT_SHELL="$SHELL_SHIMS/zsh" \
    DOTFILES_OH_MY_ZSH_REPOSITORY="$OH_MY_ZSH_SOURCE" \
    DOTFILES_AUTOSUGGESTIONS_REPOSITORY="$AUTOSUGGESTIONS_SOURCE" \
    DOTFILES_SYNTAX_HIGHLIGHTING_REPOSITORY="$SYNTAX_SOURCE" \
    "$TEST_ROOT/modules/40-shell.sh" notebook "$@" 2>&1)
  STATUS=$?
  set -e
}

run_shell_module
assert_success "checkouts Git ausentes"
[[ -d $SHELL_HOME/.oh-my-zsh/.git ]] || fail "oh-my-zsh ausente não foi clonado"
[[ -d $SHELL_HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions/.git ]] || \
  fail "plugin ausente não foi clonado"
[[ $(git -C "$SHELL_HOME/.oh-my-zsh" status --porcelain) == '' ]] || \
  fail "checkout recém-clonado não está limpo"
run_shell_module
assert_success "checkouts Git limpos"
printf 'local change\n' >> "$SHELL_HOME/.oh-my-zsh/README"
run_shell_module
assert_failure "checkout Git sujo"
assert_contains "$OUTPUT" 'possui alterações locais; atualização recusada' "checkout Git sujo"
/usr/bin/grep -Fq 'local change' "$SHELL_HOME/.oh-my-zsh/README" || \
  fail "alteração local do checkout sujo foi perdida"
pass "shell clona ausentes, atualiza limpos e protege checkouts Git sujos"

KANATA_HOME="$SANDBOX/kanata-home"
KANATA_SHIMS="$SANDBOX/kanata-shims"
KANATA_STATE="$SANDBOX/kanata-state"
KANATA_LOG="$SANDBOX/kanata.log"
mkdir -p "$KANATA_HOME/.config/kanata" "$KANATA_SHIMS" "$KANATA_STATE"
cp "$TEST_ROOT/stow/host-notebook/.config/kanata/config.kbd" \
  "$KANATA_HOME/.config/kanata/config.kbd"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$KANATA_SHIMS/kanata"
chmod +x "$KANATA_SHIMS/kanata"
{
  printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail'
  # The generated shim expands these variables when it runs.
  # shellcheck disable=SC2016
  printf '%s\n' \
    'case "$*" in' \
    '  "--user is-enabled --quiet kanata.service") [[ -e $KANATA_STATE/enabled ]] ;;' \
    '  "--user is-active --quiet kanata.service") [[ -e $KANATA_STATE/active ]] ;;' \
    '  "--user enable kanata.service") touch "$KANATA_STATE/enabled"; printf "%s\n" enable >> "$KANATA_LOG" ;;' \
    '  "--user start kanata.service") touch "$KANATA_STATE/active"; printf "%s\n" start >> "$KANATA_LOG" ;;' \
    '  "--user restart kanata.service") printf "%s\n" restart >> "$KANATA_LOG" ;;' \
    '  "--user daemon-reload") printf "%s\n" daemon-reload >> "$KANATA_LOG" ;;' \
    '  *) exit 64 ;;' \
    'esac'
} > "$KANATA_SHIMS/systemctl"
chmod +x "$KANATA_SHIMS/systemctl"
export KANATA_STATE KANATA_LOG

run_kanata_module() {
  set +e
  OUTPUT=$(env HOME="$KANATA_HOME" XDG_CONFIG_HOME="$KANATA_HOME/.config" \
    PATH="$KANATA_SHIMS:/usr/bin:/bin" \
    "$TEST_ROOT/modules/45-kanata.sh" "$@" 2>&1)
  STATUS=$?
  set -e
}

: > "$KANATA_LOG"
run_kanata_module notebook
assert_success "primeira cópia da unit Kanata"
unit_path="$KANATA_HOME/.config/systemd/user/kanata.service"
[[ -f $unit_path && ! -L $unit_path ]] || fail "unit Kanata não foi copiada como arquivo"
unit_hash=$(sha256sum "$unit_path")
run_kanata_module notebook
assert_success "segunda cópia da unit Kanata"
[[ $unit_hash == "$(sha256sum "$unit_path")" ]] || fail "unit Kanata mudou na segunda execução"
[[ $(<"$KANATA_LOG") == $'daemon-reload\nenable\nstart' ]] || \
  fail "ações Kanata não convergiram: $(<"$KANATA_LOG")"
calls_before=$(<"$KANATA_LOG")
run_kanata_module desktop
assert_success "Kanata no desktop"
[[ $calls_before == "$(<"$KANATA_LOG")" ]] || fail "desktop invocou systemctl para Kanata"
pass "Kanata copia a unit uma vez, converge e não atua no desktop"

VSCODE_HOME="$SANDBOX/vscode-home"
VSCODE_SHIMS="$SANDBOX/vscode-shims"
VSCODE_INSTALLED="$SANDBOX/vscode-installed"
VSCODE_LOG="$SANDBOX/vscode.log"
mkdir -p "$VSCODE_HOME/.config/Code/User" "$VSCODE_SHIMS"
printf '%s\n' \
  '{' \
  '  // preferência local preservada' \
  '  "workbench.colorTheme": "Local Theme",' \
  '  "local.setting": "keep",' \
  '  "editor.fontSize": 99,' \
  '}' > "$VSCODE_HOME/.config/Code/User/settings.json"
printf 'ms-python.python\n' > "$VSCODE_INSTALLED"
: > "$VSCODE_LOG"
{
  printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail'
  # The generated shim expands these variables when it runs.
  # shellcheck disable=SC2016
  printf '%s\n' \
    'case ${1:-} in' \
    '  --list-extensions) cat "$VSCODE_INSTALLED" ;;' \
    '  --install-extension) printf "%s\n" "$2" >> "$VSCODE_INSTALLED"; printf "%s\n" "$2" >> "$VSCODE_LOG" ;;' \
    '  *) exit 64 ;;' \
    'esac'
} > "$VSCODE_SHIMS/code"
chmod +x "$VSCODE_SHIMS/code"
export VSCODE_INSTALLED VSCODE_LOG

run_editors_module() {
  set +e
  OUTPUT=$(env HOME="$VSCODE_HOME" XDG_CONFIG_HOME="$VSCODE_HOME/.config" \
    PATH="$VSCODE_SHIMS:/usr/bin:/bin" \
    "$TEST_ROOT/modules/50-editors.sh" notebook "$@" 2>&1)
  STATUS=$?
  set -e
}

run_editors_module
assert_success "merge VS Code"
settings_path="$VSCODE_HOME/.config/Code/User/settings.json"
settings_get() {
  python3 "$TEST_ROOT/lib/jsonc_to_json.py" < "$settings_path" | jq -r "$1"
}
[[ $(settings_get '."workbench.colorTheme"') == 'Local Theme' ]] || \
  fail "merge removeu workbench.colorTheme local"
[[ $(settings_get '."local.setting"') == keep ]] || \
  fail "merge removeu chave local"
[[ $(settings_get '."workbench.iconTheme"') == material-icon-theme ]] || \
  fail "merge não aplicou chave gerenciada"
[[ $(settings_get '."editor.fontSize"') == 13 ]] || \
  fail "repositório não prevaleceu sobre chave gerenciada divergente"
assert_contains "$OUTPUT" 'chave gerenciada divergente' "aviso de divergência"
/usr/bin/grep -q '^[[:space:]]*//[[:space:]]*dotfiles:local[[:space:]]*$' "$settings_path" || \
  fail "sentinela ausente no settings gerado"
/usr/bin/grep -q '=== EDITOR: Aparência e comportamento ===' "$settings_path" || \
  fail "comentários do bloco gerenciado foram perdidos"
[[ $(/usr/bin/grep -c '"local.setting"' "$settings_path") == 1 ]] || \
  fail "chave local duplicada ou ausente"
sentinel_line=$(/usr/bin/grep -n 'dotfiles:local' "$settings_path" | cut -d: -f1)
local_line=$(/usr/bin/grep -n '"local.setting"' "$settings_path" | cut -d: -f1)
(( local_line > sentinel_line )) || fail "chave local não ficou abaixo da sentinela"
settings_hash=$(sha256sum "$settings_path")
extension_calls=$(wc -l < "$VSCODE_LOG")
run_editors_module
assert_success "segundo merge VS Code"
[[ $settings_hash == "$(sha256sum "$settings_path")" ]] || \
  fail "merge VS Code não foi byte a byte estável"
[[ $extension_calls == "$(wc -l < "$VSCODE_LOG")" ]] || \
  fail "extensões VS Code foram reinstaladas"

MANAGED_TRIMMED="$SANDBOX/vscode-managed-trimmed.json"
/usr/bin/grep -v '"workbench.iconTheme"' "$TEST_ROOT/config/vscode/settings.json" \
  > "$MANAGED_TRIMMED"
set +e
OUTPUT=$(env HOME="$VSCODE_HOME" XDG_CONFIG_HOME="$VSCODE_HOME/.config" \
  PATH="$VSCODE_SHIMS:/usr/bin:/bin" \
  DOTFILES_VSCODE_MANAGED="$MANAGED_TRIMMED" \
  "$TEST_ROOT/modules/50-editors.sh" notebook 2>&1)
STATUS=$?
set -e
assert_success "remoção de chave gerenciada"
[[ $(settings_get '."workbench.iconTheme" // "ausente"') == ausente ]] || \
  fail "chave removida do repositório sobreviveu no destino"
[[ $(settings_get '."local.setting"') == keep ]] || \
  fail "remoção no repositório derrubou chave local"
run_editors_module
assert_success "merge VS Code restaurado"

symlink_target="$SANDBOX/vscode-symlink-target.json"
printf '{"safe":true}\n' > "$symlink_target"
ln -s "$symlink_target" "$VSCODE_HOME/.config/Code/User/settings-link.json"
target_hash=$(sha256sum "$symlink_target")
set +e
OUTPUT=$(env \
  HOME="$VSCODE_HOME" \
  XDG_CONFIG_HOME="$VSCODE_HOME/.config" \
  XDG_DATA_HOME="$VSCODE_HOME/.local/share" \
  PATH="$VSCODE_SHIMS:/usr/bin:/bin" \
  DOTFILES_VSCODE_SETTINGS="$VSCODE_HOME/.config/Code/User/settings-link.json" \
  "$TEST_ROOT/modules/50-editors.sh" notebook 2>&1)
STATUS=$?
set -e
assert_failure "symlink de settings VS Code"
assert_contains "$OUTPUT" 'é symlink; merge recusado' "symlink de settings VS Code"
[[ $target_hash == "$(sha256sum "$symlink_target")" ]] || \
  fail "alvo do symlink VS Code foi alterado"
pass "merge VS Code preserva bloco local, propaga remoções, converge e recusa symlink"

TWEAK_HOME="$SANDBOX/tweak-home"
mkdir -p "$TWEAK_HOME/.config"
cp -a \
  "$TEST_HOME/.config/alacritty" \
  "$TEST_HOME/.config/foot" \
  "$TEST_HOME/.config/ghostty" \
  "$TEST_HOME/.config/kitty" \
  "$TEST_HOME/.config/omarchy" \
  "$TWEAK_HOME/.config/"
HOME="$TWEAK_HOME" XDG_CONFIG_HOME="$TWEAK_HOME/.config" \
  "$TEST_ROOT/modules/55-tweaks.sh" notebook >/dev/null
tweak_hashes=$(find "$TWEAK_HOME/.config" -type f -exec sha256sum {} + | sort)
HOME="$TWEAK_HOME" XDG_CONFIG_HOME="$TWEAK_HOME/.config" \
  "$TEST_ROOT/modules/55-tweaks.sh" notebook >/dev/null
[[ $tweak_hashes == "$(find "$TWEAK_HOME/.config" -type f -exec sha256sum {} + | sort)" ]] || \
  fail "tweaks mudaram bytes na segunda execução"
[[ $(jq -r '.idle.lock' "$TWEAK_HOME/.config/omarchy/shell.json") == 3600 ]] || \
  fail "idle.lock incorreto"
[[ $(jq -r '.idle.screensaver' "$TWEAK_HOME/.config/omarchy/shell.json") == 86400 ]] || \
  fail "idle.screensaver incorreto"
pass "tweaks dos quatro terminais e idle são byte a byte idempotentes"

reset_log
set +e
OUTPUT=$(env \
  HOME="$TEST_HOME" \
  XDG_CONFIG_HOME="$TEST_HOME/.config" \
  XDG_DATA_HOME="$TEST_HOME/.local/share" \
  PATH="$TEST_PATH" \
  DOTFILES_STOW_DIR="$STOW_FIXTURE" \
  "$TEST_ROOT/modules/60-mise.sh" desktop 2>&1)
STATUS=$?
set -e
assert_success "linhas mise"
[[ $(<"$SHIM_LOG") == $'mise use -g node@24\nmise use -g pnpm@12\nmise use -g dotnet@10' ]] || \
  fail "comandos mise incorretos: $(<"$SHIM_LOG")"
pass "mise fixa exatamente Node 24, pnpm 12 e .NET SDK 10"

# Teclado: numa máquina instalada com `us` puro o módulo precisa planejar os
# dois comandos, aplicá-los e reconhecer o estado já convergido depois.
LOCALE_SHIMS="$SANDBOX/locale-shims"
LOCALE_VCONSOLE="$SANDBOX/locale-vconsole.conf"
LOCALE_X11="$SANDBOX/locale-00-keyboard.conf"
LOCALE_LOG="$SANDBOX/locale.log"
mkdir -p "$LOCALE_SHIMS"
: > "$LOCALE_LOG"

printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail' 'exec "$@"' > "$LOCALE_SHIMS/sudo"

# O shim registra a chamada e escreve o que o systemd-localed escreveria, para o
# teste cobrir também a reverificação que o módulo faz depois de aplicar.
{
  printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail'
  # The generated shim expands these variables when it runs.
  # shellcheck disable=SC2016
  printf '%s\n' \
    'printf "localectl %s\n" "$*" >> "$LOCALE_LOG"' \
    'case ${1:-} in' \
    '  set-x11-keymap)' \
    '    printf "XKBLAYOUT=%s\nXKBMODEL=%s\nXKBVARIANT=%s\n" "$2" "$3" "$4" >> "$DOTFILES_VCONSOLE"' \
    '    printf "Section \"InputClass\"\n        Option \"XkbLayout\" \"%s\"\n        Option \"XkbModel\" \"%s\"\n        Option \"XkbVariant\" \"%s\"\nEndSection\n" \' \
    '      "$2" "$3" "$4" > "$DOTFILES_X11_KEYMAP"' \
    '    ;;' \
    '  set-keymap) printf "KEYMAP=%s\n" "$2" >> "$DOTFILES_VCONSOLE" ;;' \
    '  *) exit 64 ;;' \
    'esac'
} > "$LOCALE_SHIMS/localectl"
chmod +x "$LOCALE_SHIMS/sudo" "$LOCALE_SHIMS/localectl"

run_locale_module() {
  set +e
  OUTPUT=$(env \
    HOME="$TEST_HOME" \
    PATH="$LOCALE_SHIMS:/usr/bin:/bin" \
    DOTFILES_STOW_DIR="$STOW_FIXTURE" \
    DOTFILES_VCONSOLE="$LOCALE_VCONSOLE" \
    DOTFILES_X11_KEYMAP="$LOCALE_X11" \
    LOCALE_LOG="$LOCALE_LOG" \
    "$TEST_ROOT/modules/05-locale.sh" notebook "$@" 2>&1)
  STATUS=$?
  set -e
}

# Instalação com `us` puro: nem o vconsole nem o InputClass do Xorg têm variante.
printf '%s\n' 'KEYMAP=us' 'XKBLAYOUT=us' 'XKBMODEL=pc105' > "$LOCALE_VCONSOLE"
/usr/bin/rm -f -- "$LOCALE_X11"

locale_before=$(cat "$LOCALE_VCONSOLE")
run_locale_module --dry-run
assert_success "dry-run de teclado divergente"
assert_contains "$OUTPUT" 'dry-run: sudo localectl set-x11-keymap us pc105 intl' \
  "dry-run de teclado divergente"
assert_contains "$OUTPUT" 'dry-run: sudo localectl set-keymap us-acentos' \
  "dry-run de teclado divergente"
[[ $(cat "$LOCALE_VCONSOLE") == "$locale_before" ]] || fail "dry-run de teclado escreveu no vconsole"
[[ ! -e $LOCALE_X11 ]] || fail "dry-run de teclado escreveu o InputClass do Xorg"
[[ ! -s $LOCALE_LOG ]] || fail "dry-run de teclado chamou localectl"

run_locale_module
assert_success "aplicação de teclado"
assert_contains "$OUTPUT" 'teclado convergido: us(intl), console us-acentos' "aplicação de teclado"
[[ $(<"$LOCALE_LOG") == $'localectl set-x11-keymap us pc105 intl\nlocalectl set-keymap us-acentos' ]] || \
  fail "comandos de teclado incorretos: $(<"$LOCALE_LOG")"

: > "$LOCALE_LOG"
run_locale_module
assert_success "reexecução de teclado"
assert_contains "$OUTPUT" 'teclado já estava convergido' "reexecução de teclado"
[[ ! -s $LOCALE_LOG ]] || fail "reexecução de teclado chamou localectl: $(<"$LOCALE_LOG")"

run_locale_module --dry-run
assert_success "dry-run de teclado convergido"
assert_contains "$OUTPUT" 'layout X11 já é us pc105 intl' "dry-run de teclado convergido"
assert_not_contains "$OUTPUT" 'dry-run: sudo localectl' "dry-run de teclado convergido"

# vconsole certo e InputClass do Xorg ausente: o Xorg ainda cairia em `us` puro,
# então o módulo precisa reescrever os dois.
/usr/bin/rm -f -- "$LOCALE_X11"
: > "$LOCALE_LOG"
run_locale_module --dry-run
assert_success "dry-run com InputClass ausente"
assert_contains "$OUTPUT" 'dry-run: sudo localectl set-x11-keymap us pc105 intl' \
  "dry-run com InputClass ausente"
assert_not_contains "$OUTPUT" 'dry-run: sudo localectl set-keymap' "dry-run com InputClass ausente"
pass "teclado planeja, aplica e reconhece us-intl no vconsole e no InputClass do Xorg"

# Máquina recém-instalada: só o que o Omarchy já traz está no PATH e o HOME
# ainda não tem os arquivos que os módulos anteriores criariam. O dry-run deve
# planejar tudo em vez de abortar.
# A máquina de desenvolvimento já tem tudo instalado, então o PATH da máquina
# zerada é um espelho de /usr/bin sem as ferramentas que os módulos instalam.
FRESH_HOME="$SANDBOX/fresh-home"
FRESH_BIN="$SANDBOX/fresh-bin"
mkdir -p "$FRESH_HOME" "$FRESH_BIN"
for real_command in /usr/bin/*; do
  [[ -x $real_command ]] || continue
  ln -sfn -- "$real_command" "$FRESH_BIN/${real_command##*/}"
done
for absent in stow zsh mise kanata code voxtype; do
  rm -f -- "$FRESH_BIN/$absent"
done
for command in sudo pacman yay systemctl chsh curl omarchy-hw-vulkan; do
  ln -sfn -- "$SHIMS/$command" "$FRESH_BIN/$command"
done

reset_log
set +e
OUTPUT=$(env \
  HOME="$FRESH_HOME" \
  XDG_CONFIG_HOME="$FRESH_HOME/.config" \
  XDG_DATA_HOME="$FRESH_HOME/.local/share" \
  PATH="$FRESH_BIN" \
  DOTFILES_STOW_DIR="$STOW_FIXTURE" \
  DOTFILES_STOW_TARGET="$FRESH_HOME" \
  DOTFILES_OS_RELEASE="$OS_RELEASE" \
  DOTFILES_CURRENT_SHELL=/bin/bash \
  PACMAN_QUERY_STATUS=1 \
  "$BOOTSTRAP" notebook --dry-run 2>&1)
STATUS=$?
set -e
assert_success "dry-run em máquina sem stow"
for planned in \
  'dry-run: seriam instalados: stow' \
  'dry-run: stow ainda não existe' \
  'dry-run: zsh ainda não existe' \
  'dry-run: kanata ainda não existe' \
  'dry-run: mise ainda não existe' \
  'dry-run: voxtype ainda não existe' \
  'dry-run: code ainda não existe'; do
  assert_contains "$OUTPUT" "$planned" "dry-run em máquina sem stow"
done
assert_contains "$OUTPUT" 'bootstrap concluído para notebook' "dry-run em máquina sem stow"
assert_contains "$OUTPUT" 'atenção antes de aplicar' "dry-run em máquina sem stow"
assert_contains "$OUTPUT" '5 validações adiadas' "dry-run em máquina sem stow"
assert_contains "$OUTPUT" '47-voxtype       validação adiada: voxtype' \
  "dry-run em máquina sem stow"
assert_contains "$OUTPUT" 'mudanças planejadas; nada bloqueia' "dry-run em máquina sem stow"
[[ -z $(find "$FRESH_HOME" -mindepth 1 -print) ]] || \
  fail "dry-run em máquina sem stow escreveu no HOME"
assert_no_mutation "dry-run em máquina sem stow"
pass "dry-run planeja em máquina recém-instalada sem stow, zsh, kanata, mise nem voxtype"

# Máquina totalmente convergida: o dry-run deve dizer que não há nada a fazer.
# É a passada final do manual, exercitada de ponta a ponta.
CONVERGED_HOME="$SANDBOX/converged-home"
mkdir -p \
  "$CONVERGED_HOME/.config/alacritty" \
  "$CONVERGED_HOME/.config/foot" \
  "$CONVERGED_HOME/.config/ghostty" \
  "$CONVERGED_HOME/.config/kitty" \
  "$CONVERGED_HOME/.config/omarchy" \
  "$CONVERGED_HOME/.config/systemd/user" \
  "$CONVERGED_HOME/.claude-dio" \
  "$CONVERGED_HOME/.claude"

printf '[font]\nsize = 11\n' > "$CONVERGED_HOME/.config/alacritty/alacritty.toml"
printf '[main]\nfont=JetBrainsMono Nerd Font:size=11\n' > "$CONVERGED_HOME/.config/foot/foot.ini"
printf 'font-size = 11\n' > "$CONVERGED_HOME/.config/ghostty/config"
printf 'font_size 11.0\n' > "$CONVERGED_HOME/.config/kitty/kitty.conf"
jq -n '{idle:{lock:3600,screensaver:86400},local:true}' > \
  "$CONVERGED_HOME/.config/omarchy/shell.json"

cp -- "$TEST_ROOT/config/systemd/kanata.service" \
  "$CONVERGED_HOME/.config/systemd/user/kanata.service"

# O 47-voxtype sonda o modelo pelo arquivo em disco e a unit pelo caminho, não
# pelo binário, então a fixture reproduz os dois. O nome do arquivo vem do campo
# model do config versionado.
CONVERGED_MODEL=$(awk -F'"' '/^model = "/ { print $2 }' \
  "$TEST_ROOT/stow/common/.config/voxtype/config.toml")
[[ -n $CONVERGED_MODEL ]] || fail "modelo do voxtype não encontrado no config versionado"
mkdir -p "$CONVERGED_HOME/.local/share/voxtype/models"
: > "$CONVERGED_HOME/.local/share/voxtype/models/ggml-$CONVERGED_MODEL.bin"
: > "$CONVERGED_HOME/.config/systemd/user/voxtype.service"

for checkout in \
  "$CONVERGED_HOME/.oh-my-zsh" \
  "$CONVERGED_HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions" \
  "$CONVERGED_HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"; do
  mkdir -p "$checkout/.git"
done

: > "$CONVERGED_HOME/.claude/CLAUDE.md"
ln -sfn -- "$CONVERGED_HOME/.claude/CLAUDE.md" "$CONVERGED_HOME/.claude-dio/CLAUDE.md"
printf '%s\n' '{' '  "theme": "dark",' '  "model": "opus"' '}' > \
  "$CONVERGED_HOME/.claude-dio/settings.json"

# Os links que o Stow teria criado, montados sem depender do binário.
while IFS= read -r -d '' source_file; do
  package=${source_file#"$TEST_ROOT/stow/"}
  package=${package%%/*}
  [[ $package == common || $package == omarchy || $package == host-notebook ]] || continue
  relative=${source_file#"$TEST_ROOT/stow/$package/"}
  [[ $relative == .stow-local-ignore ]] && continue
  mkdir -p "$CONVERGED_HOME/$(dirname -- "$relative")"
  ln -sfn -- "$source_file" "$CONVERGED_HOME/$relative"
done < <(find "$TEST_ROOT/stow" \( -type f -o -type l \) -print0)

VSCODE_INSTALLED_FIXTURE="$SANDBOX/vscode-installed.txt"
/usr/bin/grep -v '^#' "$TEST_ROOT/packages/vscode-extensions.txt" | \
  /usr/bin/grep -v '^$' > "$VSCODE_INSTALLED_FIXTURE"

mkdir -p "$CONVERGED_HOME/.config/Code/User"
python3 "$TEST_ROOT/lib/vscode_settings_merge.py" \
  --managed "$TEST_ROOT/config/vscode/settings.json" \
  --destination "$CONVERGED_HOME/.config/Code/User/settings.json" \
  --output "$CONVERGED_HOME/.config/Code/User/settings.json" >/dev/null

reset_log
converged_before=$(find "$CONVERGED_HOME" -mindepth 1 -printf '%P %y %l\n' | sort)
set +e
OUTPUT=$(env \
  HOME="$CONVERGED_HOME" \
  XDG_CONFIG_HOME="$CONVERGED_HOME/.config" \
  XDG_DATA_HOME="$CONVERGED_HOME/.local/share" \
  PATH="$TEST_PATH" \
  DOTFILES_STOW_DIR="$TEST_ROOT/stow" \
  DOTFILES_STOW_TARGET="$CONVERGED_HOME" \
  DOTFILES_OS_RELEASE="$OS_RELEASE" \
  DOTFILES_CURRENT_SHELL="$SHIMS/zsh" \
  GIT_NAME_FIXTURE='Lucas Falcao Lopes' \
  GIT_EMAIL_FIXTURE='lfalcaolopes@gmail.com' \
  GIT_PUSH_REWRITE_FIXTURE='https://github.com/' \
  VSCODE_INSTALLED_FIXTURE="$VSCODE_INSTALLED_FIXTURE" \
  MISE_STATE_FIXTURE='{"node":[{"requested_version":"24"}],"pnpm":[{"requested_version":"12"}],"dotnet":[{"requested_version":"10"}]}' \
  SYSTEMCTL_TIMESTAMP_FIXTURE='Fri 2099-01-01 00:00:00 +0000' \
  "$BOOTSTRAP" notebook --dry-run 2>&1)
STATUS=$?
set -e
assert_success "dry-run em máquina convergida"
assert_contains "$OUTPUT" 'nada a fazer: a máquina já está convergida' \
  "dry-run em máquina convergida"
assert_not_contains "$OUTPUT" 'atenção antes de aplicar' "dry-run em máquina convergida"
converged_after=$(find "$CONVERGED_HOME" -mindepth 1 -printf '%P %y %l\n' | sort)
[[ $converged_before == "$converged_after" ]] || fail "dry-run alterou o HOME convergido"
assert_no_mutation "dry-run em máquina convergida"
pass "dry-run em máquina convergida conclui com nada a fazer"

# Mesma fixture, agora aplicada de verdade: a execução real precisa fechar com o
# mesmo veredito do plano, senão a pessoa termina o bootstrap sem saber se algo
# mudou.
reset_log
set +e
OUTPUT=$(env \
  HOME="$CONVERGED_HOME" \
  XDG_CONFIG_HOME="$CONVERGED_HOME/.config" \
  XDG_DATA_HOME="$CONVERGED_HOME/.local/share" \
  XDG_STATE_HOME="$SANDBOX/converged-state" \
  PATH="$TEST_PATH" \
  DOTFILES_STOW_DIR="$TEST_ROOT/stow" \
  DOTFILES_STOW_TARGET="$CONVERGED_HOME" \
  DOTFILES_OS_RELEASE="$OS_RELEASE" \
  DOTFILES_CURRENT_SHELL="$SHIMS/zsh" \
  GIT_NAME_FIXTURE='Lucas Falcao Lopes' \
  GIT_EMAIL_FIXTURE='lfalcaolopes@gmail.com' \
  GIT_PUSH_REWRITE_FIXTURE='https://github.com/' \
  VSCODE_INSTALLED_FIXTURE="$VSCODE_INSTALLED_FIXTURE" \
  MISE_STATE_FIXTURE='{"node":[{"requested_version":"24"}],"pnpm":[{"requested_version":"12"}],"dotnet":[{"requested_version":"10"}]}' \
  SYSTEMCTL_TIMESTAMP_FIXTURE='Fri 2099-01-01 00:00:00 +0000' \
  "$BOOTSTRAP" notebook 2>&1)
STATUS=$?
set -e
assert_success "execução real em máquina convergida"
assert_contains "$OUTPUT" 'nada a fazer: a máquina já estava convergida' \
  "execução real em máquina convergida"
assert_not_contains "$OUTPUT" 'atenção depois de aplicar' \
  "execução real em máquina convergida"
assert_not_contains "$OUTPUT" 'nada bloqueia' "execução real em máquina convergida"
pass "execução real em máquina convergida conclui com nada a fazer"

# Mesmo fixture, com um runtime fora do pino e um arquivo conflitante: o resumo
# precisa reagir, senão o teste anterior não provaria nada.
printf 'local zsh\n' > "$CONVERGED_HOME/.zshrc.local-conflict"
ln -sfn -- "$CONVERGED_HOME/.zshrc.local-conflict" "$SANDBOX/keep-conflict"
/usr/bin/rm -- "$CONVERGED_HOME/.zshrc"
printf 'local zsh\n' > "$CONVERGED_HOME/.zshrc"

reset_log
set +e
OUTPUT=$(env \
  HOME="$CONVERGED_HOME" \
  XDG_CONFIG_HOME="$CONVERGED_HOME/.config" \
  XDG_DATA_HOME="$CONVERGED_HOME/.local/share" \
  PATH="$TEST_PATH" \
  DOTFILES_STOW_DIR="$TEST_ROOT/stow" \
  DOTFILES_STOW_TARGET="$CONVERGED_HOME" \
  DOTFILES_OS_RELEASE="$OS_RELEASE" \
  DOTFILES_CURRENT_SHELL="$SHIMS/zsh" \
  GIT_NAME_FIXTURE='Lucas Falcao Lopes' \
  GIT_EMAIL_FIXTURE='lfalcaolopes@gmail.com' \
  GIT_PUSH_REWRITE_FIXTURE='https://github.com/' \
  VSCODE_INSTALLED_FIXTURE="$VSCODE_INSTALLED_FIXTURE" \
  MISE_STATE_FIXTURE='{"node":[{"requested_version":"25.2.1"}]}' \
  "$BOOTSTRAP" notebook --dry-run 2>&1)
STATUS=$?
set -e
assert_success "dry-run detecta divergência"
assert_not_contains "$OUTPUT" 'nada a fazer' "dry-run detecta divergência"
assert_contains "$OUTPUT" 'atenção antes de aplicar' "dry-run detecta divergência"
assert_contains "$OUTPUT" '1 conflito(s) seriam movidos para backup' \
  "dry-run detecta divergência"
assert_contains "$OUTPUT" '4 mudanças planejadas; nada bloqueia' \
  "dry-run detecta divergência"
assert_no_mutation "dry-run detecta divergência"
pass "dry-run contabiliza conflito e runtimes fora do pino"

# A mesma fixture com os pinos do mise fora do lugar, aplicada de verdade: o
# resumo final precisa contar o que a execução mudou. O conflito do Stow fica
# de fora porque o backup depende de cp real, e aqui cp é um shim.
ln -sfn -- "$TEST_ROOT/stow/common/.zshrc" "$CONVERGED_HOME/.zshrc"
reset_log
set +e
OUTPUT=$(env \
  HOME="$CONVERGED_HOME" \
  XDG_CONFIG_HOME="$CONVERGED_HOME/.config" \
  XDG_DATA_HOME="$CONVERGED_HOME/.local/share" \
  XDG_STATE_HOME="$SANDBOX/divergent-state" \
  PATH="$TEST_PATH" \
  DOTFILES_STOW_DIR="$TEST_ROOT/stow" \
  DOTFILES_STOW_TARGET="$CONVERGED_HOME" \
  DOTFILES_OS_RELEASE="$OS_RELEASE" \
  DOTFILES_CURRENT_SHELL="$SHIMS/zsh" \
  GIT_NAME_FIXTURE='Lucas Falcao Lopes' \
  GIT_EMAIL_FIXTURE='lfalcaolopes@gmail.com' \
  GIT_PUSH_REWRITE_FIXTURE='https://github.com/' \
  VSCODE_INSTALLED_FIXTURE="$VSCODE_INSTALLED_FIXTURE" \
  MISE_STATE_FIXTURE='{"node":[{"requested_version":"25.2.1"}]}' \
  "$BOOTSTRAP" notebook 2>&1)
STATUS=$?
set -e
assert_success "execução real com divergência"
assert_not_contains "$OUTPUT" 'nada a fazer' "execução real com divergência"
assert_contains "$OUTPUT" '3 mudanças aplicadas.' "execução real com divergência"
pass "execução real contabiliza os runtimes que saíram do pino"

# Um módulo que muda algo com consequência para a sessão precisa dizê-lo depois
# de aplicar, não só no plano.
printf '%s\n' 'KEYMAP=us' 'XKBLAYOUT=us' 'XKBMODEL=pc105' > "$LOCALE_VCONSOLE"
/usr/bin/rm -f -- "$LOCALE_X11"
: > "$LOCALE_LOG"
set +e
OUTPUT=$(env \
  HOME="$TEST_HOME" \
  PATH="$LOCALE_SHIMS:/usr/bin:/bin" \
  DOTFILES_STOW_DIR="$STOW_FIXTURE" \
  DOTFILES_VCONSOLE="$LOCALE_VCONSOLE" \
  DOTFILES_X11_KEYMAP="$LOCALE_X11" \
  LOCALE_LOG="$LOCALE_LOG" \
  "$BOOTSTRAP" notebook --only 05-locale 2>&1)
STATUS=$?
set -e
assert_success "atenção na execução real"
assert_contains "$OUTPUT" 'atenção depois de aplicar' "atenção na execução real"
assert_contains "$OUTPUT" 'hyprctl reload' "atenção na execução real"
assert_contains "$OUTPUT" '2 mudanças aplicadas.' "atenção na execução real"
assert_not_contains "$OUTPUT" 'nada bloqueia' "atenção na execução real"
pass "execução real reporta o que a pessoa precisa saber depois de aplicar"

# Navegador: numa instalação limpa que aceitou o padrão do Omarchy o Brave não
# existe e o padrão é o Chromium, então o módulo precisa planejar os dois passos,
# aplicá-los e reconhecer o estado convergido depois.
BROWSER_SHIMS="$SANDBOX/browser-shims"
BROWSER_STATE="$SANDBOX/browser-state"
BROWSER_LOG="$SANDBOX/browser.log"
mkdir -p "$BROWSER_SHIMS"
: > "$BROWSER_LOG"

# O par de shims compartilha um arquivo de estado, para o teste cobrir também a
# reverificação que o módulo faz depois de aplicar.
# The generated shim expands these variables when it runs.
# shellcheck disable=SC2016
{
  printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail'
  printf '%s\n' 'if (($# == 0)); then'
  printf '%s\n' '  printf "%s\n" "$(<"$BROWSER_STATE/default")"'
  printf '%s\n' '  exit 0'
  printf '%s\n' 'fi'
  printf '%s\n' 'printf "omarchy-default-browser %s\n" "$*" >> "$BROWSER_LOG"'
  printf '%s\n' 'printf "%s" "$1" > "$BROWSER_STATE/default"'
} > "$BROWSER_SHIMS/omarchy-default-browser"

# The generated shim expands these variables when it runs.
# shellcheck disable=SC2016
{
  printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail'
  printf '%s\n' 'printf "omarchy-install-browser %s\n" "$*" >> "$BROWSER_LOG"'
  printf '%s\n' 'touch "$BROWSER_STATE/installed"'
} > "$BROWSER_SHIMS/omarchy-install-browser"

# pacman -Qq brave-bin responde a partir do mesmo estado.
# The generated shim expands these variables when it runs.
# shellcheck disable=SC2016
{
  printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail'
  printf '%s\n' 'case ${1:-} in'
  printf '%s\n' '  -Q*) [[ -e $BROWSER_STATE/installed ]]; exit $? ;;'
  printf '%s\n' 'esac'
  printf '%s\n' 'printf "pacman %s\n" "$*" >> "$BROWSER_LOG"'
  printf '%s\n' 'exit 0'
} > "$BROWSER_SHIMS/pacman"

chmod +x "$BROWSER_SHIMS/omarchy-default-browser" \
  "$BROWSER_SHIMS/omarchy-install-browser" "$BROWSER_SHIMS/pacman"

run_browser_module() {
  set +e
  OUTPUT=$(env \
    HOME="$TEST_HOME" \
    PATH="$BROWSER_SHIMS:/usr/bin:/bin" \
    DOTFILES_STOW_DIR="$STOW_FIXTURE" \
    BROWSER_STATE="$BROWSER_STATE" \
    BROWSER_LOG="$BROWSER_LOG" \
    "$TEST_ROOT/modules/15-browser.sh" notebook "$@" 2>&1)
  STATUS=$?
  set -e
}

# Instalação limpa: sem Brave e com o Chromium como padrão.
/usr/bin/rm -rf -- "$BROWSER_STATE"
mkdir -p "$BROWSER_STATE"
printf 'chromium' > "$BROWSER_STATE/default"

run_browser_module --dry-run
assert_success "dry-run de navegador divergente"
assert_contains "$OUTPUT" 'dry-run: omarchy-install-browser brave' \
  "dry-run de navegador divergente"
assert_contains "$OUTPUT" "dry-run: navegador padrão é 'chromium', esperado 'brave'" \
  "dry-run de navegador divergente"
[[ $(<"$BROWSER_STATE/default") == chromium ]] || fail "dry-run de navegador trocou o padrão"
[[ ! -e $BROWSER_STATE/installed ]] || fail "dry-run de navegador instalou o Brave"
[[ ! -s $BROWSER_LOG ]] || fail "dry-run de navegador chamou o Omarchy: $(<"$BROWSER_LOG")"

run_browser_module
assert_success "aplicação de navegador"
assert_contains "$OUTPUT" 'navegador convergido: brave' "aplicação de navegador"
[[ $(<"$BROWSER_LOG") == $'omarchy-install-browser brave\nomarchy-default-browser brave' ]] || \
  fail "comandos de navegador incorretos: $(<"$BROWSER_LOG")"

: > "$BROWSER_LOG"
run_browser_module
assert_success "reexecução de navegador"
assert_contains "$OUTPUT" 'navegador já estava convergido' "reexecução de navegador"
[[ ! -s $BROWSER_LOG ]] || fail "reexecução de navegador chamou o Omarchy: $(<"$BROWSER_LOG")"

run_browser_module --dry-run
assert_success "dry-run de navegador convergido"
assert_contains "$OUTPUT" 'navegador padrão já é brave' "dry-run de navegador convergido"
assert_not_contains "$OUTPUT" 'dry-run: omarchy-' "dry-run de navegador convergido"

# Brave instalado mas padrão trocado a mão: só o segundo passo roda, para o
# instalador não sobrescrever o brave-flags.conf de novo.
printf 'chromium' > "$BROWSER_STATE/default"
: > "$BROWSER_LOG"
run_browser_module
assert_success "navegador com pacote presente"
[[ $(<"$BROWSER_LOG") == 'omarchy-default-browser brave' ]] || \
  fail "instalador rodou com o pacote presente: $(<"$BROWSER_LOG")"
pass "navegador instala, define o padrão e é idempotente nos dois passos"

# Terminal: numa instalação que aceitou o padrão do Omarchy o ghostty não existe
# e o xdg-terminals.list aponta para o foot, então o módulo precisa planejar os
# dois passos, aplicá-los e reconhecer o estado convergido depois.
TERMINAL_SHIMS="$SANDBOX/terminal-shims"
TERMINAL_STATE="$SANDBOX/terminal-state"
TERMINAL_LOG="$SANDBOX/terminal.log"
mkdir -p "$TERMINAL_SHIMS"
: > "$TERMINAL_LOG"

# O par de shims compartilha um arquivo de estado, e o instalador também grava o
# padrão, como o omarchy-install-terminal faz com o xdg-terminals.list.
# The generated shim expands these variables when it runs.
# shellcheck disable=SC2016
{
  printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail'
  printf '%s\n' 'if (($# == 0)); then'
  printf '%s\n' '  printf "%s\n" "$(<"$TERMINAL_STATE/default")"'
  printf '%s\n' '  exit 0'
  printf '%s\n' 'fi'
  printf '%s\n' 'printf "omarchy-default-terminal %s\n" "$*" >> "$TERMINAL_LOG"'
  printf '%s\n' 'printf "%s" "$1" > "$TERMINAL_STATE/default"'
} > "$TERMINAL_SHIMS/omarchy-default-terminal"

# The generated shim expands these variables when it runs.
# shellcheck disable=SC2016
{
  printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail'
  printf '%s\n' 'printf "omarchy-install-terminal %s\n" "$*" >> "$TERMINAL_LOG"'
  printf '%s\n' 'touch "$TERMINAL_STATE/installed"'
  printf '%s\n' 'printf "%s" "$1" > "$TERMINAL_STATE/default"'
} > "$TERMINAL_SHIMS/omarchy-install-terminal"

# pacman -Qq ghostty responde a partir do mesmo estado.
# The generated shim expands these variables when it runs.
# shellcheck disable=SC2016
{
  printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail'
  printf '%s\n' 'case ${1:-} in'
  printf '%s\n' '  -Q*) [[ -e $TERMINAL_STATE/installed ]]; exit $? ;;'
  printf '%s\n' 'esac'
  printf '%s\n' 'printf "pacman %s\n" "$*" >> "$TERMINAL_LOG"'
  printf '%s\n' 'exit 0'
} > "$TERMINAL_SHIMS/pacman"

chmod +x "$TERMINAL_SHIMS/omarchy-default-terminal" \
  "$TERMINAL_SHIMS/omarchy-install-terminal" "$TERMINAL_SHIMS/pacman"

run_terminal_module() {
  set +e
  OUTPUT=$(env \
    HOME="$TEST_HOME" \
    PATH="$TERMINAL_SHIMS:/usr/bin:/bin" \
    DOTFILES_STOW_DIR="$STOW_FIXTURE" \
    TERMINAL_STATE="$TERMINAL_STATE" \
    TERMINAL_LOG="$TERMINAL_LOG" \
    "$TEST_ROOT/modules/17-terminal.sh" notebook "$@" 2>&1)
  STATUS=$?
  set -e
}

# Instalação limpa: sem ghostty e com o foot como padrão.
/usr/bin/rm -rf -- "$TERMINAL_STATE"
mkdir -p "$TERMINAL_STATE"
printf 'foot' > "$TERMINAL_STATE/default"

run_terminal_module --dry-run
assert_success "dry-run de terminal divergente"
assert_contains "$OUTPUT" 'dry-run: omarchy-install-terminal ghostty' \
  "dry-run de terminal divergente"
assert_contains "$OUTPUT" "dry-run: terminal padrão é 'foot', esperado 'ghostty'" \
  "dry-run de terminal divergente"
[[ $(<"$TERMINAL_STATE/default") == foot ]] || fail "dry-run de terminal trocou o padrão"
[[ ! -e $TERMINAL_STATE/installed ]] || fail "dry-run de terminal instalou o ghostty"
[[ ! -s $TERMINAL_LOG ]] || fail "dry-run de terminal chamou o Omarchy: $(<"$TERMINAL_LOG")"

run_terminal_module
assert_success "aplicação de terminal"
assert_contains "$OUTPUT" 'terminal convergido: ghostty' "aplicação de terminal"
[[ $(<"$TERMINAL_LOG") == 'omarchy-install-terminal ghostty' ]] || \
  fail "comandos de terminal incorretos: $(<"$TERMINAL_LOG")"

: > "$TERMINAL_LOG"
run_terminal_module
assert_success "reexecução de terminal"
assert_contains "$OUTPUT" 'terminal já estava convergido' "reexecução de terminal"
[[ ! -s $TERMINAL_LOG ]] || fail "reexecução de terminal chamou o Omarchy: $(<"$TERMINAL_LOG")"

run_terminal_module --dry-run
assert_success "dry-run de terminal convergido"
assert_contains "$OUTPUT" 'terminal padrão já é ghostty' "dry-run de terminal convergido"
assert_not_contains "$OUTPUT" 'dry-run: omarchy-' "dry-run de terminal convergido"

# ghostty instalado mas padrão trocado a mão: só o segundo passo roda, para o
# instalador não copiar o config padrão por cima de novo.
printf 'foot' > "$TERMINAL_STATE/default"
: > "$TERMINAL_LOG"
run_terminal_module
assert_success "terminal com pacote presente"
[[ $(<"$TERMINAL_LOG") == 'omarchy-default-terminal ghostty' ]] || \
  fail "instalador rodou com o pacote presente: $(<"$TERMINAL_LOG")"
pass "terminal instala, define o padrão e é idempotente nos dois passos"

# Ditado: o módulo converge backend, modelo, serviço e o restart que faz o
# daemon reler o config. O modelo é sondado pelo arquivo em disco e o backend
# por `voxtype setup gpu`, que sem flag só imprime o estado.
VOXTYPE_HOME="$SANDBOX/voxtype-home"
VOXTYPE_MODEL=$(awk -F'"' '/^model = "/ { print $2 }' \
  "$TEST_ROOT/stow/common/.config/voxtype/config.toml")
[[ -n $VOXTYPE_MODEL ]] || fail "modelo do voxtype não encontrado no config versionado"
mkdir -p "$VOXTYPE_HOME/.config/voxtype"
cp -- "$TEST_ROOT/stow/common/.config/voxtype/config.toml" \
  "$VOXTYPE_HOME/.config/voxtype/config.toml"

run_voxtype_module() {
  set +e
  OUTPUT=$(env \
    HOME="$VOXTYPE_HOME" \
    XDG_CONFIG_HOME="$VOXTYPE_HOME/.config" \
    XDG_DATA_HOME="$VOXTYPE_HOME/.local/share" \
    PATH="$TEST_PATH" \
    DOTFILES_STOW_DIR="$STOW_FIXTURE" \
    DOTFILES_OS_RELEASE="$OS_RELEASE" \
    "$@" 2>&1)
  STATUS=$?
  set -e
}

# Nada convergido: backend na CPU, modelo ausente, unit ausente e serviço
# parado. O plano precisa listar os quatro passos sem tocar em nada.
reset_log
run_voxtype_module VOXTYPE_BACKEND_FIXTURE='CPU (AVX2)' SYSTEMCTL_STATE_STATUS=1 \
  "$BOOTSTRAP" notebook --only 47-voxtype --dry-run
assert_success "dry-run de voxtype divergente"
assert_contains "$OUTPUT" 'dry-run: sudo voxtype setup gpu --enable' \
  "dry-run de voxtype divergente"
assert_contains "$OUTPUT" "dry-run: modelo '$VOXTYPE_MODEL' ausente" \
  "dry-run de voxtype divergente"
assert_contains "$OUTPUT" "voxtype setup --download --model $VOXTYPE_MODEL --no-post-install" \
  "dry-run de voxtype divergente"
assert_contains "$OUTPUT" 'dry-run: voxtype setup systemd' "dry-run de voxtype divergente"
assert_contains "$OUTPUT" 'ocupa mais de 1 GB' "dry-run de voxtype divergente"
assert_no_mutation "dry-run de voxtype divergente"
[[ ! -e $VOXTYPE_HOME/.config/systemd/user/voxtype.service ]] || \
  fail "dry-run de voxtype instalou a unit"

# Sem Vulkan o binário de GPU não roda: o módulo segue e converge o resto em vez
# de tentar ligar um backend que a máquina não tem.
reset_log
run_voxtype_module VOXTYPE_BACKEND_FIXTURE='CPU (AVX2)' OMARCHY_VULKAN_STATUS=1 \
  "$BOOTSTRAP" notebook --only 47-voxtype --dry-run
assert_success "dry-run de voxtype sem Vulkan"
assert_contains "$OUTPUT" 'sem Vulkan nesta máquina' "dry-run de voxtype sem Vulkan"
assert_not_contains "$OUTPUT" 'setup gpu --enable' "dry-run de voxtype sem Vulkan"
assert_no_mutation "dry-run de voxtype sem Vulkan"

# Execução real. O backend já está em GPU porque `sudo` é shim e não chegaria a
# trocar o binário; o que se prova aqui é o download, a unit e o serviço.
reset_log
run_voxtype_module "$BOOTSTRAP" notebook --only 47-voxtype
assert_success "execução real de voxtype"
assert_contains "$OUTPUT" "voxtype convergido: modelo '$VOXTYPE_MODEL'" \
  "execução real de voxtype"
[[ -f $VOXTYPE_HOME/.local/share/voxtype/models/ggml-$VOXTYPE_MODEL.bin ]] || \
  fail "execução real de voxtype não baixou o modelo"
[[ -f $VOXTYPE_HOME/.config/systemd/user/voxtype.service ]] || \
  fail "execução real de voxtype não instalou a unit"

# Reexecução com o daemon subido depois do config: nada a fazer.
reset_log
run_voxtype_module SYSTEMCTL_TIMESTAMP_FIXTURE='Fri 2099-01-01 00:00:00 +0000' \
  "$BOOTSTRAP" notebook --only 47-voxtype
assert_success "reexecução de voxtype"
assert_contains "$OUTPUT" "voxtype já estava convergido" "reexecução de voxtype"
assert_not_contains "$OUTPUT" 'reiniciar voxtype.service' "reexecução de voxtype"

# Config editado no repositório depois da subida do daemon: sem o restart o
# voxtype seguiria com o modelo antigo até o próximo reboot.
reset_log
run_voxtype_module SYSTEMCTL_TIMESTAMP_FIXTURE='Sat 2000-01-01 00:00:00 +0000' \
  "$BOOTSTRAP" notebook --only 47-voxtype --dry-run
assert_success "dry-run de voxtype com config mais novo"
assert_contains "$OUTPUT" 'config mais novo que o daemon' \
  "dry-run de voxtype com config mais novo"
assert_no_mutation "dry-run de voxtype com config mais novo"

reset_log
run_voxtype_module SYSTEMCTL_TIMESTAMP_FIXTURE='Sat 2000-01-01 00:00:00 +0000' \
  "$BOOTSTRAP" notebook --only 47-voxtype
assert_success "execução real de voxtype com config mais novo"
assert_contains "$OUTPUT" 'voxtype convergido' "execução real de voxtype com config mais novo"
/usr/bin/grep -q 'systemctl --user restart voxtype.service' "$SHIM_LOG" || \
  fail "config mais novo não reiniciou o daemon: $(<"$SHIM_LOG")"
pass "voxtype converge backend, modelo, serviço e restart do daemon"

# Passos manuais: o módulo só sonda estado, então a lista final precisa sumir
# item a item conforme o login, a chave ou o clone aparecem.
reset_log
PACMAN_QUERY_STATUS=1 run_bootstrap notebook --only 70-manual --dry-run
assert_success "checklist manual pendente"
assert_contains "$OUTPUT" 'falta fazer à mão, na ordem:' "checklist manual pendente"
assert_contains "$OUTPUT" '    2. autenticar o GitHub por SSH' "checklist manual pendente"
assert_contains "$OUTPUT" '       gh auth login --git-protocol ssh --hostname github.com' \
  "checklist manual pendente"
assert_contains "$OUTPUT" '       ssh-keygen -t ed25519' "checklist manual pendente"
assert_contains "$OUTPUT" 'entrar na Steam' "checklist manual pendente"
assert_contains "$OUTPUT" "       git clone git@github.com:lfalcaolopes/notes.git $TEST_HOME/notes" \
  "checklist manual pendente"
assert_contains "$OUTPUT" '       omarchy-install-service-1password' "checklist manual pendente"
assert_no_mutation "checklist manual pendente"

mkdir -p "$TEST_HOME/.ssh" "$TEST_HOME/.config/gh" \
  "$TEST_HOME/.local/share/Steam/config" "$TEST_HOME/notes/.git"
printf 'ssh-ed25519 AAAA fixture\n' > "$TEST_HOME/.ssh/id_ed25519.pub"
printf 'github.com:\n    git_protocol: ssh\n' > "$TEST_HOME/.config/gh/hosts.yml"
printf '"users"\n' > "$TEST_HOME/.local/share/Steam/config/loginusers.vdf"

reset_log
run_bootstrap notebook --only 70-manual --dry-run
assert_success "checklist manual resolvido"
assert_not_contains "$OUTPUT" 'gh auth login' "checklist manual resolvido"
assert_not_contains "$OUTPUT" 'git_protocol ssh' "checklist manual resolvido"
assert_not_contains "$OUTPUT" 'ssh-keygen' "checklist manual resolvido"
assert_not_contains "$OUTPUT" 'entrar na Steam' "checklist manual resolvido"
assert_not_contains "$OUTPUT" 'git clone' "checklist manual resolvido"
assert_not_contains "$OUTPUT" '1Password' "checklist manual resolvido"
# O login do VS Code fica no keyring do sistema: continua lembrado sempre.
# Passo sem comando sai só com a descrição, e sozinho ele é o item 1.
assert_contains "$OUTPUT" '    1. entrar no GitHub pelo VS Code' "checklist manual resolvido"
assert_not_contains "$OUTPUT" '    2. ' "checklist manual resolvido"
assert_no_mutation "checklist manual resolvido"
# Autenticado em HTTPS conta como pendência: o login existe, mas o protocolo
# que o gh usa em clone e push ainda não é o SSH.
printf 'github.com:\n    git_protocol: https\n' > "$TEST_HOME/.config/gh/hosts.yml"
reset_log
run_bootstrap notebook --only 70-manual --dry-run
assert_success "checklist manual com gh em https"
assert_contains "$OUTPUT" 'gh config set -h github.com git_protocol ssh' \
  "checklist manual com gh em https"
assert_not_contains "$OUTPUT" 'gh auth login' "checklist manual com gh em https"
printf 'github.com:\n    git_protocol: ssh\n' > "$TEST_HOME/.config/gh/hosts.yml"
pass "checklist manual lista só o que a sondagem não encontrou"

for script in "$TEST_ROOT/bootstrap.sh" "$TEST_ROOT/lib/common.sh" "$TEST_ROOT/modules/"*.sh; do
  bash -n "$script"
done
python3 "$TEST_ROOT/lib/jsonc_to_json.py" \
  < "$TEST_ROOT/config/vscode/settings.json" | jq empty
python3 "$TEST_ROOT/lib/jsonc_to_json.py" \
  < "$TEST_ROOT/stow/common/.config/Code/User/keybindings.json" | \
  jq -e 'type == "array"' >/dev/null
PYTHONPYCACHEPREFIX="$SANDBOX/pycache" python3 -m py_compile \
  "$TEST_ROOT/lib/jsonc_to_json.py" "$TEST_ROOT/lib/vscode_settings_merge.py"
for lua_file in $(find "$TEST_ROOT/stow" -type f -name '*.lua' | sort); do
  luac -p "$lua_file"
done
pass "scripts Bash, JSON, JSONC e Lua passam nos parsers"

bindings_file="$TEST_ROOT/stow/omarchy/.config/hypr/bindings.lua"
for binding in \
  'hl.unbind("ALT + TAB")' \
  'hl.unbind("ALT + SHIFT + TAB")' \
  'hl.unbind("CTRL + ALT + TAB")' \
  'hl.unbind("CTRL + ALT + SHIFT + TAB")' \
  'o.bind("ALT + TAB", "Focus on next monitor", hl.dsp.focus({ monitor = "+1" }))' \
  'o.bind("ALT + SHIFT + TAB", "Focus on previous monitor", hl.dsp.focus({ monitor = "-1" }))' \
  'o.bind("CTRL + ALT + TAB", "Focus on next window", hl.dsp.window.cycle_next())' \
  'o.bind("CTRL + ALT + SHIFT + TAB", "Focus on previous window", hl.dsp.window.cycle_next({ next = false }))'
do
  grep -Fqx -- "$binding" "$bindings_file" || fail "binding ausente: $binding"
done
pass "Alt-Tab e Ctrl-Alt-Tab trocam ciclagem de monitores e janelas"

xcompose_file="$TEST_ROOT/stow/omarchy/.XCompose"
for sequence in \
  'include "/usr/share/omarchy/default/xcompose"' \
  '<dead_acute> <c> : "ç"' \
  '<dead_acute> <C> : "Ç"'
do
  grep -Fqx -- "$sequence" "$xcompose_file" || fail "sequência XCompose ausente: $sequence"
done
pass "XCompose produz cedilha com dead-acute seguido de C"

printf '1..%d\n' "$TESTS_RUN"
