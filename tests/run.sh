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
  "$SHIMS" \
  "$STOW_FIXTURE/common" \
  "$STOW_FIXTURE/omarchy" \
  "$STOW_FIXTURE/host-notebook" \
  "$STOW_FIXTURE/host-desktop"
: > "$SHIM_LOG"

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

for command in sudo pacman yay git stow chsh systemctl code mise mkdir cp mv rm ln install; do
  make_shim "$command"
done
make_shim curl readonly

export SHIM_LOG
TEST_PATH="$SHIMS:/usr/bin:/bin"
OUTPUT=
STATUS=0
TESTS_RUN=0

run_bootstrap() {
  set +e
  OUTPUT=$(env \
    HOME="$TEST_HOME" \
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

for selected_module in 00-preflight 10-packages 20-stow-common 30-stow-omarchy 35-stow-host; do
  reset_log
  run_bootstrap notebook --only "$selected_module" --dry-run
  assert_success "seleção --only $selected_module"
  assert_contains "$OUTPUT" "executando módulo: $selected_module" "seleção --only $selected_module"
  for other_module in 00-preflight 10-packages 20-stow-common 30-stow-omarchy 35-stow-host; do
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
'executando módulo: 10-packages'*\
'executando módulo: 20-stow-common'*\
'executando módulo: 30-stow-omarchy'*\
'executando módulo: 35-stow-host'* ]] || \
  fail "ordem do dry-run"
[[ $home_before == "$home_after" ]] || fail "dry-run alterou HOME temporário"
assert_no_mutation "dry-run completo"
pass "dry-run percorre os módulos em ordem sem escrita nem comando mutável"

reset_log
set +e
OUTPUT=$(cd /tmp && env \
  HOME="$TEST_HOME" \
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
assert_contains "$shim_calls" 'yay -S --needed --noconfirm postman-bin google-cloud-cli' \
  "pacotes AUR"
run_bootstrap desktop --only 10-packages
assert_success "reexecução de pacotes"
assert_contains "$OUTPUT" 'pacotes convergidos para o host desktop' "reexecução de pacotes"
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

printf '1..%d\n' "$TESTS_RUN"
