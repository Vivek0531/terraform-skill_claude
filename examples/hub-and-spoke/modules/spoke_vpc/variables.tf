variable "name" {
  description = "Name prefix for spoke VPC resources"
  type        = string
}

variable "cidr" {
  description = "CIDR block for the spoke VPC"
  type        = string
}

variable "azs" {
  description = "Availability zones for subnet placement"
  type        = list(string)
}

variable "private_subnets" {
  description = "Private subnet CIDR blocks (one per AZ). Spokes have no public subnets."
  type        = list(string)
}

variable "environment" {
  description = "Environment label (production, staging, development, security)"
  type        = string
}

variable "hub_cidr" {
  description = "CIDR of the hub VPC — used in NACL to allow inbound from hub"
  type        = string
  default     = "10.0.0.0/16"
}

variable "flow_log_retention_days" {
  description = "Days to retain VPC Flow Logs in CloudWatch"
  type        = number
  default     = 90
}

variable "tags" {
  description = "Tags to apply to all spoke VPC resources"
  type        = map(string)
  default     = {}
}
