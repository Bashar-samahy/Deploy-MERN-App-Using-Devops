variable "ami" {
  description = "AMI ID"
  type        = string
}

variable "instance_type" {
  description = "Instance type"
  type        = string
  default     = "t3.micro"
}

variable "subnet_id" {
  description = "Subnet ID"
  type        = string
}

variable "key_name" {
  description = "Key pair name"
  type        = string
}

variable "security_group_id" {
  description = "Security group ID"
  type        = string
}

variable "instance_name" {
  description = "Name tag of instance"
  type        = string
}
