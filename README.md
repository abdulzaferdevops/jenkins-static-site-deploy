# jenkins-shared-library

The shared Jenkins pipeline library (`ci-labs`) behind a series of CI/CD labs on Oracle Cloud
Infrastructure. Steps that were copied into every Jenkinsfile — preflight checks, release naming,
SSH to the app server, image-reference validation and "skip deploy for docs-only changes" — live
here once, versioned by tag and covered by tests.

Lab 6 of the series. First consumer:
[Lab 1, jenkins-static-site-deploy](https://github.com/abdulzaferdevops/jenkins-static-site-deploy).

## Using it

```groovy
@Library('ci-labs@v1.0.0') _

pipeline {
  agent any
  stages {
    stage('Preflight') {
      steps {
        script {
          labPreflight(vars: ['APP_HOST'])
          env.RELEASE = labRelease()                 // e.g. 00012-3f2a9c1
          env.SKIP_DEPLOY = labDocsOnly() ? 'true' : 'false'
        }
      }
    }
    stage('Deploy') {
      when { expression { env.SKIP_DEPLOY != 'true' } }
      steps {
        script { labSsh(script: 'scripts/release.sh', args: ['deploy', env.RELEASE]) }
      }
    }
  }
}
```

Pipelines pin a **tag**, never `main`: a library change cannot alter a working pipeline until
that pipeline is deliberately moved to the new version.

## Steps

| Step | What it does |
|:--|:--|
| `labPreflight(vars: [...], docker: bool)` | Fails fast if a required Jenkins global variable is missing, or Docker is unavailable |
| `labRelease()` | Release name `<build, 5 digits>-<short commit>`, sortable by build order |
| `labDocsOnly()` | `true` if every file changed since the last successful build is documentation; anything uncertain returns `false` (deploy) |
| `labImageRef(repo:, ref:)` | Fails unless `ref` is `<repo>@sha256:<64 lowercase hex>`; refuses tags, other registries and look-alike repository names |
| `labSsh(command: / script:, args:, stdin:, returnStdout:)` | Runs on the app server as `deploy` with `BatchMode=yes`; quotes every argument for **both** the local and the remote shell |
| `labShellQuote(value)` | Single-quotes a value for `/bin/sh` |

## Design

- **Logic in shell, wiring in Groovy.** The decisions (`docs_only.sh`, `image_ref.sh`) are plain bash in
  `resources/lab/`, loaded with `libraryResource`, so they can be tested without a Jenkins instance.
- **Safe defaults.** First build, rewritten history or a manual rebuild of the same commit all count as
  code changes, so uncertainty means "deploy", never "skip".
- **Quoting tested against hostile input.** `ssh` re-parses its arguments on the server; `labSsh` quotes
  twice so values with quotes, `$`, spaces, globs or `$(...)` arrive literally. Found by testing an earlier
  version, which quoted only once.

## Tests

`bash tests/run.sh` — 20 cases using only bash and git:

- `docs_only.sh`: README-only, `docs/` folder, nested `*.md`, code + docs together, a file merely *named*
  like Markdown, first build, unknown commit, manual rebuild, rewritten history.
- `image_ref.sh`: valid digest; tag; other registry; other repository; `repo-evil` look-alike prefix;
  truncated, uppercase and ellipsis-shortened digests; missing arguments.

Each check was also verified to fail when the helper is deliberately broken (mutation testing).
The library's own pipeline runs the tests and ShellCheck on every push.

## Versions

See [CHANGELOG.md](CHANGELOG.md).

## Results

| Build | Change | Outcome |
|:--|:--|:--|
| Library CI #1 | `v1.0.0` | 20/20 shell tests passed, ShellCheck clean, layout check passed |
| Lab 1 #6 | `Jenkinsfile` | `code changed` → deployed and verified `00006-e13d6d8` |
| Lab 1 #7 | `README.md` only | `only documentation changed` → deploy **skipped** |

Testing found and fixed a real defect before release: the first `labSsh` quoted arguments only for the
local shell, so a value containing `$(...)` would have run on the server.

## Licence

MIT
