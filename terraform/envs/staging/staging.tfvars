# Staging Environment Configuration
# AWS Infrastructure
aws_region = "us-east-1"
environment = "staging"
project_name = "mern-app"

# VPC Configuration
vpc_cidr = "10.1.0.0/16"
public_subnet_cidr = "10.1.1.0/24"
private_subnet_cidr = "10.1.2.0/24"

# EC2 Configuration
webserver_instance_type = "t3.small"
dbserver_instance_type = "t3.small"
key_name = "staging-key"

# Database Configuration
mongo_version = "5.0"
mongo_replica_set = true

# Kubernetes Configuration
replicas = 2
node_selector = "staging"

# Resource Limits
webserver_cpu_limit = "500m"
webserver_memory_limit = "512Mi"
mongo_cpu_limit = "250m"
mongo_memory_limit = "256Mi"

# Environment Variables
NODE_ENV = "staging"
LOG_LEVEL = "info"
