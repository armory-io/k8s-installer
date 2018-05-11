#!/bin/bash -e

NAMESPACE=${NAMESPACE:-armory}

deployments=$(kubectl -n ${NAMESPACE} get deployment -o name | tee)
for deployment in ${deployments[@]}; do
  kubectl -n ${NAMESPACE} rollout undo "${deployment}"
done
