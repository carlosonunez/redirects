#!/usr/bin/env bash
if test -e "$(dirname "$0")/../.env"
then
  # shellcheck disable=SC2046
  export $(grep -Ev '^#' "$(dirname "$0")/../.env" | xargs -0)
fi

set -e
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID?Please define AWS_ACCESS_KEY_ID.}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY?Please define AWS_SECRET_ACCESS_KEY.}"
export AWS_ROLE_ARN="${AWS_ROLE_ARN?Please define the role ARN to assume.}"
export AWS_STS_EXTERNAL_ID="${AWS_STS_EXTERNAL_ID?Please provide the password for the role to assume}"
export AWS_REGION="${AWS_REGION?Please define AWS_REGION}"
>&2 echo "INFO: Logging into AWS; please stand by."
session_name="slack-apis-deploy-$(date +%s)"
export AWS_SESSION_NAME="$session_name"
if ! aws_session_info=$(docker-compose run -T --rm obtain-aws-session-token)
then
  >&2 echo "ERROR: Unable to log into AWS with credentials provided in .env; received:
$aws_session_info"
  exit 1
fi
access_key="$(echo "$aws_session_info" | grep AccessKeyId | cut -f2 -d ':' | tr -d ' ')"
secret_key="$(echo "$aws_session_info" | grep SecretAccessKey | cut -f2 -d ':' | tr -d ' ')"
session_token="$(echo "$aws_session_info" | grep SessionToken | cut -f2 -d ':' | tr -d ' ')"

export AWS_ACCESS_KEY_ID="$access_key"
export AWS_SECRET_ACCESS_KEY="$secret_key"
export AWS_SESSION_TOKEN="$session_token"

docker-compose run --rm deploy
