#!/bin/bash -x

cd "$(dirname "$0")/.."
JENKINS_USER_HOME=${JENKINS_USER_HOME:-/root/}

uuid=$(uuidgen || dbus-uuidgen)
IMAGE=k8s-installer-test-runner:${uuid}
docker build -t $IMAGE -f bin/tester.Dockerfile .

docker run --rm \
    -e GOOGLE_APPLICATION_CREDENTIALS="${HOME}/.kube/gcp_key.json" \
    -v "${JENKINS_USER_HOME}/.aws/credentials:/root/.aws/credentials" \
    -v "${JENKINS_USER_HOME}/.kube/config:/root/.kube/config" \
    -v "${JENKINS_USER_HOME}/.kube/gcp_key.json:/root/.kube/gcp_key.json" \
    -v "$(pwd):/k8s-installer/:rw" \
    $IMAGE \
        /k8s-installer/bin/integration


#    -v "${JENKINS_USER_HOME}/.aws/credentials:/root/.aws/credentials" \
#    -v "${JENKINS_USER_HOME}/.kube/config:/root/.kube/config" \
#    -v "${JENKINS_USER_HOME}/.kube/gcp_key.json:/root/.kube/gcp_key.json" \
#    -v "${JENKINS_USER_HOME}/.aws/:/root/.aws/" \
#    -v "${JENKINS_USER_HOME}/.kube/:/root/.kube/:rw" \