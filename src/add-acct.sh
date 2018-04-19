#!/bin/bash -e

cd "$(dirname "$0")"
if [ ! -z "${ARMORY_DEBUG}" ]; then
  set -x
fi

export NAMESPACE=${NAMESPACE:-armory}
export KUBECTL_OPTIONS="--namespace=${NAMESPACE}"
export LIGHTHOUSE_URL="http://spinnaker.dev.armory.io:5000"

function error() {
  >&2 echo $1
  exit 1
}

function get_var() {
  local text=$1
  local var_name="${2}"
  local val_func=${3}
  local val_list=${4}
  local default_val="${5}"
  if [ -z ${!var_name} ]; then
    [ ! -z "$val_list" ] && $val_list
    echo -n "${text}"
    read value
    if [ -z "${value}" ]; then
      echo "Not using ${var_name}"
    elif [ ! -z "$val_func" ] && ! $val_func ${value}; then
      get_var "$1" $2 $3
    else
      export ${var_name}=${value}
    fi
  fi
}

function create_service_acct() {
  export SERVICE_ACCOUNT_NAME="$(mktemp -u armory-svc-acct-XXXXXXXXXXXX | tr '[:upper:]' '[:lower:]')"

  get_var "Enter path to cert file for the certificate authority: " CA_CERT
  if [ ! -z "$CA_CERT" ]; then
    KUBECTL_OPTIONS="--certificate-authority=$CERT_PATH $KUBECTL_OPTIONS"
  fi
  get_var "Enter path to client certificate file for TLS: " CLIENT_CERT
  if [ ! -z "$CLIENT_KEY" ]; then
    KUBECTL_OPTIONS="--client-key=$CLIENT_CERT $KUBECTL_OPTIONS"
  fi
  get_var "Enter path to client key file for TLS: " CLIENT_KEY
  if [ ! -z "$CLIENT_KEY" ]; then
    KUBECTL_OPTIONS="--client-key=$CLIENT_KEY $KUBECTL_OPTIONS"
  fi

  kubectl ${KUBECTL_OPTIONS} create serviceaccount "$SERVICE_ACCOUNT_NAME"
}

function generate_kubeconfig() {
  export KUBE_CONF="$(mktemp -u kubeconf-XXXXXXX)"  # DO NOT call this var KUBECONFIG!!
  ./create-kubeconfig "$SERVICE_ACCOUNT_NAME" "$KUBECTL_OPTIONS" > "$KUBE_CONF"
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
  curl -X POST "$LIGHTHOUSE_URL"/v1/configs/accounts/kubernetes -d @"$KUBE_CONF"
  rm -rf "$KUBE_CONF"
}

main
