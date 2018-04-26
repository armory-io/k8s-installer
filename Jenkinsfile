#!/usr/bin/env groovy

node {
  checkout scm

  stage('Testing') {
    sh('arm integration')
  }

  if (env.BRANCH_NAME == 'master') {
    stage('Upload version info to S3') {
      sh('arm build')
    }
  }
}
