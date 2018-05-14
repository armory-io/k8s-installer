#!/bin/bash -xe
cd "$(dirname "$0")"
UPLOAD=${UPLOAD:-true}
SET_AS_LATEST=${SET_AS_LATEST:-true}

COMMIT_HASH=$(git rev-parse --short HEAD)

# This will pin the latest stable version.manifest so that the script will always run with
# the same version of version.manifest.
echo "Fetching latest stable to src/build/version.manifest..."
curl -sS "https://s3-us-west-2.amazonaws.com/armory-web/install/release/armoryspinnaker-latest-version.manifest" >> ../src/build/armoryspinnaker-latest-version.manifest
source ../src/build/armoryspinnaker-latest-version.manifest

curl -sS "${armoryspinnaker_version_manifest_url}" >> ../src/version.manifest
source ../src/version.manifest


INSTALLER_TAR_NAME="kubernetes-installer-${COMMIT_HASH}-armory-v${armoryspinnaker_version}.tgz"
echo "Creating ${INSTALLER_TAR_NAME} with Armory v${armoryspinnaker_version}"
tar --exclude="src/build" -cvzf "${INSTALLER_TAR_NAME}" -C ".." src/

echo "Uploading installer tar"
INSTALLER_ARTIFACT_PATH="armory-web/install/release/${INSTALLER_TAR_NAME}"
aws s3 cp --acl public-read-write ${INSTALLER_TAR_NAME} "s3://${INSTALLER_ARTIFACT_PATH}"
export KUBERNETES_INSTALLER_LATEST_ARTIFACT_URL="https://s3-us-west-2.amazonaws.com/${INSTALLER_ARTIFACT_PATH}"

# We're going hard code the version directly into to the script, so it'll be idempotent.
# This allows user's to always have the correct version, and there's no "moving target" issues
# that potentially could happen with using the "latest" pointers.
VARS_TO_REPLACE='$KUBERNETES_INSTALLER_LATEST_ARTIFACT_URL' # to add more, do "$VAR1:$VAR2"
envsubst "${VARS_TO_REPLACE}" < ../src/public-installer.sh > ../src/build/public-installer.sh
#sed -e "s/KUBERNETES_INSTALLER_LATEST_ARTIFACT_URL/${KUBERNETES_INSTALLER_LATEST_ARTIFACT_URL}/" ../src/public-installer.sh > ../src/build/public-installer.sh


if [[ ${UPLOAD} == 'true' ]]; then
  echo "Uploading public installer"
  aws s3 cp --acl public-read-write ../src/build/public-installer.sh "s3://armory-web/install/release/kubernetes-installer/public-installer.sh"
  # TODO invalidate cloudfront cache for this file
fi
