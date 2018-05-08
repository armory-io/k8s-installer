#!/bin/bash -xe
cd "$(dirname "$0")"

ARMORY_JENKINS_JOB_ID=${ARMORY_JENKINS_JOB_ID:-"lastSuccessfulBuild"}

echo "Querying ArmorySpinnaker's Jenkins Job for '${ARMORY_JENKINS_JOB_ID}'"
arm jenkins "/job/armory/job/armoryspinnaker/job/master/${ARMORY_JENKINS_JOB_ID}/artifact/src/spinnaker/version.manifest" > ../src/version.manifest
