#!/bin/bash -xe
cd "$(dirname "$0")"

mkdir -p ../src/build

source ../src/build/version.manifest
echo "export armoryspinnaker_version_manifest_url=${armoryspinnaker_version_manifest_url}" > ../src/build/armoryspinnaker-latest-version.manifest
aws s3 cp --acl public-read-write ../src/build/armoryspinnaker-latest-version.manifest "s3://armory-web/install/release/armoryspinnaker-latest-version.manifest"
