#!/usr/bin/env groovy

node {
  checkout scm

  stage('Testing') {
    sh('bin/jenkins-test-runner.sh')
  }

  stage('Upload version info to S3') {
    if (env.BRANCH_NAME == 'master') {
        sh('''
          export S3_PREFIX=
          arm build
        ''')
    } else {
      sh('''
          export S3_PREFIX=dev/
          arm build
        ''')
    }
  }
}
