#!/bin/bash -xe
cd "$(dirname "$0")"

mkdir -p ../src/build

source ../src/build/version.manifest
echo "export armoryspinnaker_version_manifest_url=${armoryspinnaker_version_manifest_url}" > ../src/build/armoryspinnaker-latest-version.manifest
echo "promoting ArmorySpinnaker v${armoryspinnaker_version}, job# ${jenkins_build_number}"
aws s3 cp --acl public-read-write --content-type text/plain ../src/build/armoryspinnaker-latest-version.manifest "s3://armory-web/install/release/armoryspinnaker-latest-version.manifest"
