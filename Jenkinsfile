pipeline {
    agent any
    
    environment {
        DOCKER_REGISTRY = credentials('DOCKER_REGISTRY_URL')
        DOCKER_REGISTRY_CREDENTIALS = credentials('DOCKER_REGISTRY_CREDENTIALS')
        AWS_CREDENTIALS = credentials('AWS_CREDENTIALS')
        KUBECTL_CREDENTIALS = credentials('KUBECTL_CREDENTIALS')
        TERRAFORM_CREDENTIALS = credentials('TERRAFORM_CREDENTIALS')
        IMAGE_TAG = "${BUILD_NUMBER}"
        REPO_NAME = "mern-app"
    }
    
    stages {
        stage('Environment Setup') {
            steps {
                script {
                    echo "Setting up environment for build ${BUILD_NUMBER}"
                    sh '''
                        # Install required tools
                        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
                        sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
                        
                        # Install Terraform
                        sudo apt-get update && sudo apt-get install -y wget unzip
                        wget https://releases.hashicorp.com/terraform/1.5.0/terraform_1.5.0_linux_amd64.zip
                        sudo unzip terraform_1.5.0_linux_amd64.zip -d /usr/local/bin/
                        sudo chmod +x /usr/local/bin/terraform
                        
                        # Install Ansible
                        sudo apt-get install -y python3-pip
                        pip3 install ansible
                    '''
                }
            }
        }
        
        stage('Code Quality & Testing') {
            parallel {
                stage('Backend Tests') {
                    steps {
                        dir('ansible/roles/webserver/files/app') {
                            sh '''
                                npm install
                                npm test
                            '''
                        }
                    }
                }
                stage('Frontend Tests') {
                    steps {
                        dir('ansible/roles/webserver/files/app/client') {
                            sh '''
                                npm install
                                npm test
                            '''
                        }
                    }
                }
                stage('Linting') {
                    steps {
                        dir('ansible/roles/webserver/files/app') {
                            sh '''
                                npx eslint server.js
                            '''
                        }
                        dir('ansible/roles/webserver/files/app/client') {
                            sh '''
                                npx eslint src/
                            '''
                        }
                    }
                }
            }
        }
        
        stage('Build Docker Images') {
            steps {
                script {
                    def dockerfiles = [
                        'ansible/roles/webserver/files/Dockerfile'
                    ]
                    
                    dockerfiles.each { dockerfile ->
                        def serviceName = dockerfile.contains('webserver') ? 'webserver' : 'dbserver'
                        sh '''
                            docker build -f ''' + dockerfile + ''' -t ''' + serviceName + ''':''' + env.IMAGE_TAG + ''' ''' + dockerfile.split('/files/')[0] + '''
                            docker tag ''' + serviceName + ''':''' + env.IMAGE_TAG + ''' ''' + env.DOCKER_REGISTRY + '''/''' + env.REPO_NAME + '''/''' + serviceName + ''':''' + env.IMAGE_TAG + '''
                        '''
                    }
                }
            }
        }
        
        stage('Push to Registry') {
            steps {
                sh '''
                    echo ''' + env.DOCKER_REGISTRY_CREDENTIALS + ''' | docker login ''' + env.DOCKER_REGISTRY + ''' -u ''' + env.DOCKER_REGISTRY_CREDENTIALS.split(':')[0] + ''' --password-stdin
                    docker push ''' + env.DOCKER_REGISTRY + '''/''' + env.REPO_NAME + '''/webserver:''' + env.IMAGE_TAG + '''
                '''
            }
        }
        
        stage('Infrastructure Deployment') {
            when {
                anyOf {
                    branch 'main'
                    branch 'develop'
                    changeRequest()
                }
            }
            steps {
                script {
                    def environment = env.BRANCH_NAME == 'main' ? 'prod' : env.BRANCH_NAME == 'develop' ? 'staging' : 'dev'
                    dir("terraform/envs/${environment}") {
                        sh '''
                            terraform init
                            terraform plan -var-file="${environment}.tfvars" -out=tfplan
                            terraform apply tfplan
                        '''
                    }
                }
            }
        }
        
        stage('Application Deployment') {
            when {
                anyOf {
                    branch 'main'
                    branch 'develop'
                    changeRequest()
                }
            }
            steps {
                script {
                    def environment = env.BRANCH_NAME == 'main' ? 'prod' : env.BRANCH_NAME == 'develop' ? 'staging' : 'dev'
                    
                    // Update K8s manifests with new image tag
                    sh '''
                        sed -i "s/latest/''' + env.IMAGE_TAG + '''/g" k8s/webserver-deployment.yaml
                        sed -i "s/latest/''' + env.IMAGE_TAG + '''/g" k8s/mongo-deployment.yaml
                    '''
                    
                    // Deploy to K8s
                    sh '''
                        kubectl apply -f k8s/namespace.yaml
                        kubectl apply -f k8s/
                        kubectl rollout status deployment/webserver -n mern-app
                        kubectl rollout status deployment/mongo -n mern-app
                    '''
                    
                    // Run Ansible playbook for EC2 deployment
                    if (environment != 'dev') {
                        sh '''
                            cd ansible
                            ansible-playbook -i inventory/hosts playbook.yaml
                        '''
                    }
                }
            }
        }
        
        stage('Security Scanning') {
            parallel {
                stage('Container Security') {
                    steps {
                        sh '''
                            # Install Trivy
                            sudo apt-get install wget apt-transport-https gnupg lsb-release
                            wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo apt-key add -
                            echo "deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | sudo tee -a /etc/apt/sources.list.d/trivy.list
                            sudo apt-get update
                            sudo apt-get install trivy
                            
                            # Scan Docker images
                            trivy image ''' + env.DOCKER_REGISTRY + '''/''' + env.REPO_NAME + '''/webserver:''' + env.IMAGE_TAG + '''
                        '''
                    }
                }
                stage('Infrastructure Security') {
                    steps {
                        dir('terraform') {
                            sh '''
                                # Install tfsec
                                curl -s https://raw.githubusercontent.com/aquasecurity/tfsec/master/scripts/install_linux.sh | bash
                                tfsec .
                            '''
                        }
                    }
                }
            }
        }
        
        stage('Integration Tests') {
            when {
                anyOf {
                    branch 'main'
                    branch 'develop'
                    changeRequest()
                }
            }
            steps {
                script {
                    sh '''
                        # Wait for services to be ready
                        sleep 30
                        
                        # Test endpoints
                        kubectl get services -n mern-app
                        
                        # Run integration tests
                        curl -f http://webserver-service.mern-app.svc.cluster.local:5000/api || exit 1
                        
                        echo "Integration tests passed successfully"
                    '''
                }
            }
        }
        
        stage('Performance Tests') {
            when {
                branch 'main'
            }
            steps {
                sh '''
                    # Install Apache Bench
                    sudo apt-get install -y apache2-utils
                    
                    # Basic load test
                    ab -n 100 -c 10 http://webserver-service.mern-app.svc.cluster.local:5000/api
                '''
            }
        }
    }
    
    post {
        success {
            script {
                def environment = env.BRANCH_NAME == 'main' ? 'prod' : env.BRANCH_NAME == 'develop' ? 'staging' : 'dev'
                
                // Cleanup old Docker images
                sh '''
                    docker rmi $(docker images -q ''' + env.REPO_NAME + ''') || true
                '''
                
                // Send success notification
                echo "✅ Pipeline completed successfully for ${environment} environment"
            }
        }
        
        failure {
            script {
                // Send failure notification
                echo "❌ Pipeline failed for build ${BUILD_NUMBER}"
                
                // Collect logs for debugging
                sh '''
                    kubectl get pods -n mern-app
                    kubectl logs -l app=webserver -n mern-app --tail=50
                    kubectl logs -l app=mongo -n mern-app --tail=50
                '''
            }
        }
        
        always {
            // Clean up workspace
            cleanWs()
        }
    }
}
