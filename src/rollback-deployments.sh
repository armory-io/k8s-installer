#!/bin/bash -e
cd "$(dirname "$0")"

NAMESPACE=${NAMESPACE:-armory}

for deploymentFileName in manifests/*-deployment.json; do
  filename=$(basename -- "${deploymentFileName}")
  filename="${filename%.*}"
  serviceName="${filename%-deployment}"
  kubectl -n ${NAMESPACE} rollout undo deployment "${serviceName}"
done
