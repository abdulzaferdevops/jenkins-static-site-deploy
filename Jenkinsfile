// Lab 1: jenkins-static-site-deploy
// GitHub push -> Jenkins -> validate -> package -> upload release -> atomic symlink switch
// -> verify live release (automatic rollback if verification fails).
//
// One-time Jenkins setup (see README):
//   - Credential  'app-server-deploy'  (SSH username with private key, user 'deploy')
//   - Global environment variable  APP_HOST  = private IP of the app server
//   - App server host key in the Jenkins user's ~/.ssh/known_hosts

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
  }

  environment {
    SITE_ROOT     = '/var/www/static-site'
    SITE_PORT     = '8083'
    KEEP_RELEASES = '5'
    SSH_OPTS      = '-o BatchMode=yes -o ConnectTimeout=10'
  }

  stages {
    stage('Preflight') {
      steps {
        script {
          if (!env.APP_HOST?.trim()) {
            error('APP_HOST is not set: Manage Jenkins > System > Global properties > Environment variables')
          }
          env.RELEASE = sh(
            script: 'printf "%05d-%s" "$BUILD_NUMBER" "$(echo "${GIT_COMMIT:-manual}" | cut -c1-7)"',
            returnStdout: true
          ).trim()
          currentBuild.displayName = "#${env.BUILD_NUMBER} ${params.ACTION}"
          currentBuild.description = (params.ACTION == 'deploy') ? "release ${env.RELEASE}" : 'rollback'
        }
        sshagent(credentials: ['app-server-deploy']) {
          sh '''ssh $SSH_OPTS deploy@$APP_HOST 'echo "connected to $(hostname -s) as $(whoami)"' '''
        }
      }
    }

    stage('Validate') {
      when { expression { params.ACTION == 'deploy' } }
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
      when { expression { params.ACTION == 'deploy' } }
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
      when { expression { params.ACTION == 'deploy' } }
      steps {
        sshagent(credentials: ['app-server-deploy']) {
          sh '''
            ssh $SSH_OPTS deploy@$APP_HOST "mkdir -p $SITE_ROOT/releases/$RELEASE && tar -xzf - -C $SITE_ROOT/releases/$RELEASE" < release.tgz
            ssh $SSH_OPTS deploy@$APP_HOST bash -s -- "$SITE_ROOT" "$RELEASE" "$KEEP_RELEASES" < scripts/activate_release.sh
          '''
        }
      }
    }

    stage('Verify') {
      when { expression { params.ACTION == 'deploy' } }
      steps {
        sshagent(credentials: ['app-server-deploy']) {
          sh '''
            for attempt in 1 2 3 4 5; do
              if ssh $SSH_OPTS deploy@$APP_HOST "curl -fsS http://localhost:$SITE_PORT/BUILD.txt" | grep -qx "release=$RELEASE"; then
                echo "verified: release $RELEASE is live on port $SITE_PORT"
                exit 0
              fi
              sleep 2
            done
            echo "verification FAILED - rolling back to the previous release"
            ssh $SSH_OPTS deploy@$APP_HOST bash -s -- "$SITE_ROOT" < scripts/rollback_release.sh
            exit 1
          '''
        }
      }
    }

    stage('Rollback') {
      when { expression { params.ACTION == 'rollback' } }
      steps {
        sshagent(credentials: ['app-server-deploy']) {
          sh 'ssh $SSH_OPTS deploy@$APP_HOST bash -s -- "$SITE_ROOT" < scripts/rollback_release.sh'
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
