# Development Environment Configuration
# AWS Infrastructure
aws_region = "us-east-1"
environment = "dev"
project_name = "mern-app"

# VPC Configuration
vpc_cidr = "10.0.0.0/16"
public_subnet_cidr = "10.0.1.0/24"
private_subnet_cidr = "10.0.2.0/24"

# EC2 Configuration
webserver_instance_type = "t3.micro"
dbserver_instance_type = "t3.micro"
key_name = "dev-key"

# Database Configuration
mongo_version = "5.0"
mongo_replica_set = false

# Kubernetes Configuration
replicas = 1
node_selector = "development"

# Resource Limits
webserver_cpu_limit = "200m"
webserver_memory_limit = "256Mi"
mongo_cpu_limit = "100m"
mongo_memory_limit = "128Mi"

# Environment Variables
NODE_ENV = "development"
LOG_LEVEL = "debug"
