#!/usr/bin/env groovy

properties(
  [
    parameters([
      string(name: 'ARMORYSPINNAKER_JENKINS_JOB_ID', defaultValue: '',
        description: """Optional. Set this to test the ArmorySpinnaker version against the installer
        This is a Jenkins job id that looks like:
        lastSuccessfulBuild or 1864"""
      ),

      string(name: 'RELEASE_ARMORY_VERSION_IF_PASSING', defaultValue: 'false',
        description: """Optional. Set this if we're releasing this version of ArmorySpinnaker to the world."""
      ),

      string(name: 'RELEASE_INSTALLER_ONLY', defaultValue: 'false',
        description: """Optional. Set this if we're releasing only the installer."""
      ),
    ])
  ]
)

node {
  checkout scm

  if (params.ARMORYSPINNAKER_JENKINS_JOB_ID != '') {
    stage('Fetch latest Armory version') {
      sh("""
      ./bin/fetch-latest-armory-version.sh
      mv src/version.manifest src/build/pinned-version.manifest
      cp src/build/armoryspinnaker-jenkins-version.manifest src/version.manifest   # use edge as base pin
      cat src/build/pinned-version.manifest >> src/version.manifest   # apply any pins on top
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

  // Since we've provided ARMORYSPINNAKER_JENKINS_JOB_ID, and tests pass successfully, we'll upload manifest as
  // "latest" so that public people can pull it down and use it.
  if (env.BRANCH_NAME == 'master' && params.RELEASE_ARMORY_VERSION_IF_PASSING == 'true') {
    stage('Promote latest Armory version') {
      sh('''
          ./bin/promote-latest-armory-version.sh
        ''')
    }
  }

  if (env.BRANCH_NAME == 'master') {
    stage('Promote latest Armory version') {
      sh('''
          UPLOAD_NEW_PUBLIC_INSTALLER=true ./bin/jenkins-public-installer-releaser.sh
        ''')
    }
  }
}
