#!/bin/bash -e
cd "$(dirname "$0")"
if [ ! -z "${ARMORY_DEBUG}" ]; then
  set -x
  set +e
fi

export DOCKER_REGISTRY=${DOCKER_REGISTRY:-docker.io/armory}
export DOCKER_IMAGE="${DOCKER_REGISTRY}/k8s-installer:latest"

#makes a scratch dir
mkdir -p ${HOME}/.armory/

docker run \
    --rm -i -t  \
    -e USER_HOME=${HOME} \
    -e ARMORY_DEBUG=1 \
    -v ${HOME}/.aws/credentials:/root/.aws/credentials \
    -v ${HOME}/.armory/:/root/.armory/ \
    $DOCKER_IMAGE /src/install.sh
