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
    export KUBECTL_OPTIONS="--certificate-authority=$CA_CERT $KUBECTL_OPTIONS"
  fi
  get_var "Enter path to client certificate file for TLS: " CLIENT_CERT
  if [ ! -z "$CLIENT_CERT" ]; then
    export KUBECTL_OPTIONS="--client-certificate=$CLIENT_CERT $KUBECTL_OPTIONS"
  fi
  get_var "Enter path to client key file for TLS: " CLIENT_KEY
  if [ ! -z "$CLIENT_KEY" ]; then
    export KUBECTL_OPTIONS="--client-key=$CLIENT_KEY $KUBECTL_OPTIONS"
  fi
  get_var "Enter K8s API/master hostname or IP (eg: https://146.148.69.252): " SERVER_NAME
  if [ ! -z "$SERVER_NAME" ]; then
    export KUBECTL_OPTIONS="--server=$SERVER_NAME $KUBECTL_OPTIONS"
  fi

  kubectl ${KUBECTL_OPTIONS} create serviceaccount "$SERVICE_ACCOUNT_NAME"
}

function generate_kubeconfig() {
  export B64_KUBE_CONF="$(mktemp -u kubeconf-XXXXXXX)"
  get_var "Enter the K8s context you want to use: " CONTEXT
  get_var "Enter the K8s cluster you want to use: " CLUSTER
  if [ ! -z "$CONTEXT" ]; then
    ./create-kubeconfig "$SERVICE_ACCOUNT_NAME" "$CONTEXT" "$CLUSTER" "$KUBECTL_OPTIONS" | base64 > "$B64_KUBE_CONF"
  fi
}

function post_kubeconfig_to_lighthouse() {
  get_var "Enter gate URL for your spinnaker install (eg: http://spinnaker.company.com:8084): " GATE_URL

  DATA="{
    \"kubeconfig\": \"$(cat $B64_KUBE_CONF)\",
    \"namespace\": [\"$NAMESPACE\"],
    \"name\": \"$CLUSTER\"
  }"
  echo "Posting: $DATA"
  set -x
  curl -X POST "$GATE_URL"/armory/v1/configs/accounts/kubernetes -d "$DATA"
  rm -rf "$B64_KUBE_CONF"
}

function main() {
  cat <<EOF

  *****************************************************************************
  * This script will create a service account in the K8s cluster where apps   *
  * will be deployed, generate a kubconfig file using that service account    *
  * and post the file and the namespace to the armory platform                *
  *****************************************************************************

EOF
  create_service_acct
  generate_kubeconfig
  post_kubeconfig_to_lighthouse
}

main
