variable "vpc_id" {
  description = "VPC ID to create subnet in"
  type        = string
}

variable "cidr_block" {
  description = "CIDR block for the subnet"
  type        = string
}

variable "availability_zone" {
  description = "AZ for the subnet"
  type        = string
}

variable "map_public_ip_on_launch" {
  description = "Whether to assign public IP on launch"
  type        = bool
  default     = false
}

variable "subnet_name" {
  description = "Name tag for the subnet"
  type        = string
}
