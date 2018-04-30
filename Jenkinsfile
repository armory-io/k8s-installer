#!/usr/bin/env groovy

node {
  checkout scm

  stage('Testing') {
    print('Nothing to test yet.')
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
