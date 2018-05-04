#!/bin/bash -e
cd "$(dirname "$0")"
if [ ! -z "${ARMORY_DEBUG}" ]; then
  set -x
  set +e
fi

source version.manifest

export NAMESPACE=${NAMESPACE:-armory}
export BUILD_DIR=build/
export ARMORY_CONF_STORE_PREFIX=front50
# Start from a fresh build dir
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
export KUBECTL_OPTIONS="--namespace=${NAMESPACE}"

function describe_installer() {
  if [ ! -z "${NOPROMPT}" ]; then
    return
  fi
  echo "

  This installer will launch the Armory Platform into your Kubernetes cluster.
  The following are required:
    - An existing Kubernetes cluster.
    - S3, GCS, or Minio
    If using AWS:
      - AWS Credentials File
      - AWS CLI
    If using GCP:
      - GCP Credentials
      - gcloud sdk (gsutil in particular)
    - kubectl and kubeconfig file

  The following will be created:
    - AWS S3 bucket to persist configuration (If using S3)
    - GCP bucket to persist configuration (If using GCP)
    - Kubernetes namespace '${NAMESPACE}'
    - Service account in the Kubernetes cluster for redeploying the platform.

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
  type envsubst >/dev/null 2>&1 || { echo -e "I require 'envsubst' but it's not installed. Please install the 'gettext' package." 1>&2;
                                     echo -e "On Mac OS X, you can run:\n   brew install gettext && brew link --force gettext" 1>&2 && exit 1; }

  type jq >/dev/null 2>&1 || { echo -e "I require 'jq' but it's not installed. Please install the 'jq' package: https://stedolan.github.io/jq/download/" 1>&2;
                                     echo -e "On Mac OS X, you can run:\n   brew install jq && brew link --force jq" 1>&2 && exit 1; }
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
  elif [ "$1" == "MINIO" ]; then
    echo "MINIO selected as config store."
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

function validate_create_service_account() {
  if [[ "$1" != "y" ]] && [[ "$1" != "n" ]]; then
    echo "must input either 'y' or 'n'"
    return 1
  fi
  return 0
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
      if [ -z ${default_val+x} ]; then
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
  prompt_user_for_config_store
  get_var "${CONFIG_STORE} bucket to use [if blank, a bucket will be generated for you]: " ARMORY_CONF_STORE_BUCKET "" "" ""
  if [[ "$CONFIG_STORE" == "S3" ]]; then
    export S3_ENABLED=true
    export GCS_ENABLED=false
  cat <<EOF

  *****************************************************************************
  * We use an AWS profile from your ~/.aws/credentials file to access the S3  *
  * bucket during this installation. The associated credentials for the       *
  * profile will also be used to generate a secret in the k8s cluster called  *
  * 'aws-s3-credentials'. The platform will use those credentials while       *
  * running to persist data to S3.                                            *
  *                                                                           *
  * Notes:                                                                    *
  * 1. If you would like to create an AWS user/role specifically for this     *
  *    task, you can replace the k8s secret after the installation is         *
  *    complete.                                                              *
  * 2. The secret is formatted as a normal AWS credentials file.              *
  * 3. If the profile you specify is using assume role, the associated keys   *
  *    will expire. In that case please create a user/role and replace the    *
  *    secret.                                                                *
  *****************************************************************************

EOF
    get_var "Enter your AWS Profile [e.g. devprofile]: " AWS_PROFILE validate_profile
  elif [[ "$CONFIG_STORE" == "MINIO" ]]; then
    export S3_ENABLED=true
    export GCS_ENABLED=false
    export AWS_ACCESS_KEY_ID=""
    export AWS_SECRET_ACCESS_KEY=""
  cat <<EOF

  *****************************************************************************
  * Minio access key ID and secret access key are used to access the bucket   *
  * during the installation. The keys will be combined into a profile and     *
  * added to a secret in the k8s cluster called 'aws-s3-credentials'.         *
  *                                                                           *
  * Notes:                                                                    *
  * 1. If you would like to create a Minio user specifically for this         *
  *    task, you can replace the k8s secret after the installation is         *
  *    complete.                                                              *
  * 2. The secret is formatted as a normal AWS credentials file.              *
  *****************************************************************************

EOF
    get_var "Enter your minio access key: " AWS_ACCESS_KEY_ID
    get_var "Enter your minio secret key: " AWS_SECRET_ACCESS_KEY
    get_var "Enter your minio endpoint (ex: http://172.0.10.1:9000): " MINIO_ENDPOINT
    #this is a bit of hack until this gets https://github.com/spinnaker/front50/pull/308, check description of PR
    export ENDPOINT_PROPERTY="endpoint: ${MINIO_ENDPOINT}"
  elif [[ "$CONFIG_STORE" == "GCS" ]]; then
    export GCS_ENABLED=true
    export S3_ENABLED=false
    export GCP_CREDS_MNT_PATH="/home/spinnaker/.gcp/gcp.json"
    # get_var "Enter path to GCP service account creds: " GCP_CREDS validate_gcp_creds
  fi
  cat <<EOF
  *****************************************************************************
  * A kubeconfig file is needed to install The Armory Platform inside a       *
  * kubernetes cluster. The same kubeconfig file can also be added to the     *
  * cluster as a secret. Alternatively, we can create a service account in    *
  * the cluster to allow The Armory Platform to redeploy itself.              *
  *                                                                           *
  * Note: If you choose to add a kubeconfig to the cluster it must only have  *
  * one context. Specifically, context for the cluster where we are installing*
  *****************************************************************************

EOF
  get_var "Path to kubeconfig [if blank default will be used]: " KUBECONFIG validate_kubeconfig "" "${HOME}/.kube/config"
  get_var "Would you like us to use a service account? If not the kubeconfig file will be added to the cluster as a secret. [Y/n]: " CREATE_SERVICE_ACCOUNT validate_create_service_account "" "y"
  if [[ "$CREATE_SERVICE_ACCOUNT" == "y" ]]; then
    export USE_SERVICE_ACCOUNT=true
  else
    export USE_SERVICE_ACCOUNT=false
    export KUBECONFIG_CONFIG_ENTRY="kubeconfigFile: /opt/spinnaker/credentials/custom/default-kubeconfig"
    encode_kubeconfig
  fi
}

function prompt_user_for_config_store() {
  if [ ! -z $CONFIG_STORE ]; then
    return
  fi

  cat <<EOF

  *****************************************************************************
  * Configuration for the Armory Platform needs to be persisted to either S3, *
  * GCS, or Minio. This includes your pipeline configurations, deployment     *
  * target accounts, etc. We can create a storage bucket for you or you can   *
  * provide an already existing one.                                          *
  *****************************************************************************

EOF
  options=("S3" "GCS" "MINIO")
  echo "Which backing object store would you like to use for storing Spinnaker configs: "
  PS3='Enter choice: '
  select opt in "${options[@]}"
  do
    case $opt in
        "S3"|"GCS"|"MINIO")
            echo "Using $opt"
            export CONFIG_STORE="$opt"
            break
            ;;
        *) echo "Invalid option";;
    esac
  done
}


function select_kubectl_context() {
  if [ ! -z $KUBE_CONTEXT ]; then
      kubectl config use-context "${KUBE_CONTEXT}"
      return
  fi

  options=($(kubectl config get-contexts | awk '{print $2}' | grep -v NAME))
  if [ ${#options[@]} -eq 0 ]; then
      echo "It appears you do not have any K8s contexts in your KUBECONFIG file. Please refer to the docs to setup access to clusters:" 1>&2
      echo "https://kubernetes.io/docs/tasks/access-application-cluster/configure-access-multiple-clusters/"  1>&2
      exit 1
  else
    echo ""
    echo "Found the following K8s context(s) in you KUBECONFIG file: "
    PS3='Please select the one you want to use: '
    select opt in "${options[@]}"
    do
      kubectl config use-context "$opt"
      break
    done
  fi
}

function select_gcp_service_account_and_encode_creds() {
  export PROJECT_ID=$(gcloud config get-value core/project)
  export SERVICE_ACCOUNT_NAME="$(mktemp -u $NAMESPACE-svc-acct-XXXXXXXXXXXX | tr '[:upper:]' '[:lower:]' | cut -c 1-30)"
  mkdir -p ${BUILD_DIR}/credentials
  export GCP_CREDS="${BUILD_DIR}/credentials/service-account.json"

  cat <<EOF

  *****************************************************************************
  * During the installation the active GCP settings/account are used to       *
  * create and/or access the GCS bucket. After the installation, a GCP service*
  * account is used. If you already have a service account with access to the *
  * bucket, we can use it. Alternatively, we can create one for you.          *
  *****************************************************************************

EOF

  echo "Would you like to use an existing service account or create a new one?"
  PS3='Enter choice: '
  options=("Use existing" "Create new")
  select opt in "${options[@]}"
  do
    case $opt in
        "Use existing")
            accts=($(gcloud iam service-accounts list | awk '{print $NF}' | grep -v EMAIL))
            if [ ${#accts[@]} -eq 0 ]; then
                echo "Could not find any existing service account(s)" 1>&2
                exit 1
            else
              echo "Found the following service account(s):"
              PS3='Please select the one you want to use: '
              select acct in "${accts[@]}"
              do
                if [ -z "$acct" ]; then
                  echo "Invalid option"
                else
                  gcloud iam service-accounts keys create \
                    --iam-account "$acct" ${GCP_CREDS}
                  export B64CREDENTIALS=$(base64 -w 0 -i "$GCP_CREDS" 2>/dev/null || base64 -i "$GCP_CREDS")
                  break
                fi
              done
            fi
            break
            ;;
        "Create new")
            gcloud iam service-accounts create ${SERVICE_ACCOUNT_NAME} \
              --display-name "Armory GCS service account"
            gcloud projects add-iam-policy-binding ${PROJECT_ID} \
              --member="serviceAccount:${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
              --role='roles/storage.admin' > /dev/null 2>&1
            gcloud iam service-accounts keys create \
              --iam-account "${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
              ${GCP_CREDS} > /dev/null 2>&1
            export B64CREDENTIALS=$(base64 -w 0 -i "$GCP_CREDS" 2>/dev/null || base64 -i "$GCP_CREDS")
            break
            ;;
        *) echo "Invalid option";;
    esac
  done
}


function make_minio_bucket() {
  echo "Creating Minio bucket to store configuration and persist data."
  AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} aws s3 mb --endpoint-url ${MINIO_ENDPOINT} "s3://${ARMORY_CONF_STORE_BUCKET}"
}
function make_s3_bucket() {
  echo "Creating S3 bucket '${ARMORY_CONF_STORE_BUCKET}' to store configuration and persist data."
  aws --profile "${AWS_PROFILE}" --region us-east-1 s3 mb "s3://${ARMORY_CONF_STORE_BUCKET}"
}

function make_gcs_bucket() {
  echo "Found the following gcloud projects: "
  options=($(gcloud projects list | grep -v PROJECT_ID | awk '{print $1}'))
  PS3='Please select the project where you want to create the bucket: '
  select opt in "${options[@]}"
  do
    if [ ! -z "$opt" ]; then
      break
    else
      echo "Invalid Choice"
    fi
  done

  echo "Creating GCS bucket to store configuration and persist data."
  gsutil mb -p "$opt" "gs://${ARMORY_CONF_STORE_BUCKET}/"
}

function create_k8s_namespace() {
  if [ ! -z $SKIP_CREATE_NS ]; then
    return
  fi

  kubectl ${KUBECTL_OPTIONS} create namespace ${NAMESPACE} || { echo "If this is not the first time you have ran this installer, a previous run might have created a namespace. If so, please manually delete it by running 'kubectl delete namespace ${NAMESPACE}'. " 1>&2 && exit 1; }
}

function create_k8s_nginx_load_balancer() {
  echo "Creating load balancer for the Web UI."
  envsubst < manifests/nginx-svc.json > ${BUILD_DIR}/nginx-svc.json
  # Wait for IP
  kubectl ${KUBECTL_OPTIONS} apply -f ${BUILD_DIR}/nginx-svc.json
  local IP=$(kubectl ${KUBECTL_OPTIONS} get services | grep nginx | awk '{ print $4 }')
  echo -n "Waiting for load balancer to receive an IP..."
  while [ "$IP" == "<pending>" ] || [ -z "$IP" ]; do
    sleep 5
    local IP=$(kubectl ${KUBECTL_OPTIONS} get services | grep nginx | awk '{ print $4 }')
    echo -n "."
  done
  echo "Found IP $IP"
  export NGINX_IP=$IP
}

function create_k8s_svcs_and_rs() {
  cat <<EOF

  *****************************************************************************
  * Creating k8s resources. This includes 'deployments', 'services',          *
  * 'config-maps' and 'secrets'.                                              *
  *****************************************************************************

EOF
  export custom_credentials_secret_name="custom-credentials"
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
  cp "config/custom/nginx.conf" "${BUILD_DIR}/config/custom/nginx.conf"
  for filename in config/custom/*.yml; do
    envsubst < $filename > ${BUILD_DIR}/config/custom/$(basename $filename)
  done
  # dump to a file to upload to S3. Used when we deploy, we use dry-run to accomplish this
  kubectl ${KUBECTL_OPTIONS} create configmap custom-config \
    -o json \
    --dry-run \
    --from-file=${BUILD_DIR}/config/custom | jq '. + {kind:"ConfigMap",apiVersion:"v1" }' \
    > ${BUILD_DIR}/config/custom/custom-config.json

  kubectl ${KUBECTL_OPTIONS} apply -f ${BUILD_DIR}/config/custom/custom-config.json

  local config_file="${BUILD_DIR}/config/custom/custom-config.json"
  if [[ "${CONFIG_STORE}" == "S3" ]]; then
    aws --profile "${AWS_PROFILE}" --region us-east-1 s3 cp \
      "${config_file}" \
      "s3://${ARMORY_CONF_STORE_BUCKET}/front50/config_v2/config.json"
  elif [[ "${CONFIG_STORE}" == "MINIO" ]]; then
    AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} aws s3 cp \
      --endpoint-url=${MINIO_ENDPOINT} "${config_file}" "s3://${ARMORY_CONF_STORE_BUCKET}/front50/config_v2/config.json"
  elif [[ "${CONFIG_STORE}" == "GCS" ]]; then
    gsutil cp "${config_file}" "gs://${ARMORY_CONF_STORE_BUCKET}/front50/config_v2/config.json"
  fi
}

function upload_custom_credentials() {
  local credentials_manifest="${BUILD_DIR}/custom-credentials.json"
  if [[ "${CONFIG_STORE}" == "S3" ]]; then
    aws --profile "${AWS_PROFILE}" --region us-east-1 s3 cp \
      "${credentials_manifest}" \
      "s3://${ARMORY_CONF_STORE_BUCKET}/front50/secrets/custom-credentials.json"
  elif [[ "${CONFIG_STORE}" == "MINIO" ]]; then
    AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} aws s3 cp \
      --endpoint-url=${MINIO_ENDPOINT} "${credentials_manifest}" "s3://${ARMORY_CONF_STORE_BUCKET}/front50/secrets/custom-credentials.json"
  elif [[ "${CONFIG_STORE}" == "GCS" ]]; then
    gsutil cp "${credentials_manifest}" "gs://${ARMORY_CONF_STORE_BUCKET}/front50/secrets/custom-credentials.json"
  fi
}

function create_k8s_resources() {
  create_k8s_namespace
  create_k8s_nginx_load_balancer
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

function encode_credentials() {
  if [[ "$CONFIG_STORE" == "S3" ]]; then
      set_aws_vars
  fi
  #both MINIO and S3 can use the same credentials file since we'll use the S3 protocol
  if [[ "$CONFIG_STORE" == "S3" || "$CONFIG_STORE" == "MINIO" ]]; then

      export CREDENTIALS_FILE="[default]
aws_access_key_id=${AWS_ACCESS_KEY_ID}
aws_secret_access_key=${AWS_SECRET_ACCESS_KEY}
"
      export B64CREDENTIALS=$(base64 -w 0 <<< "${CREDENTIALS_FILE}" 2>/dev/null || base64 <<< "${CREDENTIALS_FILE}")
  elif [[ "$CONFIG_STORE" == "GCS" ]]; then
    select_gcp_service_account_and_encode_creds
  fi
}

function encode_kubeconfig() {
  B64KUBECONFIG=$(base64 -w 0 "${KUBECONFIG}" 2>/dev/null || base64 "${KUBECONFIG}")
  export KUBECONFIG_ENTRY_IN_SECRETS_FILE="\"default-kubeconfig\": \"${B64KUBECONFIG}\""
}

function output_results() {
cat <<EOF

Installation complete. You can access The Armory Platform via:

  http://${NGINX_IP}

Your configuration has been stored in the ${CONFIG_STORE} bucket:

  ${ARMORY_CONF_STORE_BUCKET}

EOF
}

function create_upgrade_pipeline() {

  cat <<EOF

  *****************************************************************************
  * After the installation is complete, a re-deploy pipeline will be provided *
  * You can find it by navigating the Web UI URL (provided later), selecting  *
  * 'Applications' from the top navigation bar, click on 'armory', then click *
  * on 'Pipelines'. You should see a pipeline called 'Deploy'. It can be used *
  * to both upgrade and redeploy after a configuration change.                *
  *****************************************************************************

EOF
  echo "Creating..."

  export custom_credentials_secret_name=$(echo -ne \${\#stage\(\'Deploy Credentials\'\)[\'context\'][\'artifacts\'][0][\'reference\']})

  mkdir -p ${BUILD_DIR}/pipeline
  for filename in manifests/*-deployment.json; do
    envsubst < "$filename" > "$BUILD_DIR/pipeline/pipeline-$(basename $filename)"
  done

  if [[ "${S3_ENABLED}" == "true" ]]; then
    export CONFIG_ARTIFACT_URI=s3://${ARMORY_CONF_STORE_BUCKET}/front50/config_v2/config.json
    export SECRET_ARTIFACT_URI=s3://${ARMORY_CONF_STORE_BUCKET}/front50/secrets/custom-credentials.json
    export ARTIFACT_KIND=s3
    export ARTIFACT_ACCOUNT=armory-config-s3-account
  elif [[ "${GCS_ENABLED}" == "true" ]]; then
    export CONFIG_ARTIFACT_URI=gs://${ARMORY_CONF_STORE_BUCKET}/front50/config_v2/config.json
    export SECRET_ARTIFACT_URI=gs://${ARMORY_CONF_STORE_BUCKET}/front50/secrets/custom-credentials.json
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
        "name": "${CONFIG_ARTIFACT_URI}",
        "reference": "${CONFIG_ARTIFACT_URI}",
        "type": "${ARTIFACT_KIND}/object"
      },
      "id": "ced981ba-4bf5-41e2-8ee0-07209f79d190",
      "matchArtifact": {
        "kind": "${ARTIFACT_KIND}",
        "name": "${CONFIG_ARTIFACT_URI}",
        "type": "${ARTIFACT_KIND}/object"
      },
      "useDefaultArtifact": true,
      "usePriorExecution": false
    },
    {
      "defaultArtifact": {
        "kind": "default.${ARTIFACT_KIND}",
        "name": "${SECRET_ARTIFACT_URI}",
        "reference": "${SECRET_ARTIFACT_URI}",
        "type": "${ARTIFACT_KIND}/object"
      },
      "id": "ced981ba-4bf5-41e2-8ee0-07209f79d191",
      "matchArtifact": {
        "kind": "${ARTIFACT_KIND}",
        "name": "${SECRET_ARTIFACT_URI}",
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
      "account": "kubernetes",
      "cloudProvider": "kubernetes",
      "manifestArtifactAccount": "${ARTIFACT_ACCOUNT}",
      "manifestArtifactId": "ced981ba-4bf5-41e2-8ee0-07209f79d191",
      "moniker": {
        "app": "armory",
        "cluster": "custom-credentials"
      },
      "name": "Deploy Credentials",
      "refId": "12",
      "relationships": {
        "loadBalancers": [],
        "securityGroups": []
      },
      "requisiteStageRefIds": [],
      "source": "artifact",
      "type": "deployManifest"
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
      "requisiteStageRefIds": ["1", "12"],
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
      "requisiteStageRefIds": ["1", "12"],
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
      "requisiteStageRefIds": ["1", "12"],
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
      "requisiteStageRefIds": ["1", "12"],
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
      "requisiteStageRefIds": ["1", "12"],
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
      "requisiteStageRefIds": ["1", "12"],
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
      "requisiteStageRefIds": ["1", "12"],
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
      "requisiteStageRefIds": ["1", "12"],
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
      "requisiteStageRefIds": ["1", "12"],
      "source": "text",
      "type": "deployManifest"
    }
  ]
}
EOF
  echo "Waiting for the API gateway to become ready. This may take several minutes."
  counter=0
  while true; do
        if [ `curl -s -m 3 http://${NGINX_IP}/api/applications` ]; then
          #we issue a --fail because if it's a 400 curl still returns an exit of 0 without it.
          http_code=$(curl -s -o /dev/null -w %{http_code} -X POST -d@${BUILD_DIR}/pipeline/pipeline.json -H "Content-Type: application/json" "http://${NGINX_IP}/api/pipelines")
          if [[ "$http_code" -lt "200" || "$http_code" -gt "399" ]]; then
            echo "Received a error code from pipeline curl request: $http_code"
            exit 10
          else
            break
          fi
        fi
        if [ "$counter" -gt 200 ]; then
            echo "ERROR: Timeout occurred waiting for http://${NGINX_IP}/api/applications to become available"
            exit 2
        fi
        counter=$((counter+1))
        echo -n "."
        sleep 2
  done
}

function set_profile_small() {
  export CLOUDDRIVER_CPU="100m"
  export DECK_CPU="100m"
  export ECHO_CPU="100m"
  export FRONT50_CPU="100m"
  export GATE_CPU="100m"
  export IGOR_CPU="100m"
  export LIGHTHOUSE_CPU="100m"
  export ORCA_CPU="100m"
  export REDIS_CPU="100m"
  export ROSCO_CPU="100m"
  export NGINX_CPU="100m"
  export CLOUDDRIVER_MEMORY="128Mi"
  export DECK_MEMORY="128Mi"
  export ECHO_MEMORY="128Mi"
  export FRONT50_MEMORY="128Mi"
  export GATE_MEMORY="128Mi"
  export IGOR_MEMORY="128Mi"
  export LIGHTHOUSE_MEMORY="128Mi"
  export ORCA_MEMORY="128Mi"
  export REDIS_MEMORY="128Mi"
  export ROSCO_MEMORY="128Mi"
  export NGINX_MEMORY="64Mi"
}

function set_profile_medium() {
  export CLOUDDRIVER_CPU="1000m"
  export DECK_CPU="500m"
  export ECHO_CPU="500m"
  export FRONT50_CPU="500m"
  export GATE_CPU="500m"
  export IGOR_CPU="500m"
  export LIGHTHOUSE_CPU="500m"
  export ORCA_CPU="1000m"
  export REDIS_CPU="500m"
  export ROSCO_CPU="500m"
  export NGINX_CPU="200m"
  export CLOUDDRIVER_MEMORY="2Gi"
  export DECK_MEMORY="512Mi"
  export ECHO_MEMORY="512Mi"
  export FRONT50_MEMORY="1Gi"
  export GATE_MEMORY="1Gi"
  export IGOR_MEMORY="1Gi"
  export LIGHTHOUSE_MEMORY="512Mi"
  export ORCA_MEMORY="2Gi"
  export REDIS_MEMORY="2Gi"
  export ROSCO_MEMORY="1Gi"
  export NGINX_MEMORY="128Mi"
}

function set_profile_large() {
  export CLOUDDRIVER_CPU="2000m"
  export DECK_CPU="1000m"
  export ECHO_CPU="1000m"
  export FRONT50_CPU="1000m"
  export GATE_CPU="1000m"
  export IGOR_CPU="1000m"
  export LIGHTHOUSE_CPU="500m"
  export ORCA_CPU="2000m"
  export REDIS_CPU="1000m"
  export ROSCO_CPU="1000m"
  export NGINX_CPU="500m"
  export CLOUDDRIVER_MEMORY="8Gi"
  export DECK_MEMORY="512Mi"
  export ECHO_MEMORY="1Gi"
  export FRONT50_MEMORY="2Gi"
  export GATE_MEMORY="2Gi"
  export IGOR_MEMORY="2Gi"
  export LIGHTHOUSE_MEMORY="512Mi"
  export ORCA_MEMORY="4Gi"
  export REDIS_MEMORY="16Gi"
  export ROSCO_MEMORY="1Gi"
  export NGINX_MEMORY="256Mi"
}

function set_custom_profile() {
  cpu_vars=("CLOUDDRIVER_CPU" "DECK_CPU" "ECHO_CPU" "FRONT50_CPU" "GATE_CPU" "IGOR_CPU" "LIGHTHOUSE_CPU" "ORCA_CPU" "REDIS_CPU" "ROSCO_CPU")
  for v in "${cpu_vars[@]}"; do
    echo "What allocation would you like for $v?"
    options=("500m" "1000m" "1500m" "2000m" "2500m")
    PS3="Enter choice: "
    select opt in "${options[@]}"
    do
      case $opt in
          "500m"|"1000m"|"1500m"|"2000m"|"2500m")
              echo "Setting $v to $opt"
              export "$v"="$opt"
              break
              ;;
          *) echo "Invalid option";;
      esac
    done
  done
  mem_vars=("CLOUDDRIVER_MEMORY" "DECK_MEMORY" "ECHO_MEMORY" "FRONT50_MEMORY" "GATE_MEMORY" "IGOR_MEMORY" "LIGHTHOUSE_MEMORY" "ORCA_MEMORY" "REDIS_MEMORY" "ROSCO_MEMORY")
  for v in "${mem_vars[@]}"; do
    echo "What allocation would you like for $v?"
    options=("512Mi" "1Gi" "2Gi" "4Gi" "8Gi" "16Gi")
    PS3="Enter choice: "
    select opt in "${options[@]}"
    do
      case $opt in
          "512Mi"|"1Gi"|"2Gi"|"4Gi"|"8Gi"|"16Gi")
              echo "Setting $v to $opt"
              export "$v"="$opt"
              break
              ;;
          *) echo "Invalid option";;
      esac
    done
  done
}


function set_resources() {
  if [ ! -z ${NOPROMPT} ]; then
    set_profile_small
    return
  fi

  cat <<EOF

  ******************************************************************************************
  * The Armory Platform can be installed with 4 different resource                         *
  * configurations. Which one you choose will be dependent on your expected                *
  * load. For explanation of the units for CPU & MEMORY, please refer to:                  *
  * https://kubernetes.io/docs/concepts/configuration/manage-compute-resources-container/  *
  * NOTE: the cluster should have nodes with enough resources to accommodate each          *
  * microservice's CPU/MEMORY requirements, else the pods might become "unschedulable"     *
  ******************************************************************************************

EOF
  echo ""
  echo "  'Small'"
  echo "       CPU: 100m per microservice"
  echo "       MEMORY: 128Mi per microservice"
  echo "       Total CPU: 1600m (1.6 vCPUs)"
  echo "       Total MEMROY: 2048Mi (~2 GB)"
  echo ""
  echo "  'Medium'"
  echo "       CPU: 500m for deck, echo, front50, gate, igor, lighthouse, redis & rosco"
  echo "            1000m for clouddriver & orca"
  echo "       MEMORY: 512Mi for deck, echo, lighthouse & rosco"
  echo "               1Gi for front50, gate, igor & rosco"
  echo "               2Gi for clouddriver, orca & redis"
  echo "       Total CPU: 10000m (10 vCPUs)"
  echo "       Total MEMROY: 18.5Gi (~19.86 GB)"
  echo ""
  echo "  'Large'"
  echo "       CPU: 500m for lighthouse"
  echo "            1000m for deck, echo, front50, gate, igor, redis & rosco"
  echo "            2000m for clouddriver & orca"
  echo "       MEMORY: 521Mi for deck & lighthouse"
  echo "               1Gi for echo & rosco"
  echo "               2Gi for front50, gate & igor"
  echo "               4Gi for orca"
  echo "               16Gi for redis"
  echo "       Total CPU: 19500m (19.5 vCPUs)"
  echo "       Total MEMROY: 28.5Gi (~30.6 GB)"
  echo ""
  echo "  'Custom'"
  echo "       You enter the CPU/MEMORY for each microservice"
  echo ""

  options=("Small" "Medium" "Large" "Custom")
  PS3='Which profile would you like to use: '
  select opt in "${options[@]}"
  do
    case $opt in
        "Small")
            echo "Using profile: 'Small'"
            set_profile_small
            break
            ;;
        "Medium")
            echo "Using profile: 'Medium'"
            set_profile_medium
            break
            ;;
        "Large")
            echo "Using profile: 'Large'"
            set_profile_large
            break
            ;;
        "Custom")
            echo "Using profile: 'Custom'"
            set_custom_profile
            break
            ;;
        *) echo "Invalid option";;
    esac
  done
}

function set_lb_type() {
  if [ ! -z $LB_TYPE ]; then
    return
  fi
  cat <<EOF

  *****************************************************************************
  * When the Armory Platform runs it uses two load balancers. One for the API *
  * gateway and one to serve the Web UI. Depending on how your network is     *
  * configured, you will want these load balancers to either be 'internal' or *
  * 'external'. After installation, it is also recommended that you configure *
  * a firewall rule or security group to only allow access to whitelisted IPs.*
  *****************************************************************************

EOF
  echo "Load balancer types [defaults to 'Internal']: "
  options=("Internal" "External")
  PS3='Select the LB type you want to use: '
  select opt in "${options[@]}"
  do
    case $opt in
        "Internal"|"External")
            export LB_TYPE="$opt"
            echo "Using LB type: $opt"
            break
            ;;
        *) echo "Invalid option";;
    esac
  done
}

function make_bucket() {
  if [[ "$ARMORY_CONF_STORE_BUCKET" == "" ]]; then
    export ARMORY_CONF_STORE_BUCKET=$(awk '{ print tolower($0) }' <<< ${NAMESPACE}-platform-$(uuidgen) | cut -c 1-51)
    if [ "$CONFIG_STORE" == "S3" ]; then
      make_s3_bucket
    elif [ "$CONFIG_STORE" == "GCS" ]; then
      make_gcs_bucket
    elif [ "$CONFIG_STORE" == "MINIO" ]; then
      make_minio_bucket
    fi
  else
    echo "Using existing bucket: $ARMORY_CONF_STORE_BUCKET"
  fi
}

function main() {
  describe_installer
  prompt_user
  check_prereqs
  select_kubectl_context
  set_lb_type
  set_resources
  make_bucket
  encode_credentials
  create_k8s_resources
  upload_custom_credentials
  create_upgrade_pipeline
  output_results
}

main
