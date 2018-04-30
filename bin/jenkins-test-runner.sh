#!/bin/bash -x

cd "$(dirname "$0")/.."
uuid=$(uuidgen || dbus-uuidgen)
IMAGE=(k8s-installer-test-runner:${uuid}
docker build -t $IMAGE -f bin/tester.Dockerfile .

docker run --rm -ti -v /root/:/root/ -v "$(pwd):/k8s-installer" $IMAGE /k8s-installer/integration