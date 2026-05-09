variable "name" {
  description = "Name prefix for hub VPC resources"
  type        = string
}

variable "cidr" {
  description = "CIDR block for the hub VPC"
  type        = string
}

variable "azs" {
  description = "Availability zones for subnet placement"
  type        = list(string)
}

variable "private_subnets" {
  description = "Private subnet CIDR blocks (one per AZ)"
  type        = list(string)
}

variable "public_subnets" {
  description = "Public subnet CIDR blocks for NAT/ingress (one per AZ)"
  type        = list(string)
}

variable "enable_nat_gateway" {
  description = "Create NAT Gateway(s) for spoke egress"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use a single NAT Gateway (lower cost; not HA)"
  type        = bool
  default     = false
}

variable "flow_log_retention_days" {
  description = "Days to retain VPC Flow Logs in CloudWatch"
  type        = number
  default     = 90
}

variable "tags" {
  description = "Tags to apply to all hub VPC resources"
  type        = map(string)
  default     = {}
}
