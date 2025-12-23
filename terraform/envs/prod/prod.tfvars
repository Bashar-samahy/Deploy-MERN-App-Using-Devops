# Production Environment Configuration
# AWS Infrastructure
aws_region = "us-east-1"
environment = "prod"
project_name = "mern-app"

# VPC Configuration
vpc_cidr = "10.2.0.0/16"
public_subnet_cidr = "10.2.1.0/24"
private_subnet_cidr = "10.2.2.0/24"

# EC2 Configuration
webserver_instance_type = "t3.medium"
dbserver_instance_type = "t3.medium"
key_name = "prod-key"

# Database Configuration
mongo_version = "5.0"
mongo_replica_set = true
mongo_backup_enabled = true

# Kubernetes Configuration
replicas = 3
node_selector = "production"

# Resource Limits
webserver_cpu_limit = "1000m"
webserver_memory_limit = "1024Mi"
mongo_cpu_limit = "500m"
mongo_memory_limit = "512Mi"

# Environment Variables
NODE_ENV = "production"
LOG_LEVEL = "warn"

# Security Settings
enable_rbac = true
enable_network_policy = true
enable_pod_security = true

# Monitoring
enable_monitoring = true
enable_alerting = true
monitoring_retention_days = 30
