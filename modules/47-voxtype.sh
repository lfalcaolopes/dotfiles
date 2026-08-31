#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly REPO_ROOT
# shellcheck source=lib/common.sh
source "$REPO_ROOT/lib/common.sh"

parse_module_args "$@"

# O config do voxtype é versionado em stow/common e chega aqui como link; este
# módulo cuida do que não cabe num arquivo: o backend de inferência, o modelo
# baixado, o serviço e o restart que faz o daemon reler o config.
#
# A ordem importa. O módulo roda depois dos três de Stow porque lê o modelo
# declarado no arquivo versionado, e o download precisa saber qual baixar.
stow_dir=${DOTFILES_STOW_DIR:-$REPO_ROOT/stow}
source_config="$stow_dir/common/.config/voxtype/config.toml"
config_home=${XDG_CONFIG_HOME:-$HOME/.config}
installed_config="$config_home/voxtype/config.toml"
data_home=${XDG_DATA_HOME:-$HOME/.local/share}
models_dir="$data_home/voxtype/models"
unit_destination="$config_home/systemd/user/voxtype.service"

require_file "$source_config"
require_command awk
require_command date
require_command systemctl
require_command omarchy-hw-vulkan

# O esquema do voxtype não tem default para model, então o campo existe sempre.
# Ler o arquivo versionado, e não o instalado, mantém a sondagem possível mesmo
# num dry-run onde o Stow ainda não rodou.
read_declared_model() {
  awk '
    /^\[[^]]+\][[:space:]]*$/ { in_whisper = ($0 == "[whisper]") }
    in_whisper && /^[[:space:]]*model[[:space:]]*=[[:space:]]*"[^"]+"[[:space:]]*$/ {
      match($0, /"[^"]+"/)
      print substr($0, RSTART + 1, RLENGTH - 2)
      found++
    }
    END { if (found != 1) exit 42 }
  ' "$source_config"
}

declared_model=$(read_declared_model) || die \
  "campo model não encontrado uma única vez em [whisper]: $source_config"
model_file="$models_dir/ggml-$declared_model.bin"

voxtype_available=true
if ! require_provisioned_command voxtype "o módulo 10-packages"; then
  voxtype_available=false
  log_info "dry-run: backend e modelo só podem ser sondados depois da instalação"
fi

# Sem Vulkan o binário de GPU não roda, e o voxtype fica no backend de CPU. O
# comando do Omarchy só procura um ICD em /usr/share/vulkan/icd.d: leitura pura.
gpu_supported=false
if omarchy-hw-vulkan; then
  gpu_supported=true
fi

# `voxtype setup gpu` sem flag apenas imprime o backend ativo; quem escreve em
# /usr/lib/voxtype é a variante --enable, e essa exige sudo.
gpu_diverges() {
  local status
  [[ $voxtype_available == true && $gpu_supported == true ]] || return 1
  status=$(voxtype setup gpu 2>/dev/null || true)
  [[ $status != *"Active backend: GPU"* ]]
}

model_diverges() {
  [[ ! -f $model_file ]]
}

unit_diverges() {
  [[ ! -f $unit_destination ]]
}

# O daemon lê o config uma vez, ao subir. Como o arquivo é um link para o
# repositório, editá-lo no repo não avisa ninguém: sem esta comparação o
# voxtype seguiria com o modelo antigo até o próximo reboot. `show` e
# `is-active` apenas consultam o systemd.
config_is_newer_than_daemon() {
  local started started_epoch config_epoch
  systemctl --user is-active --quiet voxtype.service || return 1
  started=$(systemctl --user show voxtype.service \
    --property=ActiveEnterTimestamp --value 2>/dev/null || true)
  [[ -n $started ]] || return 1
  started_epoch=$(date -d "$started" +%s 2>/dev/null) || return 1
  config_epoch=$(date -r "$installed_config" +%s 2>/dev/null) || return 1
  (( config_epoch > started_epoch ))
}

if [[ $DRY_RUN == true ]]; then
  if [[ $gpu_supported == false ]]; then
    log_info "sem Vulkan nesta máquina; o voxtype fica no backend de CPU"
  elif gpu_diverges; then
    log_info "dry-run: $(shell_join sudo voxtype setup gpu --enable)"
    summary_change 1 "ligar o backend Vulkan do voxtype"
  elif [[ $voxtype_available == true ]]; then
    log_info "backend do voxtype já é GPU"
  fi

  if model_diverges; then
    log_info "dry-run: modelo '$declared_model' ausente em $models_dir"
    log_info "dry-run: $(shell_join voxtype setup --download \
      --model "$declared_model" --no-post-install)"
    summary_change 1 "baixar o modelo '$declared_model'"
    summary_attention 1 \
      "o modelo '$declared_model' é baixado da rede e ocupa mais de 1 GB"
  else
    log_info "modelo '$declared_model' já está baixado"
  fi

  if unit_diverges; then
    log_info "dry-run: $(shell_join voxtype setup systemd)"
    summary_change 1 "instalar a unit voxtype.service"
  fi

  systemctl --user is-enabled --quiet voxtype.service || \
    summary_change 1 "habilitar voxtype.service"
  systemctl --user is-active --quiet voxtype.service || \
    summary_change 1 "iniciar voxtype.service"

  if config_is_newer_than_daemon; then
    log_info "dry-run: config mais novo que o daemon; reiniciar voxtype.service"
    summary_change 1 "reiniciar voxtype.service para reler o config"
  fi
  exit 0
fi

require_file "$installed_config"

applied=0

if [[ $gpu_supported == false ]]; then
  log_info "sem Vulkan nesta máquina; o voxtype fica no backend de CPU"
elif gpu_diverges; then
  sudo voxtype setup gpu --enable
  gpu_diverges && die "backend do voxtype não convergiu para GPU"
  applied=$((applied + 1))
  summary_change 1 "ligar o backend Vulkan do voxtype"
fi

if model_diverges; then
  summary_attention 1 \
    "o modelo '$declared_model' foi baixado da rede e ocupa mais de 1 GB"
  voxtype setup --download --model "$declared_model" --no-post-install
  model_diverges && die "modelo não foi baixado: $model_file"
  applied=$((applied + 1))
  summary_change 1 "baixar o modelo '$declared_model'"
fi

# `setup systemd` grava a unit e a habilita; os dois passos abaixo cobrem a
# máquina onde a unit já existe mas o serviço foi desabilitado à mão.
unit_installed=false
if unit_diverges; then
  voxtype setup systemd
  unit_diverges && die "unit não foi instalada: $unit_destination"
  unit_installed=true
  applied=$((applied + 1))
  summary_change 1 "instalar a unit voxtype.service"
fi

if ! systemctl --user is-enabled --quiet voxtype.service; then
  systemctl --user enable voxtype.service
  applied=$((applied + 1))
  summary_change 1 "habilitar voxtype.service"
fi

if ! systemctl --user is-active --quiet voxtype.service; then
  systemctl --user start voxtype.service
  applied=$((applied + 1))
  summary_change 1 "iniciar voxtype.service"
elif [[ $unit_installed == true ]] || (( applied > 0 )) || config_is_newer_than_daemon; then
  systemctl --user restart voxtype.service
  applied=$((applied + 1))
  summary_change 1 "reiniciar voxtype.service para reler o config"
fi

if (( applied > 0 )); then
  log_info "voxtype convergido: modelo '$declared_model', serviço ativo"
else
  log_info "voxtype já estava convergido: modelo '$declared_model'"
fi
