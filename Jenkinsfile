#!/usr/bin/env groovy

node {
  checkout scm

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
}
