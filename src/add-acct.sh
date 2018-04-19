#!/bin/bash -e

cd "$(dirname "$0")"
if [ ! -z "${ARMORY_DEBUG}" ]; then
  set -x
fi

export NAMESPACE=${NAMESPACE:-armory}
export KUBECTL_OPTIONS="--namespace=${NAMESPACE}"

function error() {
  >&2 echo $1
  exit 1
}

function prompt_user_for_certs() {
  echo -n "Enter path to $1: "
  read ca_cert

  openssl rsa -in "$ca_cert" -check -noout
  if [ "$?" != 0 ]; then
    error "$1 cert not valid"
  fi
  export CERT_PATH="$ca_cert"
}

function create_service_acct() {
  export SERVICE_ACCOUNT_NAME="$(mktemp -u armory-svc-acct-XXXXXXXXXXXX | tr '[:upper:]' '[:lower:]')"
  #prompt_user_for_certs "CA cert for the K8s cluster"

  if [ ! -z "$CERT_PATH" ]; then
    KUBECTL_OPTIONS="--certificate-authority=$CERT_PATH $KUBECTL_OPTIONS"
  fi
  kubectl ${KUBECTL_OPTIONS} create serviceaccount "$SERVICE_ACCOUNT_NAME"
}

function generate_kubeconfig() {
  ./create-kubeconfig "$SERVICE_ACCOUNT_NAME" "$KUBECTL_OPTIONS"
}

function main() {
  cat <<EOF

  *****************************************************************************
  * This script will create a service account in the K8s cluster where apps   *
  * will be deployed, generate a kubconfig file using that service account    *
  * and post the file and the namespace to lighthouse                         *
  *****************************************************************************

EOF
  create_service_acct
  generate_kubeconfig
}

main
