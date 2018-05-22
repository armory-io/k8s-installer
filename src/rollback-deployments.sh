#!/bin/bash -e
cd "$(dirname "$0")"

NAMESPACE=${NAMESPACE:-armory}
kubectl -n ${NAMESPACE} rollout undo deployment
