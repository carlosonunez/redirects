#!/usr/bin/env bash
set -euo pipefail

generate_terraform_vars() {
  rm terraform.tfvars && \
  docker-compose run --rm generate-terraform-vars | \
    tr -d '$\r' | \
    sed 's/,}$/}/' > terraform.tfvars
}

generate_backend_vars() {
  docker-compose run --rm generate-terraform-backend-vars | \
    tr -d '$\r' | \
    sed 's/,}$/}/' > backend.tfvars
}

initialize_terraform() {
  if ! test -f terraform.tfvars
  then
    >&2 echo "ERROR: Generate terraform.tfvars first."
    exit 1
  fi
  docker-compose run  --rm terraform-init
}

generate_terraform_vars && \
  generate_backend_vars && \
  initialize_terraform
