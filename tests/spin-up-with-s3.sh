#!/bin/bash
set -x
set -e

cd "$(dirname "$0")"/../

#this allows for integration tests to be restarted if the namespace is the same

OS=$(uname)
if [ "$OS" == "Darwin" ]; then
  uuid=$(uuidgen)
else
  uuid=$(uuidgen || dbus-uuidgen)
fi

if [ -z ${NAMESPACE} ]; then
  export NAMESPACE=$(awk '{print tolower($0) }' <<< integration-test-$uuid)
fi

if [ -z ${ARMORY_CONF_STORE_BUCKET} ]; then
  export ARMORY_CONF_STORE_BUCKET=$(awk '{ print tolower($0) }' <<< integration-test-$uuid)
fi

export NOPROMPT=true
export AWS_PROFILE=dev
export CONFIG_STORE=S3
export KUBECONFIG="${HOME}/.kube/config"
export GOOGLE_APPLICATION_CREDENTIALS="${HOME}/.kube/gcp_key.json"
export KUBE_CONTEXT=gke_cloud-armory_us-central1-c_armory-kube
if [[ -z "${JENKINS_HOME}" ]]; then
  # not on jenkins
  export LB_TYPE=external
else
  # on jenkins
  export LB_TYPE=internal
fi
aws --profile "${AWS_PROFILE}" --region us-east-1 s3 mb "s3://${ARMORY_CONF_STORE_BUCKET}"

# unset fail fast so we can clean up our mess
set +e
bash -x src/install.sh
EXIT_CODE=$?
set -e

# cleanup
kubectl delete ns $NAMESPACE
aws --profile "${AWS_PROFILE}" --region us-east-1 s3 rb --force "s3://${ARMORY_CONF_STORE_BUCKET}"

exit $EXIT_CODE
