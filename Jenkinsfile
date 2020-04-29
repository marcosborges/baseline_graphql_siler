import groovy.json.JsonOutput

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
        preserveStashes(buildCount: 2) 
        buildDiscarder(logRotator(numToKeepStr:'2')) 
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
                            "*App:* ${env.APP_NAME}\n" +
                            "*Version:* ${env.APP_VERSION}\n" +
                            "*Commit:* ${commit}\n" +
                            "*User:* ${currentBuild.rawBuild.getCause(hudson.model.Cause$UserIdCause).userName}\n" +
                            "*Job:* ${env.JOB_NAME} - (${env.JOB_URL})\n" +
                            "*Build:* ${env.BUILD_ID} - (${env.BUILD_URL})\n"

                        )
                        slackSend(channel: slack?.threadId, message: "Checkout: finalizado com sucesso.\n${currentBuild.changeSets.join('\n')}")
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
                sleep(60)
                timeout (time: 1, unit: 'HOURS') {
                    waitForQualityGate abortPipeline: true
                }
            }
            post {
                success {
                    script {
                        slackSend(channel: slack?.threadId, message: "Quality Gate: finalizado com sucesso. Link: https://sonarcloud.io/dashboard?id=marcosborges_baseline_graphql_siler")
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
            
        

        stage( 'AppConfig (DEV)') { steps {   echo "OK" } }

        stage( 'DB Migration (DEV)') { steps {  echo "OK" } }

        stage( 'Deploy (DEV)') {
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
                    """
                    def _revisions = readJSON(text:sh(
                        script: """
                            gcloud run revisions list \
                                --service ${_name} \
                                --format json \
                                --platform managed \
                                --region ${env.GOOGLE_REGION}
                        """, 
                        returnStdout : true
                    ).trim())
                    println _revisions
                    sh """
                        gcloud run deploy ${_name} \
                            --image ${env.REGISTRY_HOST}snapshot/${env.APP_NAME}:${env.APP_VERSION} \
                            --platform managed \
                            --memory 2Gi \
                            --concurrency 1000 \
                            --timeout 1m20s \
                            --max-instances 3 \
                            --cpu 1000m \
                            --port 9501 \
                            --labels "name=${_name}" \
                            --region ${env.GOOGLE_REGION} \
                            --allow-unauthenticated \
                            --revision-suffix "${env.APP_VERSION.replace('.','-')}-${commit}" \
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

        stage( 'Validation (DEV)') {

            parallel {
                stage("healthz") {
                    steps {
                        script {
                            echo "Aplicação publicada com sucesso" 
                        }
                    }
                }
                stage("smoke") {
                    agent {
                        docker { 
                            image 'postman/newman'
                            args  "--entrypoint=''"
                        }
                    }
                    steps {
                        unstash 'checkoutSources'
                        script {

                            def _newmanEnv = readJSON file: "${pwd()}/tests/smoke/environment.json"
                            for ( pe in _newmanEnv.values ) {
                                if ( pe.key == "hostname" ) {
                                    pe.value = "${url.dev}".toString()
                                }
                            }

                            new File(
                                "${pwd()}/tests/smoke/uat-environment.json"
                            ).write(
                                JsonOutput.toJson(
                                    _newmanEnv
                                )
                            )

                            echo "Aplicação publicada com sucesso: ${url.dev}" 
                            sh """
                                newman run \
                                    ${pwd()}/tests/smoke/baseline_graphql_siler_smoke.postman_collection.json \
                                        -e ${pwd()}/tests/smoke/uat-environment.json \
                                        -r cli,json,junit \
                                        --reporter-junit-export="${pwd()}/tests/smoke/_report/uat-newman-report.xml" \
                                        --insecure \
                                        --color on \
                                        --disable-unicode 
                            """
                        }
                    }
                }
                stage("functional") {
                    agent {
                        docker { 
                            image 'postman/newman'
                            args  "--entrypoint=''"
                        }
                    }
                    steps {
                        unstash 'checkoutSources'
                        script {

                            def _newmanEnv = readJSON file: "${pwd()}/tests/smoke/environment.json"
                            for ( pe in _newmanEnv.values ) {
                                if ( pe.key == "hostname" ) {
                                    pe.value = "${url.dev}".toString()
                                }
                            }

                            new File(
                                "${pwd()}/tests/smoke/uat-environment.json"
                            ).write(
                                JsonOutput.toJson(
                                    _newmanEnv
                                )
                            )

                            echo "Aplicação publicada com sucesso: ${url.dev}" 
                            sh """
                                newman run \
                                    ${pwd()}/tests/smoke/baseline_graphql_siler_smoke.postman_collection.json \
                                        -e ${pwd()}/tests/smoke/uat-environment.json \
                                        -r cli,json,junit \
                                        --reporter-junit-export="${pwd()}/tests/smoke/_report/uat-newman-report.xml" \
                                        --insecure \
                                        --color on \
                                        --disable-unicode 
                            """
                        }
                    }
                }
                stage("security") {
                    steps {
                        script {
                            echo "Aplicação publicada com sucesso" 
                        }
                    }
                }
                stage ("load") {
                    agent {
                        dockerfile { 
                            filename 'LoadTest.Dockerfile'
                            dir './'
                            additionalBuildArgs  """ -f LoadTest.Dockerfile --build-arg "version=0.0.1" \
                                --build-arg "user=jenkins" \
                                --build-arg "group=jenkins" \
                                --build-arg "uid=${env.JKS_USERID}" \
                                --build-arg "gid=${env.JKS_GROUPID}" """
                            args """ -u ${env.JKS_USERID}:${env.JKS_GROUPID} \
                                --entrypoint='' \
                                -v "${pwd()}/tests/load:/bzt-configs"
                            """
                        }
                    }
                    /*agent {
                        docker { 
                            image 'blazemeter/taurus'
                            args  """ -u 0:0 --entrypoint='' -v "${pwd()}/tests/load:/bzt-configs" """
                        }
                    }*/
                    
                    steps {
                        unstash 'checkoutSources'
                        script {
                            //pip install bzt
                            sh """  
                                pwd
                                ls -lah
                                df -h
                                cd ~/
                                whoami
                                cd /bzt-configs && bzt load-test.yml \
                                    --no-system-configs \
                                    --quiet \
                                    -o settings.env.HOSTNAME="${url.dev}"
                            """
                            /*
                                    -o modules.console.disable=true \
                                    -o settings.verbose=false \*/
                            
                        }
                    }
                }
            }
            post {
                success {
                    script {
                        echo "Aplicação publicada e validada com sucesso em desenvolvimento: ${url.dev}" 
                        slackSend(channel: slack?.threadId, message: "Validate Development: finalizado com sucesso")
                    }
                }
                failure {
                    script {
                        echo 'Falha ao realizar o deploy :('
                    }
                    
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

        stage('AppConfig (HON)') { steps {  echo "OK" } }

        stage('DB Migration (HON)') { steps {  echo "OK" } }

        stage('Deploy (HON)') {
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
                            --revision-suffix "${env.APP_VERSION.replace('.','-')}-${commit}" \
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

        stage('Validation (HON)') {
            parallel {
                stage("smoke") {
                    agent {
                        docker { 
                            image 'postman/newman'
                            args  "--entrypoint=''"
                        }
                    }
                    steps {
                        unstash 'checkoutSources'
                        script {

                            def _newmanEnv = readJSON file: "${pwd()}/tests/smoke/environment.json"
                            for ( pe in _newmanEnv.values ) {
                                if ( pe.key == "hostname" ) {
                                    pe.value = "${url.uat}".toString()
                                }
                            }

                            new File(
                                "${pwd()}/tests/smoke/uat-environment.json"
                            ).write(
                                JsonOutput.toJson(
                                    _newmanEnv
                                )
                            )

                            echo "Aplicação publicada com sucesso: ${url.uat}" 
                            sh """
                                newman run \
                                    ${pwd()}/tests/smoke/baseline_graphql_siler_smoke.postman_collection.json \
                                        -e ${pwd()}/tests/smoke/uat-environment.json \
                                        -r cli,json,junit \
                                        --reporter-junit-export="${pwd()}/tests/smoke/_report/uat-newman-report.xml" \
                                        --insecure \
                                        --color on \
                                        --disable-unicode 
                            """
                        }
                    }
                }
                stage ("load") {
                    agent {
                        docker { 
                            image 'blazemeter/taurus'
                            args  "--entrypoint=''"
                        }
                    }
                    
                    steps {
                        unstash 'checkoutSources'
                        script {
                            sh """  
                                /bzt/taurus/bzt ${pwd()}/tests/load/load-test.yml \
                                    --quiet \
                                    -o modules.console.disable=true \
                                    -o settings.verbose=false \
                                    -o settings.env.HOSTNAME="${url.uat}"
                            """
                        }
                    }
                }
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

        stage('AppConfig (PRD)') { steps {  echo "OK" } }

        stage('DB Migration (PRD)') { steps {  echo "OK" } }

        stage('Deploy (PRD)') {
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
                            --revision-suffix "${env.APP_VERSION.replace('.','-')}-${commit}" \
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

        stage('Validation (PRD)') {
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

        always {
            cleanWs()
        }

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