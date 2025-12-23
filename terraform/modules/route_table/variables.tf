variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID to associate"
  type        = string
}

variable "gateway_id" {
  description = "Gateway ID (Internet Gateway)"
  type        = string
}

variable "route_table_name" {
  description = "Name tag for the route table"
  type        = string
}
