#!/bin/bash

# Comprehensive health check script for MERN App DevOps
# Usage: ./scripts/health-check.sh [environment] [options]

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENVIRONMENT="${1:-dev}"
TIMEOUT=30

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Results tracking
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    ((PASSED_CHECKS++))
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    ((FAILED_CHECKS++))
}

log_check() {
    echo -e "${BLUE}[CHECK]${NC} $1"
    ((TOTAL_CHECKS++))
}

# Usage information
usage() {
    cat << EOF
Usage: $0 [ENVIRONMENT] [OPTIONS]

Environments:
  dev         Check development environment (default)
  staging     Check staging environment
  prod        Check production environment

Options:
  --verbose   Show detailed output
  --quick     Run quick health checks only
  --deep      Run comprehensive health checks
  --help      Show this help message

Examples:
  $0 dev --verbose
  $0 prod --deep
  $0 staging --quick

EOF
}

# Check Kubernetes cluster health
check_kubernetes_cluster() {
    log_check "Kubernetes cluster health"
    
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        return 1
    fi
    
    local nodes=$(kubectl get nodes --no-headers | wc -l)
    if [ "$nodes" -eq 0 ]; then
        log_error "No nodes found in cluster"
        return 1
    fi
    
    log_success "Cluster is accessible with $nodes nodes"
}

# Check namespace and resources
check_namespace_resources() {
    local namespace="mern-app-${ENVIRONMENT}"
    log_check "Namespace and resource checks for $namespace"
    
    # Check if namespace exists
    if ! kubectl get namespace "$namespace" &> /dev/null; then
        log_error "Namespace $namespace does not exist"
        return 1
    fi
    
    log_success "Namespace $namespace exists"
    
    # Check deployments
    local deployments=$(kubectl get deployments -n "$namespace" --no-headers | wc -l)
    log_info "Found $deployments deployments"
    
    # Check services
    local services=$(kubectl get services -n "$namespace" --no-headers | wc -l)
    log_info "Found $services services"
    
    # Check pods
    local pods=$(kubectl get pods -n "$namespace" --no-headers | wc -l)
    if [ "$pods" -eq 0 ]; then
        log_error "No pods found in namespace $namespace"
        return 1
    fi
    log_success "Found $pods pods"
}

# Check pod status and health
check_pod_health() {
    local namespace="mern-app-${ENVIRONMENT}"
    log_check "Pod health status"
    
    local pods=$(kubectl get pods -n "$namespace" -o wide --no-headers)
    local failed_pods=0
    
    while IFS= read -r pod; do
        local pod_name=$(echo "$pod" | awk '{print $1}')
        local status=$(echo "$pod" | awk '{print $3}')
        local ready=$(echo "$pod" | awk '{print $2}')
        
        log_info "Pod: $pod_name, Status: $status, Ready: $ready"
        
        case "$status" in
            "Running"|"Completed")
                if [[ "$ready" == *"1/1"* ]] || [[ "$ready" == *"2/2"* ]]; then
                    log_success "Pod $pod_name is healthy"
                else
                    log_warning "Pod $pod_name is running but not ready: $ready"
                fi
                ;;
            "Pending"|"ContainerCreating")
                log_warning "Pod $pod_name is starting up: $status"
                ;;
            "Failed"|"Error"|"CrashLoopBackOff")
                log_error "Pod $pod_name is unhealthy: $status"
                ((failed_pods++))
                ;;
            *)
                log_warning "Pod $pod_name has unknown status: $status"
                ;;
        esac
    done <<< "$pods"
    
    if [ "$failed_pods" -gt 0 ]; then
        log_error "$failed_pods pods are in failed state"
        return 1
    fi
}

# Check service endpoints
check_service_endpoints() {
    local namespace="mern-app-${ENVIRONMENT}"
    log_check "Service endpoint availability"
    
    local services=("webserver-service" "mongo-service")
    
    for service in "${services[@]}"; do
        if kubectl get service "$service" -n "$namespace" &> /dev/null; then
            local endpoints=$(kubectl get endpoints "$service" -n "$namespace" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || echo "")
            
            if [ -n "$endpoints" ]; then
                local endpoint_count=$(echo "$endpoints" | wc -w)
                log_success "Service $service has $endpoint_count healthy endpoints"
            else
                log_warning "Service $service has no healthy endpoints"
            fi
        else
            log_error "Service $service not found"
        fi
    done
}

# Check application health endpoints
check_application_health() {
    local namespace="mern-app-${ENVIRONMENT}"
    log_check "Application health endpoints"
    
    # Get webserver pod
    local webserver_pod=$(kubectl get pods -n "$namespace" -l app=webserver -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -z "$webserver_pod" ]; then
        log_error "No webserver pod found"
        return 1
    fi
    
    # Check /health endpoint
    log_info "Testing /health endpoint on pod $webserver_pod"
    if kubectl exec -n "$namespace" "$webserver_pod" -- curl -sf -m 5 http://localhost:5000/health &> /dev/null; then
        log_success "Health endpoint is responding"
        
        # Get detailed health information
        local health_response=$(kubectl exec -n "$namespace" "$webserver_pod" -- curl -sf http://localhost:5000/health 2>/dev/null || echo "{}")
        log_info "Health response: $health_response"
    else
        log_error "Health endpoint is not responding"
        return 1
    fi
    
    # Check /api endpoint
    log_info "Testing /api endpoint"
    if kubectl exec -n "$namespace" "$webserver_pod" -- curl -sf -m 5 http://localhost:5000/api &> /dev/null; then
        log_success "API endpoint is responding"
    else
        log_error "API endpoint is not responding"
        return 1
    fi
}

# Check database connectivity
check_database_health() {
    local namespace="mern-app-${ENVIRONMENT}"
    log_check "Database connectivity"
    
    # Get mongo pod
    local mongo_pod=$(kubectl get pods -n "$namespace" -l app=mongo -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -z "$mongo_pod" ]; then
        log_error "No mongo pod found"
        return 1
    fi
    
    # Check MongoDB connectivity
    log_info "Testing MongoDB connectivity"
    if kubectl exec -n "$namespace" "$mongo_pod" -- mongo --eval "db.adminCommand('ping')" --quiet | grep -q "ok.*1"; then
        log_success "MongoDB is responding to pings"
    else
        log_error "MongoDB is not responding"
        return 1
    fi
    
    # Check MongoDB stats
    local stats=$(kubectl exec -n "$namespace" "$mongo_pod" -- mongo --eval "db.stats()" --quiet 2>/dev/null || echo "{}")
    log_info "MongoDB stats: $stats"
}

# Check resource usage
check_resource_usage() {
    local namespace="mern-app-${ENVIRONMENT}"
    log_check "Resource usage"
    
    # Get CPU and memory usage for all pods
    local pod_usage=$(kubectl top pods -n "$namespace" 2>/dev/null || echo "Unable to get metrics")
    
    if [[ "$pod_usage" != *"Unable to get metrics"* ]]; then
        log_info "Pod resource usage:"
        echo "$pod_usage"
        
        # Parse and check for high resource usage
        while IFS= read -r line; do
            local pod_name=$(echo "$line" | awk '{print $1}')
            local cpu=$(echo "$line" | awk '{print $2}')
            local memory=$(echo "$line" | awk '{print $3}')
            
            # Check CPU usage (simple heuristic)
            if [[ "$cpu" == *"m"* ]]; then
                local cpu_millicores=${cpu%m}
                if [ "$cpu_millicores" -gt 500 ]; then
                    log_warning "Pod $pod_name has high CPU usage: $cpu"
                fi
            fi
            
            # Check memory usage
            if [[ "$memory" == *"Mi"* ]]; then
                local memory_mb=${memory%Mi}
                if [ "$memory_mb" -gt 512 ]; then
                    log_warning "Pod $pod_name has high memory usage: $memory"
                fi
            fi
        done <<< "$(echo "$pod_usage" | tail -n +2)"
    else
        log_warning "Metrics server not available - cannot check resource usage"
    fi
}

# Check ingress and external access
check_external_access() {
    local namespace="mern-app-${ENVIRONMENT}"
    log_check "External access and ingress"
    
    # Check ingress resources
    if kubectl get ingress -n "$namespace" &> /dev/null; then
        local ingress_count=$(kubectl get ingress -n "$namespace" --no-headers | wc -l)
        log_success "Found $ingress_count ingress resources"
    else
        log_info "No ingress resources found (might be using load balancer)"
    fi
    
    # Check load balancer services
    local lb_services=$(kubectl get services -n "$namespace" -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.name}{"\n"}{end}')
    if [ -n "$lb_services" ]; then
        log_success "Load balancer services found:"
        echo "$lb_services"
    else
        log_info "No load balancer services found"
    fi
}

# Check persistent volumes and storage
check_storage_health() {
    local namespace="mern-app-${ENVIRONMENT}"
    log_check "Storage and persistent volumes"
    
    # Check PVCs
    local pvc_count=$(kubectl get pvc -n "$namespace" --no-headers | wc -l)
    if [ "$pvc_count" -gt 0 ]; then
        log_success "Found $pvc_count persistent volume claims"
        
        # Check PVC status
        while IFS= read -r pvc; do
            local pvc_name=$(echo "$pvc" | awk '{print $1}')
            local status=$(echo "$pvc" | awk '{print $2}')
            local capacity=$(echo "$pvc" | awk '{print $4}')
            
            case "$status" in
                "Bound")
                    log_success "PVC $pvc_name is bound (capacity: $capacity)"
                    ;;
                "Pending")
                    log_warning "PVC $pvc_name is pending"
                    ;;
                *)
                    log_error "PVC $pvc_name has status: $status"
                    ;;
            esac
        done <<< "$(kubectl get pvc -n "$namespace" --no-headers)"
    else
        log_info "No persistent volume claims found"
    fi
}

# Generate health report
generate_report() {
    local report_file="${PROJECT_ROOT}/health-report-${ENVIRONMENT}-$(date +%Y%m%d-%H%M%S).txt"
    
    cat > "$report_file" << EOF
MERN App Health Check Report
=============================
Environment: $ENVIRONMENT
Timestamp: $(date)
Script Version: 1.0

Check Summary:
- Total Checks: $TOTAL_CHECKS
- Passed: $PASSED_CHECKS
- Failed: $FAILED_CHECKS
- Success Rate: $(( PASSED_CHECKS * 100 / TOTAL_CHECKS ))%

Overall Status: $([ $FAILED_CHECKS -eq 0 ] && echo "HEALTHY" || echo "ISSUES DETECTED")

Recommendations:
EOF

    if [ $FAILED_CHECKS -gt 0 ]; then
        echo "- Review failed checks and address underlying issues" >> "$report_file"
        echo "- Check application logs for detailed error information" >> "$report_file"
        echo "- Verify resource allocations and scaling policies" >> "$report_file"
    fi
    
    if [ $FAILED_CHECKS -eq 0 ]; then
        echo "- All systems are operating normally" >> "$report_file"
        echo "- Continue monitoring for performance optimization" >> "$report_file"
    fi
    
    log_info "Health report generated: $report_file"
}

# Main health check function
main() {
    local verbose=false
    local quick=false
    local deep=false
    
    # Parse options
    shift # Remove environment argument
    while [[ $# -gt 0 ]]; do
        case $1 in
            --verbose)
                verbose=true
                shift
                ;;
            --quick)
                quick=true
                shift
                ;;
            --deep)
                deep=true
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
    
    echo "========================================="
    echo "  MERN App Health Check"
    echo "  Environment: $ENVIRONMENT"
    echo "  Timestamp: $(date)"
    echo "========================================="
    echo
    
    # Core health checks (always run)
    check_kubernetes_cluster
    check_namespace_resources
    check_pod_health
    check_service_endpoints
    
    if [ "$quick" = false ]; then
        check_application_health
        check_database_health
        check_resource_usage
        check_external_access
        check_storage_health
    fi
    
    if [ "$deep" = true ]; then
        # Additional deep checks could be added here
        log_info "Deep health check mode enabled"
    fi
    
    # Generate report
    echo
    echo "========================================="
    echo "  Health Check Summary"
    echo "========================================="
    echo "Total Checks: $TOTAL_CHECKS"
    echo "Passed: $PASSED_CHECKS"
    echo "Failed: $FAILED_CHECKS"
    
    if [ $FAILED_CHECKS -eq 0 ]; then
        echo "Status: ✅ HEALTHY"
        log_success "All health checks passed!"
    else
        echo "Status: ❌ ISSUES DETECTED"
        log_error "Some health checks failed. Review the output above."
    fi
    
    generate_report
    
    # Return appropriate exit code
    if [ $FAILED_CHECKS -gt 0 ]; then
        exit 1
    else
        exit 0
    fi
}

# Run main function
main "$@"
