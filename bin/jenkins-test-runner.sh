#!/bin/bash -x

cd "$(dirname "$0")/.."
JENKINS_HOME=${JENKINS_HOME:-/root/}

uuid=$(uuidgen || dbus-uuidgen)
IMAGE=k8s-installer-test-runner:${uuid}
docker build -t $IMAGE -f bin/tester.Dockerfile .

docker run --rm \
    -e GOOGLE_APPLICATION_CREDENTIALS="${HOME}/.kube/gcp_key.json" \
    -v "${JENKINS_HOME}/.aws/:/root/.aws/" \
    -v "${JENKINS_HOME}/.kube/:/root/.kube/:rw" \
    -v "$(pwd):/k8s-installer/:rw" \
    $IMAGE \
        /k8s-installer/bin/integration


#    -v "${JENKINS_HOME}/.aws/credentials:/root/.aws/credentials" \
#    -v "${JENKINS_HOME}/.kube/config:/root/.kube/config" \
#    -v "${JENKINS_HOME}/.kube/gcp_key.json:/root/.kube/gcp_key.json" \