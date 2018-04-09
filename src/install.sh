#!/bin/bash -e
cd "$(dirname "$0")"
if [ ! -z "${ARMORY_DEBUG}" ]; then
  set -x
fi

source version.manifest

export TMP_DIR=$(mktemp -d)
export NAMESPACE=armory
# export BUILD_DIR=$TMP_DIR/build/
export BUILD_DIR=build/
mkdir -p "$BUILD_DIR"
export KUBECTL_OPTIONS="--namespace=${NAMESPACE}"

function describe_installer() {
  echo "
  This installer will launch the Armory Platform into your Kubernetes cluster.
  The following are required:
    - AWS Credentials File
    - aws cli
    - kubectl and kubeconfig file
    - Docker
  The following will be created:
    - AWS S3 bucket to persist configuration
    - Kubernetes namespace 'armory'

Need help, advice, or just want to say hello during the installation?
Chat with our eng. team at http://go.Armory.io/chat.
Press 'Enter' key to continue. Ctrl+C to quit.
"
  read
}

function check_prereqs() {
  type aws >/dev/null 2>&1 || { error "I require aws but it's not installed. Ref: http://docs.aws.amazon.com/cli/latest/userguide/installing.html"; }
  type kubectl >/dev/null 2>&1 || { error "I require 'kubectl' but it's not installed. Ref: https://kubernetes.io/docs/tasks/tools/install-kubectl/"; }
}

function validate_profile() {
  local profile=${1}
  aws configure get ${profile}.aws_access_key_id &> /dev/null
  local result=$?
  if [ "$result" == "0" ]; then
    echo "Valid Profile selected."
  else
    echo "Could not find access key id for profile '${profile}'. Are you sure there is a profile with that name in your AWS credentials file?"
  fi
  return $result
}

function validate_kubeconfig() {
  local file=${1}
  if [ -z "$file" ]; then
    echo "Using default kubeconfig"
  else
    if [ -f "$file" ]; then
      echo "Found kubeconfig."
      export KUBECONFIG=${file}
      export KUBECTL_OPTIONS="${KUBECTL_OPTIONS} --kubeconfig=$file"
    else
      echo "Could not find file ${file}"
      return 1
    fi
  fi
  return 0
}

function get_var() {
  local text=$1
  local var_name="${2}"
  local val_func=${3}
  local val_list=${4}
  local default_val=${5}
  if [ -z ${!var_name} ]; then
    [ ! -z "$val_list" ] && $val_list
    echo -n "${text}"
    read value
    if [ -z "${value}" ]; then
      if [ -z "$default_val" ]; then
        echo "This value can not be blank."
        get_var "$1" $2 $3
      else
        echo "Using default ${default_val}"
        export ${var_name}=${default_val}
      fi
    elif [ ! -z "$val_func" ] && ! $val_func ${value}; then
      get_var "$1" $2 $3
    else
      export ${var_name}=${value}
    fi
  fi
}

function prompt_user() {
  get_var "Enter your AWS Profile [e.g. devprofile]: " AWS_PROFILE validate_profile
  get_var "Path to kubeconfig [if blank default will be used]: " KUBE_CONFIG validate_kubeconfig "" "~/.kube/config"
}

function make_s3_bucket() {
  echo "Creating S3 bucket to store configuration and persist data."
  export ARMORY_S3_PREFIX=front50
  if [ -z "${ARMORY_S3_BUCKET}" ]; then
    export ARMORY_S3_BUCKET=$(awk '{ print tolower($0) }' <<< armory-platform-$(uuidgen))
    aws --profile "${AWS_PROFILE}" s3 mb "s3://${ARMORY_S3_BUCKET}" --region us-west-1
  else
    echo "Using S3 bucket - ${ARMORY_S3_BUCKET}"
  fi
}

function create_k8s_namespace() {
  kubectl ${KUBECTL_OPTIONS} create namespace armory
}

function create_k8s_gate_load_balancer() {
  echo "Creating load balancer for the API Gateway."
  # TODO: envsubst is non-standard
  envsubst < manifests/gate-svc.json > ${BUILD_DIR}/gate-svc.json
  # Wait for IP
  kubectl ${KUBECTL_OPTIONS} apply -f ${BUILD_DIR}/gate-svc.json
  local IP=$(kubectl ${KUBECTL_OPTIONS} get services | grep gate | awk '{ print $4 }')
  echo -n "Waiting for load balancer to receive an IP..."
  while [ "$IP" == "<pending>" ] || [ -z "$IP" ]; do
    sleep 15
    local IP=$(kubectl ${KUBECTL_OPTIONS} get services | grep gate | awk '{ print $4 }')
    echo -n "."
  done
  echo "Found IP $IP"
  export GATE_IP=$IP
}

function create_k8s_deck_load_balancer() {
  echo "Creating load balancer for the Web UI."
  # TODO: envsubst is non-standard
  envsubst < manifests/deck-svc.json > ${BUILD_DIR}/deck-svc.json
  # Wait for IP
  kubectl ${KUBECTL_OPTIONS} apply -f ${BUILD_DIR}/deck-svc.json
  local IP=$(kubectl ${KUBECTL_OPTIONS} get services | grep deck | awk '{ print $4 }')
  echo -n "Waiting for load balancer to receive an IP..."
  while [ "$IP" == "<pending>" ] || [ -z "$IP" ]; do
    sleep 15
    local IP=$(kubectl ${KUBECTL_OPTIONS} get services | grep deck | awk '{ print $4 }')
    echo -n "."
  done
  echo "Found IP $IP"
  export DECK_IP=$IP
}

function create_k8s_svcs_and_rs() {
  for filename in manifests/*.json; do
    envsubst < "$filename" > "$BUILD_DIR/$(basename $filename)"
  done
  for filename in build/*.json; do
    kubectl ${KUBECTL_OPTIONS} apply -f "$filename"
  done
}

function create_k8s_default_config() {
  kubectl ${KUBECTL_OPTIONS} delete configmap default-config || true
  kubectl ${KUBECTL_OPTIONS} create configmap default-config --from-file=$(pwd)/config/default
}

function create_k8s_custom_config() {
  kubectl ${KUBECTL_OPTIONS} delete configmap config || true
  kubectl ${KUBECTL_OPTIONS} create configmap custom-config --from-file=$(pwd)/config/custom
}

function create_k8s_resources() {
  create_k8s_namespace
  create_k8s_gate_load_balancer
  create_k8s_deck_load_balancer
  create_k8s_default_config
  create_k8s_custom_config
  create_k8s_svcs_and_rs
}

function set_aws_vars() {
  role_arn=$(aws configure get ${AWS_PROFILE}.role_arn || true)
  if [[ "${role_arn}" == "" ]]; then
    export AWS_ACCESS_KEY_ID=$(aws configure get ${AWS_PROFILE}.aws_access_key_id)
    export AWS_SECRET_ACCESS_KEY=$(aws configure get ${AWS_PROFILE}.aws_secret_access_key)
  else
    #for more info on setting up your credentials file go here: http://docs.aws.amazon.com/cli/latest/topic/config-vars.html#using-aws-iam-roles
    source_profile=$(aws configure get ${AWS_PROFILE}.source_profile)
    temp_session_data=$(aws sts assume-role --role-arn ${role_arn} --role-session-name armory-spinnaker --profile ${source_profile} --output text)
    export AWS_ACCESS_KEY_ID=$(echo ${temp_session_data} | awk '{print $5}')
    export AWS_SECRET_ACCESS_KEY=$(echo ${temp_session_data} | awk '{print $7}')
    export AWS_SESSION_TOKEN=$(echo ${temp_session_data} | awk '{print $8}')
  fi
  export AWS_REGION=${TF_VAR_aws_region}
}

function encode_kubeconfig() {
  export B64KUBECONFIG=$(base64 "${KUBECONFIG}")
}

function encode_credentials() {
  set_aws_vars
  export B64CREDENTIALS=$(base64 <<EOF
[default]
aws_access_key_id=${AWS_ACCESS_KEY_ID}
aws_secret_access_key=${AWS_SECRET_ACCESS_KEY}
EOF
)
}

function output_results() {
cat <<EOF

Installation complete. You can access The Armory Platform via:

  http://${DECK_IP}

EOF
}

function main() {
  describe_installer
  check_prereqs
  prompt_user
  make_s3_bucket
  encode_credentials
  encode_kubeconfig
  create_k8s_resources
  output_results
}

main
