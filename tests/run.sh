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
mkdir -p "$TEST_HOME" "$SHIMS" "$STOW_FIXTURE/host-notebook" "$STOW_FIXTURE/host-desktop"
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

for selected_module in 00-preflight 10-packages; do
  reset_log
  run_bootstrap notebook --only "$selected_module" --dry-run
  assert_success "seleção --only $selected_module"
  assert_contains "$OUTPUT" "executando módulo: $selected_module" "seleção --only $selected_module"
  for other_module in 00-preflight 10-packages; do
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
[[ $OUTPUT == *'executando módulo: 00-preflight'*'executando módulo: 10-packages'* ]] || \
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

printf '1..%d\n' "$TESTS_RUN"
