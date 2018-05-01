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

function create_kubeconf() {
  get_var "Enter path to cert file for the certificate authority: " CA_CERT
  get_var "Enter path to client certificate file for TLS: " CLIENT_CERT
  get_var "Enter path to client key file for TLS: " CLIENT_KEY
  get_var "Enter K8s API/master hostname or IP (eg: https://149.142.10.199): " SERVER_NAME
  get_var "Initial namespace to use (eg: tools): " NAMESPACE

  CA_CERT_DATA=$(cat $CA_CERT | base64)
  CLIENT_CERT_DATA=$(cat $CLIENT_CERT | base64)
  CLIENT_KEY_DATA=$(cat $CLIENT_KEY | base64)
  ARMORY_KUBECONF=$(mktemp -u /tmp/armory-kubeconf-XXXXXXXXXX)
  cat <<EOF > $ARMORY_KUBECONF
  apiVersion: v1
  clusters:
  - cluster:
      certificate-authority-data: ${CA_CERT_DATA}
      server: ${SERVER_NAME}
    name: armory-cluster
  contexts:
  - context:
      cluster: armory-cluster
      user: armory-user
    name: armory-context
  current-context: armory-context
  kind: Config
  preferences: {}
  users:
  - name: armory-user
    user:
      client-certificate-data: ${CLIENT_CERT_DATA}
      client-key-data: ${CLIENT_KEY_DATA}
EOF
}

function post_kubeconfig_to_lighthouse() {
  get_var "Enter gate URL for your spinnaker install (eg: http://spinnaker.tools.company.com:8084): " GATE_URL
  get_var "Enter account name to display in Spinnaker (eg: production): " ACCOUNT_NAME

  KUBECONF_B64=$(cat $ARMORY_KUBECONF | base64)
  DATA="{
    \"kubeconfig\": \"$KUBECONF_B64\",
    \"namespaces\": [\"$NAMESPACE\"],
    \"account_name\": \"$ACCOUNT_NAME\",
    \"is_service_account\": false
  }"

  curl -X POST -H "Content-Type: application/json" "$GATE_URL"/armory/v1/configs/accounts/kubernetes -d "$DATA"
}

function main() {
  cat <<EOF

  *****************************************************************************
  * This script will create a service account in the K8s cluster where apps   *
  * will be deployed, generate a kubconfig file using that service account    *
  * and post the file and the namespace to the armory platform                *
  *****************************************************************************

EOF
  create_kubeconf
  post_kubeconfig_to_lighthouse
}

main
