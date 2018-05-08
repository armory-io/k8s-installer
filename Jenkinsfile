#!/usr/bin/env groovy

properties(
  [
    parameters([
      string(name: 'PUBLIC_ARMORY_JENKINS_JOB_VERSION', defaultValue: '',
        description: "Optional. Use to explicitly set the version of Armory platform to make public using Jenkins job id." +
        "ex: lastSuccessfulBuild or 1864"
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

  if (params.PUBLIC_ARMORY_JENKINS_JOB_VERSION != '') {
    stage('Promote latest Armory version') {
      sh('''
          ./bin/promote-latest-armory-version.sh
        ''')
    }
  }
}
