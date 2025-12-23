variable "vpc_id" {
  description = "VPC ID to attach IGW"
  type        = string
}

variable "igw_name" {
  description = "Name tag for the IGW"
  type        = string
  default     = "terraform-mern-igw"
}
