#!/bin/bash -x

cd "$(dirname "$0")/.."
uuid=$(uuidgen || dbus-uuidgen)
IMAGE=k8s-installer-test-runner:${uuid}
docker build -t $IMAGE -f bin/tester.Dockerfile .

docker run --rm \
    -v /root/.aws/credentials:/root/.aws/credentials \
    -v /root/.kube/config:/root/.kube/config \
    -v "$(pwd):/k8s-installer/" \
    $IMAGE \
        /k8s-installer/bin/integration