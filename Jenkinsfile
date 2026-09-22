pipeline {
    agent any

    tools {
        // Jenkins itself must run on Java 21; the application is compiled for Java 17.
        jdk 'JDK21'
        maven 'maven3'
    }

    options {
        skipDefaultCheckout(true)
        disableConcurrentBuilds()
        timestamps()
        timeout(time: 30, unit: 'MINUTES')
    }

    parameters {
        choice(
            name: 'DEPLOY_ENV',
            choices: ['kind', 'eks'],
            description: 'Target cluster environment. EKS deployments require approval.'
        )
        string(
            name: 'IMAGE_REPOSITORY',
            defaultValue: 'your-dockerhub-user/abc-retail-portal',
            description: 'Docker Hub repository, without a tag'
        )
        string(
            name: 'DOCKER_CREDENTIALS_ID',
            defaultValue: 'dockerhub-credentials',
            description: 'Jenkins username/password credential ID for Docker Hub'
        )
        string(
            name: 'KUBECONFIG_CREDENTIALS_ID',
            defaultValue: 'abc-retail-kubeconfig',
            description: 'Jenkins secret-file credential ID containing kubeconfig'
        )
    }

    environment {
        APP_DIRECTORY = 'app'
        K8S_NAMESPACE = 'abc-retail'
        IMAGE_TAG = "${BUILD_NUMBER}"
        MAVEN_COMPILER_RELEASE = '17'
    }

    stages {
        stage('Checkout') {
            steps {
                // The Jenkins job's SCM configuration supplies repository credentials.
                checkout scm
            }
            post {
                success {
                    echo 'Source checkout completed.'
                }
                failure {
                    echo 'Checkout failed; verify the Jenkins SCM configuration and credentials.'
                }
            }
        }

        stage('Maven Compile & Test') {
            steps {
                sh '''
                    set -eu
                    mvn --batch-mode --file "${APP_DIRECTORY}/pom.xml" \
                        -Dmaven.compiler.release="${MAVEN_COMPILER_RELEASE}" \
                        clean compile
                    mvn --batch-mode --file "${APP_DIRECTORY}/pom.xml" \
                        -Dmaven.compiler.release="${MAVEN_COMPILER_RELEASE}" \
                        test
                '''
            }
            post {
                always {
                    junit testResults: "${APP_DIRECTORY}/target/surefire-reports/*.xml",
                          allowEmptyResults: true
                }
            }
        }

        stage('Package WAR') {
            steps {
                sh '''
                    set -eu
                    mvn --batch-mode --file "${APP_DIRECTORY}/pom.xml" \
                        -Dmaven.compiler.release="${MAVEN_COMPILER_RELEASE}" \
                        package -DskipTests
                '''
                archiveArtifacts artifacts: "${APP_DIRECTORY}/target/*.war",
                                 fingerprint: true
            }
        }

        stage('Docker Build & Push to Docker Hub') {
            steps {
                script {
                    withCredentials([
                        usernamePassword(
                            credentialsId: params.DOCKER_CREDENTIALS_ID,
                            usernameVariable: 'DOCKER_USERNAME',
                            passwordVariable: 'DOCKER_PASSWORD'
                        )
                    ]) {
                        sh '''
                            set -eu
                            IMAGE="${IMAGE_REPOSITORY}:${IMAGE_TAG}"

                            printf '%s' "${DOCKER_PASSWORD}" | \
                                docker login --username "${DOCKER_USERNAME}" --password-stdin
                            docker build --tag "${IMAGE}" .
                            docker push "${IMAGE}"
                            docker logout
                        '''
                    }
                }
            }
        }

        stage('Manual Approval Gate') {
            when {
                expression {
                    params.DEPLOY_ENV == 'eks'
                }
            }
            steps {
                timeout(time: 10, unit: 'MINUTES') {
                    input(
                        message: "Deploy ${params.IMAGE_REPOSITORY}:${env.IMAGE_TAG} to EKS?",
                        ok: 'Approve production deployment'
                    )
                }
            }
        }

        stage('Kubernetes Deploy') {
            steps {
                script {
                    withCredentials([
                        file(
                            credentialsId: params.KUBECONFIG_CREDENTIALS_ID,
                            variable: 'KUBECONFIG'
                        )
                    ]) {
                        sh '''
                            set -eu

                            kubectl apply -f k8s/namespace.yaml
                            kubectl apply -f k8s/deployment.yaml
                            kubectl apply -f k8s/service.yaml

                            if [ "${DEPLOY_ENV}" = "eks" ]; then
                                kubectl apply -f k8s/ingress-alb.yaml
                            else
                                kubectl apply -f k8s/ingress-nginx.yaml
                            fi

                            kubectl -n "${K8S_NAMESPACE}" set image \
                                deployment/abc-retail \
                                abc-retail="${IMAGE_REPOSITORY}:${IMAGE_TAG}"
                            kubectl -n "${K8S_NAMESPACE}" rollout status \
                                deployment/abc-retail --timeout=5m
                        '''
                    }
                }
            }
        }
    }

    post {
        success {
            echo "Build ${env.BUILD_NUMBER} completed successfully."
        }
        failure {
            echo "Build ${env.BUILD_NUMBER} failed. Review the failed stage and console output."
        }
        always {
            junit testResults: "${APP_DIRECTORY}/target/surefire-reports/*.xml",
                  allowEmptyResults: true
            sh(
                script: '''
                    if [ -n "${IMAGE_REPOSITORY:-}" ] && [ -n "${IMAGE_TAG:-}" ]; then
                        docker image rm "${IMAGE_REPOSITORY}:${IMAGE_TAG}" || true
                    fi
                ''',
                returnStatus: true
            )
            cleanWs()
        }
    }
}
