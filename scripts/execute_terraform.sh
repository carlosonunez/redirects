#!/usr/bin/env bash
source $(dirname "$0")/helpers/shared_secrets.sh
TERRAFORM_STATE_S3_BUCKET="${TERRAFORM_STATE_S3_BUCKET?Please provide a S3 bucket to store state in.}"
TERRAFORM_STATE_S3_KEY="${TERRAFORM_STATE_S3_KEY:-terraform_state}"
AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID?Please provide an AWS access key.}"
AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY?Please provide an AWS secret key.}"
AWS_REGION="${AWS_REGION?Please provide an AWS region.}"
WRITE_SECRETS="${WRITE_SECRETS:-false}"

set -e
action=$1
shift

terraform init --backend-config="bucket=${TERRAFORM_STATE_S3_BUCKET}" \
  --reconfigure \
  --backend-config="key=${TERRAFORM_STATE_S3_KEY}" \
  --backend-config="region=$AWS_REGION" && \

terraform $action $* && \
  if [ "$WRITE_SECRETS" == "true" ] && { [ "$action" == "apply" ] || [ "$action" == "output" ]; }
  then
    mkdir -p ./secrets
    secrets=$(terraform output)
    for output_var in app_account_ak app_account_sk certificate_arn bucket_name dlq
    do
      value=$(echo "$secrets" | grep -E "^$output_var" | cut -f2 -d = | sed 's/^ //' | tr -d '"')
      write_secret "$value" "$output_var"
    done
  elif [ "$action" == "destroy" ]
  then
    rm -rf "$(secret_dir)"
  fi
