#!/bin/bash -e
cd "$(dirname "$0")"

rm -rf ../src/build || true
mkdir -p ../src/build/

ARMORYSPINNAKER_JENKINS_JOB_ID=${ARMORYSPINNAKER_JENKINS_JOB_ID:-"lastSuccessfulBuild"}

echo "Querying ArmorySpinnaker's Jenkins Job for '${ARMORYSPINNAKER_JENKINS_JOB_ID}'"
arm jenkins "/job/armory/job/armoryspinnaker/job/master/${ARMORYSPINNAKER_JENKINS_JOB_ID}/artifact/src/spinnaker/version.manifest" >> ../src/build/armoryspinnaker-jenkins-version.manifest
source ../src/build/armoryspinnaker-jenkins-version.manifest
echo "Found ArmorySpinnaker v${armoryspinnaker_version} at ${packager_version}, build number ${jenkins_build_number}."
