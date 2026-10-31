// Lab 1: jenkins-static-site-deploy - now using the ci-labs shared library (Lab 6).
// GitHub push -> Jenkins -> validate -> package -> upload release -> atomic symlink switch
// -> verify live release (automatic rollback if verification fails).
// Documentation-only changes (README, docs/, *.md) skip the deploy unless FORCE_DEPLOY is ticked.

@Library('ci-labs@v1.0.0') _

pipeline {
  agent any

  options {
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '20'))
    timeout(time: 10, unit: 'MINUTES')
  }

  triggers {
    githubPush()
  }

  parameters {
    choice(name: 'ACTION', choices: ['deploy', 'rollback'],
           description: 'deploy = release this commit; rollback = switch back to the previous release')
    booleanParam(name: 'FORCE_DEPLOY', defaultValue: false,
                 description: 'Deploy even if only documentation changed')
  }

  environment {
    SITE_ROOT     = '/var/www/static-site'
    SITE_PORT     = '8083'
    KEEP_RELEASES = '5'
  }

  stages {
    stage('Preflight') {
      steps {
        script {
          labPreflight(vars: ['APP_HOST'])
          env.RELEASE = labRelease()
          String action = params.ACTION ?: 'deploy'
          boolean docsOnly = action == 'deploy' && !params.FORCE_DEPLOY && labDocsOnly()
          env.DO_DEPLOY = (action == 'deploy' && !docsOnly) ? 'true' : 'false'
          currentBuild.displayName = "#${env.BUILD_NUMBER} ${docsOnly ? 'docs-only' : action}"
          currentBuild.description = docsOnly ? 'documentation change: deploy skipped'
                                   : (action == 'deploy' ? "release ${env.RELEASE}" : 'rollback')
          labSsh(command: 'echo "connected to $(hostname -s) as $(whoami)"')
        }
      }
    }

    stage('Validate') {
      when { expression { env.DO_DEPLOY == 'true' } }
      steps {
        sh '''
          test -s site/index.html || { echo "site/index.html is missing"; exit 1; }
          grep -qi "<title>" site/index.html || { echo "site/index.html has no <title>"; exit 1; }
          if grep -rIlE --exclude-dir=.git -e "-----BEGIN [A-Z ]*PRIVATE KEY-----" . ; then
            echo "Refusing to deploy: a private key is committed in the file(s) above"
            exit 1
          fi
          echo "validation passed"
        '''
      }
    }

    stage('Package') {
      when { expression { env.DO_DEPLOY == 'true' } }
      steps {
        sh '''
          rm -rf build release.tgz
          mkdir -p build
          cp -a site/. build/
          {
            echo "release=$RELEASE"
            echo "commit=${GIT_COMMIT:-unknown}"
            echo "built=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
          } > build/BUILD.txt
          tar -C build -czf release.tgz .
          ls -l release.tgz
        '''
      }
    }

    stage('Deploy') {
      when { expression { env.DO_DEPLOY == 'true' } }
      steps {
        script {
          String dir = "${env.SITE_ROOT}/releases/${env.RELEASE}"
          labSsh(command: "mkdir -p ${labShellQuote(dir)} && tar -xzf - -C ${labShellQuote(dir)}",
                 stdin: 'release.tgz', label: 'upload release')
          labSsh(script: 'scripts/activate_release.sh',
                 args: [env.SITE_ROOT, env.RELEASE, env.KEEP_RELEASES], label: 'activate release')
        }
      }
    }

    stage('Verify') {
      when { expression { env.DO_DEPLOY == 'true' } }
      steps {
        script {
          String expected = "release=${env.RELEASE}"
          boolean live = false
          for (int attempt = 1; attempt <= 5 && !live; attempt++) {
            String body = labSsh(command: "curl -fsS http://localhost:${env.SITE_PORT}/BUILD.txt || true",
                                 returnStdout: true, label: "verify attempt ${attempt}")
            live = ("\n" + body + "\n").contains("\n" + expected + "\n")
            if (!live) {
              sleep(time: 2, unit: 'SECONDS')
            }
          }
          if (!live) {
            echo 'verification FAILED - rolling back to the previous release'
            labSsh(script: 'scripts/rollback_release.sh', args: [env.SITE_ROOT], label: 'automatic rollback')
            error("release ${env.RELEASE} did not go live")
          }
          echo "verified: release ${env.RELEASE} is live on port ${env.SITE_PORT}"
        }
      }
    }

    stage('Rollback') {
      when { expression { (params.ACTION ?: 'deploy') == 'rollback' } }
      steps {
        script {
          labSsh(script: 'scripts/rollback_release.sh', args: [env.SITE_ROOT], label: 'rollback')
        }
      }
    }
  }

  post {
    always {
      sh 'rm -rf build release.tgz'
    }
  }
}
