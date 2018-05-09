#!/bin/bash -xe
cd "$(dirname "$0")"

PUBLIC_ARMORY_JENKINS_JOB_VERSION=${PUBLIC_ARMORY_JENKINS_JOB_VERSION:-"lastSuccessfulBuild"}

echo "Querying ArmorySpinnaker's Jenkins Job for '${PUBLIC_ARMORY_JENKINS_JOB_VERSION}'"
arm jenkins "/job/armory/job/armoryspinnaker/job/master/${PUBLIC_ARMORY_JENKINS_JOB_VERSION}/artifact/src/spinnaker/version.manifest" > ../src/version.manifest
