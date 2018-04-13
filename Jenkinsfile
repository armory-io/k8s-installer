#!/usr/bin/env groovy

node {
  checkout scm

  stage('Testing') {
    print('Nothing to test yet.')
  }

  if (env.BRANCH_NAME == 'master') {
    stage('Upload version info to S3') {
      sh('arm build')
    }
  }
}
