#!/bin/bash -xe
cd "$(dirname "$0")"

aws s3 cp --acl public-read-write src/build/armoryspinnaker-latest-version.manifest "s3://armory-web/install/release/armoryspinnaker-latest-version.manifest"
