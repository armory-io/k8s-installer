#!/usr/bin/env groovy

properties(
  [
    parameters([
      string(name: 'PUBLIC_ARMORY_JENKINS_JOB_VERSION', defaultValue: '',
        description: """Optional. Set this to test the ArmorySpinnaker version against the installer
        This is a Jenkins job id that looks like:
        lastSuccessfulBuild or 1864"""
      ),

      string(name: 'RELEASE_ARMORY_VERSION_IF_PASSING', defaultValue: '',
        description: """Optional. Set this if we're releasing this version of ArmorySpinnaker to the world."""
      ),
    ]),
    disableConcurrentBuilds(),
  ]
)

node {
  checkout scm

  sh ('git commit -m "hello"  && git push')
}
