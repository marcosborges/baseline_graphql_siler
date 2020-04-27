def container
def commit
def commitChangeset
def url = [
    dev : "",
    uat : "",
    prd : "",
]
def slack





pipeline {

    agent any

    options {
        preserveStashes(buildCount: 10) 
        buildDiscarder(logRotator(numToKeepStr:'10')) 
    }

    environment {
        JKS_USERID = sh(script:"""id -u jenkins """, returnStdout: true).trim()
        JKS_GROUPID = sh(script:"""id -g jenkins """, returnStdout: true).trim()
        APP_NAME = readJSON(file: 'composer.json').name.trim()
        APP_VERSION = readJSON(file: 'composer.json').version.trim()
        SONAR_PROJECT_KEY = "marcosborges_baseline_graphql_siler"
        SONAR_ORGANIZATION_KEY = "baseline-graphql-siler"
        REGISTRY_HOST = credentials('REGISTRY_HOST')
        GOOGLE_APPLICATION_CREDENTIALS = credentials('GCP_SERVICE_ACCOUNT')
        GOOGLE_REGION = "us-east1"
        GOOGLE_ZONE = "us-east1-a"
    }

    stages {

        stage('Checkout Sources') {
            steps {
                //checkout scm
                script {
                    commit = sh(returnStdout: true, script: 'git rev-parse --short=8 HEAD').trim()
                    commitChangeset = sh(returnStdout: true, script: 'git diff-tree --no-commit-id --name-status -r HEAD').trim()
                }
                stash includes: '**/*', name: 'checkoutSources'
            }
            post {
                success {
                    script {
                        slack = slackSend(
                            message: "Iniciando uma nova entrega, segue links para mais informações:\n" +
                            "${env.JOB_NAME} (${env.JOB_URL})\n" +
                            "${env.BUILD_ID} (${env.BUILD_URL})\n"
                        )
                        slackSend(channel: slack?.threadId, message: "Checkout: finalizado com sucesso")
                    }
                }
                failure {
                    echo 'Falha ao executar o checkout do projeto :('
                }
            }
        }

        stage('Dependencies Restore') {
            agent {
                docker { image 'phpswoole/swoole' }
            }
            steps {
                sh " composer -q -n install "
                stash includes: 'vendor/**/*', name: 'restoreSources'
            }
            post {
                success {
                    script {
                        slackSend(channel: slack?.threadId, message: "Dependencies Restore: finalizado com sucesso")
                    }
                }
                failure {
                    echo 'Falha ao executar o restauração de dependencias :('
                }
            }
        }

        stage('Testing') {
            agent {
                dockerfile { 
                    filename 'Dockerfile'
                    dir './'
                }
            }
            steps {
                unstash 'restoreSources'
                sh " composer test "
                sh """
                    sed -i 's|${pwd()}/||' ${pwd()}/tests/unit/_reports/logs/clover.xml 
                    sed -i 's|${pwd()}/||' ${pwd()}/tests/unit/_reports/logs/junit.xml
                """
                stash includes: '**/*', name: 'testSources'
            }
            post {
                success {
                    script {
                        slackSend(channel: slack?.threadId, message: "Testing: finalizado com sucesso")
                    }
                }
                failure {
                    echo 'Falha ao executar os testes :('
                }
            }
        }

        stage('Quality Gate') {
            steps {
                unstash 'checkoutSources'
                unstash 'restoreSources'
                unstash 'testSources'
              
                script {
                    def scannerHome = tool 'SonarScanner';
                    withSonarQubeEnv ('SonarQubeCloud') {
                        sh """    
                            ${scannerHome}/bin/sonar-scanner \
                                -Dsonar.projectKey="${env.SONAR_PROJECT_KEY}" \
                                -Dsonar.organization="${env.SONAR_ORGANIZATION_KEY}" \
                                -Dsonar.projectName="${env.APP_NAME}" \
                                -Dsonar.projectVersion="${env.APP_VERSION}" \
                                -Dsonar.sources="src" \
                                -Dsonar.tests="tests" \
                                -Dsonar.language="php" \
                                -Dsonar.sourceEncoding="UTF-8" \
                                -Dsonar.php.coverage.reportPaths=tests/unit/_reports/logs/clover.xml \
                                -Dsonar.php.tests.reportPath=tests/unit/_reports/logs/junit.xml \
                        """
                    }
                }
                timeout (time: 1, unit: 'HOURS') {
                    waitForQualityGate abortPipeline: true
                }
            }
            post {
                success {
                    script {
                        slackSend(channel: slack?.threadId, message: "Quality Gate: finalizado com sucesso")
                    }
                }
                failure {
                    echo 'Falha ao executar a revisão de código e cobertura de testes :('
                }
            }
        }

        stage('Container Build') {
            steps {
                script {
                    unstash 'restoreSources'
                    echo "${env.REGISTRY_HOST}snapshot/${env.APP_NAME}:${env.APP_VERSION}"
                    container = docker.build("${env.REGISTRY_HOST}snapshot/${env.APP_NAME}:${env.APP_VERSION}", " -f Build.Dockerfile . ")
                }
            }
            post {
                success {
                    script {
                        slackSend(channel: slack?.threadId, message: "Container Build: finalizado com sucesso")
                    }
                }
                failure {
                    echo 'Falha ao executar a construção do container :('
                }
            }
        }

        stage('Snapshot Registry') {
            steps {
                script {
                    sh script:'#!/bin/sh -e\n' +  """ docker login -u _json_key -p "\$(cat ${env.GOOGLE_APPLICATION_CREDENTIALS})" https://${env.REGISTRY_HOST}""", returnStdout: false
                    docker.withRegistry("https://${env.REGISTRY_HOST}snapshot/") {
                        container.push("${env.APP_VERSION}")
                        container.push("${commit}")
                    }
                }
            }
            post {
                success {
                    script {
                        slackSend(channel: slack?.threadId, message: "Snapshot Registry: finalizado com sucesso")
                    }
                }
                failure {
                    echo 'Falha ao registrar o container :('
                }
            }
        }

        stage('Development Deploy') {
            when {
                expression {
                    currentBuild.result == null || currentBuild.result == 'SUCCESS' 
                }
            }
            steps {
                script {
                    def data = readJSON file: env.GOOGLE_APPLICATION_CREDENTIALS 
                    def _name = "dev-${env.APP_NAME.toLowerCase().replace('_','-').replace('/','-').replace('.','-')}"
                    sh """
                        export GOOGLE_APPLICATION_CREDENTIALS=${env.GOOGLE_APPLICATION_CREDENTIALS}
                        gcloud config set project ${data.project_id}
                        gcloud config set compute/zone ${env.GOOGLE_ZONE}
                        gcloud auth activate-service-account ${data.client_email} --key-file=${env.GOOGLE_APPLICATION_CREDENTIALS} --project=${data.project_id}
                        gcloud run deploy ${_name} \
                            --image ${env.REGISTRY_HOST}snapshot/${env.APP_NAME}:${env.APP_VERSION} \
                            --platform managed \
                            --memory 2Gi \
                            --concurrency 10 \
                            --timeout 1m20s \
                            --max-instances 2 \
                            --cpu 1000m \
                            --port 9501 \
                            --labels "name=${_name}" \
                            --region ${env.GOOGLE_REGION} \
                            --allow-unauthenticated \
                            --set-env-vars "APP_ENV=development"
                    """
                    
                    def service = readJSON(text: sh(script: """
                        gcloud run services describe ${_name} \
                            --platform managed \
                            --region ${env.GOOGLE_REGION} \
                            --format json
                        """, returnStdout : true).trim()
                    )

                    url.dev = service.status.address.url

                }
            }
            post {
                success {
                    script {
                        slackSend(channel: slack?.threadId, message: "Development Deploy: finalizado com sucesso. Url: ${url.dev}")
                    }
                }
                failure {
                    echo 'Falha ao realizar o deploy :('
                }
            }
        }

        stage('Development Validation') {

            agent {
                docker { 
                    image 'postman/newman'
                    args  "--entrypoint=''"
                }
            }
            
            steps {
                unstash 'checkoutSources'
                script {

                    //sh """ curl -X POST -H "Content-type: application/json" -d '{"query": "query{helloWorld}"}' ${url.dev}/graphql """

                    def _newmanEnv = readJSON file: "tests/smoke/environment.json"
                    for ( pe in _newmanEnv.values ) {
                        if ( pe.key == "host" ) {
                            pe.value = url
                        }
                    }
                    new File(
                        "tests/smoke/environment.json"
                        ).write(
                            JsonOutput.toJson(
                                _postmanEnvironments
                            )
                        )

                    echo "Aplicação publicada com sucesso: ${url.dev}" 
                    sh """
                        pwd
                        ls -lah
                        df -h
                        newman run \
                            ${pwd()}/tests/smoke/baseline_graphql_siler_smoke.postman_collection.json \
                                -e ${pwd()}/tests/smoke/postman_environment.json \
                                -r cli,json,junit \
                                --reporter-junit-export="${pwd()}/tests/smoke/_report/newman-report.xml" \
                                --insecure \
                                --color on \
                                --disable-unicode 
                    """
                }
            }
            post {
                success {
                    script {
                        slackSend(channel: slack?.threadId, message: "Validate Development: finalizado com sucesso")
                    }
                }
                failure {
                    echo 'Falha ao realizar o deploy :('
                }
            }
        }

        /*stage('Approval Homologation Deploy') {
            steps {
                script {
                    script {
                        slackSend(channel: slack?.threadId, message: "Solicitando aprovação para entregar no ambiente de homologação.")
                    }
                
                    timeout(time: 2, unit: 'HOURS') {
                        input message: 'Approve Deploy on Homologation?', ok: 'Yes'
                    }
                }
            }
        }*/

        stage('Homologation Deploy') {
            when {
                expression {
                    currentBuild.result == null || currentBuild.result == 'SUCCESS' 
                }
            }
            steps {
                script {
                    def data = readJSON file: env.GOOGLE_APPLICATION_CREDENTIALS 
                    def _name = "uat-${env.APP_NAME.toLowerCase().replace('_','-').replace('/','-').replace('.','-')}"
                    sh """
                        export GOOGLE_APPLICATION_CREDENTIALS=${env.GOOGLE_APPLICATION_CREDENTIALS}
                        gcloud config set project ${data.project_id}
                        gcloud config set compute/zone ${env.GOOGLE_ZONE}
                        gcloud auth activate-service-account ${data.client_email} --key-file=${env.GOOGLE_APPLICATION_CREDENTIALS} --project=${data.project_id}
                        gcloud run deploy ${_name} \
                            --image ${env.REGISTRY_HOST}snapshot/${env.APP_NAME}:${env.APP_VERSION} \
                            --platform managed \
                            --memory 2Gi \
                            --concurrency 10 \
                            --timeout 1m20s \
                            --max-instances 2 \
                            --cpu 1000m \
                            --port 9501 \
                            --labels "name=${_name}" \
                            --region ${env.GOOGLE_REGION} \
                            --allow-unauthenticated \
                            --set-env-vars "APP_ENV=development"
                    """
                    
                    def service = readJSON(text: sh(script: """
                        gcloud run services describe ${_name} \
                            --platform managed \
                            --region ${env.GOOGLE_REGION} \
                            --format json
                        """, returnStdout : true).trim()
                    )

                    url.uat = service.status.address.url

                }
            }
            post {
                success {
                    script {
                        slackSend(channel: slack?.threadId, message: "Homologation Deploy: finalizado com sucesso. Url: ${url.uat}")
                    }
                }
                failure {
                    echo 'Falha ao realizar o deploy :('
                }
            }
        }

        stage('Homologation Validation') {
            steps {
                script {
                    sh """ curl -X POST -H "Content-type: application/json" -d '{"query": "query{helloWorld}"}' ${url.uat}/graphql """
                    echo "Aplicação publicada cm sucesso: ${url.uat}" 
                }
                /*
                docker.image('blazemeter/taurus').inside (""" -u 0:0 --net=host --entrypoint='' -v ${javaHome}:${javaHome} -v ${app.workspace}:/bzt """) {
                    sh """  
                        pip3 install Faker \
                        cd /bzt/taurus && \
                        chmod +x /bzt/taurus/seeder.py && \
                        ./seeder.py > data.csv && \
                        bzt *.yml \
                        --quiet \
                            -o modules.console.disable=true \
                            -o settings.verbose=false \
                            -o settings.env.HOSTNAME="${url.uat}" \
                    """
                }
                */
            }
            post {
                success {
                    script {
                        slackSend(channel: slack?.threadId, message: "Validate Homologation: finalizado com sucesso")
                    }
                }
                failure {
                    echo 'Falha ao realizar o deploy :('
                }
            }
        }
        
        stage('Release Registry') {
            steps {
                script {
                    def _snapshot = """${env.REGISTRY_HOST}snapshot/${env.APP_NAME}"""
                    def _release = """${env.REGISTRY_HOST}release/${env.APP_NAME}"""
                    sh script:'#!/bin/sh -e\n' +  """ docker login -u _json_key -p "\$(cat ${env.GOOGLE_APPLICATION_CREDENTIALS})" https://${env.REGISTRY_HOST}""", returnStdout: false
                    sh("docker pull ${_snapshot}:${env.APP_VERSION}")
                    sh("docker tag  ${_snapshot}:${env.APP_VERSION} ${_release}:${env.APP_VERSION}")
                    sh("docker tag  ${_snapshot}:${env.APP_VERSION} ${_release}:${commit}")
                    sh("docker push ${_release}:${env.APP_VERSION}")
                    sh("docker push ${_release}:${commit}")
                }
            }
            post {
                failure {
                    echo 'Falha ao registrar o container :('
                }
            }
        }

        /*stage('Approval Production Deploy') {
            steps {
                script {
                    script {
                        slackSend(channel: slack?.threadId, message: "Solicitando aprovação para entregar no ambiente de produção.")
                    }
                    timeout(time: 2, unit: 'HOURS') {
                        input message: 'Approve Deploy on Production?', ok: 'Yes'
                    }
                }
            }
        }*/

        stage('Production Deploy') {
            when {
                expression {
                    currentBuild.result == null || currentBuild.result == 'SUCCESS' 
                }
            }
            steps {
                script {
                    def data = readJSON file: env.GOOGLE_APPLICATION_CREDENTIALS 
                    def _name = "prd-${env.APP_NAME.toLowerCase().replace('_','-').replace('/','-').replace('.','-')}"
                    sh """
                        export GOOGLE_APPLICATION_CREDENTIALS=${env.GOOGLE_APPLICATION_CREDENTIALS}
                        gcloud config set project ${data.project_id}
                        gcloud config set compute/zone ${env.GOOGLE_ZONE}
                        gcloud auth activate-service-account ${data.client_email} --key-file=${env.GOOGLE_APPLICATION_CREDENTIALS} --project=${data.project_id}
                        gcloud run deploy ${_name} \
                            --image ${env.REGISTRY_HOST}release/${env.APP_NAME}:${env.APP_VERSION} \
                            --platform managed \
                            --memory 2Gi \
                            --concurrency 10 \
                            --timeout 1m20s \
                            --max-instances 2 \
                            --cpu 1000m \
                            --port 9501 \
                            --labels "name=${_name}" \
                            --region ${env.GOOGLE_REGION} \
                            --allow-unauthenticated \
                            --set-env-vars "APP_ENV=development"
                    """
                    
                    def service = readJSON(text: sh(script: """
                        gcloud run services describe ${_name} \
                            --platform managed \
                            --region ${env.GOOGLE_REGION} \
                            --format json
                        """, returnStdout : true).trim()
                    )

                    url.prd = service.status.address.url

                }
            }
            post {
                success {
                    script {
                        slackSend(channel: slack?.threadId, message: "Production Deploy: finalizado com sucesso. Url: ${url.prd}")
                    }
                }
                failure {
                    echo 'Falha ao realizar o deploy :('
                }
            }
        }

        stage('Production Validation') {
            steps {
                script {
                    sh """ curl -X POST -H "Content-type: application/json" -d '{"query": "query{helloWorld}"}' ${url.prd}/graphql """
                    echo "Aplicação publicada cm sucesso: ${url.prd}" 
                }
            }
            post {
                success {
                    script {
                        slackSend(channel: slack?.threadId, message: "Validate Production: finalizado com sucesso.")
                    }
                }
                failure {
                    echo 'Falha ao realizar o deploy :('
                }
            }
        }
    }

    post {

        success {
            echo 'The Pipeline success :)'
            
            script {
                sh "zip -r dist.zip ./"
            }

            junit "tests/_reports/**/*.xml"

            archiveArtifacts artifacts: 'dist.zip', fingerprint: true
            
            /*
            allure([
                includeProperties: false,
                jdk: 'JDK8',
                properties: [],
                reportBuildPolicy: 'ALWAYS',
                results: [
                    [path: "tests/_reports/logs/"]
                ]
            ])
            */
            
            publishHTML target: [
                allowMissing: false,
                alwaysLinkToLastBuild: false,
                keepAll: true,
                reportDir: 'tests/_reports/coverage',
                reportFiles: 'index.html',
                reportName: 'Coverage'
            ]
        }

        failure {
            echo 'The Pipeline failed :('
        }
    }
}