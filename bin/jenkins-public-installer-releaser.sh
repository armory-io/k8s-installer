#!/bin/bash -xe
cd "$(dirname "$0")/.."
JENKINS_USER_HOME=${JENKINS_USER_HOME:-/root/}

uuid=$(uuidgen || dbus-uuidgen)
IMAGE="public-release-builder:${uuid}"
docker build -t ${IMAGE} -f bin/tester.Dockerfile .

docker run --rm \
  -e "COMMIT_HASH=$(git rev-parse --short HEAD)" \
  -e "UPLOAD_NEW_PUBLIC_INSTALLER=${UPLOAD_NEW_PUBLIC_INSTALLER}" \
  -v "${JENKINS_USER_HOME}/.aws/credentials:/root/.aws/credentials" \
  -v "$(pwd):/k8s-installer/:rw" \
  ${IMAGE} \
  "/k8s-installer/bin/public-installer-releaser.sh"
