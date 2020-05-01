import groovy.json.JsonOutput

def container
def commit
def commitChangeset
def changeLogSets = ""
def _environments = [
    dev : [
        name : "",
        url : "",
        prev : "",
        envFile : ""
    ],
    uat : [
        name : "",
        url : "",
        prev : "",
        envFile : ""
    ],
    prd : [
        name : "",
        url : "",
        prev : "",
        envFile : ""
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
                    slack = slackSend(
                        notifyCommitters : true,
                        color : "#162e63",
                        message: "Iniciando uma nova entrega, segue links para mais informações:\n" +
                        "*App:* ${env.APP_NAME}\n" +
                        "*Version:* ${env.APP_VERSION}\n" +
                        "*Commit:* ${commit}\n" +
                        "*User:* ${currentBuild.rawBuild.getCause(hudson.model.Cause$UserIdCause)?.userName?:'auto'}\n" +
                        "*Job:* ${env.JOB_NAME} - (${env.JOB_URL})\n" +
                        "*Build:* ${env.BUILD_ID} - (${env.BUILD_URL})\n"
                    )
                    for (int i = 0; i < currentBuild.changeSets.size(); i++) {
                        def entries = currentBuild.changeSets[i].items
                        for (int j = 0; j < entries.length; j++) {
                            def entry = entries[j]
                            changeLogSets += "${entry.msg} \nby ${entry.author}\n(${new Date(entry.timestamp)})\n\n"
                            def files = new ArrayList(entry.affectedFiles)
                            for (int k = 0; k < files.size(); k++) {
                                def file = files[k]
                                //changeLogSets += "    ${file.editType.name} ${file.path}\n"
                            }
                        }
                    }
                }
                stash includes: '**/*', name: 'checkoutSources'
            }
            post {
                success {
                    slackSend( color : "#073d15",  channel: slack?.threadId, message: "Os fontes da aplicação foram obtidos com sucesso. Confira o change-log:\n${changeLogSets}")
                }
                failure {
                    slackSend(color: "#540c05",  channel: slack?.threadId, message: "Falha ao obter os fontes da aplicação.\nLink: ${env.BUILD_URL}")
                }
            }
        }

        stage ( 'Dependencies Restore' ) {
            agent {
                docker { image 'phpswoole/swoole' }
            }
            steps {
                slackSend( color : "#7a7c80",  channel: slack?.threadId, message: "Iniciando a restauração das dependências.")
                sh " composer -q -n install "
                stash includes: 'vendor/**/*', name: 'restoreSources'
            }
            post {
                success {
                    slackSend(color: "#073d15", channel: slack?.threadId, message: "Restauração de dependencias finalizada com sucesso.")
                }
                failure {
                    slackSend(color: "#540c05", channel: slack?.threadId, message: "Falha ao restaur as dependencias.\nLink: ${env.BUILD_URL}")
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
                slackSend( color : "#7a7c80",  channel: slack?.threadId, message: "Iniciando a execução dos testes unitários.")
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
                    slackSend(color: "#073d15", channel: slack?.threadId, message: "Testes realizados com sucesso.")
                }
                failure {
                    slackSend(color: "#540c05", channel: slack?.threadId, message: "Falha ao realizar os testes.\nLink: ${env.BUILD_URL}")
                }
            }
        }

        stage ( 'Quality Gate' ) {
            steps {
                slackSend( color : "#7a7c80",  channel: slack?.threadId, message: "Iniciando o processo de analise de código.")
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
                sleep(10)
                timeout (time: 1, unit: 'HOURS') {
                    waitForQualityGate abortPipeline: true
                }
            }
            post {
                success {
                    slackSend(color: "#073d15", channel: slack?.threadId, message: "Portal de qualidade finalizado com sucesso.\nlink:https://sonarcloud.io/dashboard?id=${env.SONAR_PROJECT_KEY}")
                }
                failure {
                    slackSend(color: "#540c05", channel: slack?.threadId, message: "Falha ao passar pelo portal de qualidade.\nLink: ${env.BUILD_URL}")
                }
            }
        }

        stage ( 'Container Build' ) {
            steps {
                slackSend( color : "#7a7c80",  channel: slack?.threadId, message: "Criando o container com a aplicação.")
                script {
                    unstash 'restoreSources'
                    echo "${env.REGISTRY_HOST}snapshot/${env.APP_NAME}:${env.APP_VERSION}"
                    container = docker.build("${env.REGISTRY_HOST}snapshot/${env.APP_NAME}:${env.APP_VERSION}", " -f Build.Dockerfile . ")
                }
            }
            post {
                success {
                    slackSend(color: "#073d15", channel: slack?.threadId, message: "Aplicação containerizada com sucesso.")
                }
                failure {
                    slackSend(color: "#540c05", channel: slack?.threadId, message: "Falha ao construir o container com a aplicação.\nLink: ${env.BUILD_URL}")
                }
            }
        }

        stage ( 'Snapshot Registry' ) {
            steps {
                slackSend( color : "#7a7c80",  channel: slack?.threadId, message: "Enviando o container para o registry. Link: https://${env.REGISTRY_HOST}snapshot/")
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
                    slackSend(color: "#073d15", channel: slack?.threadId, message: "Container classificado como snapshot e enviado para o registrador com sucesso.")
                }
                failure {
                    slackSend(color: "#540c05", channel: slack?.threadId, message: "Falha ao registrar o container.\nLink: ${env.BUILD_URL}")
                }
            }
        }
        
        stage( 'AppConfig (Development)') { 
            steps {   
                echo "OK" 
                script {
                    _environments.dev.envFile = requestEnv(env.APP_NAME, "development")
                }
            } 
        }

        /*stage( 'DB Migration (Development)') { steps {  echo "OK" } }*/

        stage ( 'Deploy (Development)' ) {
            steps {
                script {
                    slackSend( color : "#7a7c80",  channel: slack?.threadId, message: "Inicializando a implantação no ambiente de desenvolvimento.")
                    def data = readJSON file: env.GOOGLE_APPLICATION_CREDENTIALS 
                    _environments.dev.name = "dev-${env.APP_NAME.toLowerCase().replace('_','-').replace('/','-').replace('.','-')}"
                    sh """
                        export GOOGLE_APPLICATION_CREDENTIALS=${env.GOOGLE_APPLICATION_CREDENTIALS}
                        gcloud config set project ${data.project_id}
                        gcloud config set compute/zone ${env.GOOGLE_ZONE}
                        gcloud auth activate-service-account ${data.client_email} --key-file=${env.GOOGLE_APPLICATION_CREDENTIALS} --project=${data.project_id}
                    """
                    try{
                        _environments.dev.prev = readJSON(text:sh(
                            script: """ gcloud run revisions list \
                                --service ${_environments.dev.name} \
                                --format json \
                                --platform managed \
                                --region ${env.GOOGLE_REGION}
                            """, 
                            returnStdout : true
                        ).trim())?.first()?.metadata?.name
                    } catch (e) {
                        _environments.dev.prev = ""
                    }
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
                    slackSend(color: "#073d15", channel: slack?.threadId, message: "Implantação do container no *ambiente de desenvolvimento* realizada com sucesso.\nlink: ${_environments.dev.url}")
                }
                failure {
                    slackSend(color: "#540c05", channel: slack?.threadId, message: "Falha ao implantar o container no *ambiente de desenvolvimento*.\nLink: ${env.BUILD_URL}")
                }
            }
        }

        stage ( 'Validation (Development)' ) {
            parallel {
                stage ("notify") {
                    steps {
                        slackSend( color : "#7a7c80",  channel: slack?.threadId, message: "Validando a nova implantação no ambiente de desenvolvimento.")
                    }
                }
                stage("healthz") {
                    steps {
                        script {
                            httpRequest(
                                url : "${_environments.dev.url}/health",
                                httpMode : "GET",
                                acceptType : "APPLICATION_JSON",
                                contentType : "APPLICATION_JSON",
                                validResponseCodes : "200"
                            )
                            //sh """ curl -X GET -H "Content-type: application/json" ${_environments.dev.url}/health """ 
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
                        stash includes: 'tests/functional/_report/*', name: 'testFuncDevSources'
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
                    unstash 'testFuncDevSources'
                    junit "tests/functional/_report/*.xml"

                    allure([
                        includeProperties: false,
                        jdk: '',
                        properties: [],
                        reportBuildPolicy: 'ALWAYS',
                        results: [
                            [path: "tests/functional/_report/"]
                        ]
                    ])
                    slackSend(color: "#073d15", channel: slack?.threadId, message: "Validação da implantação no *ambiente de desenvolvimento* realizada com sucesso.")
                }
                failure {
                    slackSend(color: "#540c05", channel: slack?.threadId, message: "Falha ao realizar a implantação no *ambiente de desenvolvimento*.\nLink: ${env.BUILD_URL}")
                }
            }
        }

        stage ( 'Approval Homologation Deploy' ) {
            steps {
                slackSend(notifyCommitters : true, color : "#ffb833",  channel: slack?.threadId, message: "Solicitação de aprovação para implantar a nova versão em homologação.\nlink: ${env.BUILD_URL}input")
                script {
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
                slackSend( color : "#7a7c80",  channel: slack?.threadId, message: "Iniciando a implantação da nova versão no ambiente de homologação.")
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
                    slackSend(color: "#073d15", channel: slack?.threadId, message: "Implantação do container no *ambiente de homologação* realizada com sucesso.\nlink: ${_environments.uat.url}")
                }
                failure {
                    slackSend(color: "#540c05", channel: slack?.threadId, message: "Falha ao implantar o container no *ambiente de homologação* .\nLink: ${env.BUILD_URL}")
                }
            }
        }

        stage ( 'Validation (Homologation)' ) {
            parallel {
                stage ("notify") {
                    steps {
                        slackSend( color : "#7a7c80",  channel: slack?.threadId, message: "Validando a nova versão no ambiente de homologação.")
                    }
                }
                stage("healthz") {
                    steps {
                        script {
                            httpRequest(
                                url : "${_environments.uat.url}/health",
                                httpMode : "GET",
                                acceptType : "APPLICATION_JSON",
                                contentType : "APPLICATION_JSON",
                                validResponseCodes : "200"
                            )
                            //sh """ curl -X GET -H "Content-type: application/json"  """ 
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
                    slackSend(color: "#073d15", channel: slack?.threadId, message: "Validação da implantação no *ambiente de homologação* realizada com sucesso.")
                }
                failure {
                    slackSend(color: "#540c05", channel: slack?.threadId, message: "Falha ao realizar a implantação no *ambiente de homologação*.\nLink: ${env.BUILD_URL}")
                }
            }
        }
        
        stage ( 'Release Registry' ) {
            steps {
                slackSend( color : "#7a7c80",  channel: slack?.threadId, message: "Promovendo e registrando o container no registrador de lançamentos. Link: https://${env.REGISTRY_HOST}release")
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

        stage ( 'Approval Production Deploy' ) {
            steps {
                slackSend( notifyCommitters : true, color : "#ffb833",  channel: slack?.threadId, message: "Solicitação de aprovação para implantar a nova versão no ambiente de produção.\nlink: ${env.BUILD_URL}input")
                script {
                    timeout(time: 1, unit: 'HOURS') {
                        input message: 'Aprovar a implantação em produção?', ok: 'Sim'
                    }
                }
            }
        }

        /*stage('AppConfig (Production)') { steps {  echo "OK" } }
        stage('DB Migration (Production)') { steps {  echo "OK" } }*/

        stage ( 'Deploy (Production)' ) {
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
                    slackSend(color: "#073d15", channel: slack?.threadId, message: "Implantação do container no *ambiente de produção* realizada com sucesso.\nlink: ${_environments.prd.url}")
                }
                failure {
                    slackSend(color: "#540c05", channel: slack?.threadId, message: "Falha ao implantar o container no *ambiente de produção* .\nLink: ${env.BUILD_URL}")
                }
            }
        }

        stage( 'Validation (Production)' ) {
            parallel {
                stage ("notify") {
                    steps {
                        slackSend( color : "#7a7c80",  channel: slack?.threadId, message: "Validando a nova versão no ambiente de produção.")
                    }
                }
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
                    slackSend(color: "#073d15", channel: slack?.threadId, message: "Validação da implantação no ambiente de produção realizada com sucesso.")
                }
                failure {
                    slackSend(color: "#540c05", channel: slack?.threadId, message: "Falha ao realizar a implantação no ambiente de produção.\nLink: ${env.BUILD_URL}")
                }
            }
        }
    }

    post {

        always {
            cleanWs()
        }

        success {
            slackSend(color: "#073d15", channel: slack?.threadId, message: "*Processo de CI/CD* finalizado com sucesso!")
            
            /*script {
                sh "zip -r dist.zip ./"
            }*/

            //junit "tests/_reports/**/*.xml"

            //archiveArtifacts artifacts: 'dist.zip', fingerprint: true
            
            

            /*publishHTML target: [
                allowMissing: false,
                alwaysLinkToLastBuild: false,
                keepAll: true,
                reportDir: 'tests/_reports/coverage',
                reportFiles: 'index.html',
                reportName: 'Coverage'
            ]*/
        }

        failure {
            slackSend(color: "#540c05", channel: slack?.threadId, message: "Falha ao realizar o *processo de CI/CD*!")
        }
    }
}

def requestEnv(name, environment) {
    def envFile
    try{
        envFile = credentials("${name}.${environment}".toLowerCase())
        println "SUCESS:${envFile}"
    } catch (e) {
        println "ERRO:${e.getMessage()}"
        /*
        input("credential")
        store()
        envFile = credentials("${name}.${environment}".toLowerCase())
        */
    }
    envFile
}