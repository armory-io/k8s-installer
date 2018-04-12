#!/bin/bash -e
cd "$(dirname "$0")"
if [ ! -z "${ARMORY_DEBUG}" ]; then
  set -x
fi

source version.manifest

export TMP_DIR=$(mktemp -d)
export NAMESPACE=${NAMESPACE:-armory}
# export BUILD_DIR=$TMP_DIR/build/
export BUILD_DIR=build/
mkdir -p "$BUILD_DIR"
export KUBECTL_OPTIONS="--namespace=${NAMESPACE}"

function describe_installer() {
  echo "
  This installer will launch the Armory Platform into your Kubernetes cluster.
  The following are required:
    If using AWS:
      - AWS Credentials File
      - aws cli
    If using GCP:
      - GCP Credentials
      - gcloud sdk (gsutil in particular)
    - kubectl and kubeconfig file
    - Docker
  The following will be created:
    - AWS S3 bucket to persist configuration (If using S3)
    - GCP bucket to persist configuration (If using GCP)
    - Kubernetes namespace '${NAMESPACE}'

Need help, advice, or just want to say hello during the installation?
Chat with our eng. team at http://go.Armory.io/chat.
Press 'Enter' key to continue. Ctrl+C to quit.
"
  read
}

function error() {
  >&2 echo $1
  exit 1
}

function check_kubectl_version() {
  version=$(kubectl version help | grep "^Client Version" | sed 's/^.*GitVersion:"v\([0-9\.v]*\)".*$/\1/')
  version_major=$(echo $version | cut -d. -f1)
  version_minor=$(echo $version | cut -d. -f2)

  if [ $version_major -lt 1 ] || [ $version_minor -lt 8 ]; then
    error "I require 'kubectl' version 1.8.x or higher. Ref: https://kubernetes.io/docs/tasks/tools/install-kubectl/"
  fi
}

function check_prereqs() {
  if [[ "$CONFIG_STORE" == "S3" ]]; then
    type aws >/dev/null 2>&1 || { echo "I require aws but it's not installed. Ref: http://docs.aws.amazon.com/cli/latest/userguide/installing.html" 1>&2 && exit 1; }
  fi
  type kubectl >/dev/null 2>&1 || { echo "I require 'kubectl' but it's not installed. Ref: https://kubernetes.io/docs/tasks/tools/install-kubectl/" 1>&2 && exit 1; }
  check_kubectl_version
  if [[ "$CONFIG_STORE" == "GCS" ]]; then
    type gsutil >/dev/null 2>&1 || { echo "I require 'gsutil' but it's not installed. Ref: https://cloud.google.com/storage/docs/gsutil_install#sdk-install" 1>&2 && exit 1; }
  fi
  type envsubst >/dev/null 2>&1 || { echo "I require 'envsubst' but it's not installed. Please install the 'gettext' package." 1>&2;
                                     echo "On Mac OS X, you can run: 'brew install gettext && brew link --force gettext'" 1>&2 && exit 1; }
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

function validate_config_store() {
  if [ "$1" == "GCS" ]; then
    echo "GCS selected as config store."
  elif [ "$1" == "S3" ]; then
    echo "S3 selected as config store."
  else
    echo "Config store has to be one of GCS or S3" 1>&2
    return 1
  fi
  return 0
}

function validate_gcp_creds() {
  # might need more robust validation of creds
  if [ ! -f "$1" ]; then
    echo "$1 does not exist!" 1>&2
    return 1
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
  get_var "Do you want to persist config data in S3 or GCS [defaults to S3]: " CONFIG_STORE validate_config_store "" "S3"
  if [[ "$CONFIG_STORE" == "S3" ]]; then
    export S3_ENABLED=true
    export GCS_ENABLED=false
    get_var "Enter your AWS Profile [e.g. devprofile]: " AWS_PROFILE validate_profile
  elif [[ "$CONFIG_STORE" == "GCS" ]]; then
    export GCS_ENABLED=true
    export S3_ENABLED=false
    export GCP_CREDS_MNT_PATH="/root/.gcp/gcp.json"
    get_var "Enter path to GCP service account creds: " GCP_CREDS validate_gcp_creds
  fi
  get_var "Path to kubeconfig [if blank default will be used]: " KUBECONFIG validate_kubeconfig "" "${HOME}/.kube/config"

}

function make_s3_bucket() {
  echo "Creating S3 bucket to store configuration and persist data."
  export ARMORY_CONF_STORE_PREFIX=front50
  if [ -z "${ARMORY_CONF_STORE_BUCKET}" ]; then
    export ARMORY_CONF_STORE_BUCKET=$(awk '{ print tolower($0) }' <<< armory-platform-$(uuidgen))
    aws --profile "${AWS_PROFILE}" --region us-east-1 s3 mb "s3://${ARMORY_CONF_STORE_BUCKET}"
  else
    echo "Using S3 bucket - ${ARMORY_CONF_STORE_BUCKET}"
  fi
}

function make_gcs_bucket() {
  echo "Creating GCS bucket to store configuration and persist data."
  if [ -z "${ARMORY_CONF_STORE_BUCKET}" ]; then
    export ARMORY_CONF_STORE_BUCKET=$(awk '{ print tolower($0) }' <<< armory-platform-$(uuidgen))
    gsutil mb "gs://${ARMORY_CONF_STORE_BUCKET}/"
  else
    echo "Using GCS bucket - ${ARMORY_CONF_STORE_BUCKET}"
  fi
}

function create_k8s_namespace() {
  kubectl ${KUBECTL_OPTIONS} create namespace ${NAMESPACE}
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
    sleep 5
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
    sleep 5
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
    echo "Applying $filename..."
    kubectl ${KUBECTL_OPTIONS} apply -f "$filename"
  done
}

function create_k8s_default_config() {
  kubectl ${KUBECTL_OPTIONS} create configmap default-config --from-file=$(pwd)/config/default
}

function create_k8s_custom_config() {
  mkdir -p ${BUILD_DIR}/config/custom/
  for filename in config/custom/*.yml; do
    envsubst < $filename > ${BUILD_DIR}/config/custom/$(basename $filename)
  done
  kubectl ${KUBECTL_OPTIONS} create configmap custom-config --from-file=${BUILD_DIR}/config/custom
  # dump to a file to upload to S3. Used when we re-deploy
  kubectl ${KUBECTL_OPTIONS} get cm custom-config -o json > ${BUILD_DIR}/config/custom/custom-config.json
  if [[ "${S3_ENABLED}" == "true" ]]; then
    aws --profile "${AWS_PROFILE}" --region us-east-1 s3 cp \
      "${BUILD_DIR}/config/custom/custom-config.json" \
      "s3://${ARMORY_CONF_STORE_BUCKET}/front50/config_v2/config.json"
  elif [[ "${GCS_ENABLED}" == "true" ]]; then
    # TODO: upload to GCS
    echo "TODO - should load custom-config.json to GCS"
  fi
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
  export AWS_REGION=us-east-1
}

function encode_kubeconfig() {
  export B64KUBECONFIG=$(base64 "${KUBECONFIG}")
}

function encode_credentials() {
  if [[ "$CONFIG_STORE" == "S3" ]]; then
      set_aws_vars
      export B64CREDENTIALS=$(base64 <<EOF
[default]
aws_access_key_id=${AWS_ACCESS_KEY_ID}
aws_secret_access_key=${AWS_SECRET_ACCESS_KEY}
EOF
)
  elif [[ "$CONFIG_STORE" == "GCS" ]]; then
    export B64CREDENTIALS=$(base64 -i "$GCP_CREDS")

  fi
}

function output_results() {
cat <<EOF

Installation complete. You can access The Armory Platform via:

  http://${DECK_IP}

EOF
}

function create_upgrade_pipeline() {
  export packager_version=$(echo -ne \${\#stage\(\'Fetch latest version\'\)[\'context\'][\'webhook\'][\'body\'][\'packager_version\']})
  export armoryspinnaker_version=$(echo -ne \${\#stage\(\'Fetch latest version\'\)[\'context\'][\'webhook\'][\'body\'][\'armoryspinnaker_version\']})
  export fiat_version=$(echo -ne \${\#stage\(\'Fetch latest version\'\)[\'context\'][\'webhook\'][\'body\'][\'fiat_version\']})
  export front50_version=$(echo -ne \${\#stage\(\'Fetch latest version\'\)[\'context\'][\'webhook\'][\'body\'][\'front50_version\']})
  export igor_version=$(echo -ne \${\#stage\(\'Fetch latest version\'\)[\'context\'][\'webhook\'][\'body\'][\'igor_version\']})
  export rosco_version=$(echo -ne \${\#stage\(\'Fetch latest version\'\)[\'context\'][\'webhook\'][\'body\'][\'rosco_version\']})
  export clouddriver_version=$(echo -ne \${\#stage\(\'Fetch latest version\'\)[\'context\'][\'webhook\'][\'body\'][\'clouddriver_version\']})
  export orca_version=$(echo -ne \${\#stage\(\'Fetch latest version\'\)[\'context\'][\'webhook\'][\'body\'][\'orca_version\']})
  export lighthouse_version=$(echo -ne \${\#stage\(\'Fetch latest version\'\)[\'context\'][\'webhook\'][\'body\'][\'lighthouse_version\']})
  export barometer_version=$(echo -ne \${\#stage\(\'Fetch latest version\'\)[\'context\'][\'webhook\'][\'body\'][\'barometer_version\']})
  export dinghy_version=$(echo -ne \${\#stage\(\'Fetch latest version\'\)[\'context\'][\'webhook\'][\'body\'][\'dinghy_version\']})
  export platform_version=$(echo -ne \${\#stage\(\'Fetch latest version\'\)[\'context\'][\'webhook\'][\'body\'][\'platform_version\']})
  export kayenta_version=$(echo -ne \${\#stage\(\'Fetch latest version\'\)[\'context\'][\'webhook\'][\'body\'][\'kayenta_version\']})
  export gate_armory_version=$(echo -ne \${\#stage\(\'Fetch latest version\'\)[\'context\'][\'webhook\'][\'body\'][\'gate_armory_version\']})
  export gate_version=$(echo -ne \${\#stage\(\'Fetch latest version\'\)[\'context\'][\'webhook\'][\'body\'][\'gate_version\']})
  export echo_armory_version=$(echo -ne \${\#stage\(\'Fetch latest version\'\)[\'context\'][\'webhook\'][\'body\'][\'echo_armory_version\']})
  export echo_version=$(echo -ne \${\#stage\(\'Fetch latest version\'\)[\'context\'][\'webhook\'][\'body\'][\'echo_version\']})
  export deck_armory_version=$(echo -ne \${\#stage\(\'Fetch latest version\'\)[\'context\'][\'webhook\'][\'body\'][\'deck_armory_version\']})
  export deck_version=$(echo -ne \${\#stage\(\'Fetch latest version\'\)[\'context\'][\'webhook\'][\'body\'][\'deck_version\']})

  mkdir -p ${BUILD_DIR}/pipeline
  for filename in manifests/*-deployment.json; do
    envsubst < "$filename" > "$BUILD_DIR/pipeline/pipeline-$(basename $filename)"
  done

  # TODO: the s3/gcs substitutions below are probably wrong.
  if [[ "${S3_ENABLED}" == "true" ]]; then
    export ARTIFACT_URI=s3://${ARMORY_CONF_STORE_BUCKET}/front50/config_v2/config.json
    export ARTIFACT_KIND=s3
    export ARTIFACT_ACCOUNT=armory-config-s3-account
  elif [[ "${GCS_ENABLED}" == "true" ]]; then
    export ARTIFACT_URI=gs://${ARMORY_CONF_STORE_BUCKET}/front50/config_v2/config.json
    export ARTIFACT_KIND=gcs
    export ARTIFACT_ACCOUNT=armory-config-gcs-account
  else
    error "Either S3 or GCS must be enabled."
  fi

cat <<EOF > ${BUILD_DIR}/pipeline/pipeline.json
{
  "application": "armory",
  "name": "Deploy",
  "keepWaitingPipelines": false,
  "limitConcurrent": true,
  "expectedArtifacts": [
    {
      "defaultArtifact": {
        "kind": "default.${ARTIFACT_KIND}",
        "name": "${ARTIFACT_URI}",
        "reference": "${ARTIFACT_URI}",
        "type": "${ARTIFACT_KIND}/object"
      },
      "id": "ced981ba-4bf5-41e2-8ee0-07209f79d190",
      "matchArtifact": {
        "kind": "${ARTIFACT_KIND}",
        "name": "${ARTIFACT_URI}",
        "type": "${ARTIFACT_KIND}/object"
      },
      "useDefaultArtifact": true,
      "usePriorExecution": false
    }
  ],
  "stages": [
      {
        "account": "kubernetes",
        "cloudProvider": "kubernetes",
        "manifestArtifactAccount": "${ARTIFACT_ACCOUNT}",
        "manifestArtifactId": "ced981ba-4bf5-41e2-8ee0-07209f79d190",
        "moniker": {
          "app": "armory",
          "cluster": "custom-config"
        },
        "name": "Deploy Config",
        "refId": "1",
        "relationships": {
          "loadBalancers": [],
          "securityGroups": []
        },
        "requisiteStageRefIds": [],
        "source": "artifact",
        "type": "deployManifest"
      },
      {
        "method": "GET",
        "name": "Fetch latest version",
        "refId": "2",
        "requisiteStageRefIds": [],
        "statusUrlResolution": "getMethod",
        "type": "webhook",
        "url": "https://get.armory.io/k8s-latest.json",
        "waitForCompletion": false
    },
    {
        "account": "kubernetes",
        "cloudProvider": "kubernetes",
        "manifests": [
            $(cat ${BUILD_DIR}/pipeline/pipeline-rosco-deployment.json)
        ],
        "moniker": {
            "app": "armory",
            "cluster": "rosco"
        },
        "name": "Deploy Rosco",
        "refId": "10",
        "requisiteStageRefIds": ["2", "1"],
        "source": "text",
        "type": "deployManifest"
    },
    {
        "account": "kubernetes",
        "cloudProvider": "kubernetes",
        "manifests": [
            $(cat ${BUILD_DIR}/pipeline/pipeline-clouddriver-deployment.json)
        ],
        "moniker": {
            "app": "armory",
            "cluster": "clouddriver"
        },
        "name": "Deploy clouddriver",
        "refId": "11",
        "requisiteStageRefIds": ["2", "1"],
        "source": "text",
        "type": "deployManifest"
    },
    {
        "account": "kubernetes",
        "cloudProvider": "kubernetes",
        "manifests": [
            $(cat ${BUILD_DIR}/pipeline/pipeline-deck-deployment.json)
        ],
        "moniker": {
            "app": "armory",
            "cluster": "deck"
        },
        "name": "Deploy deck",
        "refId": "3",
        "requisiteStageRefIds": ["2", "1"],
        "source": "text",
        "type": "deployManifest"
    },
    {
        "account": "kubernetes",
        "cloudProvider": "kubernetes",
        "manifests": [
            $(cat ${BUILD_DIR}/pipeline/pipeline-echo-deployment.json)
        ],
        "moniker": {
            "app": "armory",
            "cluster": "echo"
        },
        "name": "Deploy echo",
        "refId": "4",
        "requisiteStageRefIds": ["2", "1"],
        "source": "text",
        "type": "deployManifest"
    },
    {
        "account": "kubernetes",
        "cloudProvider": "kubernetes",
        "manifests": [
            $(cat ${BUILD_DIR}/pipeline/pipeline-front50-deployment.json)
        ],
        "moniker": {
            "app": "armory",
            "cluster": "front50"
        },
        "name": "Deploy front50",
        "refId": "5",
        "requisiteStageRefIds": ["2", "1"],
        "source": "text",
        "type": "deployManifest"
    },
    {
        "account": "kubernetes",
        "cloudProvider": "kubernetes",
        "manifests": [
            $(cat ${BUILD_DIR}/pipeline/pipeline-gate-deployment.json)
        ],
        "moniker": {
            "app": "armory",
            "cluster": "gate"
        },
        "name": "Deploy gate",
        "refId": "6",
        "requisiteStageRefIds": ["2", "1"],
        "source": "text",
        "type": "deployManifest"
    },
    {
        "account": "kubernetes",
        "cloudProvider": "kubernetes",
        "manifests": [
            $(cat ${BUILD_DIR}/pipeline/pipeline-igor-deployment.json)
        ],
        "moniker": {
            "app": "armory",
            "cluster": "igor"
        },
        "name": "Deploy igor",
        "refId": "7",
        "requisiteStageRefIds": ["2", "1"],
        "source": "text",
        "type": "deployManifest"
    },
    {
        "account": "kubernetes",
        "cloudProvider": "kubernetes",
        "manifests": [
            $(cat ${BUILD_DIR}/pipeline/pipeline-lighthouse-deployment.json)
        ],
        "moniker": {
            "app": "armory",
            "cluster": "lighthouse"
        },
        "name": "Deploy lighthouse",
        "refId": "8",
        "requisiteStageRefIds": ["2", "1"],
        "source": "text",
        "type": "deployManifest"
    },
    {
        "account": "kubernetes",
        "cloudProvider": "kubernetes",
        "manifests": [
            $(cat ${BUILD_DIR}/pipeline/pipeline-orca-deployment.json)
        ],
        "moniker": {
            "app": "armory",
            "cluster": "orca"
        },
        "name": "Deploy orca",
        "refId": "9",
        "requisiteStageRefIds": ["2", "1"],
        "source": "text",
        "type": "deployManifest"
    }
  ]
}
EOF
  echo "Waiting for the API gateway to become ready. This may take several minutes."
  counter=0
  while true; do
        if [ `curl -s -m 3 http://${GATE_IP}:8084/applications` ]; then
          #we issue a --fail because if it's a 400 curl still returns an exit of 0 without it.
          http_code=$(curl -s -o /dev/null -w %{http_code} -X POST -d@${BUILD_DIR}/pipeline/pipeline.json -H "Content-Type: application/json" "http://${GATE_IP}:8084/pipelines")
          if [[ "$http_code" -lt "200" || "$http_code" -gt "399" ]]; then
            echo "Received a error code from pipeline curl request: $http_code"
            exit 10
          else
            break
          fi
        fi
        if [ "$counter" -gt 30 ]; then
            echo "ERROR: Timeout occurred waiting for http://${GATE_IP}:8084/applications to become available"
            exit 2
        fi
        counter=$((counter+1))
        echo -n "."
        sleep 2
  done
}

function main() {
  describe_installer
  prompt_user
  check_prereqs
  if [[ "$CONFIG_STORE" == "S3" ]]; then
    make_s3_bucket
  else
    make_gcs_bucket
  fi
  encode_credentials
  encode_kubeconfig
  create_k8s_resources
  create_upgrade_pipeline
  output_results
}

main
