import groovy.json.JsonOutput

def container
def commit
def commitChangeset
def _environments = [
    dev : [
        name : "",
        url : "",
        prev : ""
    ],
    uat : [
        name : "",
        url : "",
        prev : ""
    ],
    prd : [
        name : "",
        url : "",
        prev : ""
    ]
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
        
        stage ( 'Checkout Sources' ) {
            steps {
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
                            "*User:* ${currentBuild.rawBuild.getCause(hudson.model.Cause$UserIdCause)?.userName}\n" +
                            "*Job:* ${env.JOB_NAME} - (${env.JOB_URL})\n" +
                            "*Build:* ${env.BUILD_ID} - (${env.BUILD_URL})\n"
                        )
                        def changeLogSets = ""
                        for (int i = 0; i < currentBuild.changeSets.size(); i++) {
                            def entries = currentBuild.changeSets[i].items
                            for (int j = 0; j < entries.length; j++) {
                                def entry = entries[j]
                                changeLogSets += "${entry.commitId} \nby ${entry.author} on ${new Date(entry.timestamp)}: ${entry.msg}\n"
                                def files = new ArrayList(entry.affectedFiles)
                                for (int k = 0; k < files.size(); k++) {
                                    def file = files[k]
                                    changeLogSets += "    ${file.editType.name} ${file.path}\n"
                                }
                            }
                        }
                        slackSend(channel: slack?.threadId, message: "Os fontes da aplicação foram obtidos com sucesso. Confira o change-log:\n${changeLogSets}")
                    }
                }
                failure {
                    slackSend(channel: slack?.threadId, message: "Falha ao obter os fontes da aplicação.\nlink:${env.BUILD_URL}")
                }
            }
        }

        stage ( 'Dependencies Restore' ) {
            agent {
                docker { image 'phpswoole/swoole' }
            }
            steps {
                sh " composer -q -n install "
                stash includes: 'vendor/**/*', name: 'restoreSources'
            }
            post {
                success {
                    slackSend(channel: slack?.threadId, message: "Restauração de dependencias finalizada com sucesso.")
                }
                failure {
                    slackSend(channel: slack?.threadId, message: "Falha ao restaur as dependencias.\nlink:${env.BUILD_URL}")
                }
            }
        }

        stage ( 'Testing' ) {
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
                    slackSend(channel: slack?.threadId, message: "Testes realizados com sucesso.")
                }
                failure {
                    slackSend(channel: slack?.threadId, message: "Falha ao realizar os testes.\nlink:${env.BUILD_URL}")
                }
            }
        }

        stage ( 'Quality Gate' ) {
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
                sleep(30)
                timeout (time: 1, unit: 'HOURS') {
                    waitForQualityGate abortPipeline: true
                }
            }
            post {
                success {
                    slackSend(channel: slack?.threadId, message: "Portal de qualidade finalizado com sucesso.\nlink:https://sonarcloud.io/dashboard?id=marcosborges_baseline_graphql_siler")
                }
                failure {
                    slackSend(channel: slack?.threadId, message: "Falha ao passar pelo portal de qualidade.\nlink:${env.BUILD_URL}")
                }
            }
        }

        stage ( 'Container Build' ) {
            steps {
                script {
                    unstash 'restoreSources'
                    echo "${env.REGISTRY_HOST}snapshot/${env.APP_NAME}:${env.APP_VERSION}"
                    container = docker.build("${env.REGISTRY_HOST}snapshot/${env.APP_NAME}:${env.APP_VERSION}", " -f Build.Dockerfile . ")
                }
            }
            post {
                success {
                    slackSend(channel: slack?.threadId, message: "Aplicação containerizada com sucesso.")
                }
                failure {
                    slackSend(channel: slack?.threadId, message: "Falha ao construir o container com a aplicação.\nlink:${env.BUILD_URL}")
                }
            }
        }

        stage ( 'Snapshot Registry' ) {
            steps {
                script {
                    sh script:'#!/bin/sh -e\n' +  """ docker login -u _json_key -p "\$(cat ${env.GOOGLE_APPLICATION_CREDENTIALS})" https://${env.REGISTRY_HOST}""", returnStdout: false
                    docker.withRegistry("https://${env.REGISTRY_HOST}snapshot/") {
                        parallel {
                            stage("version") {
                                container.push("${env.APP_VERSION}")
                            }
                            stage("commit") {
                                container.push("${commit}")
                            }
                        }
                    }
                }
            }
            post {
                success {
                    slackSend(channel: slack?.threadId, message: "Container classificado como snapshot e enviado para o registrador com sucesso.")
                }
                failure {
                    slackSend(channel: slack?.threadId, message: "Falha ao registrar o container.\nlink:${env.BUILD_URL}")
                }
            }
        }
        
        /*stage( 'AppConfig (Development)') { steps {   echo "OK" } }
        stage( 'DB Migration (Development)') { steps {  echo "OK" } }*/

        stage ( 'Deploy (Development)' ) {
            steps {
                script {
                    def data = readJSON file: env.GOOGLE_APPLICATION_CREDENTIALS 
                    _environments.dev.name = "dev-${env.APP_NAME.toLowerCase().replace('_','-').replace('/','-').replace('.','-')}"
                    sh """
                        export GOOGLE_APPLICATION_CREDENTIALS=${env.GOOGLE_APPLICATION_CREDENTIALS}
                        gcloud config set project ${data.project_id}
                        gcloud config set compute/zone ${env.GOOGLE_ZONE}
                        gcloud auth activate-service-account ${data.client_email} --key-file=${env.GOOGLE_APPLICATION_CREDENTIALS} --project=${data.project_id}
                    """
                    _environments.dev.prev = readJSON(text:sh(
                        script: """ gcloud run revisions list \
                            --service ${_environments.dev.name} \
                            --format json \
                            --platform managed \
                            --region ${env.GOOGLE_REGION}
                        """, 
                        returnStdout : true
                    ).trim())?.first()?.metadata?.name
                    sh """
                        gcloud run deploy ${_environments.dev.name} \
                            --image ${env.REGISTRY_HOST}snapshot/${env.APP_NAME}:${env.APP_VERSION} \
                            --platform managed \
                            --memory 2Gi \
                            --concurrency 1000 \
                            --timeout 1m20s \
                            --max-instances 3 \
                            --cpu 1000m \
                            --port 9501 \
                            --labels "name=${_environments.dev.name}" \
                            --region ${env.GOOGLE_REGION} \
                            --allow-unauthenticated \
                            --revision-suffix "${env.APP_VERSION.replace('.','-')}-${commit}" \
                            --set-env-vars "APP_ENV=development"
                    """
                    def _service = readJSON(text: sh(script: """
                        gcloud run services describe ${_environments.dev.name} \
                            --platform managed \
                            --region ${env.GOOGLE_REGION} \
                            --format json
                        """, returnStdout : true).trim()
                    )
                    _environments.dev.url = _service.status.address.url
                }
            }
            post {
                success {
                    slackSend(channel: slack?.threadId, message: "Implantação do container no ambiente de desenvolvimento realizada com sucesso.\nlink: ${_environments.dev.url}")
                }
                failure {
                    slackSend(channel: slack?.threadId, message: "Falha ao implantar o container no ambiente de desenvolvimento.\nlink:${env.BUILD_URL}")
                }
            }
        }

        stage ( 'Validation (Development)' ) {
            parallel {
                stage("healthz") {
                    steps {
                        script {
                            sh """ curl -X GET -H "Content-type: application/json" ${_environments.dev.url}/health """ 
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
                                    pe.value = "${_environments.dev.url}".toString()
                                }
                            }

                            new File(
                                "${pwd()}/tests/smoke/dev-environment.json"
                            ).write(
                                JsonOutput.toJson(
                                    _newmanEnv
                                )
                            )

                            echo "Aplicação publicada com sucesso: ${_environments.dev.url}" 
                            sh """
                                newman run \
                                    ${pwd()}/tests/smoke/baseline_graphql_siler_smoke.postman_collection.json \
                                        -e ${pwd()}/tests/smoke/dev-environment.json \
                                        -r cli,json,junit \
                                        --reporter-junit-export="${pwd()}/tests/smoke/_report/dev-newman-report.xml" \
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

                            def _newmanEnv = readJSON file: "${pwd()}/tests/functional/environment.json"
                            for ( pe in _newmanEnv.values ) {
                                if ( pe.key == "hostname" ) {
                                    pe.value = "${_environments.dev.url}".toString()
                                }
                            }

                            new File(
                                "${pwd()}/tests/functional/dev-environment.json"
                            ).write(
                                JsonOutput.toJson(
                                    _newmanEnv
                                )
                            )

                            echo "Aplicação publicada com sucesso: ${_environments.dev.url}" 
                            sh """
                                newman run \
                                    ${pwd()}/tests/functional/baseline_graphql_siler_functional.postman_collection.json \
                                        -e ${pwd()}/tests/functional/dev-environment.json \
                                        -r cli,json,junit \
                                        --reporter-junit-export="${pwd()}/tests/functional/_report/dev-newman-report.xml" \
                                        --insecure \
                                        --color on \
                                        --disable-unicode 
                            """
                        }
                    }
                }
                /*stage("security") {
                    steps {
                        script {
                            echo "Aplicação publicada com sucesso" 
                        }
                    }
                }*/
                /*stage ("load") {
                    
                    agent {
                        docker { 
                            image 'blazemeter/taurus'
                            args  """ -u 0:0 --entrypoint='' -v "${pwd()}/tests/load:/bzt-configs" """
                        }
                    }
                    
                    steps {
                        unstash 'checkoutSources'
                        script {
                            sh """  
                                cd /bzt-configs 
                                bzt load-test.yml \
                                    --quiet \
                                    -o modules.console.disable=true \
                                    -o settings.verbose=false \
                                    -o settings.env.HOSTNAME="${_environments.dev.url}"
                                chown ${env.JKS_USERID}:${env.JKS_GROUPID} * -R
                            """
                        }
                    }
                }*/
            }                
            post {
                success {
                    slackSend(channel: slack?.threadId, message: "Validação da implantação no ambiente de desenvolvimento realizada com sucesso.")
                }
                failure {
                    slackSend(channel: slack?.threadId, message: "Falha ao realizar a implantação no ambiente de desenvolvimento.\nlink:${env.BUILD_URL}")
                }
            }
        }

        stage ( 'Approval Homologation Deploy' ) {
            steps {
                script {
                    slackSend(channel: slack?.threadId, message: "Solicitando aprovação para entregar no ambiente de homologação.\nlink:${env.BUILD_URL}/input")
                    timeout(time: 1, unit: 'HOURS') {
                        input message: 'Aprovar a implantação em homologação?', ok: 'Sim'
                    }
                }
            }
        }

        /*stage('AppConfig (Homologation)') { steps {  echo "OK" } }
        stage('DB Migration (Homologation)') { steps {  echo "OK" } }*/

        stage ( 'Deploy (Homologation)' ) {
            steps {
                script {
                    def data = readJSON file: env.GOOGLE_APPLICATION_CREDENTIALS 
                     _environments.uat.name = "uat-${env.APP_NAME.toLowerCase().replace('_','-').replace('/','-').replace('.','-')}"
                    sh """
                        export GOOGLE_APPLICATION_CREDENTIALS=${env.GOOGLE_APPLICATION_CREDENTIALS}
                        gcloud config set project ${data.project_id}
                        gcloud config set compute/zone ${env.GOOGLE_ZONE}
                        gcloud auth activate-service-account ${data.client_email} --key-file=${env.GOOGLE_APPLICATION_CREDENTIALS} --project=${data.project_id}
                        gcloud run deploy ${_environments.uat.name} \
                            --image ${env.REGISTRY_HOST}snapshot/${env.APP_NAME}:${env.APP_VERSION} \
                            --platform managed \
                            --memory 2Gi \
                            --concurrency 1000 \
                            --timeout 1m20s \
                            --max-instances 5 \
                            --cpu 1000m \
                            --port 9501 \
                            --labels "name=${_environments.uat.name}" \
                            --region ${env.GOOGLE_REGION} \
                            --allow-unauthenticated \
                            --revision-suffix "${env.APP_VERSION.replace('.','-')}-${commit}" \
                            --set-env-vars "APP_ENV=development"
                    """
                    def service = readJSON(text: sh(script: """
                        gcloud run services describe ${_environments.uat.name} \
                            --platform managed \
                            --region ${env.GOOGLE_REGION} \
                            --format json
                        """, returnStdout : true).trim()
                    )
                    _environments.uat.url = service.status.address.url
                }
            }
            post {
                success {
                    slackSend(channel: slack?.threadId, message: "Implantação do container no ambiente de homologação realizada com sucesso.\nlink: ${_environments.uat.url}")
                }
                failure {
                    slackSend(channel: slack?.threadId, message: "Falha ao implantar o container no ambiente de homologação .\nlink:${env.BUILD_URL}")
                }
            }
        }

        stage ('Validation (Homologation)') {
            parallel {
                stage("healthz") {
                     steps {
                        script {
                            sh """ curl -X GET -H "Content-type: application/json" ${_environments.uat.url}/health """ 
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
                                    pe.value = "${_environments.uat.url}".toString()
                                }
                            }
                            new File("${pwd()}/tests/smoke/uat-environment.json").write(JsonOutput.toJson(_newmanEnv))
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

                            def _newmanEnv = readJSON file: "${pwd()}/tests/functional/environment.json"
                            for ( pe in _newmanEnv.values ) {
                                if ( pe.key == "hostname" ) {
                                    pe.value = "${_environments.uat.url}".toString()
                                }
                            }

                            new File(
                                "${pwd()}/tests/functional/uat-environment.json"
                            ).write(
                                JsonOutput.toJson(
                                    _newmanEnv
                                )
                            )

                            echo "Aplicação publicada com sucesso: ${_environments.dev.url}" 
                            sh """
                                newman run \
                                    ${pwd()}/tests/functional/baseline_graphql_siler_functional.postman_collection.json \
                                        -e ${pwd()}/tests/functional/uat-environment.json \
                                        -r cli,json,junit \
                                        --reporter-junit-export="${pwd()}/tests/functional/_report/uat-newman-report.xml" \
                                        --insecure \
                                        --color on \
                                        --disable-unicode 
                            """
                        }
                    }
                }
                /*stage("security") {
                    steps {
                        script {
                            echo "Aplicação publicada com sucesso" 
                        }
                    }
                }*/
                stage ("load") {
                    agent {
                        docker { 
                            image 'blazemeter/taurus'
                            args  """ -u 0:0 --entrypoint='' -v "${pwd()}/tests/load:/bzt-configs" """
                        }
                    }
                    steps {
                        unstash 'checkoutSources'
                        script {
                            sh """  
                                cd /bzt-configs 
                                bzt load-test.yml \
                                    --quiet \
                                    -o modules.console.disable=true \
                                    -o settings.verbose=false \
                                    -o settings.env.HOSTNAME="${_environments.dev.url}"
                                chown ${env.JKS_USERID}:${env.JKS_GROUPID} * -R
                            """
                        }
                    }
                }
            }
            post {
                success {
                    slackSend(channel: slack?.threadId, message: "Validação da implantação no ambiente de homologação realizada com sucesso.")
                }
                failure {
                    slackSend(channel: slack?.threadId, message: "Falha ao realizar a implantação no ambiente de homologação.\nlink:${env.BUILD_URL}")
                }
            }
        }
        
        stage ('Release Registry') {
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

        stage ('Approval Production Deploy') {
            steps {
                script {
                    slackSend(channel: slack?.threadId, message: "Solicitando aprovação para entregar no ambiente de produção.\nlink:${enb.BUILD_URL}/input")
                    timeout(time: 1, unit: 'HOURS') {
                        input message: 'Aprovar a implantação em produção?', ok: 'Yes'
                    }
                }
            }
        }

        /*stage('AppConfig (Production)') { steps {  echo "OK" } }
        stage('DB Migration (Production)') { steps {  echo "OK" } }*/

        stage('Deploy (Production)') {
            steps {
                script {
                    def data = readJSON file: env.GOOGLE_APPLICATION_CREDENTIALS 
                    _environments.prd.name = "prd-${env.APP_NAME.toLowerCase().replace('_','-').replace('/','-').replace('.','-')}"
                    sh """
                        export GOOGLE_APPLICATION_CREDENTIALS=${env.GOOGLE_APPLICATION_CREDENTIALS}
                        gcloud config set project ${data.project_id}
                        gcloud config set compute/zone ${env.GOOGLE_ZONE}
                        gcloud auth activate-service-account ${data.client_email} --key-file=${env.GOOGLE_APPLICATION_CREDENTIALS} --project=${data.project_id}
                        gcloud run deploy ${_environments.prd.name} \
                            --image ${env.REGISTRY_HOST}release/${env.APP_NAME}:${env.APP_VERSION} \
                            --platform managed \
                            --memory 2Gi \
                            --concurrency 1000 \
                            --timeout 1m20s \
                            --max-instances 5 \
                            --cpu 1000m \
                            --port 9501 \
                            --labels "name=${_environments.prd.name}" \
                            --region ${env.GOOGLE_REGION} \
                            --allow-unauthenticated \
                            --revision-suffix "${env.APP_VERSION.replace('.','-')}-${commit}" \
                            --set-env-vars "APP_ENV=development"
                    """
                    
                    def service = readJSON(text: sh(script: """
                        gcloud run services describe ${_environments.prd.name} \
                            --platform managed \
                            --region ${env.GOOGLE_REGION} \
                            --format json
                        """, returnStdout : true).trim()
                    )

                    _environments.prd.url = service.status.address.url

                }
            }
            post {
                success {
                    slackSend(channel: slack?.threadId, message: "Production Deploy: finalizado com sucesso. Url: ${_environments.prd.url}")
                }
                failure {
                    slackSend(channel: slack?.threadId, message: "Falha ao implantar o container no ambiente de produção .\nlink:${env.BUILD_URL}")
                }
            }
        }

        stage('Validation (Production)') {
            parallel {
                stage("healthz") {
                    steps {
                        script {
                            sh """ curl -X GET -H "Content-type: application/json" ${_environments.prd.url}/health """ 
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
                                    pe.value = "${_environments.prd.url}".toString()
                                }
                            }

                            new File(
                                "${pwd()}/tests/smoke/prd-environment.json"
                            ).write(
                                JsonOutput.toJson(
                                    _newmanEnv
                                )
                            )

                            echo "Aplicação publicada com sucesso: ${_environments.prd.url}" 
                            sh """
                                newman run \
                                    ${pwd()}/tests/smoke/baseline_graphql_siler_smoke.postman_collection.json \
                                        -e ${pwd()}/tests/smoke/prd-environment.json \
                                        -r cli,json,junit \
                                        --reporter-junit-export="${pwd()}/tests/smoke/_report/prd-newman-report.xml" \
                                        --insecure \
                                        --color on \
                                        --disable-unicode 
                            """
                        }
                    }
                }
            } 
            post {
                success {
                    slackSend(channel: slack?.threadId, message: "Validação da implantação no ambiente de produção realizada com sucesso.")
                }
                failure {
                    slackSend(channel: slack?.threadId, message: "Falha ao realizar a implantação no ambiente de produção.\nlink:${env.BUILD_URL}")
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
            /*
            script {
                sh "zip -r dist.zip ./"
            }
            */

            //junit "tests/_reports/**/*.xml"

            //archiveArtifacts artifacts: 'dist.zip', fingerprint: true
            
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
            /*
            publishHTML target: [
                allowMissing: false,
                alwaysLinkToLastBuild: false,
                keepAll: true,
                reportDir: 'tests/_reports/coverage',
                reportFiles: 'index.html',
                reportName: 'Coverage'
            ]*/
        }

        failure {
            echo 'The Pipeline failed :('
        }
    }
}