#!/usr/bin/env bash

set -ex

schema_registry_url="${1?Schema Registry URL is required}"
prefix="${2?Prefix is required}"

curl -f ${schema_registry_url}/subjects | jq -r .[] | grep ${prefix}_* | xargs -I % curl -f -X DELETE ${schema_registry_url}/subjects/%
