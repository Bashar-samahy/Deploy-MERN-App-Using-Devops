#!/bin/bash

# Comprehensive deployment script for MERN App DevOps
# Usage: ./scripts/deploy.sh [environment] [options]

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENVIRONMENT="${1:-dev}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%s)}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Usage information
usage() {
    cat << EOF
Usage: $0 [ENVIRONMENT] [OPTIONS]

Environments:
  dev         Deploy to development (default)
  staging     Deploy to staging
  prod        Deploy to production

Options:
  --skip-tests     Skip running tests
  --force-deploy   Force deployment without confirmation
  --rollback       Rollback to previous version
  --dry-run        Show what would be deployed without deploying
  --help           Show this help message

Examples:
  $0 dev --dry-run
  $0 prod --force-deploy
  $0 staging --skip-tests

EOF
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local tools=("kubectl" "terraform" "ansible" "docker" "helm")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "$tool is not installed or not in PATH"
            exit 1
        fi
    done
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed"
        exit 1
    fi
    
    log_success "All prerequisites satisfied"
}

# Validate environment
validate_environment() {
    log_info "Validating environment: $ENVIRONMENT"
    
    local valid_envs=("dev" "staging" "prod")
    if [[ ! " ${valid_envs[@]} " =~ " ${ENVIRONMENT} " ]]; then
        log_error "Invalid environment: $ENVIRONMENT"
        log_error "Valid environments: ${valid_envs[*]}"
        exit 1
    fi
    
    log_success "Environment validation passed"
}

# Build Docker images
build_images() {
    log_info "Building Docker images for environment: $ENVIRONMENT"
    
    local registry="${DOCKER_REGISTRY:-}"
    local image_tag="${BUILD_NUMBER}"
    
    # Build webserver image
    if [ -f "${PROJECT_ROOT}/ansible/roles/webserver/files/Dockerfile" ]; then
        log_info "Building webserver image..."
        docker build \
            -f "${PROJECT_ROOT}/ansible/roles/webserver/files/Dockerfile" \
            -t "mern-webserver:${image_tag}" \
            "${PROJECT_ROOT}/ansible/roles/webserver/files/"
        
        if [ -n "$registry" ]; then
            docker tag "mern-webserver:${image_tag}" "${registry}/mern-app/webserver:${image_tag}"
            docker push "${registry}/mern-app/webserver:${image_tag}"
            log_success "Webserver image pushed to registry"
        fi
    else
        log_warning "Dockerfile not found, skipping webserver build"
    fi
    
    log_success "Docker image building completed"
}

# Deploy infrastructure with Terraform
deploy_infrastructure() {
    log_info "Deploying infrastructure for environment: $ENVIRONMENT"
    
    cd "${PROJECT_ROOT}/terraform/envs/${ENVIRONMENT}"
    
    # Initialize Terraform
    terraform init
    
    # Plan deployment
    log_info "Planning Terraform deployment..."
    terraform plan -var-file="${ENVIRONMENT}.tfvars" -out=tfplan
    
    # Apply changes
    log_info "Applying Terraform changes..."
    terraform apply tfplan
    
    log_success "Infrastructure deployment completed"
}

# Deploy application with Ansible
deploy_application() {
    log_info "Deploying application with Ansible..."
    
    cd "${PROJECT_ROOT}/ansible"
    
    # Update inventory with Terraform outputs
    terraform output > /tmp/terraform_outputs.txt
    
    # Run Ansible playbook
    ansible-playbook -i inventory/hosts playbook.yaml \
        -e "environment=${ENVIRONMENT}" \
        -e "build_number=${BUILD_NUMBER}"
    
    log_success "Application deployment completed"
}

# Deploy to Kubernetes
deploy_kubernetes() {
    log_info "Deploying to Kubernetes..."
    
    # Update image tags in K8s manifests
    local image_tag="${BUILD_NUMBER}"
    sed -i "s/latest/${image_tag}/g" "${PROJECT_ROOT}/k8s/envs/${ENVIRONMENT}/deployments.yaml"
    
    # Apply Kubernetes manifests
    kubectl apply -f "${PROJECT_ROOT}/k8s/envs/${ENVIRONMENT}/"
    
    # Wait for rollout
    kubectl rollout status deployment/webserver -n "mern-app-${ENVIRONMENT}" --timeout=300s
    kubectl rollout status deployment/mongo -n "mern-app-${ENVIRONMENT}" --timeout=300s
    
    log_success "Kubernetes deployment completed"
}

# Run tests
run_tests() {
    log_info "Running test suite..."
    
    # Unit tests
    if [ -f "${PROJECT_ROOT}/ansible/roles/webserver/files/app/package.json" ]; then
        cd "${PROJECT_ROOT}/ansible/roles/webserver/files/app"
        npm test
    fi
    
    # Integration tests
    if command -v k6 &> /dev/null; then
        log_info "Running integration tests with k6..."
        k6 run "${PROJECT_ROOT}/tests/integration.js"
    fi
    
    # Security tests
    if command -v tfsec &> /dev/null; then
        log_info "Running security tests..."
        tfsec "${PROJECT_ROOT}/terraform/" --format json --out tfsec-report.json || true
    fi
    
    log_success "Test suite completed"
}

# Health checks
run_health_checks() {
    log_info "Running health checks..."
    
    local namespace="mern-app-${ENVIRONMENT}"
    
    # Check pods status
    kubectl get pods -n "$namespace"
    
    # Check services
    kubectl get services -n "$namespace"
    
    # Test endpoints
    local webserver_pod=$(kubectl get pods -n "$namespace" -l app=webserver -o jsonpath='{.items[0].metadata.name}')
    if [ -n "$webserver_pod" ]; then
        kubectl exec -n "$namespace" "$webserver_pod" -- curl -f http://localhost:5000/health || {
            log_error "Health check failed"
            return 1
        }
    fi
    
    log_success "Health checks passed"
}

# Rollback deployment
rollback_deployment() {
    log_warning "Rolling back deployment for environment: $ENVIRONMENT"
    
    local namespace="mern-app-${ENVIRONMENT}"
    
    # Rollback Kubernetes deployments
    kubectl rollout undo deployment/webserver -n "$namespace"
    kubectl rollout undo deployment/mongo -n "$namespace"
    
    # Wait for rollback to complete
    kubectl rollout status deployment/webserver -n "$namespace" --timeout=300s
    kubectl rollout status deployment/mongo -n "$namespace" --timeout=300s
    
    log_success "Rollback completed"
}

# Cleanup old resources
cleanup() {
    log_info "Cleaning up old resources..."
    
    # Remove old Docker images
    docker image prune -f
    
    # Clean up Terraform plan files
    find "${PROJECT_ROOT}/terraform/" -name "*.tfplan" -delete
    
    log_success "Cleanup completed"
}

# Main deployment function
main() {
    local skip_tests=false
    local force_deploy=false
    local rollback=false
    local dry_run=false
    
    # Parse options
    shift # Remove environment argument
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-tests)
                skip_tests=true
                shift
                ;;
            --force-deploy)
                force_deploy=true
                shift
                ;;
            --rollback)
                rollback=true
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Confirm deployment unless forced
    if [ "$force_deploy" = false ] && [ "$dry_run" = false ] && [ "$rollback" = false ]; then
        echo -n "Deploy to $ENVIRONMENT environment? (y/N): "
        read -r confirmation
        if [[ ! "$confirmation" =~ ^[Yy]$ ]]; then
            log_info "Deployment cancelled"
            exit 0
        fi
    fi
    
    log_info "Starting deployment to $ENVIRONMENT environment"
    log_info "Build number: $BUILD_NUMBER"
    
    # Execute deployment steps
    check_prerequisites
    validate_environment
    
    if [ "$rollback" = true ]; then
        rollback_deployment
        exit 0
    fi
    
    if [ "$dry_run" = false ]; then
        build_images
        deploy_infrastructure
        deploy_application
        deploy_kubernetes
        
        if [ "$skip_tests" = false ]; then
            run_tests
        fi
        
        run_health_checks
        cleanup
    else
        log_info "DRY RUN - Would execute the following steps:"
        echo "  - Build Docker images"
        echo "  - Deploy infrastructure with Terraform"
        echo "  - Deploy application with Ansible"
        echo "  - Deploy to Kubernetes"
        if [ "$skip_tests" = false ]; then
            echo "  - Run tests"
        fi
        echo "  - Run health checks"
        echo "  - Cleanup"
    fi
    
    log_success "Deployment to $ENVIRONMENT completed successfully!"
}

# Error handling
trap 'log_error "Script failed at line $LINENO"' ERR

# Run main function
main "$@"
