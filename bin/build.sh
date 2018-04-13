#!/bin/sh
cd "$(dirname "$0")"

function generate_json_with_trailing_comma() {
  source ../src/version.manifest
  fields=$(cat ../src/version.manifest | cut -d' ' -f2 | cut -d'=' -f1)

  printf "{"
  for field in $fields; do
    printf "\"$field\": \"${!field}\","
  done
  echo "}"
}

function generate_json() {
  # remove trailing comma
  generate_json_with_trailing_comma | sed 's/,}/}/g'
}

function upload_version_info() {
  generate_json > versions.tmp.json
  aws s3 cp versions.tmp.json s3://armory-web/k8s-latest.json
  rm versions.tmp.json
}

upload_version_info
