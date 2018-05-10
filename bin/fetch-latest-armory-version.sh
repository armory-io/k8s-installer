#!/bin/bash -e
cd "$(dirname "$0")"

PUBLIC_ARMORY_JENKINS_JOB_VERSION=${PUBLIC_ARMORY_JENKINS_JOB_VERSION:-"lastSuccessfulBuild"}

echo "Querying ArmorySpinnaker's Jenkins Job for '${PUBLIC_ARMORY_JENKINS_JOB_VERSION}'"

cat <<EOF > ../src/version.manifest
## INFO: this file has been created as an untracked file so that the installer can run idempotently with pinned versions below.
## Committing this file means you'll be pinning the installer with the versions listed below.
##
## To fetch the latest stable/edge versions of Armory, see:
##   ./src/install.sh --help

EOF
arm jenkins "/job/armory/job/armoryspinnaker/job/master/${PUBLIC_ARMORY_JENKINS_JOB_VERSION}/artifact/src/spinnaker/version.manifest" >> ../src/version.manifest
source ../src/version.manifest
echo "Found ArmorySpinnaker v${armoryspinnaker_version} at ${packager_version}, build number ${jenkins_build_number}."
