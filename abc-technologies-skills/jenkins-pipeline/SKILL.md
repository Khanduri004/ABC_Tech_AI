---
name: jenkins-pipeline
description: Writes and extends declarative Jenkins pipelines (Jenkinsfile) — checkout, compile, test, package, Docker build/push, and Kubernetes deploy stages. Use whenever the user is writing or reviewing a Jenkinsfile, adding a new pipeline stage, or wiring Jenkins to Docker Hub or a Kubernetes cluster.
---

## 1. Overall structure
```groovy
pipeline {
    agent any
    tools {
        maven 'maven3'
        jdk 'JDK17'
    }
    stages {
        stage('Checkout') { ... }
        stage('Compile')  { ... }
        stage('Test')     { ... }
        stage('Package')  { ... }
        stage('Build & Push Image') { ... }
        stage('Deploy')   { ... }
    }
}
```
Pin `tools` versions explicitly (as above) rather than relying on whatever's default on the agent — this is what makes the build reproducible across Jenkins restarts/agent changes.

## 2. Stage ordering: fail fast
Keep Compile, Test, and Package as **separate stages**, not combined into one `sh` block — this is what makes the Jenkins UI point at the actual failing stage instead of a wall of shell output. Default ordering should be:
```
Checkout → Compile → Test → Package → Build & Push Image → Deploy
```
Run Test **before** Package where possible: there's no point producing a build artifact from code that fails its own test suite. If the project's existing pipeline runs Package before Test, that's a valid choice too (e.g. when packaging is needed to run integration tests against the packaged artifact) — but call out the tradeoff rather than picking one silently.

## 3. Checkout stage
```groovy
stage('Checkout') {
    steps {
        git branch: 'main',
            credentialsId: 'github-credentials',
            url: 'https://github.com/<org>/<repo>.git'
    }
}
```
Reference `credentialsId` from the Jenkins credentials store — never inline a PAT or token as plain text in the Jenkinsfile, even in a private repo.

## 4. Compile / Test / Package stages
```groovy
stage('Compile') {
    steps { sh 'mvn clean compile' }
}
stage('Test') {
    steps { sh 'mvn test' }
}
stage('Package') {
    steps { sh 'mvn package -DskipTests' }   // tests already ran above — don't re-run them
}
```
Use `-DskipTests` (not `-Dmaven.test.skip=true`) in the Package stage if Test already ran — this still compiles test classes but skips re-execution, which is usually the intended behavior when Test is its own prior stage.

## 5. post blocks
Attach `post { success { ... } failure { ... } }` per stage (or once at the pipeline level for shared behavior). Typical use:
```groovy
post {
    success {
        echo 'Compilation successful!'
        archiveArtifacts artifacts: 'target/classes/**/*', allowEmptyArchive: true
    }
    failure {
        echo 'Stage failed — check console output above.'
    }
}
```
Always set `allowEmptyArchive: true` on `archiveArtifacts` unless you specifically want the build to fail when no matching files exist.

## 6. Docker build & push stage
```groovy
stage('Build & Push Image') {
    steps {
        withCredentials([usernamePassword(credentialsId: 'dockerhub-creds', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
            sh """
                docker build -t \$DOCKER_USER/<image>:${env.BUILD_NUMBER} .
                echo \$DOCKER_PASS | docker login -u \$DOCKER_USER --password-stdin
                docker push \$DOCKER_USER/<image>:${env.BUILD_NUMBER}
            """
        }
    }
}
```
Tag with `${env.BUILD_NUMBER}` (or a git SHA) — never push only `:latest`, since that makes rollback and "what's actually deployed" impossible to answer later.

## 7. Deploy stage
```groovy
stage('Deploy') {
    steps {
        sh "kubectl set image deployment/<name> <container>=<user>/<image>:${env.BUILD_NUMBER} -n <namespace>"
    }
}
```
If different manifests exist per environment (e.g. `ingress-nginx.yaml` for local/kind vs `ingress-alb.yaml` for production EKS — see the `k8s-container-orchestration` skill), parameterize which manifest set gets applied rather than hardcoding one, so the same Jenkinsfile can target either environment.

## 8. Secrets discipline
Nothing sensitive (registry passwords, kubeconfig contents, API tokens) belongs as a literal string anywhere in the Jenkinsfile. Everything goes through Jenkins' credentials store via `credentialsId`/`withCredentials`, referenced by ID only.
