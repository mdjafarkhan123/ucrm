#!/usr/bin/env bash
# AWS CLI `credential_process` helper for local development. It prints the app's SES worker key from .env in
# the format the CLI expects, so `aws --profile ucrm ...` uses the same identity as the app without copying the
# secret into ~/.aws. Nothing here is a secret; the key itself stays only in .env.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a
# shellcheck disable=SC1091
. ./.env
set +a
printf '{"Version":1,"AccessKeyId":"%s","SecretAccessKey":"%s"}\n' \
	"$AWS_SES_ACCESS_KEY_ID" "$AWS_SES_SECRET_ACCESS_KEY"
