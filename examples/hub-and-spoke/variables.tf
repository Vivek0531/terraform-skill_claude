variable "aws_region" {
  description = "AWS region to deploy all resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used as a prefix for all resource names"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,24}$", var.project_name))
    error_message = "project_name must be 3-24 lowercase alphanumeric characters or hyphens."
  }
}

variable "environment" {
  description = "Top-level environment label (e.g. production, staging)"
  type        = string
  default     = "production"
}

variable "owner" {
  description = "Team or person responsible for this infrastructure"
  type        = string
}

variable "availability_zones" {
  description = "List of AZs to spread subnets across (minimum 2 for HA)"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least 2 availability zones are required for high availability."
  }
}

# ── Hub VPC ────────────────────────────────────────────────────────────────
variable "hub_cidr" {
  description = "CIDR block for the hub (shared-services) VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "hub_private_subnets" {
  description = "Private subnet CIDRs for the hub VPC (one per AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "hub_public_subnets" {
  description = "Public subnet CIDRs for the hub VPC NAT/ingress (one per AZ)"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

# ── Transit Gateway ────────────────────────────────────────────────────────
variable "tgw_asn" {
  description = "BGP ASN for the Transit Gateway (64512-65534 for private ASNs)"
  type        = number
  default     = 64512

  validation {
    condition     = var.tgw_asn >= 64512 && var.tgw_asn <= 65534
    error_message = "tgw_asn must be a private BGP ASN in the range 64512-65534."
  }
}

# ── Spoke VPCs ─────────────────────────────────────────────────────────────
variable "spoke_vpcs" {
  description = "Map of spoke VPCs to create and attach to the Transit Gateway"
  type = map(object({
    cidr            = string
    private_subnets = list(string)
    environment     = string
  }))

  default = {
    production = {
      cidr            = "10.1.0.0/16"
      private_subnets = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
      environment     = "production"
    }
    staging = {
      cidr            = "10.2.0.0/16"
      private_subnets = ["10.2.1.0/24", "10.2.2.0/24", "10.2.3.0/24"]
      environment     = "staging"
    }
    development = {
      cidr            = "10.3.0.0/16"
      private_subnets = ["10.3.1.0/24", "10.3.2.0/24", "10.3.3.0/24"]
      environment     = "development"
    }
    security = {
      cidr            = "10.4.0.0/16"
      private_subnets = ["10.4.1.0/24", "10.4.2.0/24", "10.4.3.0/24"]
      environment     = "security"
    }
  }

  validation {
    condition     = length(var.spoke_vpcs) >= 1
    error_message = "At least one spoke VPC must be defined."
  }
}
