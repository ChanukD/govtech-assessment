#!/usr/bin/env bash
#
# Static checks for the Terraform configuration. Runs without AWS credentials and
# without touching any infrastructure: no backend is initialised, no plan is made, and
# nothing is applied.
#
#   ./validate.sh          run every check
#   ./validate.sh fmt      run a single check (fmt | validate | lint | scan)
#
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

ENV_DIR="envs/dev"
readonly ENV_DIR

red() { printf '\033[31m%s\033[0m\n' "$1"; }
green() { printf '\033[32m%s\033[0m\n' "$1"; }
heading() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }

failed=0

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    red "  $1 is not installed - skipping"
    return 1
  fi
}

check_fmt() {
  heading "terraform fmt"
  require terraform || return 0
  if terraform fmt -recursive -check -diff; then
    green "  formatting is canonical"
  else
    red "  formatting differs - run 'terraform fmt -recursive'"
    failed=1
  fi
}

check_validate() {
  heading "terraform validate"
  require terraform || return 0

  # -backend=false is what lets this run with no credentials and no state bucket: it
  # initialises modules and providers only.
  if ! terraform -chdir="$ENV_DIR" init -backend=false -input=false >/dev/null; then
    red "  init failed"
    failed=1
    return 0
  fi

  if terraform -chdir="$ENV_DIR" validate; then
    green "  configuration is valid"
  else
    failed=1
  fi
}

check_lint() {
  heading "tflint"
  require tflint || return 0

  # The config lives at the repo root, so pass an absolute path: --recursive changes
  # directory as it walks.
  local config="$PWD/.tflint.hcl"

  if ! tflint --init --config="$config" >/dev/null 2>&1; then
    red "  plugin init failed (network required on first run)"
    failed=1
    return 0
  fi

  if tflint --recursive --config="$config"; then
    green "  no lint findings"
  else
    red "  lint findings above"
    failed=1
  fi
}

check_scan() {
  heading "trivy"
  require trivy || return 0

  # Advisory only: trivy does not gate this script. Findings that are accepted
  # deliberately are listed with a reason in .trivyignore.
  if trivy config --exit-code 0 --ignorefile .trivyignore .; then
    green "  scan complete (advisory)"
  else
    red "  scan could not complete"
  fi
}

main() {
  case "${1:-all}" in
  fmt) check_fmt ;;
  validate) check_validate ;;
  lint) check_lint ;;
  scan) check_scan ;;
  all)
    check_fmt
    check_validate
    check_lint
    check_scan
    ;;
  *)
    red "unknown check: $1 (expected fmt, validate, lint, scan or all)"
    exit 2
    ;;
  esac

  if [[ $failed -ne 0 ]]; then
    heading "FAILED"
    exit 1
  fi

  heading "OK"
}

main "$@"
