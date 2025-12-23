# Jenkins Deployment Guide for MERN App DevOps

This guide provides step-by-step instructions for setting up Jenkins to deploy the MERN App DevOps infrastructure.

## 📋 Prerequisites

### Jenkins Requirements
- Jenkins 2.350+ with plugins:
  - Pipeline
  - Docker Pipeline
  - Kubernetes CLI Plugin
  - Terraform Plugin
  - Ansible Plugin
  - AWS Credentials Plugin
  - Git Parameter Plugin
  - Blue Ocean (recommended)

### System Requirements
- Jenkins server with Docker support
- At least 4GB RAM and 2 CPU cores
- Internet connectivity for tool installations

## 🔧 Jenkins Setup

### 1. Jenkins Credentials Setup

Configure the following credentials in Jenkins:

```bash
# Navigate to: Jenkins > Manage Jenkins > Manage Credentials

DOCKER_REGISTRY_URL
├── ID: DOCKER_REGISTRY_URL
├── Description: Docker registry URL
└── Type: Secret Text

DOCKER_REGISTRY_CREDENTIALS
├── ID: DOCKER_REGISTRY_CREDENTIALS
├── Description: Docker registry username:password
└── Type: Username with password

AWS_CREDENTIALS
├── ID: AWS_CREDENTIALS
├── Description: AWS Access Key and Secret Key
└── Type: AWS Credentials

KUBECTL_CREDENTIALS
├── ID: KUBECTL_CREDENTIALS
├── Description: Kubernetes config file
└── Type: Secret File

TERRAFORM_CREDENTIALS
├── ID: TERRAFORM_CREDENTIALS
├── Description: Terraform backend credentials
└── Type: Username with password
```

### 2. Jenkins Global Tool Configuration

```bash
# Navigate to: Jenkins > Manage Jenkins > Global Tool Configuration

# Docker
├── Name: docker
└── Path: /usr/bin/docker

# Terraform
├── Name: terraform
├── Version: 1.5.0
└── Install automatically: checked

# kubectl
├── Name: kubectl
└── Path: /usr/local/bin/kubectl

# Ansible
├── Name: ansible
└── Path: /usr/bin/ansible
```

### 3. Create Jenkins Job

#### Option A: Pipeline Job (Recommended)

```bash
# Navigate to: Jenkins > New Item
# Job Name: mern-app-deploy
# Select: Pipeline
# Click OK

Pipeline Configuration:
├── Definition: Pipeline script from SCM
├── SCM: Git
│   ├── Repository URL: <your-repo-url>
│   ├── Credentials: <your-git-credentials>
│   └── Script Path: Jenkinsfile
├── Branches to build: */main, */develop
└── Pipeline triggers: GitHub hook trigger for GITScm polling
```

#### Option B: Multibranch Pipeline

```bash
# Navigate to: Jenkins > New Item
# Job Name: mern-app-multibranch
# Select: Multibranch Pipeline
# Click OK

Branch Sources:
├── GitHub
│   ├── Repository URL: <your-repo-url>
│   ├── Credentials: <your-git-credentials>
│   └── Behaviors: Discover branches, Discover pull requests

Build Configuration:
├── Mode: by Jenkinsfile
└── Script Path: Jenkinsfile

Scan Multibranch Pipeline Triggers:
├── Periodically if not otherwise run
└── Interval: 1 minute
```

### 4. Pipeline Parameters

Add the following parameters to your job:

```bash
# Navigate to: Job Configuration > General > This project is parameterized

ENVIRONMENT
├── Type: Choice
├── Choices:
│   ├── dev
│   ├── staging
│   └── prod
└── Default: dev

SKIP_TESTS
├── Type: Boolean
├── Description: Skip running tests during deployment
└── Default: false

FORCE_DEPLOY
├── Type: Boolean
├── Description: Force deployment without confirmation
└── Default: false

ROLLBACK
├── Type: Boolean
├── Description: Rollback to previous version
└── Default: false
```

## 🏗️ Jenkins Pipeline Stages

### Stage 1: Environment Setup
- Installs required tools (kubectl, terraform, ansible)
- Sets up environment variables
- Validates credentials

### Stage 2: Code Quality & Testing
- **Backend Tests**: Runs Jest tests for Node.js backend
- **Frontend Tests**: Runs React component tests
- **Linting**: ESLint validation for code quality
- **Security Audit**: npm audit for vulnerability scanning

### Stage 3: Build Docker Images
- Builds multi-stage Docker images
- Optimizes image size and security
- Tags images with build number

### Stage 4: Push to Registry
- Authenticates with Docker registry
- Pushes images to registry
- Verifies image upload

### Stage 5: Infrastructure Deployment
- Deploys AWS infrastructure with Terraform
- Creates VPC, subnets, security groups
- Provisions EC2 instances
- Sets up networking

### Stage 6: Application Deployment
- Deploys with Ansible
- Configures web server and database
- Updates Kubernetes manifests
- Applies to cluster

### Stage 7: Security Scanning
- **Container Security**: Trivy vulnerability scanning
- **Infrastructure Security**: tfsec Terraform analysis
- **Dependency Security**: npm audit

### Stage 8: Integration Tests
- Tests API endpoints
- Validates database connectivity
- Checks service availability

### Stage 9: Performance Tests
- Load testing with Apache Bench
- Response time monitoring
- Resource utilization checks

## 🔄 Deployment Workflows

### Development Deployment
```bash
# Trigger: Manual or on feature branch push
Environment: dev
Stages: Build, Test, Deploy
Success Criteria: All tests pass, services healthy
Rollback: Automatic on failure
```

### Staging Deployment
```bash
# Trigger: Merge to develop branch
Environment: staging
Stages: Full pipeline including security scans
Success Criteria: All tests, security scans, integration tests pass
Rollback: Manual approval required
```

### Production Deployment
```bash
# Trigger: Merge to main branch
Environment: prod
Stages: Full pipeline with performance tests
Success Criteria: All tests, security scans, performance benchmarks
Rollback: Manual approval with change management
```

## 📊 Monitoring & Notifications

### Jenkins Notification Setup

```groovy
// Add to Jenkinsfile post section
post {
    success {
        // Send success notifications
        emailext (
            subject: "✅ MERN App Deployment Success - ${env.ENVIRONMENT}",
            body: """
                Deployment Details:
                - Environment: ${env.ENVIRONMENT}
                - Build Number: ${env.BUILD_NUMBER}
                - Branch: ${env.BRANCH_NAME}
                - Timestamp: ${new Date().toString()}
                
                <a href="${env.BUILD_URL}">View Build Details</a>
            """,
            to: "devops@yourcompany.com"
        )
    }
    
    failure {
        // Send failure notifications
        emailext (
            subject: "❌ MERN App Deployment Failed - ${env.ENVIRONMENT}",
            body: """
                Deployment Failed:
                - Environment: ${env.ENVIRONMENT}
                - Build Number: ${env.BUILD_NUMBER}
                - Branch: ${env.BRANCH_NAME}
                - Timestamp: ${new Date().toString()}
                
                <a href="${env.BUILD_URL}">View Build Details</a>
            """,
            to: "devops@yourcompany.com"
        )
        
        // Collect logs for debugging
        sh '''
            kubectl get pods -n mern-app-${ENVIRONMENT}
            kubectl logs -l app=webserver -n mern-app-${ENVIRONMENT} --tail=50
        '''
    }
}
```

### Slack Integration

```groovy
// Add Slack notification to Jenkinsfile
post {
    always {
        script {
            if (env.SLACK_WEBHOOK_URL) {
                def color = currentBuild.currentResult == 'SUCCESS' ? 'good' : 'danger'
                def message = currentBuild.currentResult == 'SUCCESS' ? 
                    "✅ Deployment successful to ${env.ENVIRONMENT}" : 
                    "❌ Deployment failed to ${env.ENVIRONMENT}"
                
                slackSend(
                    channel: '#devops',
                    color: color,
                    message: message,
                    attachments: [
                        [
                            fields: [
                                [title: 'Environment', value: env.ENVIRONMENT, short: true],
                                [title: 'Build Number', value: env.BUILD_NUMBER, short: true],
                                [title: 'Branch', value: env.BRANCH_NAME, short: true]
                            ]
                        ]
                    ]
                )
            }
        }
    }
}
```

## 🔧 Troubleshooting

### Common Issues

1. **Docker Build Fails**
   ```bash
   # Check Docker daemon status
   sudo systemctl status docker
   
   # Verify Dockerfile syntax
   docker build -f ansible/roles/webserver/files/Dockerfile .
   ```

2. **Terraform State Issues**
   ```bash
   # Check Terraform state
   terraform show
   
   # Force state refresh
   terraform refresh
   ```

3. **Kubernetes Connection Issues**
   ```bash
   # Verify kubeconfig
   kubectl config view
   
   # Test cluster connectivity
   kubectl cluster-info
   ```

4. **Ansible Playbook Errors**
   ```bash
   # Check Ansible syntax
   ansible-playbook --check ansible/playbook.yaml
   
   # Test connectivity
   ansible -m ping all
   ```

### Debug Mode

Enable debug mode in Jenkinsfile:

```groovy
pipeline {
    agent any
    environment {
        DEBUG = 'true'
        ANSIBLE_VERBOSITY = '3'
    }
    // ... rest of pipeline
}
```

### Log Collection

```bash
# Collect deployment logs
./scripts/health-check.sh dev --verbose > deployment-logs.txt

# Collect system information
kubectl get nodes -o wide > cluster-info.txt
kubectl get all -n mern-app-dev > k8s-resources.txt
```

## 🔐 Security Best Practices

### Jenkins Security
- Enable CSRF protection
- Use role-based access control
- Restrict job configuration access
- Enable audit logging

### Credential Management
- Use Jenkins credential store
- Rotate credentials regularly
- Use environment variables for sensitive data
- Never hardcode secrets in pipeline scripts

### Pipeline Security
- Validate all inputs
- Use least privilege principle
- Implement proper error handling
- Log all security-sensitive operations

## 📈 Performance Optimization

### Jenkins Performance
- Use agent nodes for builds
- Implement build caching
- Use parallel execution where possible
- Monitor job execution times

### Pipeline Optimization
- Cache dependencies
- Use incremental builds
- Parallelize test execution
- Implement build artifacts

## 🚀 Advanced Features

### Blue Ocean UI
- Install Blue Ocean plugin
- Create visual pipeline representations
- Monitor pipeline health
- Track deployment metrics

### GitOps Integration
- Use ArgoCD for GitOps workflows
- Sync Kubernetes manifests from Git
- Implement progressive deployments
- Add rollback capabilities

### Monitoring Integration
- Integrate with Prometheus/Grafana
- Set up alerting rules
- Monitor deployment success rates
- Track performance metrics

## 📞 Support

For Jenkins deployment support:
- Documentation: [Jenkins Documentation](https://www.jenkins.io/doc/)
- Community: [Jenkins Community](https://www.jenkins.io/community/)
- Issues: Create issue in project repository

---

**Next Steps**: After setting up Jenkins, proceed with testing the deployment pipeline and customizing configurations for your specific environment.
