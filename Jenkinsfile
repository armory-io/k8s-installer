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

  if (params.PUBLIC_ARMORY_JENKINS_JOB_VERSION != '') {
    stage('Fetch latest Armory version') {
      sh("""
      ./bin/fetch-latest-armory-version.sh
    """)
    }
  }

  stage('Testing') {
    def runner = { testName ->
      return {
        sh "export TEST_NAME=$testName ; bin/jenkins-test-runner.sh"
      }
    }
    def tests = [
      "Install backed by S3": runner("spin-up-with-s3.sh"),
      "TODO: Install backed by GCS": runner("spin-up-with-gcs.sh")
    ]
    parallel tests
  }

  stage('Upload version info to S3') {
    if (env.BRANCH_NAME == 'master') {
        sh('''
          export S3_PREFIX=/
          arm build
        ''')
    } else {
      sh('''
          export S3_PREFIX=/dev/
          arm build
        ''')
    }
  }

  // Since we've provided PUBLIC_ARMORY_JENKINS_JOB_VERSION, and tests pass successfully, we'll upload manifest as
  // "latest" so that public people can pull it down and use it.
  if (params.RELEASE_ARMORY_VERSION_IF_PASSING != 'true') {
    stage('Promote latest Armory version') {
      sh('''
          ./bin/promote-latest-armory-version.sh
        ''')
    }
  }
}
