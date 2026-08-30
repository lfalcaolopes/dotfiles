#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly REPO_ROOT
# shellcheck source=lib/common.sh
source "$REPO_ROOT/lib/common.sh"

parse_module_args "$@"
require_command mise

run_mutating "fixar Node 24 global" mise use -g node@24
run_mutating "fixar pnpm 12 global" mise use -g pnpm@12
run_mutating "fixar .NET SDK 10 global" mise use -g dotnet@10

log_info "runtimes globais do mise convergidos"
